// Connects to the root control helper through a private Unix socket.
//
// A socket path alone is not proof of identity: another process could listen
// on it. Before connecting, this file checks that:
//   1. systemd reports the expected unit's MainPID,
//   2. the helper's D-Bus name belongs to that PID and runs as root,
//   3. the socket peer's credentials name the same PID.
// Only then does it open a D-Bus connection that uses EXTERNAL authentication.
#include "portable_peer.h"
#include "portable_unit.h"

#include <climits>
#include <cstring>
#include <gio/gunixsocketaddress.h>
#include <poll.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <utility>

namespace legion_control {
namespace {

// Set a plain GIO error and return false, so callers can `return Fail(...)`.
bool Fail(GError **error, GIOErrorEnum code, const char *message) {
  g_set_error_literal(error, G_IO_ERROR, code, message);
  return false;
}

// Extract the filesystem path from a D-Bus address such as
// `unix:path=/run/...`. The address must name one path and may end with a
// GUID. Returns an empty string when the address is not acceptable.
std::string SocketPath(const std::string &address) {
  constexpr char prefix[] = "unix:path=";
  if (address.compare(0, strlen(prefix), prefix) != 0 ||
      address.find(';') != std::string::npos ||
      address.find('\0') != std::string::npos)
    return {};
  const auto separator = address.find(',');
  if (separator != std::string::npos) {
    const auto guid = address.substr(separator);
    if (guid.size() != 38 || guid.compare(0, 6, ",guid=") != 0)
      return {};
    for (size_t index = 6; index < guid.size(); ++index)
      if (!g_ascii_isxdigit(guid[index]))
        return {};
  }
  const auto encoded =
      address.substr(strlen(prefix), separator - strlen(prefix));
  char *decoded = g_uri_unescape_string(encoded.c_str(), nullptr);
  std::string path = decoded ? decoded : "";
  g_free(decoded);
  return !path.empty() && path[0] == '/' && path.size() < 108 ? path : "";
}

// State shared by the async connect call and its five-second deadline.
struct ConnectTask {
  PortableEndpoint endpoint;
  PortablePeerCompletion completion;
  GSource *deadline;
  GCancellable *cancel;
  bool timed_out = false;

