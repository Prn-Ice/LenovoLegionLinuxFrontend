// One private app session using the shared typed dispatcher and managed runner.
#include "portable_control_session.h"
#include "control_protocol.h"
#include "control_service_runtime.h"
#include "portable_cli.h"
#include "portable_unit.h"
#include "trusted_executable.h"

#include <cstdio>
#include <cstring>
#include <fcntl.h>
#include <fstream>
#include <glib-unix.h>
#include <poll.h>
#include <sstream>
#include <sys/stat.h>
#include <syslog.h>
#include <unistd.h>

namespace {
using legion_control::ControlConnectionMode;
using legion_control::ControlContext;
using legion_control::dispatch;
using legion_control::done;
using legion_control::reply_capabilities;
using legion_control::reply_error;
constexpr const char *path = legion_control::control_object_path,
                     *xml = legion_control::control_xml;

bool AppAlive(int descriptor = STDIN_FILENO) {
  pollfd app{descriptor, POLLIN, 0};
  return poll(&app, 1, 0) == 0;
}

bool PinnedApp(pid_t expected, uid_t uid) {
  std::ifstream info("/proc/self/fdinfo/0");
  std::string line;
  pid_t actual = -1;
  while (std::getline(info, line)) {
    if (line.compare(0, 4, "Pid:") == 0) {
      std::istringstream value(line.substr(4));
      value >> actual;
    }
  }
  struct stat process{};
  const std::string directory = "/proc/" + std::to_string(expected);
  return actual == expected && AppAlive() &&
         stat(directory.c_str(), &process) == 0 && process.st_uid == uid &&
         AppAlive();
}

struct PeerIdentity {
  pid_t pid;
  uid_t uid;
  int app;
  int launcher;
  ~PeerIdentity() {
    if (app >= 0)
      close(app);
    if (launcher >= 0)
      close(launcher);
  }
};

struct Session {
  ControlContext control{};
  GDBusServer *server = nullptr;
  GDBusAuthObserver *observer = nullptr;
  PeerIdentity *peer = nullptr;
  bool accepted = false, authorized = false;
  gint64 activity = g_get_monotonic_time();
  unsigned idle_seconds = 0;
};

bool PeerMatches(GCredentials *credentials, PeerIdentity *peer) {
  if (!credentials || !AppAlive(peer->app) || !AppAlive(peer->launcher))
    return false;
  GError *error = nullptr;
  const uid_t uid = g_credentials_get_unix_user(credentials, &error);
  if (error) {
    g_clear_error(&error);
    return false;
  }
  const pid_t pid = g_credentials_get_unix_pid(credentials, &error);
  if (error) {
    g_clear_error(&error);
    return false;
  }
  return uid == peer->uid && pid == peer->pid && AppAlive(peer->app) &&
         AppAlive(peer->launcher);
}

void PeerCall(GDBusConnection *, const gchar *, const gchar *, const gchar *,
              const gchar *method, GVariant *arguments,
              GDBusMethodInvocation *invocation, gpointer data) {
  auto *session = static_cast<Session *>(data);
  if (!AppAlive() || !AppAlive(session->peer->launcher)) {
    reply_error(invocation, "Unavailable", "the app session has ended");
    g_main_loop_quit(session->control.loop);
    return;
  }
  session->activity = g_get_monotonic_time();
  if (g_str_equal(method, "GetCapabilities")) {
    reply_capabilities(&session->control, invocation);
    return;
  }
  if (g_str_equal(method, "Authorize")) {
    // systemd already obtained host approval before executing this snapshot.
    // The EXTERNAL exchange and pinned pidfd bind it to this one app process.
    session->authorized = true;
    done(invocation);
    return;
  }
  if (!session->authorized) {
    g_dbus_method_invocation_return_dbus_error(
        invocation, "org.freedesktop.DBus.Error.AccessDenied",
        "Authorize must be called first");
    return;
  }
  dispatch(&session->control, method, arguments, invocation);
}

gboolean Accept(GDBusServer *, GDBusConnection *connection, gpointer data) {
  auto *session = static_cast<Session *>(data);
  if (session->accepted ||
      !PeerMatches(g_dbus_connection_get_peer_credentials(connection),
                   session->peer))
    return FALSE;
  GError *error = nullptr;
  static const GDBusInterfaceVTable vtable = {
      PeerCall, nullptr, nullptr, {nullptr}};
  session->control.reg = g_dbus_connection_register_object(
      connection, path, session->control.info->interfaces[0], &vtable, session,
      nullptr, &error);
  if (!session->control.reg) {
    g_clear_error(&error);
    g_main_loop_quit(session->control.loop);
    return FALSE;
  }
  session->accepted = true;
  session->activity = g_get_monotonic_time();
  g_set_object(&session->control.conn, connection);
  g_dbus_connection_set_exit_on_close(connection, FALSE);
  g_signal_connect(
      connection, "closed",
      G_CALLBACK(+[](GDBusConnection *, gboolean, GError *, gpointer data) {
        g_main_loop_quit(static_cast<Session *>(data)->control.loop);
      }),
      session);
  g_dbus_server_stop(session->server);
  return TRUE;
}
} // namespace

