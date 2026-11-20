#pragma once

#include <functional>
#include <gio/gio.h>
#include <string>

namespace legion_control {
struct ControlEndpoint {
  std::string address;
  std::string unit;
  guint32 helper_pid = 0;
  std::string bus_name;
};

bool ValidateControlEndpoint(const ControlEndpoint &, GError **error);

// The caller owns the returned connection. The fixed host system bus supplies
// the unit's MainPID and helper's host UID/PID. Kernel socket credentials and
// a pinned process descriptor bind that identity before EXTERNAL.
GDBusConnection *ConnectControlPeerSync(const ControlEndpoint &,
                                         GCancellable *, GError **error,
                                         bool *server_verified = nullptr);

// Runs connection setup off the UI thread, with a five-second deadline.
// Supply a non-null cancellable.
// Completion owns the connection or error and runs on the calling GLib context.
using ControlPeerCompletion = std::function<void(GDBusConnection *, GError *)>;
void ConnectControlPeer(const ControlEndpoint &, GCancellable *,
                         ControlPeerCompletion);
}  // namespace legion_control