  ~ConnectTask() {
    g_source_destroy(deadline);
    g_source_unref(deadline);
    g_object_unref(cancel);
  }
};
}  // namespace

bool ValidatePortableEndpoint(const PortableEndpoint &endpoint,
                              GError **error) {
  if (!ValidPortableUnit(endpoint.unit) || endpoint.helper_pid <= 1 ||
      endpoint.helper_pid > INT_MAX || SocketPath(endpoint.address).empty() ||
      !g_dbus_is_unique_name(endpoint.bus_name.c_str()))
    return Fail(error, G_IO_ERROR_INVALID_ARGUMENT,
                "invalid portable helper endpoint");
  return true;
}

// Perform the checks and connect. This runs on a worker thread in the async
// wrapper below; all calls are the blocking variants for that reason.
GDBusConnection *ConnectPortablePeerSync(const PortableEndpoint &endpoint,
                                         GCancellable *cancel, GError **error,
                                         bool *server_verified) {
  if (server_verified)
    *server_verified = false;
  if (!ValidatePortableEndpoint(endpoint, error))
    return nullptr;
  if (g_cancellable_set_error_if_cancelled(cancel, error))
    return nullptr;
  // Pin the helper process. If the PID is reused after the helper exits, this
  // pidfd still refers to the old process, so Alive() stays correct.
  const int process = syscall(SYS_pidfd_open, endpoint.helper_pid, 0);
  if (process < 0) {
    Fail(error, G_IO_ERROR_PERMISSION_DENIED,
         "could not pin the portable helper process");
    return nullptr;
  }

  struct PinnedProcess {
    int descriptor;

    ~PinnedProcess() {
      close(descriptor);
    }

    bool Alive() const {
      pollfd state{descriptor, POLLIN, 0};
      return poll(&state, 1, 0) == 0;
    }
  } pinned{process};

  // Ask the system bus for the systemd manager's current unique name.
  auto *manager = g_dbus_connection_new_for_address_sync(
      "unix:path=/run/dbus/system_bus_socket",
      static_cast<GDBusConnectionFlags>(
          G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT |
          G_DBUS_CONNECTION_FLAGS_MESSAGE_BUS_CONNECTION),
      nullptr, cancel, error);
  if (!manager)
    return nullptr;
  auto *owner = g_dbus_connection_call_sync(
      manager, "org.freedesktop.DBus", "/org/freedesktop/DBus",
      "org.freedesktop.DBus", "GetNameOwner",
      g_variant_new("(s)", "org.freedesktop.systemd1"), G_VARIANT_TYPE("(s)"),
      G_DBUS_CALL_FLAGS_NO_AUTO_START, 2000, cancel, error);
  const char *manager_owner = nullptr;
  if (owner)
    g_variant_get(owner, "(&s)", &manager_owner);
  // Find the unit and read its MainPID.
  auto *location =
      owner ? g_dbus_connection_call_sync(
                  manager, manager_owner, "/org/freedesktop/systemd1",
                  "org.freedesktop.systemd1.Manager", "GetUnit",
                  g_variant_new("(s)", endpoint.unit.c_str()),
                  G_VARIANT_TYPE("(o)"), G_DBUS_CALL_FLAGS_NO_AUTO_START, 2000,
                  cancel, error)
            : nullptr;
  const char *unit_path = nullptr;
  if (location)
    g_variant_get(location, "(&o)", &unit_path);
  auto *pid_reply =
      location ? g_dbus_connection_call_sync(
                     manager, manager_owner, unit_path,
                     "org.freedesktop.DBus.Properties", "Get",
                     g_variant_new("(ss)", "org.freedesktop.systemd1.Service",
                                   "MainPID"),
                     G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NO_AUTO_START,
                     2000, cancel, error)
               : nullptr;
  guint32 actual_pid = 0;
  if (pid_reply) {
    GVariant *value;
    g_variant_get(pid_reply, "(v)", &value);
    if (g_variant_is_of_type(value, G_VARIANT_TYPE_UINT32))
      actual_pid = g_variant_get_uint32(value);
    g_variant_unref(value);
    g_variant_unref(pid_reply);
  }
  // The helper's D-Bus name must belong to the same PID and UID 0.
  auto *identity =
      actual_pid == endpoint.helper_pid
          ? g_dbus_connection_call_sync(
                manager, "org.freedesktop.DBus", "/org/freedesktop/DBus",
                "org.freedesktop.DBus", "GetConnectionCredentials",
                g_variant_new("(s)", endpoint.bus_name.c_str()),
                G_VARIANT_TYPE("(a{sv})"), G_DBUS_CALL_FLAGS_NO_AUTO_START,
                2000, cancel, error)
          : nullptr;
  bool root_service = false;
  if (identity) {
    GVariant *credentials;
    g_variant_get(identity, "(@a{sv})", &credentials);
    guint32 uid, pid;
    root_service = g_variant_lookup(credentials, "UnixUserID", "u", &uid) &&
                   uid == 0 &&
                   g_variant_lookup(credentials, "ProcessID", "u", &pid) &&
                   pid == endpoint.helper_pid;
    g_variant_unref(credentials);
    g_variant_unref(identity);
  }
  if (location)
    g_variant_unref(location);
  if (owner)
    g_variant_unref(owner);
  g_dbus_connection_close_sync(manager, nullptr, nullptr);
  g_object_unref(manager);
  if (!root_service || !actual_pid || actual_pid != endpoint.helper_pid ||
      !pinned.Alive()) {
    if (!error || !*error)
      Fail(error, G_IO_ERROR_PERMISSION_DENIED,
           "portable helper does not match a host root systemd service");
    return nullptr;
  }
  // The endpoint passed the process checks. Connect to its private socket.
  const std::string socket_path = SocketPath(endpoint.address);
  auto *socket_client = g_socket_client_new();
  g_socket_client_set_timeout(socket_client, 5);
  auto *socket_address = g_unix_socket_address_new(socket_path.c_str());
  auto *stream = g_socket_client_connect(
      socket_client, G_SOCKET_CONNECTABLE(socket_address), cancel, error);
  g_object_unref(socket_address);
  g_object_unref(socket_client);
  if (!stream)
    return nullptr;
  // Finally, bind the socket connection to the pinned PID. The host bus
  // supplies the UID; socket credentials alone are ambiguous inside a user
  // namespace.
  auto *credentials =
      g_socket_get_credentials(g_socket_connection_get_socket(stream), error);
  bool verified = false;
  if (credentials) {
    const auto pid = g_credentials_get_unix_pid(credentials, error);
    verified = (!error || !*error) &&
               pid == static_cast<pid_t>(endpoint.helper_pid) && pinned.Alive();
    g_object_unref(credentials);
  }
  if (!verified) {
    g_object_unref(stream);
    if (!error || !*error)
      Fail(error, G_IO_ERROR_PERMISSION_DENIED,
           "portable socket is not owned by the approved root helper");
    return nullptr;
  }
  if (server_verified)
    *server_verified = true;
  // D-Bus EXTERNAL authentication uses the socket's peer credentials. The
  // observer rejects every other mechanism.
  auto *observer = g_dbus_auth_observer_new();
  g_signal_connect(observer, "allow-mechanism",
                   G_CALLBACK(+[](GDBusAuthObserver *, const gchar *mechanism,
                                  gpointer) -> gboolean {
                     return g_str_equal(mechanism, "EXTERNAL");
                   }),
                   nullptr);
  auto *connection = g_dbus_connection_new_sync(
      G_IO_STREAM(stream), nullptr,
      G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT, observer, cancel, error);
  if (connection) {
    // Setup is complete. Method deadlines and the helper's session timer now
    // bound access; an idle socket must remain usable between commands.
    g_socket_set_timeout(g_socket_connection_get_socket(stream), 0);
  }
  g_object_unref(observer);
  g_object_unref(stream);
  if (connection) {
    g_dbus_connection_set_exit_on_close(connection, FALSE);
    if (g_cancellable_is_cancelled(cancel)) {
      g_dbus_connection_close_sync(connection, nullptr, nullptr);
      g_object_unref(connection);
      g_cancellable_set_error_if_cancelled(cancel, error);
      return nullptr;
    }
  }
  return connection;
}

// Run ConnectPortablePeerSync on a worker thread so the UI stays responsive.
// A five-second deadline cancels the work and reports a timeout.
void ConnectPortablePeer(const PortableEndpoint &endpoint, GCancellable *cancel,
                         PortablePeerCompletion completion) {
  auto *deadline = g_timeout_source_new(5000);
  auto *state = new ConnectTask{endpoint, std::move(completion), deadline,
                                G_CANCELLABLE(g_object_ref(cancel))};
  g_source_set_callback(
      deadline,
      [](gpointer data) -> gboolean {
        auto *state = static_cast<ConnectTask *>(data);
        if (!g_cancellable_is_cancelled(state->cancel)) {
          state->timed_out = true;
          g_cancellable_cancel(state->cancel);
        }
        return G_SOURCE_REMOVE;
      },
      state, nullptr);
  g_source_attach(deadline, g_main_context_get_thread_default());
  auto *task = g_task_new(
      nullptr, cancel,
      [](GObject *, GAsyncResult *result, gpointer) {
        auto *task = G_TASK(result);
        auto *state = static_cast<ConnectTask *>(g_task_get_task_data(task));
        GError *error = nullptr;
        auto *peer = static_cast<GDBusConnection *>(
            g_task_propagate_pointer(task, &error));
        if (state->timed_out) {
          if (peer) {
            g_dbus_connection_close(peer, nullptr, nullptr, nullptr);
            g_object_unref(peer);
            peer = nullptr;
          }
          g_clear_error(&error);
          g_set_error_literal(&error, G_IO_ERROR, G_IO_ERROR_TIMED_OUT,
                              "Portable helper connection timed out.");
        }
        state->completion(peer, error);
      },
      nullptr);
  g_task_set_task_data(task, state, [](gpointer data) {
    delete static_cast<ConnectTask *>(data);
  });
  g_task_run_in_thread(
      task, [](GTask *task, gpointer, gpointer data, GCancellable *cancel) {
        auto *state = static_cast<ConnectTask *>(data);
        GError *error = nullptr;
        auto *peer = ConnectPortablePeerSync(state->endpoint, cancel, &error);
        if (peer)
          g_task_return_pointer(task, peer, g_object_unref);
        else
          g_task_return_error(task, error);
      });
  g_object_unref(task);
}
}  // namespace legion_control
