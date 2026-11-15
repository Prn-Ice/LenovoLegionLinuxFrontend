#include "control_service_runtime.h"
#include "control_commands.h"
#include "control_protocol.h"

#include <cerrno>
#include <cstring>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

namespace legion_control {
namespace {
constexpr const char *iface = control_bus_name;
constexpr size_t input_limit = 128;
} // namespace
void reply_error(GDBusMethodInvocation *i, const char *name,
                 const std::string &s) {
  if (g_str_equal(name, "InvalidArgs")) {
    g_dbus_method_invocation_return_error(
        i, G_DBUS_ERROR, G_DBUS_ERROR_INVALID_ARGS, "%s", s.c_str());
    return;
  }
  g_dbus_method_invocation_return_dbus_error(
      i, (std::string(iface) + ".Error." + name).c_str(), s.c_str());
}
void done(GDBusMethodInvocation *i) {
  g_dbus_method_invocation_return_value(i, nullptr);
}
void reply_capabilities(ControlContext *context,
                        GDBusMethodInvocation *invocation) {
  GVariantBuilder capabilities;
  g_variant_builder_init(&capabilities, G_VARIANT_TYPE("as"));
  g_variant_builder_add(&capabilities, "s", "interactive-control");
  if (context->mode == ControlConnectionMode::installed)
    g_variant_builder_add(&capabilities, "s", "persistent-services");
  if (context->mode == ControlConnectionMode::installed &&
      !context->graphics_boot.empty())
    g_variant_builder_add(&capabilities, "s", "next-boot-graphics");
  g_dbus_method_invocation_return_value(
      invocation, g_variant_new("(uas)", 1u, &capabilities));
}
namespace {
void auth_done(GObject *source, GAsyncResult *result, gpointer data) {
  auto *p =
      static_cast<std::pair<ControlContext *, GDBusMethodInvocation *> *>(data);
  --p->first->authorization_callbacks;
  GError *e = nullptr;
  PolkitAuthorizationResult *r = polkit_authority_check_authorization_finish(
      POLKIT_AUTHORITY(source), result, &e);
  const std::string sender = g_dbus_method_invocation_get_sender(p->second);
  auto pending = p->first->pending.find(sender);
  if (pending == p->first->pending.end()) {
    if (e)
      g_clear_error(&e);
    if (r)
      g_object_unref(r);
    g_object_unref(p->second);
    delete p;
    return;
  }
  g_object_unref(pending->second);
  p->first->pending.erase(pending);
  if (e || !r) {
    g_dbus_method_invocation_return_error(
        p->second, G_IO_ERROR, G_IO_ERROR_FAILED, "Authorization failed: %s",
        e ? e->message : "no authorization result");
    g_clear_error(&e);
  } else if (!polkit_authorization_result_get_is_authorized(r)) {
    g_dbus_method_invocation_return_dbus_error(
        p->second, "org.freedesktop.DBus.Error.AccessDenied",
        "Authorization denied");
  } else {
    p->first->auth[sender] = true;
    done(p->second);
  }
  if (r)
    g_object_unref(r);
  g_object_unref(p->second);
  delete p;
}
void finish_operation(ControlContext::ActiveOperation *op) {
  ControlContext *c = op->ctx;
  if (!op->temp_path.empty())
    unlink(op->temp_path.c_str());
  g_clear_object(&op->invocation);
  c->active.reset();
}
std::string valid_utf8(const std::string &value) {
  gchar *text = g_utf8_make_valid(value.data(), value.size());
  std::string result(text);
  g_free(text);
  return result;
}
void complete_operation(ControlContext::ActiveOperation *op,
                        legion_control::ManagedCommandResult result) {
  using Status = legion_control::ManagedCommandStatus;
  if (result.status == Status::cleanupFailed) {
    op->ctx->cleanup_failed = true;
    if (!result.error.empty())
      g_message("Backend cleanup could not be confirmed: %s",
                result.error.c_str());
  }
  if (!op->disconnected) {
    if (result.status == Status::cleanupFailed)
      reply_error(op->invocation, "Unavailable",
                  "backend cleanup could not be confirmed; restart the control "
                  "service");
    else if (result.status == Status::unavailable)
      reply_error(op->invocation, "Unavailable", result.error);
    else if (result.status == Status::busy)
      reply_error(op->invocation, "Busy", result.error);
    else if (result.status == Status::timeout)
      reply_error(op->invocation, "Timeout", "control operation timed out");
    else if (result.status == Status::outputLimit)
      reply_error(op->invocation, "CommandFailed",
                  "backend output exceeded limit");
    else if (result.status != Status::success) {
      const std::string output = valid_utf8(result.output);
      const auto graphics_exit =
          legion_control::ClassifyGraphicsExit(result.exit_status);
      if (op->graphics_operation &&
          graphics_exit == legion_control::GraphicsExit::kBlocked)
        reply_error(op->invocation, "GraphicsBlocked",
                    output.empty() ? "graphics change was blocked before write"
                                   : output);
      else if (op->graphics_operation &&
               graphics_exit == legion_control::GraphicsExit::kPending)
        reply_error(op->invocation, "GraphicsPending",
                    output.empty()
                        ? "graphics policy changed but topology did not settle"
                        : output);
      else
        reply_error(op->invocation, "CommandFailed",
                    output.empty() ? "backend command failed"
                                   : "backend command failed: " + output);
    } else if (op->return_output)
      g_dbus_method_invocation_return_value(
          op->invocation,
          g_variant_new("(s)", valid_utf8(result.output).c_str()));
    else
      done(op->invocation);
  }
  finish_operation(op);
}
enum class CommandBackend { kCli, kSystemctl, kGraphicsBoot };
void invoke(ControlContext *c, GDBusMethodInvocation *i,
            const legion_control::Command &command,
            CommandBackend backend = CommandBackend::kCli,
            const std::string &temp_path = {}, bool graphics = false,
            bool return_output = false) {
  if (c->active) {
    if (!temp_path.empty())
      unlink(temp_path.c_str());
    reply_error(i, "Busy", "another control operation is running");
    return;
  }
  if (c->cleanup_failed || !c->runner) {
    if (!temp_path.empty())
      unlink(temp_path.c_str());
    reply_error(i, "Unavailable",
                "command runner unavailable; restart the control service");
    return;
  }
  const std::string *executable = &c->cli;
  if (backend == CommandBackend::kGraphicsBoot)
    executable = &c->graphics_boot;
  else if (backend == CommandBackend::kSystemctl)
    executable = &c->systemctl;
  auto operation = std::unique_ptr<ControlContext::ActiveOperation>(
      new ControlContext::ActiveOperation{});
  operation->ctx = c;
  operation->invocation = G_DBUS_METHOD_INVOCATION(g_object_ref(i));
  operation->temp_path = temp_path;
  const char *sender = g_dbus_method_invocation_get_sender(i);
  operation->sender = sender ? sender : "";
  operation->graphics_operation = graphics;
  operation->return_output = return_output;
  ControlContext::ActiveOperation *q = operation.get();
  c->active = std::move(operation);
  q->command =
      c->runner->Start(*executable, command.argv, graphics ? 35 : 10,
                       [q](legion_control::ManagedCommandResult result) {
                         complete_operation(q, std::move(result));
                       });
}
bool authorized(ControlContext *c, GDBusMethodInvocation *i) {
  if (c->auth.count(g_dbus_method_invocation_get_sender(i)))
    return true;
  g_dbus_method_invocation_return_dbus_error(
      i, "org.freedesktop.DBus.Error.AccessDenied",
      "Authorize must be called first");
  return false;
}
bool bounded(const char *value, const char *label, std::string *error) {
  if (strnlen(value, input_limit + 1) <= input_limit)
    return true;
  *error = std::string(label) + " exceeds maximum length";
  return false;
}
} // namespace

void dispatch(ControlContext *c, const gchar *m, GVariant *v,
              GDBusMethodInvocation *i) {
  if (c->mode == ControlConnectionMode::portable &&
      (!g_strcmp0(m, "SetServiceEnabled") ||
       !g_strcmp0(m, "RequestGraphicsModeAtBoot") ||
       !g_strcmp0(m, "CancelGraphicsModeAtBoot") ||
       !g_strcmp0(m, "GetGraphicsBootRequest"))) {
    reply_error(i, "NotSupported",
                "this operation requires installed system integration");
    return;
  }
  std::string err;
  const gchar *f_raw = nullptr;
  const gchar *val_raw = nullptr;
  const gchar *cap_raw = nullptr;
  const gchar *pre_raw = nullptr;
  const gchar *sid_raw = nullptr;
  const gchar *mode_raw = nullptr;
  std::string f, val, cap, pre, sid, mode;
  gboolean en;
  if (!g_strcmp0(m, "SetFeature")) {
    g_variant_get(v, "(&s&s)", &f_raw, &val_raw);
    if (!bounded(f_raw, "feature", &err) || !bounded(val_raw, "value", &err)) {
      reply_error(i, "InvalidArgs", err);
      return;
    }
    f = f_raw;
    val = val_raw;
    if (!legion_control::ValidateFeature(f, val, &err)) {
      reply_error(i, "InvalidArgs", err);
      return;
    }
    invoke(c, i, legion_control::FeatureCommand(f, val));
  } else if (!g_strcmp0(m, "SetToggle")) {
    g_variant_get(v, "(&sb)", &cap_raw, &en);
    if (!bounded(cap_raw, "toggle", &err)) {
      reply_error(i, "InvalidArgs", err);
      return;
    }
    cap = cap_raw;
    if (!legion_control::ValidateToggle(cap, en, &err)) {
      reply_error(i, "InvalidArgs", err);
      return;
    }
    invoke(c, i, legion_control::ToggleCommand(cap, en));
  } else if (!g_strcmp0(m, "SetGraphicsMode")) {
    g_variant_get(v, "(&s)", &mode_raw);
    if (!bounded(mode_raw, "graphics mode", &err)) {
      reply_error(i, "InvalidArgs", err);
      return;
    }
    mode = mode_raw;
    if (!legion_control::ValidateGraphicsMode(mode, &err)) {
      reply_error(i, "InvalidArgs", err);
      return;
    }
    invoke(c, i, legion_control::GraphicsModeCommand(mode),
           CommandBackend::kCli, {}, true);
  } else if (!g_strcmp0(m, "RequestGraphicsModeAtBoot") ||
             !g_strcmp0(m, "CancelGraphicsModeAtBoot") ||
             !g_strcmp0(m, "GetGraphicsBootRequest")) {
    if (c->graphics_boot.empty()) {
      reply_error(i, "Unavailable",
                  "next-boot graphics switching is not enabled");
      return;
    }
    legion_control::Command command;
    if (!g_strcmp0(m, "RequestGraphicsModeAtBoot")) {
      g_variant_get(v, "(&s)", &mode_raw);
      if (!bounded(mode_raw, "graphics mode", &err) ||
          !legion_control::ValidateBootGraphicsMode(mode_raw, &err)) {
        reply_error(i, "InvalidArgs", err);
        return;
      }
      command = legion_control::BootGraphicsRequestCommand(mode_raw);
    } else {
      command.argv = {!g_strcmp0(m, "CancelGraphicsModeAtBoot") ? "cancel"
                                                                : "status"};
    }
    invoke(c, i, command, CommandBackend::kGraphicsBoot, {}, false, true);
  } else if (!g_strcmp0(m, "ApplyFanPreset")) {
    g_variant_get(v, "(&s)", &pre_raw);
    if (!bounded(pre_raw, "preset", &err)) {
      reply_error(i, "InvalidArgs", err);
      return;
    }
    pre = pre_raw;
    if (!legion_control::ValidatePreset(pre, &err)) {
      reply_error(i, "InvalidArgs", err);
      return;
    }
    invoke(c, i, legion_control::PresetCommand(pre));
  } else if (!g_strcmp0(m, "ApplyCurrentFanPreset"))
    invoke(c, i, legion_control::CurrentPresetCommand());
  else if (!g_strcmp0(m, "ApplyCustomConservation")) {
    guint l, u;
    g_variant_get(v, "(uu)", &l, &u);
    if (!legion_control::ValidateConservation(l, u, &err)) {
      reply_error(i, "InvalidArgs", err);
      return;
    }
    invoke(c, i, legion_control::ConservationCommand(l, u));
  } else if (!g_strcmp0(m, "ApplyFanCurve") || !g_strcmp0(m, "SetBootLogo")) {
    GVariant *b = nullptr;
    g_variant_get(v, "(@ay)", &b);
    gsize n = 0;
    const guint8 *p = static_cast<const guint8 *>(
        g_variant_get_fixed_array(b, &n, sizeof(guint8)));
    size_t max = !g_strcmp0(m, "ApplyFanCurve") ? 64 * 1024 : 16 * 1024 * 1024;
    if (n == 0 || n > max) {
      g_variant_unref(b);
      reply_error(i, "InvalidArgs",
                  n == 0 ? "payload must not be empty"
                         : "payload exceeds maximum size");
      return;
    }
    std::vector<uint8_t> bytes(p, p + n);
    if (!legion_control::ValidateBytes(bytes, max, &err)) {
      g_variant_unref(b);
      reply_error(i, "InvalidArgs", err);
      return;
    }
    char t[] = "/tmp/legion-control-XXXXXX";
    int fd = mkstemp(t);
    if (fd < 0) {
      g_variant_unref(b);
      reply_error(i, "Backend", "cannot create private temporary file");
      return;
    }
    fchmod(fd, 0600);
    size_t written = 0;
    while (written < n) {
      const ssize_t result = write(fd, p + written, n - written);
      if (result < 0 && errno == EINTR)
        continue;
      if (result <= 0) {
        close(fd);
        unlink(t);
        g_variant_unref(b);
        reply_error(i, "Unavailable", "could not write payload");
        return;
      }
      written += static_cast<size_t>(result);
    }
    close(fd);
    invoke(c, i,
           !g_strcmp0(m, "ApplyFanCurve") ? legion_control::FileCommand(t)
                                          : legion_control::BootLogoCommand(t),
           CommandBackend::kCli, t);
    g_variant_unref(b);
  } else if (!g_strcmp0(m, "RestoreBootLogo"))
    invoke(c, i, legion_control::RestoreBootLogoCommand());
  else if (!g_strcmp0(m, "SetServiceEnabled")) {
    g_variant_get(v, "(&sb)", &sid_raw, &en);
    if (!bounded(sid_raw, "service id", &err)) {
      reply_error(i, "InvalidArgs", err);
      return;
    }
    sid = sid_raw;
    if (!legion_control::ValidateService(sid, &err)) {
      reply_error(i, "InvalidArgs", err);
      return;
    }
    invoke(c, i, legion_control::ServiceCommand(sid, en),
           CommandBackend::kSystemctl);
  } else
    reply_error(i, "InvalidArgs", "unknown method");
}
namespace {
void call(GDBusConnection *, const gchar *, const gchar *, const gchar *,
          const gchar *m, GVariant *v, GDBusMethodInvocation *i, gpointer d) {
  auto *c = static_cast<ControlContext *>(d);
  if (!g_strcmp0(m, "GetCapabilities")) {
    reply_capabilities(c, i);
    return;
  }
  if (!g_strcmp0(m, "Authorize")) {
    const std::string sender = g_dbus_method_invocation_get_sender(i);
    if (c->auth.count(sender)) {
      done(i);
      return;
    }
    if (!c->authority) {
      reply_error(i, "Authorization", "polkit unavailable");
      return;
    }
    if (c->pending.count(sender)) {
      reply_error(i, "Busy", "authorization is already pending");
      return;
    }
    PolkitSubject *s =
        polkit_system_bus_name_new(g_dbus_method_invocation_get_sender(i));
    PolkitDetails *x = polkit_details_new();
    auto *cancel = g_cancellable_new();
    c->pending.emplace(sender, G_CANCELLABLE(g_object_ref(cancel)));
    auto *q = new std::pair<ControlContext *, GDBusMethodInvocation *>(
        c, g_object_ref(i));
    ++c->authorization_callbacks;
    polkit_authority_check_authorization(
        c->authority, s, "io.github.prnice.legion-control.manage", x,
        POLKIT_CHECK_AUTHORIZATION_FLAGS_ALLOW_USER_INTERACTION, cancel,
        auth_done, q);
    g_object_unref(x);
    g_object_unref(s);
    g_object_unref(cancel);
    return;
  }
  if (!authorized(c, i))
    return;
  dispatch(c, m, v, i);
}
} // namespace

const GDBusInterfaceVTable control_vtable = {call, nullptr, nullptr, {nullptr}};
} // namespace legion_control
