#pragma once

#include <functional>
#include <gio/gio.h>
#include <string>

namespace legion_control {
struct PortableEndpoint {
  std::string address;
  std::string unit;
  guint32 helper_pid = 0;
};

bool ValidatePortableEndpoint(const PortableEndpoint &, GError **error);

// The caller owns the returned connection. The fixed host system bus supplies
// the unit's MainPID; kernel socket credentials are checked before EXTERNAL.
GDBusConnection *ConnectPortablePeerSync(const PortableEndpoint &,
                                         GCancellable *, GError **error,
                                         bool *server_verified = nullptr);

// Runs connection setup off the UI thread, with a five-second deadline.
// Supply a non-null cancellable.
// Completion owns the connection or error and runs on the calling GLib context.
using PortablePeerCompletion = std::function<void(GDBusConnection *, GError *)>;
void ConnectPortablePeer(const PortableEndpoint &, GCancellable *,
                         PortablePeerCompletion);
} // namespace legion_control
