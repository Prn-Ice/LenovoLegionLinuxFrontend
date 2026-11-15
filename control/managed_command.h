#pragma once

#include <functional>
#include <gio/gio.h>
#include <memory>
#include <string>
#include <vector>

namespace legion_control {
enum class ManagedCommandStatus {
  success,
  busy,
  commandFailed,
  unavailable,
  timeout,
  outputLimit,
  cleanupFailed
};
struct ManagedCommandResult {
  std::string output;
  std::string error;
  int exit_status = -1;
  ManagedCommandStatus status = ManagedCommandStatus::commandFailed;
};

class ManagedCommandOperation {
public:
  virtual ~ManagedCommandOperation() = default;
  virtual void Cancel() = 0;
};

class ManagedCommandRunner {
public:
  using Completion = std::function<void(ManagedCommandResult)>;
  virtual ~ManagedCommandRunner() = default;
  virtual std::shared_ptr<ManagedCommandOperation>
  Start(const std::string &executable, const std::vector<std::string> &argv,
        unsigned runtime_seconds, Completion completion) = 0;
};

// Start and completion use the owning GLib context; completion is asynchronous.
// Operations retain the connection and drain their owned callbacks.
// Supply a dedicated manager connection: uncertain cleanup closes it to release
// systemd references. Do not share it with the exported control interface.
// state_directory is the installed helper's optional systemd StateDirectory
// name. operation_lock_path coordinates installed and portable helpers. Its
// empty regular file is also passed to systemd as stdin, retaining the lock if
// the helper dies while backend processes are still being stopped.
std::shared_ptr<ManagedCommandRunner>
CreateManagedCommandRunner(GDBusConnection *manager_connection,
                           const std::string &parent_unit,
                           const std::string &state_directory = {},
                           const std::string &operation_lock_path = {});
} // namespace legion_control
