// Reuse the production dispatcher and subprocess runner without starting its
// system-bus daemon.
#define main legion_control_daemon_main
#include "../legion_control_service.cc"
#undef main

#include <fcntl.h>
#include <glib-unix.h>
#include <limits>

namespace {
struct Probe {
  Ctx control{};
  GDBusServer *server = nullptr;
  GDBusAuthObserver *observer = nullptr;
  std::string temp_dir;
  std::string fixture_path;
  std::string fake_helper_path;
  uid_t expected_uid = static_cast<uid_t>(-1);
  pid_t expected_pid = -1;
  guint timeout_source = 0;
  guint terminate_source = 0;
  guint interrupt_source = 0;
  bool peer_verified = false;
  bool authorized = false;
  bool cancel_authorization = false;
  bool accepted = false;
  bool timed_out = false;
  bool cancelled = false;
  bool failed = false;
};

bool peer_identity_matches(GCredentials *credentials, Probe *probe) {
  if (!credentials)
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
  return uid == probe->expected_uid && pid == probe->expected_pid;
}

gboolean allow_mechanism(GDBusAuthObserver *, const gchar *mechanism,
                         gpointer) {
  return g_str_equal(mechanism, "EXTERNAL");
}

gboolean authorize_authenticated_peer(GDBusAuthObserver *, GIOStream *,
                                      GCredentials *credentials,
                                      gpointer data) {
  return peer_identity_matches(credentials, static_cast<Probe *>(data));
}

gboolean startup_timeout(gpointer data) {
  auto *probe = static_cast<Probe *>(data);
  probe->timeout_source = 0;
  probe->timed_out = true;
  g_printerr("private peer startup timed out\n");
  g_main_loop_quit(probe->control.loop);
  return G_SOURCE_REMOVE;
}

gboolean cancel_probe(gpointer data) {
  auto *probe = static_cast<Probe *>(data);
  probe->cancelled = true;
  g_main_loop_quit(probe->control.loop);
  return G_SOURCE_CONTINUE;
}

void peer_closed(GDBusConnection *, gboolean, GError *, gpointer data) {
  auto *probe = static_cast<Probe *>(data);
  g_main_loop_quit(probe->control.loop);
}

void probe_call(GDBusConnection *, const gchar *, const gchar *, const gchar *,
                const gchar *method, GVariant *parameters,
                GDBusMethodInvocation *invocation, gpointer data) {
  auto *probe = static_cast<Probe *>(data);
  if (g_str_equal(method, "Authorize")) {
    if (!probe->peer_verified) {
      g_dbus_method_invocation_return_dbus_error(
          invocation, "org.freedesktop.DBus.Error.AccessDenied",
          "private peer was not verified");
    } else if (probe->cancel_authorization) {
      g_dbus_method_invocation_return_dbus_error(
          invocation, "org.freedesktop.DBus.Error.AccessDenied",
          "FAKE authorization was cancelled by the probe scenario");
    } else {
      probe->authorized = true;
      done(invocation);
    }
    return;
  }
  if (!probe->authorized) {
    g_dbus_method_invocation_return_dbus_error(
        invocation, "org.freedesktop.DBus.Error.AccessDenied",
        "Authorize must be called first");
    return;
  }
  dispatch(&probe->control, method, parameters, invocation);
}

const GDBusInterfaceVTable probe_vtable = {
    probe_call, nullptr, nullptr, {nullptr}};

gboolean new_connection(GDBusServer *, GDBusConnection *connection,
                        gpointer data) {
  auto *probe = static_cast<Probe *>(data);
  if (probe->accepted ||
      !peer_identity_matches(g_dbus_connection_get_peer_credentials(connection),
                             probe))
    return FALSE;

  probe->accepted = true;
  probe->peer_verified = true;
  g_set_object(&probe->control.conn, connection);
  if (probe->timeout_source != 0) {
    g_source_remove(probe->timeout_source);
    probe->timeout_source = 0;
  }
  g_signal_connect(connection, "closed", G_CALLBACK(peer_closed), probe);
  GError *error = nullptr;
  probe->control.reg = g_dbus_connection_register_object(
      connection, path, probe->control.info->interfaces[0], &probe_vtable,
      probe, nullptr, &error);
  if (probe->control.reg == 0) {
    g_printerr("could not export LegionControl1: %s\n",
               error ? error->message : "unknown error");
    g_clear_error(&error);
    probe->failed = true;
    g_main_loop_quit(probe->control.loop);
    return FALSE;
  }

  return TRUE;
}

bool write_fixture(const std::string &path, const char *contents) {
  const int fd =
      open(path.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW,
           0600);
  if (fd < 0)
    return false;
  const size_t size = strlen(contents);
  size_t offset = 0;
  while (offset < size) {
    const ssize_t count = write(fd, contents + offset, size - offset);
    if (count < 0 && errno == EINTR)
      continue;
    if (count <= 0)
      break;
    offset += static_cast<size_t>(count);
  }
  const bool closed = close(fd) == 0;
  return offset == size && closed;
}

bool create_fake_backend(Probe *probe) {
  gchar *shell_path = g_find_program_in_path("sh");
  if (!shell_path)
    return false;
  char resolved_shell[PATH_MAX];
  if (!realpath(shell_path, resolved_shell)) {
    g_free(shell_path);
    return false;
  }
  g_free(shell_path);

  gchar *quoted_fixture = g_shell_quote(probe->fixture_path.c_str());
  const std::string script =
      std::string("#!") + resolved_shell +
      "\nif [ \"$#\" -eq 2 ] && [ \"$1\" = '--donotexpecthwmon' ] && "
      "[ \"$2\" = 'batteryconservation-enable' ]; then\n"
      "  printf 'enabled\\n' > " +
      quoted_fixture +
      "\nelif [ \"$#\" -eq 2 ] && [ \"$1\" = '--donotexpecthwmon' ] && "
      "[ \"$2\" = 'batteryconservation-disable' ]; then\n"
      "  printf 'disabled\\n' > " +
      quoted_fixture + "\nelse\n  exit 64\nfi\n";
  g_free(quoted_fixture);

  GError *error = nullptr;
  if (!g_file_set_contents(probe->fake_helper_path.c_str(), script.c_str(), -1,
                           &error)) {
    g_printerr("could not write fixed fake backend: %s\n",
               error ? error->message : "unknown error");
    g_clear_error(&error);
    return false;
  }
  if (chmod(probe->fake_helper_path.c_str(), 0700) != 0) {
    g_printerr("could not make fixed fake backend executable\n");
    return false;
  }
  return true;
}

std::string json_quote(const std::string &value) {
  static constexpr char hex[] = "0123456789abcdef";
  std::string result = "\"";
  for (const unsigned char byte : value) {
    if (byte == '"' || byte == '\\') {
      result.push_back('\\');
      result.push_back(static_cast<char>(byte));
    } else if (byte < 0x20) {
      result += "\\u00";
      result.push_back(hex[byte >> 4]);
      result.push_back(hex[byte & 0x0f]);
    } else {
      result.push_back(static_cast<char>(byte));
    }
  }
  result.push_back('"');
  return result;
}

bool parse_positive_integer(const char *value, long *result) {
  if (!value || !*value)
    return false;
  char *end = nullptr;
  errno = 0;
  const long parsed = strtol(value, &end, 10);
  if (errno != 0 || *end != '\0' || parsed <= 0 ||
      parsed > std::numeric_limits<pid_t>::max())
    return false;
  *result = parsed;
  return true;
}

void cleanup(Probe *probe) {
  if (probe->terminate_source != 0)
    g_source_remove(probe->terminate_source);
  if (probe->interrupt_source != 0)
    g_source_remove(probe->interrupt_source);
  if (probe->timeout_source != 0)
    g_source_remove(probe->timeout_source);
  if (probe->control.reg != 0 && probe->control.conn)
    g_dbus_connection_unregister_object(probe->control.conn,
                                        probe->control.reg);
  if (probe->control.active) {
    probe->control.active->disconnected = true;
    g_subprocess_force_exit(probe->control.active->subprocess);
    while (probe->control.active)
      g_main_context_iteration(nullptr, TRUE);
  }
  if (probe->server)
    g_dbus_server_stop(probe->server);
  if (probe->control.conn && !g_dbus_connection_is_closed(probe->control.conn))
    g_dbus_connection_close_sync(probe->control.conn, nullptr, nullptr);
  g_clear_object(&probe->control.conn);
  g_clear_object(&probe->server);
  g_clear_object(&probe->observer);
  g_clear_pointer(&probe->control.info, g_dbus_node_info_unref);
  if (!probe->fixture_path.empty())
    unlink(probe->fixture_path.c_str());
  if (!probe->fake_helper_path.empty())
    unlink(probe->fake_helper_path.c_str());
  if (!probe->temp_dir.empty()) {
    const std::string socket_path = probe->temp_dir + "/control.sock";
    unlink(socket_path.c_str());
    rmdir(probe->temp_dir.c_str());
  }
  if (probe->control.loop)
    g_main_loop_unref(probe->control.loop);
}
} // namespace