int RunPortableControlSession(pid_t client_pid, uid_t client_uid,
                              const std::string &parent_unit,
                              int launcher_pidfd, const std::string &cli,
                              unsigned idle_seconds) {
  if (!legion_control::ValidPortableUnit(parent_unit))
    return 2;
  if (getuid() != 0 || geteuid() != 0 || client_uid == 0 ||
      !PinnedApp(client_pid, client_uid) || !AppAlive(launcher_pidfd))
    return 2;
  const std::string directory =
      "/run/" + parent_unit.substr(0, parent_unit.size() - 8);
  struct stat info{};
  if (lstat(directory.c_str(), &info) != 0 || !S_ISDIR(info.st_mode) ||
      info.st_uid != 0 || (info.st_mode & 0022))
    return 2;
  Session session{};
  session.idle_seconds = idle_seconds;
  session.control.mode = ControlConnectionMode::portable;
  if (!legion_control::TrustedExecutable(cli, &session.control.cli))
    return 2;
  session.control.loop = g_main_loop_new(nullptr, FALSE);
  GError *error = nullptr;
  GDBusConnection *manager = g_dbus_connection_new_for_address_sync(
      "unix:path=/run/dbus/system_bus_socket",
      static_cast<GDBusConnectionFlags>(
          G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT |
          G_DBUS_CONNECTION_FLAGS_MESSAGE_BUS_CONNECTION),
      nullptr, nullptr, &error);
  if (!manager) {
    g_clear_error(&error);
    g_main_loop_unref(session.control.loop);
    return 1;
  }
  session.control.runner =
      legion_control::CreateManagedCommandRunner(manager, parent_unit);
  if (!legion_control::QualifyPortableCli(session.control.runner,
                                          session.control.cli, STDIN_FILENO,
                                          launcher_pidfd, &error)) {
    printf("CONTROL_SETUP_ERROR %s\n",
           error ? error->message : "CLI qualification failed");
    fflush(stdout);
    g_clear_error(&error);
    g_object_unref(manager);
    g_main_loop_unref(session.control.loop);
    return 1;
  }
  session.control.runner = legion_control::CreateManagedCommandRunner(
      manager, parent_unit, {}, "/run/legion-control/operation.lock");
  g_object_unref(manager);
  session.control.info = g_dbus_node_info_new_for_xml(xml, &error);
  if (!session.control.info) {
    g_clear_error(&error);
    g_main_loop_unref(session.control.loop);
    return 1;
  }
  session.observer = g_dbus_auth_observer_new();
  session.peer = new PeerIdentity{client_pid, client_uid,
                                  fcntl(STDIN_FILENO, F_DUPFD_CLOEXEC, 3),
                                  fcntl(launcher_pidfd, F_DUPFD_CLOEXEC, 3)};
  if (session.peer->app < 0 || session.peer->launcher < 0) {
    delete session.peer;
    g_object_unref(session.observer);
    g_dbus_node_info_unref(session.control.info);
    g_main_loop_unref(session.control.loop);
    return 1;
  }
  g_signal_connect(session.observer, "allow-mechanism",
                   G_CALLBACK(+[](GDBusAuthObserver *, const gchar *mechanism,
                                  gpointer) -> gboolean {
                     return g_str_equal(mechanism, "EXTERNAL");
                   }),
                   nullptr);
  // GIO authenticates on worker threads. The immutable identity and its pidfd
  // therefore belong to the observer, independently of main-loop shutdown.
  g_signal_connect_data(
      session.observer, "authorize-authenticated-peer",
      G_CALLBACK(+[](GDBusAuthObserver *, GIOStream *,
                     GCredentials *credentials, gpointer data) -> gboolean {
        return PeerMatches(credentials, static_cast<PeerIdentity *>(data));
      }),
      session.peer,
      [](gpointer data, GClosure *) {
        delete static_cast<PeerIdentity *>(data);
      },
      G_CONNECT_DEFAULT);
  const std::string socket = directory + "/control.sock";
  char *guid = g_dbus_generate_guid();
  session.server = g_dbus_server_new_sync(("unix:path=" + socket).c_str(),
                                          G_DBUS_SERVER_FLAGS_NONE, guid,
                                          session.observer, nullptr, &error);
  g_free(guid);
  if (!session.server) {
    g_clear_error(&error);
    g_clear_object(&session.observer);
    g_clear_pointer(&session.control.info, g_dbus_node_info_unref);
    g_main_loop_unref(session.control.loop);
    return 1;
  }
  // The root-owned directory prevents replacement; the credential check decides
  // which process may authenticate, including among processes of the same user.
  if (chmod(socket.c_str(), 0666) != 0) {
    g_object_unref(session.server);
    g_object_unref(session.observer);
    g_dbus_node_info_unref(session.control.info);
    g_main_loop_unref(session.control.loop);
    return 1;
  }
  g_signal_connect(session.server, "new-connection", G_CALLBACK(Accept),
                   &session);
  g_dbus_server_start(session.server);
  openlog("legion-portable-control", LOG_PID, LOG_AUTHPRIV);
  g_log_set_default_handler(
      [](const gchar *domain, GLogLevelFlags, const gchar *message, gpointer) {
        syslog(LOG_INFO, "%s: %s", domain ? domain : "control", message);
      },
      nullptr);
  printf("CONTROL_READY helper=%d unit=%s address=%s\n", getpid(),
         parent_unit.c_str(), g_dbus_server_get_client_address(session.server));
  fflush(stdout);
  const guint app_watch = g_unix_fd_add(
      STDIN_FILENO, G_IO_IN,
      [](gint, GIOCondition, gpointer data) -> gboolean {
        g_main_loop_quit(static_cast<Session *>(data)->control.loop);
        return G_SOURCE_CONTINUE;
      },
      &session);
  const guint timer = g_timeout_add(
      100,
      [](gpointer data) -> gboolean {
        auto *session = static_cast<Session *>(data);
        const auto now = g_get_monotonic_time();
        if (session->control.active)
          session->activity = now;
        else if (now - session->activity >=
                 (session->accepted ? gint64(session->idle_seconds) * 1000000
                                    : 10000000))
          g_main_loop_quit(session->control.loop);
        return G_SOURCE_CONTINUE;
      },
      &session);
  const guint launcher_watch = g_unix_fd_add(
      launcher_pidfd, G_IO_IN,
      [](gint, GIOCondition, gpointer data) -> gboolean {
        g_main_loop_quit(static_cast<Session *>(data)->control.loop);
        return G_SOURCE_CONTINUE;
      },
      &session);
  g_main_loop_run(session.control.loop);
  g_source_remove(app_watch);
  g_source_remove(launcher_watch);
  g_source_remove(timer);
  g_dbus_server_stop(session.server);
  g_signal_handlers_disconnect_by_data(session.server, &session);
  if (session.control.conn)
    g_signal_handlers_disconnect_by_data(session.control.conn, &session);
  if (session.control.reg && session.control.conn)
    g_dbus_connection_unregister_object(session.control.conn,
                                        session.control.reg);
  if (session.control.active) {
    session.control.active->disconnected = true;
    session.control.active->command->Cancel();
    while (session.control.active)
      g_main_context_iteration(nullptr, TRUE);
  }
  if (session.control.conn &&
      !g_dbus_connection_is_closed(session.control.conn))
    g_dbus_connection_close_sync(session.control.conn, nullptr, nullptr);
  g_clear_object(&session.control.conn);
  g_clear_object(&session.server);
  g_clear_object(&session.observer);
  g_clear_pointer(&session.control.info, g_dbus_node_info_unref);
  g_main_loop_unref(session.control.loop);
  unlink(socket.c_str());
  return 0;
}
