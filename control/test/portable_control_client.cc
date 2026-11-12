#include "portable_peer.h"
#include "test_vm_guard.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <gio/gio.h>
#include <gio/gunixinputstream.h>
#include <glib-unix.h>
#include <iostream>
#include <poll.h>
#include <signal.h>
#include <sstream>
#include <string>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/un.h>
#include <unistd.h>

namespace {
constexpr char interface[] = "io.github.prnice.LegionControl1";
constexpr char path[] = "/io/github/prnice/LegionControl1";

int FakePeer(const char *path, bool stall = false) {
  sockaddr_un address{};
  address.sun_family = AF_UNIX;
  if (strlen(path) >= sizeof(address.sun_path))
    return 2;
  memcpy(address.sun_path, path, strlen(path) + 1);
  const int listener = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
  if (listener < 0 ||
      bind(listener, reinterpret_cast<sockaddr *>(&address), sizeof(address)) !=
          0 ||
      chmod(path, 0666) != 0 || listen(listener, 1) != 0)
    return 1;
  puts("FAKE_READY");
  fflush(stdout);
  const int peer = accept4(listener, nullptr, nullptr, SOCK_CLOEXEC);
  char byte;
  bool refused = peer >= 0 && read(peer, &byte, 1) == 0;
  if (stall && peer >= 0 && !refused) {
    puts("AUTH_SEEN");
    fflush(stdout);
    while (read(peer, &byte, 1) > 0) {
    }
    puts("AUTH_CLOSED");
    refused = true;
  }
  if (peer >= 0)
    close(peer);
  close(listener);
  unlink(path);
  if (refused && !stall)
    puts("FAKE_CLOSED_BEFORE_AUTH");
  return refused ? 0 : 1;
}

bool ReadLine(int descriptor, std::string *line) {
  const auto deadline = g_get_monotonic_time() + 20000000;
  line->clear();
  while (line->size() < 4096) {
    const auto remaining = deadline - g_get_monotonic_time();
    if (remaining <= 0)
      return false;
    pollfd input{descriptor, POLLIN, 0};
    if (poll(&input, 1, int(remaining / 1000) + 1) <= 0)
      return false;
    char byte;
    if (read(descriptor, &byte, 1) != 1)
      return false;
    if (byte == '\n')
      return true;
    line->push_back(byte);
  }
  return false;
}

GDBusConnection *Connect(const std::string &address, const std::string &unit,
                         guint32 expected_pid, int *failure) {
  GError *error = nullptr;
  bool verified = false;
  auto *connection = legion_control::ConnectPortablePeerSync(
      {address, unit, expected_pid}, nullptr, &error, &verified);
  *failure = verified ? 7 : 8;
  g_clear_error(&error);
  return connection;
}

GDBusConnection *ConnectAsync(const legion_control::PortableEndpoint &endpoint,
                              GError **error, bool cancel_by_signal = false) {
  auto *loop = g_main_loop_new(nullptr, FALSE);
  auto *cancel = g_cancellable_new();
  const guint watch = cancel_by_signal
                          ? g_unix_signal_add(
                                SIGUSR1,
                                [](gpointer data) -> gboolean {
                                  g_cancellable_cancel(G_CANCELLABLE(data));
                                  return G_SOURCE_CONTINUE;
                                },
                                cancel)
                          : 0;
  GDBusConnection *peer = nullptr;
  legion_control::ConnectPortablePeer(
      endpoint, cancel, [&](GDBusConnection *connection, GError *failure) {
        peer = connection;
        if (failure)
          g_propagate_error(error, failure);
        g_main_loop_quit(loop);
      });
  if (cancel_by_signal) {
    printf("CONNECTING pid=%d\n", getpid());
    fflush(stdout);
  }
  g_main_loop_run(loop);
  if (watch)
    g_source_remove(watch);
  g_object_unref(cancel);
  g_main_loop_unref(loop);
  return peer;
}

std::string Call(GDBusConnection *connection, const char *method,
                 GVariant *arguments,
                 const GVariantType *reply_type = G_VARIANT_TYPE("()")) {
  GError *error = nullptr;
  auto *reply = g_dbus_connection_call_sync(
      connection, nullptr, path, interface, method, arguments, reply_type,
      G_DBUS_CALL_FLAGS_NONE, 45000, nullptr, &error);
  if (!reply) {
    g_printerr("%s failed: %s\n", method,
               error ? error->message : "unknown transport error");
    char *remote = error ? g_dbus_error_get_remote_error(error) : nullptr;
    std::string name = remote ? remote : "transport-error";
    g_free(remote);
    g_clear_error(&error);
    return name;
  }
  if (g_str_equal(method, "GetCapabilities")) {
    guint32 version;
    GVariant *capabilities;
    g_variant_get(reply, "(u@as)", &version, &capabilities);
    bool interactive = false, persistent = false;
    GVariantIter values;
    g_variant_iter_init(&values, capabilities);
    const char *value;
    while (g_variant_iter_next(&values, "&s", &value)) {
      interactive |= g_str_equal(value, "interactive-control");
      persistent |= g_str_equal(value, "persistent-services") ||
                    g_str_equal(value, "next-boot-graphics");
    }
    g_variant_unref(capabilities);
    g_variant_unref(reply);
    return version == 1 && interactive && !persistent ? ""
                                                      : "incompatible-protocol";
  }
  g_variant_unref(reply);
  return {};
}

bool IdleClosed(GDBusConnection *connection) {
  if (g_dbus_connection_is_closed(connection))
    return true;
  GMainLoop *loop = g_main_loop_new(nullptr, FALSE);
  const gulong closed = g_signal_connect(
      connection, "closed",
      G_CALLBACK(+[](GDBusConnection *, gboolean, GError *, gpointer data) {
        g_main_loop_quit(static_cast<GMainLoop *>(data));
      }),
      loop);
  const guint timeout = g_timeout_add(
      8000,
      [](gpointer data) -> gboolean {
        g_main_loop_quit(static_cast<GMainLoop *>(data));
        return G_SOURCE_CONTINUE;
      },
      loop);
  g_main_loop_run(loop);
  g_source_remove(timeout);
  g_signal_handler_disconnect(connection, closed);
  g_main_loop_unref(loop);
  return g_dbus_connection_is_closed(connection);
}
} // namespace

