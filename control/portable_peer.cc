#include "portable_peer.h"
#include "portable_unit.h"

#include <climits>
#include <cstring>
#include <gio/gunixsocketaddress.h>
#include <utility>

namespace legion_control {
namespace {
bool Fail(GError **error, GIOErrorEnum code, const char *message) {
  g_set_error_literal(error, G_IO_ERROR, code, message);
  return false;
}

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
} // namespace

bool ValidatePortableEndpoint(const PortableEndpoint &endpoint,
                              GError **error) {
  if (!ValidPortableUnit(endpoint.unit) || endpoint.helper_pid <= 1 ||
      endpoint.helper_pid > INT_MAX || SocketPath(endpoint.address).empty())
    return Fail(error, G_IO_ERROR_INVALID_ARGUMENT,
                "invalid portable helper endpoint");
  return true;
}

GDBusConnection *ConnectPortablePeerSync(const PortableEndpoint &endpoint,
                                         GCancellable *cancel, GError **error,
                                         bool *server_verified) {
  if (server_verified)
    *server_verified = false;
  if (!ValidatePortableEndpoint(endpoint, error))
    return nullptr;
  if (g_cancellable_set_error_if_cancelled(cancel, error))
    return nullptr;
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
  if (location)
    g_variant_unref(location);
  if (owner)
    g_variant_unref(owner);
  g_dbus_connection_close_sync(manager, nullptr, nullptr);
  g_object_unref(manager);
  if (!actual_pid || actual_pid != endpoint.helper_pid) {
    if (!error || !*error)
      Fail(error, G_IO_ERROR_PERMISSION_DENIED,
           "portable helper does not match the systemd unit");
    return nullptr;
  }
  auto *socket_client = g_socket_client_new();
  g_socket_client_set_timeout(socket_client, 5);
  auto *socket_address =
      g_unix_socket_address_new(SocketPath(endpoint.address).c_str());
  auto *stream = g_socket_client_connect(
      socket_client, G_SOCKET_CONNECTABLE(socket_address), cancel, error);
  g_object_unref(socket_address);
  g_object_unref(socket_client);
  if (!stream)
    return nullptr;
  auto *credentials =
      g_socket_get_credentials(g_socket_connection_get_socket(stream), error);
  bool verified = false;
  if (credentials) {
    const auto uid = g_credentials_get_unix_user(credentials, error);
    if (!error || !*error) {
      const auto pid = g_credentials_get_unix_pid(credentials, error);
      verified = (!error || !*error) && uid == 0 &&
                 pid == static_cast<pid_t>(endpoint.helper_pid);
    }
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
} // namespace legion_control
