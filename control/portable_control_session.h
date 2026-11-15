#pragma once

#include <string>
#include <sys/types.h>

// stdin is the pinned app pidfd received from the approved launcher.
// The bootstrap supplies its fixed trusted CLI; protocol callers cannot choose
// it.
int RunPortableControlSession(pid_t client_pid, uid_t client_uid,
                              const std::string &parent_unit,
                              int launcher_pidfd, const std::string &cli,
                              unsigned idle_seconds);