int main(int argc, char **argv) {
  if (!InControlTestVm())
    return 2;
  if (argc == 3 && std::string(argv[1]) == "--stall-peer" && getuid() == 0)
    return FakePeer(argv[2], true);
  if (getuid() == 0 || getuid() != geteuid())
    return 2;
  if (argc == 5 && (std::string(argv[1]) == "--connection-timeout" ||
                    std::string(argv[1]) == "--connection-cancel")) {
    const bool cancel = std::string(argv[1]) == "--connection-cancel";
    const auto started = g_get_monotonic_time();
    GError *error = nullptr;
    auto *peer = ConnectAsync(
        {argv[2], argv[3], static_cast<guint32>(strtoul(argv[4], nullptr, 10))},
        &error, cancel);
    const auto elapsed = g_get_monotonic_time() - started;
    const bool expected =
        !peer && elapsed < 10000000 &&
        g_error_matches(error, G_IO_ERROR,
                        cancel ? G_IO_ERROR_CANCELLED : G_IO_ERROR_TIMED_OUT);
    if (peer)
      g_object_unref(peer);
    g_clear_error(&error);
    puts(expected ? "CONNECTION_ENDED" : "UNEXPECTED_CONNECTION_RESULT");
    return expected ? 0 : 1;
  }
  if (argc == 3 && std::string(argv[1]) == "--fake-peer")
    return FakePeer(argv[2]);
  if (argc == 5 && std::string(argv[1]) == "--intrude") {
    int failure;
    auto *connection =
        Connect(argv[2], argv[3],
                static_cast<guint32>(strtoul(argv[4], nullptr, 10)), &failure);
    if (!connection)
      return failure;
    g_dbus_connection_close_sync(connection, nullptr, nullptr);
    g_object_unref(connection);
    return 0;
  }
  if (argc != 2)
    return 2;
  GError *error = nullptr;
  auto *launcher = g_subprocess_new(G_SUBPROCESS_FLAGS_STDOUT_PIPE, &error,
                                    argv[1], "--control", nullptr);
  if (!launcher) {
    g_clear_error(&error);
    return 1;
  }
  const int descriptor = g_unix_input_stream_get_fd(
      G_UNIX_INPUT_STREAM(g_subprocess_get_stdout_pipe(launcher)));
  std::string line, address, unit, cli;
  guint32 helper_pid = 0;
  while (ReadLine(descriptor, &line)) {
    if (line.compare(0, 14, "CONTROL_READY ") != 0)
      continue;
    std::istringstream fields(line);
    std::string field;
    while (fields >> field) {
      if (field.compare(0, 7, "helper=") == 0)
        helper_pid =
            static_cast<guint32>(strtoul(field.c_str() + 7, nullptr, 10));
      if (field.compare(0, 5, "unit=") == 0)
        unit = field.substr(5);
      if (field.compare(0, 4, "cli=") == 0)
        cli = field.substr(4);
      if (field.compare(0, 8, "address=") == 0)
        address = field.substr(8);
    }
    break;
  }
  if (address.empty() || unit.empty() || !helper_pid) {
    g_subprocess_send_signal(launcher, SIGTERM);
    g_subprocess_wait(launcher, nullptr, nullptr);
    g_object_unref(launcher);
    return 1;
  }
  printf("CLIENT_READY client=%d helper=%u unit=%s address=%s cli=%s\n",
         getpid(), helper_pid, unit.c_str(), address.c_str(), cli.c_str());
  fflush(stdout);
  GDBusConnection *connection = nullptr;
  while (std::getline(std::cin, line)) {
    std::string result;
    if (line == "connect") {
      GError *error = nullptr;
      connection = ConnectAsync({address, unit, helper_pid}, &error);
      g_clear_error(&error);
      result = connection ? Call(connection, "GetCapabilities", nullptr,
                                 G_VARIANT_TYPE("(uas)"))
                          : "authentication-failed";
    } else if (!connection)
      result = "not-connected";
    else if (line == "authorize")
      result = Call(connection, "Authorize", nullptr);
    else if (line == "enable" || line == "disable")
      result =
          Call(connection, "SetToggle",
               g_variant_new("(sb)", "battery-conservation", line == "enable"));
    else if (line == "invalid")
      result = Call(connection, "SetToggle",
                    g_variant_new("(sb)", "unlisted-toggle", TRUE));
    else if (line == "persistent")
      result = Call(connection, "SetServiceEnabled",
                    g_variant_new("(sb)", "legiond_stack", TRUE));
    else if (line == "fan") {
      constexpr char payload[] = "synthetic fan data\n";
      auto *bytes = g_variant_new_fixed_array(G_VARIANT_TYPE_BYTE, payload,
                                              sizeof(payload) - 1, 1);
      result = Call(connection, "ApplyFanCurve", g_variant_new("(@ay)", bytes));
    } else if (line == "resume-after-idle") {
      // Cross the connection setup deadline before using the live session.
      auto *loop = g_main_loop_new(nullptr, FALSE);
      g_timeout_add(
          6000,
          [](gpointer data) -> gboolean {
            g_main_loop_quit(static_cast<GMainLoop *>(data));
            return G_SOURCE_REMOVE;
          },
          loop);
      g_main_loop_run(loop);
      g_main_loop_unref(loop);
      result =
          Call(connection, "GetCapabilities", nullptr, G_VARIANT_TYPE("(uas)"));
    } else if (line == "idle")
      result = IdleClosed(connection) ? "" : "idle-helper-did-not-close";
    else if (line == "close")
      break;
    else
      result = "unknown-test-command";
    printf("%s %s%s%s\n", result.empty() ? "PASS" : "ERROR", line.c_str(),
           result.empty() ? "" : " ", result.c_str());
    fflush(stdout);
  }
  if (connection) {
    if (!g_dbus_connection_is_closed(connection))
      g_dbus_connection_close_sync(connection, nullptr, nullptr);
    g_object_unref(connection);
  }
  g_subprocess_send_signal(launcher, SIGTERM);
  g_subprocess_wait(launcher, nullptr, nullptr);
  g_object_unref(launcher);
  puts("CLIENT_CLOSED");
  return 0;
}
