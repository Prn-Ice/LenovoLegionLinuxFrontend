#pragma once

#include "managed_command.h"
#include <map>
#include <polkit/polkit.h>

namespace legion_control {
enum class ControlConnectionMode { installed, portable };
struct ControlContext {
  GMainLoop *loop = nullptr;
  GDBusNodeInfo *info = nullptr;
  GDBusConnection *conn = nullptr;
  guint reg = 0, owner = 0, names = 0;
  std::string cli, systemctl, graphics_boot;
  ControlConnectionMode mode = ControlConnectionMode::installed;
  std::map<std::string, bool> auth;
  std::map<std::string, GCancellable *> pending;
  PolkitAuthority *authority = nullptr;
  std::shared_ptr<legion_control::ManagedCommandRunner> runner;
  bool cleanup_failed = false;
  unsigned authorization_callbacks = 0;
  struct ActiveOperation {
    ControlContext *ctx;
    GDBusMethodInvocation *invocation;
    std::shared_ptr<legion_control::ManagedCommandOperation> command;
    std::string temp_path;
    std::string sender;
    bool disconnected = false;
    bool graphics_operation = false;
    bool return_output = false;
  };
  std::unique_ptr<ActiveOperation> active;
};
void reply_error(GDBusMethodInvocation *, const char *, const std::string &);
void done(GDBusMethodInvocation *);
void reply_capabilities(ControlContext *, GDBusMethodInvocation *);
void dispatch(ControlContext *, const gchar *, GVariant *,
              GDBusMethodInvocation *);
extern const GDBusInterfaceVTable control_vtable;
} // namespace legion_control
