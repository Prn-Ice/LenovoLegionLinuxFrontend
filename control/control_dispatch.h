#pragma once

#include "managed_command.h"

namespace legion_control {
struct ControlContext {
  GMainLoop *loop = nullptr;
  GDBusNodeInfo *info = nullptr;
  GDBusConnection *connection = nullptr;
  guint registration_id = 0;
  std::string cli_path;
  std::shared_ptr<ManagedCommandRunner> runner;
  bool cleanup_failed = false;

  // Only one hardware operation runs at a time. The runner callback owns this
  // record until the operation completes and the reply is sent.
  struct ActiveOperation {
    ControlContext *context;
    GDBusMethodInvocation *invocation;
    std::shared_ptr<ManagedCommandOperation> command;
    std::string temp_path;
    bool disconnected = false;
    bool graphics_operation = false;
  };

  std::unique_ptr<ActiveOperation> active;
};

// Send an empty reply, or a D-Bus error whose name is scoped to this interface.
void reply_error(GDBusMethodInvocation *invocation, const char *name,
                 const std::string &message);
void done(GDBusMethodInvocation *invocation);
void reply_capabilities(GDBusMethodInvocation *invocation);

// Check the method name, validate its arguments, and start the matching
// operation. The D-Bus handler performs the common Authorize check first.
void dispatch(ControlContext *context, const gchar *method,
              GVariant *parameters, GDBusMethodInvocation *invocation);
}  // namespace legion_control
