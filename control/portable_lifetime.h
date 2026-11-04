#pragma once

#include <gio/gio.h>
#include <sys/types.h>

namespace legion_control {
struct PortableLifetime {
  int app = -1;
  int launcher = -1;
  uid_t owner = static_cast<uid_t>(-1);
  PortableLifetime() = default;
  PortableLifetime(const PortableLifetime &) = delete;
  PortableLifetime &operator=(const PortableLifetime &) = delete;
  ~PortableLifetime();
};

// The returned socket owns a queued message containing the app's pidfd and a
// pidfd for this launcher. The caller owns the socket; no PID path is used.
int CreatePortableLifetimeMessage(int app_pidfd, GError **error);
// Receives owned pidfds, validates the sending launcher, and rejects dead
// processes even if the message was queued before authentication completed.
bool ReceivePortableLifetimeMessage(int socket, PortableLifetime *lifetime,
                                    GError **error);
} // namespace legion_control
