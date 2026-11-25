#pragma once

#include <gio/gio.h>
#include <sys/types.h>

namespace legion_control {
struct HelperLifetime {
  int app = -1;
  int launcher = -1;
  uid_t owner = static_cast<uid_t>(-1);
  HelperLifetime() = default;
  HelperLifetime(const HelperLifetime &) = delete;
  HelperLifetime &operator=(const HelperLifetime &) = delete;
  ~HelperLifetime();
};

// The returned socket owns a queued message containing the app's pidfd and a
// pidfd for this launcher. The caller owns the socket; it uses no PID path.
int CreateHelperLifetimeMessage(int app_pidfd, GError **error);
// Receives owned pidfds, validates the sending launcher, and rejects dead
// processes even if the launcher queued the message before authentication
// completed.
bool ReceiveHelperLifetimeMessage(int socket, HelperLifetime *lifetime,
                                    GError **error);
}  // namespace legion_control
