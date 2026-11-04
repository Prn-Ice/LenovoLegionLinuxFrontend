#include "portable_lifetime.h"

#include <cerrno>
#include <cstring>
#include <fstream>
#include <poll.h>
#include <sstream>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <vector>

namespace legion_control {
namespace {
bool Failure(GError **error, const char *message) {
  g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_FAILED, message);
  return false;
}
pid_t PidfdProcess(int descriptor) {
  std::ifstream info("/proc/self/fdinfo/" + std::to_string(descriptor));
  std::string line;
  pid_t process = -1;
  while (std::getline(info, line)) {
    if (line.compare(0, 4, "Pid:") == 0) {
      std::istringstream value(line.substr(4));
      value >> process;
    }
  }
  pollfd state{descriptor, POLLIN, 0};
  return process > 1 && poll(&state, 1, 0) == 0 ? process : -1;
}
} // namespace

PortableLifetime::~PortableLifetime() {
  if (app >= 0)
    close(app);
  if (launcher >= 0)
    close(launcher);
}

int CreatePortableLifetimeMessage(int app_pidfd, GError **error) {
  const int self = syscall(SYS_pidfd_open, getpid(), 0);
  if (self < 0) {
    Failure(error, "could not pin launcher lifetime");
    return -1;
  }
  int channel[2];
  if (socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, channel) != 0) {
    close(self);
    Failure(error, "could not create lifetime channel");
    return -1;
  }
  char marker = 'L';
  iovec bytes{&marker, 1};
  alignas(cmsghdr) unsigned char control[CMSG_SPACE(2 * sizeof(int))] = {};
  msghdr message{};
  message.msg_iov = &bytes;
  message.msg_iovlen = 1;
  message.msg_control = control;
  message.msg_controllen = sizeof(control);
  auto *rights = CMSG_FIRSTHDR(&message);
  rights->cmsg_level = SOL_SOCKET;
  rights->cmsg_type = SCM_RIGHTS;
  rights->cmsg_len = CMSG_LEN(2 * sizeof(int));
  const int handles[] = {app_pidfd, self};
  memcpy(CMSG_DATA(rights), handles, sizeof(handles));
  const bool sent = sendmsg(channel[0], &message, MSG_NOSIGNAL) == 1;
  close(self);
  close(channel[0]);
  if (!sent) {
    close(channel[1]);
    Failure(error, "could not send pinned process handles");
    return -1;
  }
  return channel[1];
}

bool ReceivePortableLifetimeMessage(int socket, PortableLifetime *lifetime,
                                    GError **error) {
  if (lifetime->app >= 0 || lifetime->launcher >= 0)
    return Failure(error, "process handles were already received");
  int type = 0;
  socklen_t size = sizeof(type);
  ucred sender{};
  socklen_t sender_size = sizeof(sender);
  if (getsockopt(socket, SOL_SOCKET, SO_TYPE, &type, &size) != 0 ||
      type != SOCK_SEQPACKET ||
      getsockopt(socket, SOL_SOCKET, SO_PEERCRED, &sender, &sender_size) != 0)
    return Failure(error,
                   "lifetime channel is not a private Unix packet socket");
  pollfd ready{socket, POLLIN, 0};
  if (poll(&ready, 1, 3000) <= 0)
    return Failure(error, "pinned process handles did not arrive");
  char marker = 0;
  iovec bytes{&marker, 1};
  alignas(cmsghdr) unsigned char control[CMSG_SPACE(4 * sizeof(int))] = {};
  msghdr message{};
  message.msg_iov = &bytes;
  message.msg_iovlen = 1;
  message.msg_control = control;
  message.msg_controllen = sizeof(control);
  const auto count = recvmsg(socket, &message, MSG_CMSG_CLOEXEC | MSG_DONTWAIT);
  std::vector<int> handles;
  bool valid = count == 1 && marker == 'L' &&
               !(message.msg_flags & (MSG_CTRUNC | MSG_TRUNC));
  for (auto *rights = CMSG_FIRSTHDR(&message); rights;
       rights = CMSG_NXTHDR(&message, rights)) {
    if (rights->cmsg_level != SOL_SOCKET || rights->cmsg_type != SCM_RIGHTS ||
        rights->cmsg_len < CMSG_LEN(0)) {
      valid = false;
      continue;
    }
    const auto length = rights->cmsg_len - CMSG_LEN(0);
    if (length % sizeof(int))
      valid = false;
    for (size_t offset = 0; offset + sizeof(int) <= length;
         offset += sizeof(int)) {
      int descriptor;
      memcpy(&descriptor, CMSG_DATA(rights) + offset, sizeof(descriptor));
      handles.push_back(descriptor);
    }
  }
  valid = valid && handles.size() == 2;
  if (valid)
    valid =
        PidfdProcess(handles[0]) > 1 && PidfdProcess(handles[1]) == sender.pid;
  if (!valid) {
    for (int descriptor : handles)
      close(descriptor);
    return Failure(
        error, "lifetime handles are invalid or their processes have exited");
  }
  lifetime->app = handles[0];
  lifetime->launcher = handles[1];
  lifetime->owner = sender.uid;
  return true;
}
} // namespace legion_control
