// The D-Bus dispatcher shared by the installed control service and the
// portable helper. It checks authorization, validates request arguments, and
// starts one managed backend command at a time.

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
constexpr const char *interface_name = control_bus_name;
constexpr size_t input_limit = 128;

// Owned by the polkit callback. The callback removes it when the check ends.
struct AuthorizationRequest {
  ControlContext *context;
  GDBusMethodInvocation *invocation;
};

// Methods that only make sense when the installed service manages system units
// and next-boot graphics policy.
bool RequiresInstalledIntegration(const char *method) {
  return g_str_equal(method, "SetServiceEnabled") ||
         g_str_equal(method, "RequestGraphicsModeAtBoot") ||
         g_str_equal(method, "CancelGraphicsModeAtBoot") ||
         g_str_equal(method, "GetGraphicsBootRequest");
}
}  // namespace

void reply_error(GDBusMethodInvocation *invocation, const char *name,
                 const std::string &message) {
  if (g_str_equal(name, "InvalidArgs")) {
    g_dbus_method_invocation_return_error(invocation, G_DBUS_ERROR,
                                          G_DBUS_ERROR_INVALID_ARGS, "%s",
                                          message.c_str());
    return;
  }

  // Other errors use the control interface prefix so clients can tell them
  // apart from generic D-Bus failures.
  g_dbus_method_invocation_return_dbus_error(
      invocation, (std::string(interface_name) + ".Error." + name).c_str(),
      message.c_str());
}

void done(GDBusMethodInvocation *invocation) {
  g_dbus_method_invocation_return_value(invocation, nullptr);
}

void reply_capabilities(ControlContext *context,
                        GDBusMethodInvocation *invocation) {
  GVariantBuilder capabilities;
  g_variant_builder_init(&capabilities, G_VARIANT_TYPE("as"));
  g_variant_builder_add(&capabilities, "s", "interactive-control");
  if (context->mode == ControlConnectionMode::installed)
    g_variant_builder_add(&capabilities, "s", "persistent-services");
  if (context->mode == ControlConnectionMode::installed &&
      !context->graphics_boot_path.empty())
    g_variant_builder_add(&capabilities, "s", "next-boot-graphics");

  g_dbus_method_invocation_return_value(
      invocation, g_variant_new("(uas)", 1u, &capabilities));
}