int main(int argc, char **argv) {
  long client_pid = -1;
  guint startup_timeout_ms = 10000;
  bool cancel_authorization = false;
  for (int index = 1; index < argc; ++index) {
    const std::string option = argv[index];
    if (option == "--client-pid" && index + 1 < argc) {
      if (!parse_positive_integer(argv[++index], &client_pid))
        return 2;
    } else if (option == "--startup-timeout-ms" && index + 1 < argc) {
      long value = 0;
      if (!parse_positive_integer(argv[++index], &value) || value > 60000)
        return 2;
      startup_timeout_ms = static_cast<guint>(value);
    } else if (option == "--fake-auth-cancel") {
      cancel_authorization = true;
    } else {
      g_printerr("unsupported probe option: %s\n", option.c_str());
      return 2;
    }
  }

  // The probe never runs with root credentials or an elevated effective UID.
  if (client_pid < 0)
    client_pid = getppid();
  if (client_pid <= 0 || getuid() == 0 || geteuid() != getuid()) {
    g_printerr("probe requires an unprivileged, non-elevated user\n");
    return 2;
  }

  Probe probe{};
  probe.expected_uid = getuid();
  probe.expected_pid = static_cast<pid_t>(client_pid);
  probe.cancel_authorization = cancel_authorization;
  probe.control.loop = g_main_loop_new(nullptr, FALSE);
  probe.terminate_source = g_unix_signal_add(SIGTERM, cancel_probe, &probe);
  probe.interrupt_source = g_unix_signal_add(SIGINT, cancel_probe, &probe);

  GError *error = nullptr;
  gchar *directory = g_dir_make_tmp("portable-control-probe-XXXXXX", &error);
  if (!directory) {
    g_printerr("could not create probe directory: %s\n",
               error ? error->message : "unknown error");
    g_clear_error(&error);
    cleanup(&probe);
    return 1;
  }
  probe.temp_dir = directory;
  g_free(directory);
  probe.fixture_path = probe.temp_dir + "/battery-conservation";
  probe.fake_helper_path = probe.temp_dir + "/fake-backend";
  if (!write_fixture(probe.fixture_path, "disabled\n") ||
      !create_fake_backend(&probe)) {
    cleanup(&probe);
    return 1;
  }
  probe.control.cli = probe.fake_helper_path;
  probe.control.systemctl = probe.fake_helper_path;

  probe.control.info = g_dbus_node_info_new_for_xml(xml, &error);
  if (!probe.control.info) {
    g_printerr("could not parse control interface: %s\n",
               error ? error->message : "unknown error");
    g_clear_error(&error);
    cleanup(&probe);
    return 1;
  }
  probe.observer = g_dbus_auth_observer_new();
  g_signal_connect(probe.observer, "allow-mechanism",
                   G_CALLBACK(allow_mechanism), &probe);
  g_signal_connect(probe.observer, "authorize-authenticated-peer",
                   G_CALLBACK(authorize_authenticated_peer), &probe);
  const std::string socket_path = probe.temp_dir + "/control.sock";
  gchar *escaped_socket_path = g_dbus_address_escape_value(socket_path.c_str());
  const std::string listen_address =
      std::string("unix:path=") + escaped_socket_path;
  g_free(escaped_socket_path);
  gchar *guid = g_dbus_generate_guid();
  probe.server =
      g_dbus_server_new_sync(listen_address.c_str(), G_DBUS_SERVER_FLAGS_NONE,
                             guid, probe.observer, nullptr, &error);
  g_free(guid);
  if (!probe.server) {
    g_printerr("could not start private peer server: %s\n",
               error ? error->message : "unknown error");
    g_clear_error(&error);
    cleanup(&probe);
    return 1;
  }
  g_signal_connect(probe.server, "new-connection", G_CALLBACK(new_connection),
                   &probe);
  g_dbus_server_start(probe.server);

  const std::string address = g_dbus_server_get_client_address(probe.server);
  const std::string handshake =
      "{\"address\":" + json_quote(address) +
      ",\"fixture\":" + json_quote(probe.fixture_path) +
      ",\"directory\":" + json_quote(probe.temp_dir) +
      ",\"authorization\":\"FAKE\"}\n";
  g_print("%s", handshake.c_str());
  fflush(stdout);
  probe.timeout_source =
      g_timeout_add(startup_timeout_ms, startup_timeout, &probe);
  g_main_loop_run(probe.control.loop);

  cleanup(&probe);
  if (probe.failed)
    return 1;
  if (probe.timed_out)
    return 5;
  return probe.accepted || probe.cancelled ? 0 : 1;
}
