#include "test_vm_guard.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <gio/gio.h>
#include <gio/gunixinputstream.h>
#include <iostream>
#include <poll.h>
#include <signal.h>
#include <sstream>
#include <string>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/un.h>
#include <unistd.h>

namespace {
constexpr char interface[] = "io.github.prnice.LegionControl1";
constexpr char path[] = "/io/github/prnice/LegionControl1";

int FakePeer(const char *path) {
  sockaddr_un address{};
  address.sun_family = AF_UNIX;
  if (strlen(path) >= sizeof(address.sun_path))
    return 2;
  memcpy(address.sun_path, path, strlen(path) + 1);
  const int listener = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
  if (listener < 0 ||
      bind(listener, reinterpret_cast<sockaddr *>(&address), sizeof(address)) !=
          0 ||
      listen(listener, 1) != 0)
    return 1;
  puts("FAKE_READY");
  fflush(stdout);
  const int peer = accept4(listener, nullptr, nullptr, SOCK_CLOEXEC);
  char byte;
  const bool refused = peer >= 0 && read(peer, &byte, 1) == 0;
  if (peer >= 0)
    close(peer);
  close(listener);
  unlink(path);
  if (refused)
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
  *failure = 8;
  GError *error = nullptr;
  auto *manager = g_dbus_connection_new_for_address_sync(
      "unix:path=/run/dbus/system_bus_socket",
      static_cast<GDBusConnectionFlags>(
          G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT |
          G_DBUS_CONNECTION_FLAGS_MESSAGE_BUS_CONNECTION),
      nullptr, nullptr, &error);
  if (!manager) {
    g_clear_error(&error);
    return nullptr;
  }
  auto *location = g_dbus_connection_call_sync(
      manager, "org.freedesktop.systemd1", "/org/freedesktop/systemd1",
      "org.freedesktop.systemd1.Manager", "GetUnit",
      g_variant_new("(s)", unit.c_str()), G_VARIANT_TYPE("(o)"),
      G_DBUS_CALL_FLAGS_NO_AUTO_START, 2000, nullptr, &error);
  const char *unit_path = nullptr;
  if (location)
    g_variant_get(location, "(&o)", &unit_path);
  GVariant *pid_reply =
      location ? g_dbus_connection_call_sync(
                     manager, "org.freedesktop.systemd1", unit_path,
                     "org.freedesktop.DBus.Properties", "Get",
                     g_variant_new("(ss)", "org.freedesktop.systemd1.Service",
                                   "MainPID"),
                     G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NO_AUTO_START,
                     2000, nullptr, &error)
               : nullptr;
  guint32 actual_pid = 0;
  if (pid_reply) {
    GVariant *value;
    g_variant_get(pid_reply, "(v)", &value);
    actual_pid = g_variant_get_uint32(value);
    g_variant_unref(value);
    g_variant_unref(pid_reply);
  }
  if (location)
    g_variant_unref(location);
  g_dbus_connection_close_sync(manager, nullptr, nullptr);
  g_object_unref(manager);
  g_clear_error(&error);
  if (!actual_pid || actual_pid != expected_pid)
    return nullptr;
  GIOStream *stream =
      g_dbus_address_get_stream_sync(address.c_str(), nullptr, nullptr, &error);
  if (!stream) {
    g_clear_error(&error);
    return nullptr;
  }
  // GDBus client credentials are unavailable through get_peer_credentials().
  // Check the underlying Unix socket before beginning D-Bus authentication.
  GCredentials *credentials =
      G_IS_SOCKET_CONNECTION(stream)
          ? g_socket_get_credentials(
                g_socket_connection_get_socket(G_SOCKET_CONNECTION(stream)),
                &error)
          : nullptr;
  bool verified = false;
  if (credentials) {
    const auto uid = g_credentials_get_unix_user(credentials, &error);
    if (!error) {
      const auto pid = g_credentials_get_unix_pid(credentials, &error);
      verified = !error && uid == 0 && pid == static_cast<pid_t>(expected_pid);
    }
    g_object_unref(credentials);
  }
  g_clear_error(&error);
  if (!verified) {
    g_object_unref(stream);
    return nullptr;
  }
  auto *observer = g_dbus_auth_observer_new();
  g_signal_connect(observer, "allow-mechanism",
                   G_CALLBACK(+[](GDBusAuthObserver *, const gchar *mechanism,
                                  gpointer) -> gboolean {
                     return g_str_equal(mechanism, "EXTERNAL");
                   }),
                   nullptr);
  auto *connection = g_dbus_connection_new_sync(
      stream, nullptr, G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT, observer,
      nullptr, &error);
  *failure = 7; // The root endpoint was verified; authentication then failed.
  g_clear_error(&error);
  g_object_unref(observer);
  g_object_unref(stream);
  if (connection)
    g_dbus_connection_set_exit_on_close(connection, FALSE);
  return connection;
}

std::string Call(GDBusConnection *connection, const char *method,
                 GVariant *arguments,
                 const GVariantType *reply_type = G_VARIANT_TYPE("()")) {
  GError *error = nullptr;
  auto *reply = g_dbus_connection_call_sync(
      connection, nullptr, path, interface, method, arguments, reply_type,
      G_DBUS_CALL_FLAGS_NONE, 45000, nullptr, &error);
  if (!reply) {
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
  if (!InControlTestVm() || getuid() == 0 || getuid() != geteuid())
    return 2;
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
  std::string line, address, unit;
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
  printf("CLIENT_READY client=%d helper=%u unit=%s address=%s\n", getpid(),
         helper_pid, unit.c_str(), address.c_str());
  fflush(stdout);
  GDBusConnection *connection = nullptr;
  while (std::getline(std::cin, line)) {
    std::string result;
    if (line == "connect") {
      int failure;
      connection = Connect(address, unit, helper_pid, &failure);
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