namespace {
void authorization_done(GObject *source, GAsyncResult *result, gpointer data) {
  std::unique_ptr<AuthorizationRequest> request(
      static_cast<AuthorizationRequest *>(data));
  ControlContext *context = request->context;
  --context->authorization_callbacks;

  GError *error = nullptr;
  PolkitAuthorizationResult *authorization =
      polkit_authority_check_authorization_finish(POLKIT_AUTHORITY(source),
                                                  result, &error);

  const std::string sender =
      g_dbus_method_invocation_get_sender(request->invocation);
  auto pending = context->pending_authorizations.find(sender);
  if (pending == context->pending_authorizations.end()) {
    // The client disconnected while polkit was asking. There is no one left
    // to answer, so drop the result.
    g_clear_error(&error);
    if (authorization)
      g_object_unref(authorization);
    g_object_unref(request->invocation);
    return;
  }
  g_object_unref(pending->second);
  context->pending_authorizations.erase(pending);

  if (error || !authorization) {
    g_dbus_method_invocation_return_error(
        request->invocation, G_IO_ERROR, G_IO_ERROR_FAILED,
        "Authorization failed: %s",
        error ? error->message : "no authorization result");
    g_clear_error(&error);
  } else if (!polkit_authorization_result_get_is_authorized(authorization)) {
    g_dbus_method_invocation_return_dbus_error(
        request->invocation, "org.freedesktop.DBus.Error.AccessDenied",
        "Authorization denied");
  } else {
    context->authorized_senders[sender] = true;
    done(request->invocation);
  }

  if (authorization)
    g_object_unref(authorization);
  g_object_unref(request->invocation);
}

void finish_operation(ControlContext::ActiveOperation *operation) {
  ControlContext *context = operation->context;
  if (!operation->temp_path.empty())
    unlink(operation->temp_path.c_str());
  g_clear_object(&operation->invocation);

  // Destroying the active operation releases its runner handle and any
  // captured shared state.
  context->active.reset();
}

std::string make_valid_utf8(const std::string &value) {
  gchar *text = g_utf8_make_valid(value.data(), value.size());
  std::string result(text);
  g_free(text);
  return result;
}

void complete_operation(ControlContext::ActiveOperation *operation,
                        ManagedCommandResult result) {
  using Status = ManagedCommandStatus;

  // A cleanup failure means the service cannot prove that the backend stopped.
  // Refuse later operations until the service restarts.
  if (result.status == Status::cleanupFailed) {
    operation->context->cleanup_failed = true;
    if (!result.error.empty())
      g_message("Could not confirm backend cleanup: %s", result.error.c_str());
  }

  if (!operation->disconnected) {
    if (result.status == Status::cleanupFailed)
      reply_error(operation->invocation, "Unavailable",
                  "could not confirm backend cleanup; restart the control "
                  "service");
    else if (result.status == Status::unavailable)
      reply_error(operation->invocation, "Unavailable", result.error);
    else if (result.status == Status::busy)
      reply_error(operation->invocation, "Busy", result.error);
    else if (result.status == Status::timeout)
      reply_error(operation->invocation, "Timeout",
                  "control operation timed out");
    else if (result.status == Status::outputLimit)
      reply_error(operation->invocation, "CommandFailed",
                  "backend output exceeded limit");
    else if (result.status != Status::success) {
      const std::string output = make_valid_utf8(result.output);
      const auto graphics_exit = ClassifyGraphicsExit(result.exit_status);

      if (operation->graphics_operation &&
          graphics_exit == GraphicsExit::kBlocked) {
        reply_error(operation->invocation, "GraphicsBlocked",
                    output.empty() ? "graphics change was blocked before write"
                                   : output);
      } else if (operation->graphics_operation &&
                 graphics_exit == GraphicsExit::kPending) {
        reply_error(operation->invocation, "GraphicsPending",
                    output.empty()
                        ? "graphics policy changed but topology did not settle"
                        : output);
      } else if (operation->cli_exit_contract) {
        const auto cli_exit = ClassifyCliExit(result.exit_status);
        if (cli_exit == CliExit::kUnavailable) {
          reply_error(operation->invocation, "Unavailable",
                      output.empty()
                          ? "backend capability is unavailable"
                          : "backend capability is unavailable: " + output);
        } else if (cli_exit == CliExit::kFeatureNotFound) {
          reply_error(operation->invocation, "NotSupported",
                      output.empty()
                          ? "backend feature is not supported"
                          : "backend feature is not supported: " + output);
        } else {
          reply_error(operation->invocation, "CommandFailed",
                      output.empty() ? "backend command failed"
                                     : "backend command failed: " + output);
        }
      } else {
        reply_error(operation->invocation, "CommandFailed",
                    output.empty() ? "backend command failed"
                                   : "backend command failed: " + output);
      }
    } else if (operation->return_output) {
      g_dbus_method_invocation_return_value(
          operation->invocation,
          g_variant_new("(s)", make_valid_utf8(result.output).c_str()));
    } else {
      done(operation->invocation);
    }
  }

  finish_operation(operation);
}

enum class CommandBackend { kCli, kSystemctl, kGraphicsBoot };

// Start one managed command. The completion callback runs on this GLib
// context and owns the reply until the operation ends.
void start_operation(ControlContext *context, GDBusMethodInvocation *invocation,
                     const Command &command,
                     CommandBackend backend = CommandBackend::kCli,
                     const std::string &temp_path = {}, bool graphics = false,
                     bool return_output = false) {
  if (context->active) {
    if (!temp_path.empty())
      unlink(temp_path.c_str());
    reply_error(invocation, "Busy", "another control operation is running");
    return;
  }
  if (context->cleanup_failed || !context->runner) {
    if (!temp_path.empty())
      unlink(temp_path.c_str());
    reply_error(invocation, "Unavailable",
                "command runner unavailable; restart the control service");
    return;
  }

  const std::string *executable = &context->cli_path;
  if (backend == CommandBackend::kGraphicsBoot)
    executable = &context->graphics_boot_path;
  else if (backend == CommandBackend::kSystemctl)
    executable = &context->systemctl_path;

  auto operation = std::make_unique<ControlContext::ActiveOperation>();
  operation->context = context;
  operation->invocation = G_DBUS_METHOD_INVOCATION(g_object_ref(invocation));
  operation->temp_path = temp_path;
  const char *sender = g_dbus_method_invocation_get_sender(invocation);
  operation->sender = sender ? sender : "";
  operation->graphics_operation = graphics;
  operation->cli_exit_contract = backend == CommandBackend::kCli;
  operation->return_output = return_output;

  ControlContext::ActiveOperation *operation_ptr = operation.get();
  context->active = std::move(operation);

  // Graphics changes may wait for a display-manager transition, so they get a
  // longer runtime than ordinary feature writes.
  const unsigned runtime_seconds = graphics ? 35 : 10;
  operation_ptr->command = context->runner->Start(
      *executable, command.argv, runtime_seconds,
      [operation_ptr](ManagedCommandResult result) {
        complete_operation(operation_ptr, std::move(result));
      });
}

bool is_authorized(ControlContext *context, GDBusMethodInvocation *invocation) {
  if (context->authorized_senders.count(
          g_dbus_method_invocation_get_sender(invocation)))
    return true;
  g_dbus_method_invocation_return_dbus_error(
      invocation, "org.freedesktop.DBus.Error.AccessDenied",
      "Authorize must be called first");
  return false;
}

bool within_limit(const char *value, const char *label, std::string *error) {
  if (strnlen(value, input_limit + 1) <= input_limit)
    return true;
  *error = std::string(label) + " exceeds maximum length";
  return false;
}

// Write a validated payload to a private temporary file for legion_cli. The
// caller unlinks the file after the command ends.
bool write_payload(const std::vector<uint8_t> &bytes, std::string *path,
                   const char **error_name, std::string *error) {
  char temporary[] = "/tmp/legion-control-XXXXXX";
  const int descriptor = mkstemp(temporary);
  if (descriptor < 0) {
    *error_name = "Backend";
    *error = "cannot create private temporary file";
    return false;
  }
  fchmod(descriptor, 0600);

  size_t written = 0;
  while (written < bytes.size()) {
    const ssize_t count =
        write(descriptor, bytes.data() + written, bytes.size() - written);
    if (count < 0 && errno == EINTR)
      continue;
    if (count <= 0) {
      close(descriptor);
      unlink(temporary);
      *error_name = "Unavailable";
      *error = "could not write payload";
      return false;
    }
    written += static_cast<size_t>(count);
  }
  close(descriptor);
  *path = temporary;
  return true;
}
}  // namespace

