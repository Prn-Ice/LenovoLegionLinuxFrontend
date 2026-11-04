#pragma once

#include <string>
#include <sys/types.h>

// VM-only integration of the approved startup path and production dispatcher.
// stdin must be the app's pinned pidfd, supplied by the launcher through
// systemd.
int RunPortableControlProbe(pid_t client_pid, uid_t client_uid,
                            const std::string &parent_unit, int launcher_pidfd);
bool ValidPortableProbeUnit(const std::string &unit);
