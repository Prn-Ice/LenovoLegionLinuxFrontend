#include "portable_lifetime.h"

#include <cstring>
#include <poll.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

namespace {
void test_owned_handles_survive_sender_close() {
  const int app = syscall(SYS_pidfd_open, getpid(), 0);
  g_assert_cmpint(app, >=, 0);
  GError *error = nullptr;
  const int channel =
      legion_control::CreatePortableLifetimeMessage(app, &error);
  g_assert_no_error(error);
  g_assert_cmpint(channel, >=, 0);
  close(app);
  legion_control::PortableLifetime lifetime;
  const bool received = legion_control::ReceivePortableLifetimeMessage(
      channel, &lifetime, &error);
  g_assert_no_error(error);
  g_assert_true(received);
  close(channel);
  g_assert_cmpuint(lifetime.owner, ==, getuid());
  pollfd handles[] = {{lifetime.app, POLLIN, 0},
                      {lifetime.launcher, POLLIN, 0}};
  g_assert_cmpint(poll(handles, 2, 0), ==, 0);
}

void test_dead_launcher_cannot_replay_queued_handles() {
  int transfer[2];
  g_assert_cmpint(
      socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, transfer), ==, 0);
  const pid_t child = fork();
  g_assert_cmpint(child, >=, 0);
  if (child == 0) {
    close(transfer[0]);
    const int app = syscall(SYS_pidfd_open, getppid(), 0);
    GError *error = nullptr;
    const int channel =
        legion_control::CreatePortableLifetimeMessage(app, &error);
    if (channel < 0)
      _exit(1);
    char marker = 'S';
    iovec bytes{&marker, 1};
    alignas(cmsghdr) unsigned char control[CMSG_SPACE(sizeof(int))] = {};
    msghdr message{};
    message.msg_iov = &bytes;
    message.msg_iovlen = 1;
    message.msg_control = control;
    message.msg_controllen = sizeof(control);
    auto *rights = CMSG_FIRSTHDR(&message);
    rights->cmsg_level = SOL_SOCKET;
    rights->cmsg_type = SCM_RIGHTS;
    rights->cmsg_len = CMSG_LEN(sizeof(int));
    memcpy(CMSG_DATA(rights), &channel, sizeof(channel));
    _exit(sendmsg(transfer[1], &message, MSG_NOSIGNAL) == 1 ? 0 : 1);
  }
  close(transfer[1]);
  char marker;
  iovec bytes{&marker, 1};
  alignas(cmsghdr) unsigned char control[CMSG_SPACE(sizeof(int))] = {};
  msghdr message{};
  message.msg_iov = &bytes;
  message.msg_iovlen = 1;
  message.msg_control = control;
  message.msg_controllen = sizeof(control);
  g_assert_cmpint(recvmsg(transfer[0], &message, MSG_CMSG_CLOEXEC), ==, 1);
  int channel;
  g_assert_nonnull(CMSG_FIRSTHDR(&message));
  memcpy(&channel, CMSG_DATA(CMSG_FIRSTHDR(&message)), sizeof(channel));
  int status;
  g_assert_cmpint(waitpid(child, &status, 0), ==, child);
  g_assert_true(WIFEXITED(status));
  g_assert_cmpint(WEXITSTATUS(status), ==, 0);
  close(transfer[0]);
  GError *error = nullptr;
  legion_control::PortableLifetime lifetime;
  g_assert_false(legion_control::ReceivePortableLifetimeMessage(
      channel, &lifetime, &error));
  g_assert_nonnull(error);
  g_clear_error(&error);
  close(channel);
  g_assert_cmpint(lifetime.app, ==, -1);
  g_assert_cmpint(lifetime.launcher, ==, -1);
}

void test_rejects_non_pidfd_and_malformed_message() {
  int pipe_fds[2];
  g_assert_cmpint(pipe(pipe_fds), ==, 0);
  GError *error = nullptr;
  const int channel =
      legion_control::CreatePortableLifetimeMessage(pipe_fds[0], &error);
  g_assert_no_error(error);
  legion_control::PortableLifetime lifetime;
  g_assert_false(legion_control::ReceivePortableLifetimeMessage(
      channel, &lifetime, &error));
  g_assert_nonnull(error);
  g_clear_error(&error);
  close(channel);
  close(pipe_fds[0]);
  close(pipe_fds[1]);
  int sockets[2];
  g_assert_cmpint(
      socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, sockets), ==, 0);
  g_assert_cmpint(send(sockets[0], "bad", 3, MSG_NOSIGNAL), ==, 3);
  g_assert_false(legion_control::ReceivePortableLifetimeMessage(
      sockets[1], &lifetime, &error));
  g_assert_nonnull(error);
  g_clear_error(&error);
  close(sockets[0]);
  close(sockets[1]);
}
void test_dead_app_cannot_replay_queued_handles() {
  int release[2];
  g_assert_cmpint(pipe(release), ==, 0);
  const pid_t child = fork();
  g_assert_cmpint(child, >=, 0);
  if (child == 0) {
    close(release[1]);
    char byte;
    _exit(read(release[0], &byte, 1) == 1 ? 0 : 1);
  }
  close(release[0]);
  const int app = syscall(SYS_pidfd_open, child, 0);
  g_assert_cmpint(app, >=, 0);
  GError *error = nullptr;
  const int channel =
      legion_control::CreatePortableLifetimeMessage(app, &error);
  g_assert_no_error(error);
  close(app);
  g_assert_cmpint(write(release[1], "x", 1), ==, 1);
  close(release[1]);
  int status;
  g_assert_cmpint(waitpid(child, &status, 0), ==, child);
  g_assert_true(WIFEXITED(status));
  g_assert_cmpint(WEXITSTATUS(status), ==, 0);
  legion_control::PortableLifetime lifetime;
  g_assert_false(legion_control::ReceivePortableLifetimeMessage(
      channel, &lifetime, &error));
  g_assert_nonnull(error);
  g_clear_error(&error);
  close(channel);
}
} // namespace

int main(int argc, char **argv) {
  g_test_init(&argc, &argv, nullptr);
  g_test_add_func("/portable-lifetime/owned-handles",
                  test_owned_handles_survive_sender_close);
  g_test_add_func("/portable-lifetime/dead-launcher-message",
                  test_dead_launcher_cannot_replay_queued_handles);
  g_test_add_func("/portable-lifetime/dead-app-message",
                  test_dead_app_cannot_replay_queued_handles);
  g_test_add_func("/portable-lifetime/malformed-handles",
                  test_rejects_non_pidfd_and_malformed_message);
  return g_test_run();
}