void dispatch(ControlContext *context, const gchar *method,
              GVariant *parameters, GDBusMethodInvocation *invocation) {
  if (context->mode == ControlConnectionMode::portable &&
      RequiresInstalledIntegration(method)) {
    reply_error(invocation, "NotSupported",
                "this operation requires installed system integration");
    return;
  }

  std::string error;

  if (g_strcmp0(method, "SetFeature") == 0) {
    const gchar *feature_raw = nullptr;
    const gchar *value_raw = nullptr;
    g_variant_get(parameters, "(&s&s)", &feature_raw, &value_raw);
    if (!within_limit(feature_raw, "feature", &error) ||
        !within_limit(value_raw, "value", &error)) {
      reply_error(invocation, "InvalidArgs", error);
      return;
    }
    const std::string feature = feature_raw;
    const std::string value = value_raw;
    if (!ValidateFeature(feature, value, &error)) {
      reply_error(invocation, "InvalidArgs", error);
      return;
    }
    start_operation(context, invocation, FeatureCommand(feature, value));
    return;
  }

  if (g_strcmp0(method, "SetToggle") == 0) {
    const gchar *capability_raw = nullptr;
    gboolean enabled = FALSE;
    g_variant_get(parameters, "(&sb)", &capability_raw, &enabled);
    if (!within_limit(capability_raw, "toggle", &error)) {
      reply_error(invocation, "InvalidArgs", error);
      return;
    }
    const std::string capability = capability_raw;
    if (!ValidateToggle(capability, &error)) {
      reply_error(invocation, "InvalidArgs", error);
      return;
    }
    start_operation(context, invocation, ToggleCommand(capability, enabled));
    return;
  }

  if (g_strcmp0(method, "SetGraphicsMode") == 0) {
    const gchar *mode_raw = nullptr;
    g_variant_get(parameters, "(&s)", &mode_raw);
    if (!within_limit(mode_raw, "graphics mode", &error)) {
      reply_error(invocation, "InvalidArgs", error);
      return;
    }
    const std::string mode = mode_raw;
    if (!ValidateGraphicsMode(mode, &error)) {
      reply_error(invocation, "InvalidArgs", error);
      return;
    }
    start_operation(context, invocation, GraphicsModeCommand(mode),
                    CommandBackend::kCli, {}, true);
    return;
  }

  if (g_strcmp0(method, "RequestGraphicsModeAtBoot") == 0 ||
      g_strcmp0(method, "CancelGraphicsModeAtBoot") == 0 ||
      g_strcmp0(method, "GetGraphicsBootRequest") == 0) {
    if (context->graphics_boot_path.empty()) {
      reply_error(invocation, "Unavailable",
                  "next-boot graphics switching is not enabled");
      return;
    }

    Command command;
    if (g_strcmp0(method, "RequestGraphicsModeAtBoot") == 0) {
      const gchar *mode_raw = nullptr;
      g_variant_get(parameters, "(&s)", &mode_raw);
      if (!within_limit(mode_raw, "graphics mode", &error) ||
          !ValidateBootGraphicsMode(mode_raw, &error)) {
        reply_error(invocation, "InvalidArgs", error);
        return;
      }
      command = BootGraphicsRequestCommand(mode_raw);
    } else {
      command.argv = {g_strcmp0(method, "CancelGraphicsModeAtBoot") == 0
                          ? "cancel"
                          : "status"};
    }
    start_operation(context, invocation, command, CommandBackend::kGraphicsBoot,
                    {}, false, true);
    return;
  }

  if (g_strcmp0(method, "ApplyFanPreset") == 0) {
    const gchar *preset_raw = nullptr;
    g_variant_get(parameters, "(&s)", &preset_raw);
    if (!within_limit(preset_raw, "preset", &error)) {
      reply_error(invocation, "InvalidArgs", error);
      return;
    }
    const std::string preset = preset_raw;
    if (!ValidatePreset(preset, &error)) {
      reply_error(invocation, "InvalidArgs", error);
      return;
    }
    start_operation(context, invocation, PresetCommand(preset));
    return;
  }

  if (g_strcmp0(method, "ApplyCurrentFanPreset") == 0) {
    start_operation(context, invocation, CurrentPresetCommand());
    return;
  }

  if (g_strcmp0(method, "ApplyCustomConservation") == 0) {
    guint lower = 0;
    guint upper = 0;
    g_variant_get(parameters, "(uu)", &lower, &upper);
    if (!ValidateConservation(lower, upper, &error)) {
      reply_error(invocation, "InvalidArgs", error);
      return;
    }
    start_operation(context, invocation, ConservationCommand(lower, upper));
    return;
  }

  if (g_strcmp0(method, "ApplyFanCurve") == 0 ||
      g_strcmp0(method, "SetBootLogo") == 0) {
    const bool fan_curve = g_strcmp0(method, "ApplyFanCurve") == 0;
    const gsize maximum_size = fan_curve ? 64 * 1024 : 16 * 1024 * 1024;

    g_autoptr(GVariant) payload = nullptr;
    g_variant_get(parameters, "(@ay)", &payload);
    gsize length = 0;
    const guint8 *data = static_cast<const guint8 *>(
        g_variant_get_fixed_array(payload, &length, sizeof(guint8)));
    if (length == 0) {
      reply_error(invocation, "InvalidArgs", "payload must not be empty");
      return;
    }
    if (length > maximum_size) {
      reply_error(invocation, "InvalidArgs", "payload exceeds maximum size");
      return;
    }

    std::vector<uint8_t> bytes(data, data + length);
    std::string path;
    const char *error_name = nullptr;
    if (!write_payload(bytes, &path, &error_name, &error)) {
      reply_error(invocation, error_name, error);
      return;
    }
    start_operation(context, invocation,
                    fan_curve ? FileCommand(path) : BootLogoCommand(path),
                    CommandBackend::kCli, path);
    return;
  }

  if (g_strcmp0(method, "RestoreBootLogo") == 0) {
    start_operation(context, invocation, RestoreBootLogoCommand());
    return;
  }

  if (g_strcmp0(method, "SetServiceEnabled") == 0) {
    const gchar *service_raw = nullptr;
    gboolean enabled = FALSE;
    g_variant_get(parameters, "(&sb)", &service_raw, &enabled);
    if (!within_limit(service_raw, "service id", &error)) {
      reply_error(invocation, "InvalidArgs", error);
      return;
    }
    const std::string service_id = service_raw;
    if (!ValidateService(service_id, &error)) {
      reply_error(invocation, "InvalidArgs", error);
      return;
    }
    start_operation(context, invocation, ServiceCommand(service_id, enabled),
                    CommandBackend::kSystemctl);
    return;
  }

  reply_error(invocation, "InvalidArgs", "unknown method");
}

