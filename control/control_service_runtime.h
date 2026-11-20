#pragma once

#include "managed_command.h"
#include <map>
#include <polkit/polkit.h>

namespace legion_control {
// Installed mode owns a system service and may start persistent services or
// queue a next-boot graphics request. Portable mode serves one app session and
// supports only the operations that session can perform safely.
enum class ControlConnectionMode { installed, portable };

// State shared by the installed control service and the portable control
// session. Both use the same dispatcher so validation and error handling stay
// identical; only the transport and available capabilities differ.
struct ControlContext {
  GMainLoop *loop = nullptr;
  GDBusNodeInfo *info = nullptr;
  GDBusConnection *connection = nullptr;
  guint registration_id = 0;
  guint owner_id = 0;
  guint name_watch_id = 0;
  std::string cli_path;
  std::string systemctl_path;
  std::string graphics_boot_path;
  ControlConnectionMode mode = ControlConnectionMode::installed;

  // D-Bus senders that completed Authorize. Polkit checks are tracked
  // separately so a client disconnect can cancel its prompt.
  std::map<std::string, bool> authorized_senders;
  std::map<std::string, GCancellable *> pending_authorizations;
  PolkitAuthority *polkit_authority = nullptr;

  std::shared_ptr<ManagedCommandRunner> runner;
  bool cleanup_failed = false;
  unsigned authorization_callbacks = 0;

  // Only one hardware operation runs at a time. The runner callback owns this
  // record until the operation completes and the reply is sent.
  struct ActiveOperation {
    ControlContext *context;
    GDBusMethodInvocation *invocation;
    std::shared_ptr<ManagedCommandOperation> command;
    std::string temp_path;
    std::string sender;
    bool disconnected = false;
    bool graphics_operation = false;
    bool cli_exit_contract = false;
    bool return_output = false;
  };

  std::unique_ptr<ActiveOperation> active;
};

// Send an empty reply, or a D-Bus error whose name is scoped to this interface.
void reply_error(GDBusMethodInvocation *invocation, const char *name,
                 const std::string &message);
void done(GDBusMethodInvocation *invocation);
void reply_capabilities(ControlContext *context,
                        GDBusMethodInvocation *invocation);

// Check the method name, validate its arguments, and start the matching
// operation. The D-Bus handler performs the common Authorize check first.
void dispatch(ControlContext *context, const gchar *method,
              GVariant *parameters, GDBusMethodInvocation *invocation);
extern const GDBusInterfaceVTable control_vtable;
}  // namespace legion_control
