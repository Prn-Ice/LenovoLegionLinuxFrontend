#include "control_commands.h"
#include <cerrno>
#include <climits>
#include <cstdio>
#include <cstring>
#include <gio/gio.h>
#include <map>
#include <memory>
#include <polkit/polkit.h>
#include <string>
#include <sys/stat.h>
#include <tuple>
#include <unistd.h>
#include <vector>

namespace {
constexpr char bus[] = "io.github.prnice.LegionControl1",
               path[] = "/io/github/prnice/LegionControl1",
               iface[] = "io.github.prnice.LegionControl1";
constexpr gsize output_limit = 64 * 1024;
constexpr size_t input_limit = 128;
constexpr char xml[] =
    R"(<node><interface name="io.github.prnice.LegionControl1"><method name="Authorize"/><method name="SetFeature"><arg type="s" direction="in"/><arg type="s" direction="in"/></method><method name="SetToggle"><arg type="s" direction="in"/><arg type="b" direction="in"/></method><method name="ApplyFanPreset"><arg type="s" direction="in"/></method><method name="ApplyCurrentFanPreset"/><method name="ApplyFanCurve"><arg type="ay" direction="in"/></method><method name="ApplyCustomConservation"><arg type="u" direction="in"/><arg type="u" direction="in"/></method><method name="SetBootLogo"><arg type="ay" direction="in"/></method><method name="RestoreBootLogo"/><method name="SetServiceEnabled"><arg type="s" direction="in"/><arg type="b" direction="in"/></method></interface></node>)";
struct Ctx {
  GMainLoop *loop;
  GDBusNodeInfo *info;
  GDBusConnection *conn = nullptr;
  guint reg = 0, owner = 0, names = 0;
  std::string cli, systemctl;
  std::map<std::string, bool> auth;
  std::map<std::string, GCancellable *> pending;
  PolkitAuthority *authority = nullptr;
  struct ActiveOperation {
    Ctx *ctx;
    GDBusMethodInvocation *invocation;
    GSubprocess *subprocess;
    GInputStream *output;
    guint timeout_source = 0;
    std::string temp_path;
    std::string sender;
    std::string output_text;
    std::string process_error;
    bool process_finished = false;
    bool output_finished = false;
    bool process_success = false;
    bool output_exceeded = false;
    bool timed_out = false;
    bool disconnected = false;
    bool completed = false;
  };
  std::unique_ptr<ActiveOperation> active;
};
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
void auth_done(GObject *source, GAsyncResult *result, gpointer data) {
  auto *p = static_cast<std::pair<Ctx *, GDBusMethodInvocation *> *>(data);
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
void finish_operation(Ctx::ActiveOperation *op) {
  Ctx *c = op->ctx;
  if (op->timeout_source != 0) {
    g_source_remove(op->timeout_source);
    op->timeout_source = 0;
  }
  if (!op->temp_path.empty())
    unlink(op->temp_path.c_str());
  g_clear_object(&op->output);
  g_clear_object(&op->subprocess);
  g_clear_object(&op->invocation);
  c->active.reset();
}
std::string valid_utf8(const std::string &value) {
  gchar *text = g_utf8_make_valid(value.data(), value.size());
  std::string result(text);
  g_free(text);
  return result;
}
void maybe_finish_operation(Ctx::ActiveOperation *op) {
  if (!op->process_finished || !op->output_finished || op->completed)
    return;
  if (!op->timed_out && !op->disconnected) {
    if (op->output_exceeded)
      reply_error(op->invocation, "CommandFailed",
                  "backend output exceeded limit");
    else if (!op->process_error.empty())
      reply_error(op->invocation, "CommandFailed", op->process_error);
    else if (!op->process_success) {
      const std::string output = valid_utf8(op->output_text);
      reply_error(op->invocation, "CommandFailed",
                  output.empty() ? "backend command failed"
                                 : "backend command failed: " + output);
    } else
      done(op->invocation);
  }
  op->completed = true;
  finish_operation(op);
}
void read_output(Ctx::ActiveOperation *op);
void output_read_done(GObject *source, GAsyncResult *result, gpointer data) {
  auto *op = static_cast<Ctx::ActiveOperation *>(data);
  GError *error = nullptr;
  GBytes *bytes = g_input_stream_read_bytes_finish(
      G_INPUT_STREAM(source), result, &error);
  if (!bytes) {
    op->process_error =
        error ? "could not read backend output: " + std::string(error->message)
              : "could not read backend output";
    g_clear_error(&error);
    op->output_finished = true;
    g_subprocess_force_exit(op->subprocess);
  } else {
    gsize size = 0;
    const char *contents =
        static_cast<const char *>(g_bytes_get_data(bytes, &size));
    if (size == 0) {
      op->output_finished = true;
    } else if (op->output_text.size() + size > output_limit) {
      op->output_exceeded = true;
      op->output_finished = true;
      g_input_stream_close(op->output, nullptr, nullptr);
      g_subprocess_force_exit(op->subprocess);
    } else {
      op->output_text.append(contents, size);
      read_output(op);
    }
    g_bytes_unref(bytes);
  }
  maybe_finish_operation(op);
}
void read_output(Ctx::ActiveOperation *op) {
  g_input_stream_read_bytes_async(op->output, 4096, G_PRIORITY_DEFAULT, nullptr,
                                  output_read_done, op);
}
void operation_timeout(gpointer data) {
  auto *op = static_cast<Ctx::ActiveOperation *>(data);
  op->timeout_source = 0;
  if (op->completed)
    return;
  op->timed_out = true;
  if (!op->disconnected)
    reply_error(op->invocation, "Timeout", "control operation timed out");
  g_subprocess_force_exit(op->subprocess);
}
void invoke(Ctx *c, GDBusMethodInvocation *i,
            const legion_control::Command &command, bool systemctl = false,
            const std::string &temp_path = {}) {
  if (c->active) {
    if (!temp_path.empty())
      unlink(temp_path.c_str());
    reply_error(i, "Busy", "another control operation is running");
    return;
  }
  GError *e = nullptr;
  const auto flags = static_cast<GSubprocessFlags>(
      G_SUBPROCESS_FLAGS_STDOUT_PIPE | G_SUBPROCESS_FLAGS_STDERR_MERGE);
  GSubprocessLauncher *l = g_subprocess_launcher_new(flags);
  std::vector<const char *> a;
  const std::string &executable = systemctl ? c->systemctl : c->cli;
  a.push_back(executable.c_str());
  for (const auto &x : command.argv)
    a.push_back(x.c_str());
  a.push_back(nullptr);
  GSubprocess *p = g_subprocess_launcher_spawnv(l, a.data(), &e);
  g_object_unref(l);
  if (!p) {
    if (!temp_path.empty())
      unlink(temp_path.c_str());
    reply_error(i, "Unavailable", e ? e->message : "could not start backend");
    g_clear_error(&e);
    return;
  }
  auto operation =
      std::unique_ptr<Ctx::ActiveOperation>(new Ctx::ActiveOperation{});
  operation->ctx = c;
  operation->invocation = G_DBUS_METHOD_INVOCATION(g_object_ref(i));
  operation->subprocess = p;
  operation->output = G_INPUT_STREAM(
      g_object_ref(g_subprocess_get_stdout_pipe(p)));
  operation->temp_path = temp_path;
  operation->sender = g_dbus_method_invocation_get_sender(i);
  Ctx::ActiveOperation *q = operation.get();
  c->active = std::move(operation);
  read_output(q);
  g_subprocess_wait_async(
      p, nullptr,
      [](GObject *o, GAsyncResult *r, gpointer d) {
        auto *op = static_cast<Ctx::ActiveOperation *>(d);
        GError *e = nullptr;
        if (!g_subprocess_wait_finish(G_SUBPROCESS(o), r, &e)) {
          op->process_error = e ? e->message : "backend failed";
          g_clear_error(&e);
        } else
          op->process_success =
              g_subprocess_get_successful(G_SUBPROCESS(o));
        op->process_finished = true;
        maybe_finish_operation(op);
      },
      q);
  q->timeout_source = g_timeout_add_seconds(
      10,
      [](gpointer d) -> gboolean {
        operation_timeout(d);
        return G_SOURCE_REMOVE;
      },
      q);
}
bool authorized(Ctx *c, GDBusMethodInvocation *i) {
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
void call(GDBusConnection *, const gchar *, const gchar *, const gchar *,
          const gchar *m, GVariant *v, GDBusMethodInvocation *i, gpointer d) {
  auto *c = static_cast<Ctx *>(d);
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
    auto *q = new std::pair<Ctx *, GDBusMethodInvocation *>(c, g_object_ref(i));
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
  std::string err;
  const gchar *f_raw = nullptr;
  const gchar *val_raw = nullptr;
  const gchar *cap_raw = nullptr;
  const gchar *pre_raw = nullptr;
  const gchar *sid_raw = nullptr;
  std::string f, val, cap, pre, sid;
  gboolean en;
  if (!g_strcmp0(m, "SetFeature")) {
    g_variant_get(v, "(&s&s)", &f_raw, &val_raw);
    if (!bounded(f_raw, "feature", &err) ||
        !bounded(val_raw, "value", &err)) {
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
           false, t);
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
    invoke(c, i, legion_control::ServiceCommand(sid, en), true);
  } else
    reply_error(i, "InvalidArgs", "unknown method");
}
const GDBusInterfaceVTable vt = {call, nullptr, nullptr, {nullptr}};
bool trusted_executable(const std::string &input, std::string *resolved) {
  char canonical[PATH_MAX];
  if (!realpath(input.c_str(), canonical))
    return false;
  struct stat file_stat {};
  if (stat(canonical, &file_stat) != 0 || file_stat.st_uid != 0 ||
      !S_ISREG(file_stat.st_mode) ||
      (file_stat.st_mode & (S_IWGRP | S_IWOTH)) != 0 ||
      access(canonical, X_OK) != 0)
    return false;
  std::string parent = canonical;
  while (true) {
    const auto slash = parent.rfind('/');
    parent = slash == 0 ? "/" : parent.substr(0, slash);
    struct stat directory_stat {};
    if (stat(parent.c_str(), &directory_stat) != 0 ||
        directory_stat.st_uid != 0 || !S_ISDIR(directory_stat.st_mode) ||
        (directory_stat.st_mode & S_IWOTH) != 0 ||
        ((directory_stat.st_mode & S_IWGRP) != 0 &&
         (directory_stat.st_mode & S_ISVTX) == 0))
      return false;
    if (parent == "/")
      break;
  }
  *resolved = canonical;
  return true;
}
} // namespace
int main(int argc, char **argv) {
  std::string cli, sys;
  for (int n = 1; n < argc; n++) {
    if (n + 1 < argc && std::string(argv[n]) == "--cli")
      cli = argv[++n];
    else if (n + 1 < argc && std::string(argv[n]) == "--systemctl")
      sys = argv[++n];
    else
      return 2;
  }
  if (cli.empty() || sys.empty() || cli[0] != '/' || sys[0] != '/' ||
      !trusted_executable(cli, &cli) || !trusted_executable(sys, &sys))
    return 2;
  Ctx c{};
  c.loop = g_main_loop_new(nullptr, FALSE);
  c.cli = cli;
  c.systemctl = sys;
  GError *e = nullptr;
  c.authority = polkit_authority_get_sync(nullptr, &e);
  if (!c.authority) {
    g_clear_error(&e);
    g_main_loop_unref(c.loop);
    return 1;
  }
  c.info = g_dbus_node_info_new_for_xml(xml, &e);
  if (!c.info) {
    g_clear_error(&e);
    g_clear_object(&c.authority);
    g_main_loop_unref(c.loop);
    return 1;
  }
  c.owner = g_bus_own_name(
      G_BUS_TYPE_SYSTEM, bus, G_BUS_NAME_OWNER_FLAGS_NONE,
       [](GDBusConnection *x, const gchar *, gpointer d) {
         auto *c = static_cast<Ctx *>(d);
         g_set_object(&c->conn, x);
         GError *error = nullptr;
         c->reg = g_dbus_connection_register_object(
             x, path, c->info->interfaces[0], &vt, c, nullptr, &error);
         if (c->reg == 0) {
           g_warning("Could not export LegionControl1: %s",
                     error ? error->message : "unknown error");
           g_clear_error(&error);
           g_main_loop_quit(c->loop);
           return;
         }
        c->names = g_dbus_connection_signal_subscribe(
            x, "org.freedesktop.DBus", "org.freedesktop.DBus",
            "NameOwnerChanged", "/org/freedesktop/DBus", nullptr,
            G_DBUS_SIGNAL_FLAGS_NONE,
            [](GDBusConnection *, const gchar *, const gchar *, const gchar *,
               const gchar *, GVariant *v, gpointer d) {
              auto *c = static_cast<Ctx *>(d);
              const char *n;
              const char *old;
              const char *now;
              g_variant_get(v, "(&s&s&s)", &n, &old, &now);
              if (!*now) {
                c->auth.erase(n);
                if (c->active && c->active->sender == n &&
                    !c->active->completed) {
                  c->active->disconnected = true;
                  g_subprocess_force_exit(c->active->subprocess);
                }
                auto pending = c->pending.find(n);
                if (pending != c->pending.end()) {
                  g_cancellable_cancel(pending->second);
                  g_object_unref(pending->second);
                  c->pending.erase(pending);
                }
              }
            },
             c, nullptr);
         if (c->names == 0) {
           g_warning("Could not subscribe to D-Bus owner changes");
           g_main_loop_quit(c->loop);
         }
       },
      nullptr,
      [](GDBusConnection *, const gchar *, gpointer d) {
        g_main_loop_quit(static_cast<Ctx *>(d)->loop);
      },
      &c, nullptr);
  g_main_loop_run(c.loop);
  if (c.names != 0 && c.conn != nullptr)
    g_dbus_connection_signal_unsubscribe(c.conn, c.names);
  if (c.reg != 0 && c.conn != nullptr)
    g_dbus_connection_unregister_object(c.conn, c.reg);
  if (c.active) {
    c.active->disconnected = true;
    g_subprocess_force_exit(c.active->subprocess);
    while (c.active)
      g_main_context_iteration(nullptr, TRUE);
  }
  for (auto &entry : c.pending)
    g_cancellable_cancel(entry.second);
  while (!c.pending.empty())
    g_main_context_iteration(nullptr, TRUE);
  g_bus_unown_name(c.owner);
  g_clear_object(&c.conn);
  g_clear_object(&c.authority);
  g_clear_pointer(&c.info, g_dbus_node_info_unref);
  g_main_loop_unref(c.loop);
  return 0;
}