namespace {
void handle_method_call(GDBusConnection *, const gchar *, const gchar *,
                        const gchar *, const gchar *method,
                        GVariant *parameters, GDBusMethodInvocation *invocation,
                        gpointer data) {
  auto *context = static_cast<ControlContext *>(data);

  if (g_strcmp0(method, "GetCapabilities") == 0) {
    reply_capabilities(context, invocation);
    return;
  }

  if (g_strcmp0(method, "Authorize") == 0) {
    const std::string sender = g_dbus_method_invocation_get_sender(invocation);
    if (context->authorized_senders.count(sender)) {
      done(invocation);
      return;
    }
    if (!context->polkit_authority) {
      reply_error(invocation, "Authorization", "polkit unavailable");
      return;
    }
    if (context->pending_authorizations.count(sender)) {
      reply_error(invocation, "Busy", "authorization is already pending");
      return;
    }

    PolkitSubject *subject = polkit_system_bus_name_new(sender.c_str());
    PolkitDetails *details = polkit_details_new();
    auto *cancel = g_cancellable_new();
    context->pending_authorizations.emplace(
        sender, G_CANCELLABLE(g_object_ref(cancel)));

    auto *request = new AuthorizationRequest{
        context, G_DBUS_METHOD_INVOCATION(g_object_ref(invocation))};
    ++context->authorization_callbacks;
    polkit_authority_check_authorization(
        context->polkit_authority, subject,
        "io.github.prnice.legion-control.manage", details,
        POLKIT_CHECK_AUTHORIZATION_FLAGS_ALLOW_USER_INTERACTION, cancel,
        authorization_done, request);

    g_object_unref(details);
    g_object_unref(subject);
    g_object_unref(cancel);
    return;
  }

  if (!is_authorized(context, invocation))
    return;

  dispatch(context, method, parameters, invocation);
}
}  // namespace

const GDBusInterfaceVTable control_vtable = {
    handle_method_call, nullptr, nullptr, {nullptr}};
}  // namespace legion_control
