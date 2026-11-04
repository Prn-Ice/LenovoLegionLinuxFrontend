#include "managed_command.h"
// These private-bus tests verify protocol and callback ownership. Kernel cgroup
// containment is exercised by the separate real-systemd VM suite.
#include <cerrno>
#include <fcntl.h>
#include <functional>
#include <gio/gunixfdlist.h>
#include <glib-unix.h>
#include <map>
#include <sys/file.h>
#include <unistd.h>

namespace {
using legion_control::ManagedCommandStatus;
constexpr char manager_path[] = "/org/freedesktop/systemd1";
constexpr char unit_path[] = "/org/freedesktop/systemd1/unit/fake";
constexpr char xml[] = R"XML(<node>
<interface name="org.freedesktop.systemd1.Manager">
 <method name="StartTransientUnit"><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="a(sv)" direction="in"/><arg type="a(sa(sv))" direction="in"/><arg type="o" direction="out"/></method>
 <method name="GetUnit"><arg type="s" direction="in"/><arg type="o" direction="out"/></method>
 <method name="StopUnit"><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="o" direction="out"/></method>
 <method name="UnrefUnit"><arg type="s" direction="in"/></method>
</interface>
<interface name="org.freedesktop.DBus.Properties">
 <method name="Get"><arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="out"/></method>
 <method name="GetAll"><arg type="s" direction="in"/><arg type="a{sv}" direction="out"/></method>
</interface></node>)XML";

void until(const std::function<bool()> &condition) {
  bool expired = false;
  guint timer = g_timeout_add(
      12000,
      [](gpointer data) -> gboolean {
        *static_cast<bool *>(data) = true;
        return G_SOURCE_REMOVE;
      },
      &expired);
  while (!condition() && !expired)
    g_main_context_iteration(nullptr, TRUE);
  if (!expired)
    g_source_remove(timer);
  g_assert_false(expired);
}

struct Manager {
  GTestDBus *test_bus = g_test_dbus_new(G_TEST_DBUS_NONE);
  GDBusConnection *server = nullptr, *client = nullptr;
  GDBusNodeInfo *info = nullptr;
  guint manager_registration = 0, properties_registration = 0, writer = 0;
  GDBusMethodInvocation *start_reply = nullptr;
  std::map<std::string, GVariant *> properties;
  std::shared_ptr<legion_control::ManagedCommandRunner> runner;
  std::shared_ptr<legion_control::ManagedCommandOperation> operation;
  legion_control::ManagedCommandResult result;
  std::string unit, mode, state = "inactive", service_result = "success";
  std::string payload = "backend output\n";
  std::string control_group;
  guint32 job = 0;
  unsigned unit_reads = 0, service_reads = 0;
  bool omit_job = false, omit_control_group = false;
  size_t written = 0;
  int output = -1, exit_status = 0, calls = 0, stops = 0, unrefs = 0;
  int input = -1;
  bool keep_input = false;
  bool hold_start = false, reject_start = false, reject_unref = false;
  const char *start_error = "org.freedesktop.DBus.Error.InvalidArgs";
  bool keep_output = false, ignore_stop = false, status_read = false;
  static void method(GDBusConnection *, const gchar *, const gchar *,
                     const gchar *, const gchar *name, GVariant *params,
                     GDBusMethodInvocation *i, gpointer data) {
    auto *manager = static_cast<Manager *>(data);
    g_assert_cmpstr(
        g_dbus_message_get_destination(g_dbus_method_invocation_get_message(i)),
        ==, g_dbus_connection_get_unique_name(manager->server));
    manager->Call(name, params, i);
  }
  explicit Manager(const std::string &state_directory = {},
                   const std::string &lock_path = {}) {
    g_test_dbus_up(test_bus);
    const auto flags = static_cast<GDBusConnectionFlags>(
        G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT |
        G_DBUS_CONNECTION_FLAGS_MESSAGE_BUS_CONNECTION);
    GError *error = nullptr;
    server = g_dbus_connection_new_for_address_sync(
        g_test_dbus_get_bus_address(test_bus), flags, nullptr, nullptr, &error);
    g_assert_no_error(error);
    client = g_dbus_connection_new_for_address_sync(
        g_test_dbus_get_bus_address(test_bus), flags, nullptr, nullptr, &error);
    g_assert_no_error(error);
    GVariant *reply = g_dbus_connection_call_sync(
        server, "org.freedesktop.DBus", "/org/freedesktop/DBus",
        "org.freedesktop.DBus", "RequestName",
        g_variant_new("(su)", "org.freedesktop.systemd1", 0u),
        G_VARIANT_TYPE("(u)"), G_DBUS_CALL_FLAGS_NONE, 3000, nullptr, &error);
    g_assert_no_error(error);
    g_variant_unref(reply);
    info = g_dbus_node_info_new_for_xml(xml, &error);
    g_assert_no_error(error);
    static const GDBusInterfaceVTable table = {
        method, nullptr, nullptr, {nullptr}};
    manager_registration = g_dbus_connection_register_object(
        server, manager_path, info->interfaces[0], &table, this, nullptr,
        &error);
    g_assert_no_error(error);
    properties_registration = g_dbus_connection_register_object(
        server, unit_path, info->interfaces[1], &table, this, nullptr, &error);
    g_assert_no_error(error);
    runner = legion_control::CreateManagedCommandRunner(
        client, "legion-control.service", state_directory, lock_path);
  }
  ~Manager() {
    g_assert_cmpint(calls, ==, 1);
    if (writer)
      g_source_remove(writer);
    if (output >= 0)
      close(output);
    if (input >= 0)
      close(input);
    if (start_reply) {
      g_dbus_method_invocation_return_dbus_error(
          start_reply, "org.freedesktop.DBus.Error.Failed", "fixture closed");
      g_object_unref(start_reply);
    }
    operation.reset();
    runner.reset();
    for (const auto &entry : properties)
      g_variant_unref(entry.second);
    g_dbus_connection_unregister_object(server, manager_registration);
    g_dbus_connection_unregister_object(server, properties_registration);
    g_dbus_node_info_unref(info);
    g_dbus_connection_close_sync(client, nullptr, nullptr);
    if (!g_dbus_connection_is_closed(server))
      g_dbus_connection_close_sync(server, nullptr, nullptr);
    g_object_unref(client);
    g_object_unref(server);
    g_test_dbus_down(test_bus);
    g_object_unref(test_bus);
  }
  void Start(unsigned runtime = 10) {
    operation = runner->Start(
        "/trusted/backend", {"literal $HOME", "${PATH}", "a b", ""}, runtime,
        [this](legion_control::ManagedCommandResult value) {
          ++calls;
          result = std::move(value);
        });
    g_assert_cmpint(calls, ==, 0);
  }
  void Finish() {
    until([this] { return calls != 0; });
    g_assert_cmpint(calls, ==, 1);
  }
  void ReleaseStart() {
    g_assert_nonnull(start_reply);
    g_dbus_method_invocation_return_value(start_reply,
                                          g_variant_new("(o)", "/job/1"));
    g_clear_object(&start_reply);
  }
  GVariant *Property(const char *name, const char *type) {
    g_assert_true(properties.count(name) != 0);
    GVariant *value = properties.at(name);
    g_assert_cmpstr(g_variant_get_type_string(value), ==, type);
    return value;
  }
  void Call(const char *name, GVariant *params, GDBusMethodInvocation *i) {
    if (g_str_equal(name, "StartTransientUnit")) {
      const char *n, *m;
      GVariant *props, *aux;
      g_variant_get(params, "(&s&s@a(sv)@a(sa(sv)))", &n, &m, &props, &aux);
      unit = n;
      mode = m;
      g_assert_cmpuint(g_variant_n_children(aux), ==, 0);
      g_variant_unref(aux);
      GVariantIter iter;
      g_variant_iter_init(&iter, props);
      const char *key;
      GVariant *value;
      while (g_variant_iter_next(&iter, "(&sv)", &key, &value))
        properties.emplace(key, value);
      g_variant_unref(props);
      if (reject_start) {
        g_dbus_method_invocation_return_dbus_error(i, start_error,
                                                   "unsupported property");
        return;
      }
      GUnixFDList *fds = g_dbus_message_get_unix_fd_list(
          g_dbus_method_invocation_get_message(i));
      GError *error = nullptr;
      output = g_unix_fd_list_get(
          fds,
          g_variant_get_handle(Property("StandardOutputFileDescriptor", "h")),
          &error);
      g_assert_no_error(error);
      if (properties.count("StandardInputFileDescriptor")) {
        input = g_unix_fd_list_get(
            fds,
            g_variant_get_handle(Property("StandardInputFileDescriptor", "h")),
            &error);
        g_assert_no_error(error);
        char byte;
        g_assert_cmpint(read(input, &byte, 1), ==, 0);
      }
      g_assert_cmpint(
          g_variant_get_handle(Property("StandardErrorFileDescriptor", "h")),
          ==,
          g_variant_get_handle(Property("StandardOutputFileDescriptor", "h")));
      g_assert_cmpint(fcntl(output, F_SETFL, O_NONBLOCK), ==, 0);
      writer = g_unix_fd_add(
          output, G_IO_OUT,
          [](gint fd, GIOCondition, gpointer data) -> gboolean {
            auto *self = static_cast<Manager *>(data);
            ssize_t n = write(fd, self->payload.data() + self->written,
                              self->payload.size() - self->written);
            if (n > 0)
              self->written += n;
            else
              g_assert_true(errno == EAGAIN || errno == EINTR);
            if (self->written < self->payload.size())
              return G_SOURCE_CONTINUE;
            self->writer = 0;
            return G_SOURCE_REMOVE;
          },
          this);
      start_reply = G_DBUS_METHOD_INVOCATION(g_object_ref(i));
      if (!hold_start)
        ReleaseStart();
    } else if (g_str_equal(name, "GetUnit")) {
      g_dbus_method_invocation_return_value(i, g_variant_new("(o)", unit_path));
    } else if (g_str_equal(name, "StopUnit")) {
      g_assert_null(start_reply);
      ++stops;
      if (!ignore_stop) {
        state = "inactive";
        job = 0;
      }
      g_dbus_method_invocation_return_value(i, g_variant_new("(o)", "/job/2"));
    } else if (g_str_equal(name, "Get")) {
      g_dbus_method_invocation_return_value(
          i, g_variant_new("(v)", g_variant_new_string(state.c_str())));
    } else if (g_str_equal(name, "GetAll")) {
      const char *interface;
      g_variant_get(params, "(&s)", &interface);
      GVariantBuilder b;
      g_variant_builder_init(&b, G_VARIANT_TYPE("a{sv}"));
      if (g_str_equal(interface, "org.freedesktop.systemd1.Unit")) {
        ++unit_reads;
        g_variant_builder_add(&b, "{sv}", "ActiveState",
                              g_variant_new_string(state.c_str()));
        if (!omit_job)
          g_variant_builder_add(
              &b, "{sv}", "Job",
              g_variant_new("(uo)", job, job ? "/job/1" : "/"));
        g_dbus_method_invocation_return_value(i, g_variant_new("(a{sv})", &b));
        return;
      }
      g_assert_cmpstr(interface, ==, "org.freedesktop.systemd1.Service");
      ++service_reads;
      status_read = true;
      g_variant_builder_add(&b, "{sv}", "ExecMainCode", g_variant_new_int32(1));
      g_variant_builder_add(&b, "{sv}", "ExecMainStatus",
                            g_variant_new_int32(exit_status));
      g_variant_builder_add(&b, "{sv}", "Result",
                            g_variant_new_string(service_result.c_str()));
      if (!omit_control_group)
        g_variant_builder_add(&b, "{sv}", "ControlGroup",
                              g_variant_new_string(control_group.c_str()));
      g_dbus_method_invocation_return_value(i, g_variant_new("(a{sv})", &b));
    } else if (g_str_equal(name, "UnrefUnit")) {
      if (reject_start) {
        ++unrefs;
        g_dbus_method_invocation_return_dbus_error(
            i, "org.freedesktop.systemd1.NoSuchUnit", "rejected unit absent");
        return;
      }
      g_assert_true(status_read);
      ++unrefs;
      if (reject_unref) {
        g_dbus_method_invocation_return_dbus_error(
            i, "org.freedesktop.DBus.Error.Failed", "unref failed");
        return;
      }
      if (!keep_output) {
        close(output);
        output = -1;
      }
      if (input >= 0 && !keep_input) {
        close(input);
        input = -1;
      }
      g_dbus_method_invocation_return_value(i, nullptr);
    } else
      g_assert_not_reached();
  }
};

void test_success_properties() {
  Manager m;
  m.Start();
  m.Finish();
  g_assert_true(m.result.status == ManagedCommandStatus::success);
  g_assert_cmpstr(m.result.output.c_str(), ==, "backend output\n");
  g_assert_cmpint(m.unrefs, ==, 1);
  g_assert_cmpint(m.stops, ==, 0);
  g_assert_false(m.properties.count("StateDirectory"));
  g_assert_true(g_str_has_prefix(m.unit.c_str(), "legion-control-op-"));
  g_assert_true(g_str_has_suffix(m.unit.c_str(), ".service"));
  g_assert_cmpstr(m.mode.c_str(), ==, "fail");
  for (const auto &entry :
       std::map<std::string, std::string>{{"Type", "exec"},
                                          {"KillMode", "control-group"},
                                          {"CollectMode", "inactive-or-failed"},
                                          {"Restart", "no"},
                                          {"StandardInput", "null"},
                                          {"ProtectHome", "yes"},
                                          {"ProtectSystem", "strict"}})
    g_assert_cmpstr(
        g_variant_get_string(m.Property(entry.first.c_str(), "s"), nullptr), ==,
        entry.second.c_str());
  for (const char *name :
       {"AddRef", "SendSIGKILL", "NoNewPrivileges", "PrivateTmp",
        "ProtectHostname", "ProtectClock", "ProtectControlGroups",
        "ProtectKernelLogs", "ProtectKernelModules"})
    g_assert_true(g_variant_get_boolean(m.Property(name, "b")));
  g_assert_cmpuint(
      g_variant_get_uint64(m.Property("JobRunningTimeoutUSec", "t")), ==,
      5000000);
  g_assert_cmpuint(g_variant_get_uint64(m.Property("TimeoutStartUSec", "t")),
                   ==, 5000000);
  g_assert_cmpuint(g_variant_get_uint64(m.Property("RuntimeMaxUSec", "t")), ==,
                   10000000);
  g_assert_cmpuint(g_variant_get_uint64(m.Property("TimeoutStopUSec", "t")), ==,
                   2000000);
  g_assert_cmpuint(g_variant_get_uint64(m.Property("RestrictNamespaces", "t")),
                   ==, 0);
  g_assert_cmpint(g_variant_get_int32(m.Property("SystemCallErrorNumber", "i")),
                  ==, EPERM);
  for (const char *name : {"BindsTo", "After", "JoinsNamespaceOf"}) {
    GVariant *p = m.Property(name, "as");
    const char *parent;
    g_assert_cmpuint(g_variant_n_children(p), ==, 1);
    g_variant_get_child(p, 0, "&s", &parent);
    g_assert_cmpstr(parent, ==, "legion-control.service");
  }
  for (const auto &entry : std::map<std::string, std::string>{
           {"RestrictAddressFamilies", "AF_UNIX"},
           {"SystemCallFilter", "@system-service"}}) {
    gboolean allow;
    GVariant *values;
    g_variant_get(m.Property(entry.first.c_str(), "(bas)"), "(b@as)", &allow,
                  &values);
    g_assert_true(allow);
    const char *value;
    g_variant_get_child(values, 0, "&s", &value);
    g_assert_cmpstr(value, ==, entry.second.c_str());
    g_variant_unref(values);
  }
  const char *exe;
  GVariant *argv, *flags;
  g_variant_get_child(m.Property("ExecStartEx", "a(sasas)"), 0, "(&s@as@as)",
                      &exe, &argv, &flags);
  g_assert_cmpstr(exe, ==, "/trusted/backend");
  g_assert_cmpuint(g_variant_n_children(argv), ==, 5);
  unsigned index = 0;
  for (const char *expected :
       {"/trusted/backend", "literal $HOME", "${PATH}", "a b", ""}) {
    const char *actual;
    g_variant_get_child(argv, index++, "&s", &actual);
    g_assert_cmpstr(actual, ==, expected);
  }
  const char *flag;
  g_variant_get_child(flags, 0, "&s", &flag);
  g_assert_cmpstr(flag, ==, "no-env-expand");
  g_variant_unref(argv);
  g_variant_unref(flags);
}
void test_persistent_state_directory() {
  Manager m("legion-graphics-boot");
  m.Start();
  m.Finish();
  g_assert_true(m.result.status == ManagedCommandStatus::success);
  GVariant *directories = m.Property("StateDirectory", "as");
  g_assert_cmpuint(g_variant_n_children(directories), ==, 1);
  const char *directory;
  g_variant_get_child(directories, 0, "&s", &directory);
  g_assert_cmpstr(directory, ==, "legion-graphics-boot");
  g_assert_cmpuint(g_variant_get_uint32(m.Property("StateDirectoryMode", "u")),
                   ==, 0700);
}
void test_helpers_share_operation_lock() {
  char *directory = g_dir_make_tmp("legion-operation-lock-XXXXXX", nullptr);
  g_assert_nonnull(directory);
  const std::string path = std::string(directory) + "/operation.lock";
  {
    Manager first({}, path);
    first.state = "active";
    first.Start();
    until([&] { return first.input >= 0; });
    Manager second({}, path);
    second.Start();
    second.Finish();
    g_assert_true(second.result.status == ManagedCommandStatus::busy);
    g_assert_true(second.properties.empty());
    first.operation->Cancel();
    first.Finish();
    Manager retry({}, path);
    retry.Start();
    retry.Finish();
    g_assert_true(retry.result.status == ManagedCommandStatus::success);
  }
  unlink(path.c_str());
  rmdir(directory);
  g_free(directory);
}
void test_manager_retains_operation_lock() {
  char *directory = g_dir_make_tmp("legion-operation-lock-XXXXXX", nullptr);
  g_assert_nonnull(directory);
  const std::string path = std::string(directory) + "/operation.lock";
  {
    Manager manager({}, path);
    manager.keep_input = true;
    manager.Start();
    manager.Finish();
    manager.operation.reset();
    manager.runner.reset();
    const int contender = open(path.c_str(), O_RDWR | O_CLOEXEC);
    g_assert_cmpint(contender, >=, 0);
    g_assert_cmpint(flock(contender, LOCK_EX | LOCK_NB), ==, -1);
    g_assert_cmpint(errno, ==, EWOULDBLOCK);
    close(manager.input);
    manager.input = -1;
    g_assert_cmpint(flock(contender, LOCK_EX | LOCK_NB), ==, 0);
    close(contender);
  }
  unlink(path.c_str());
  rmdir(directory);
  g_free(directory);
}
void test_unsafe_operation_lock() {
  char *directory = g_dir_make_tmp("legion-operation-lock-XXXXXX", nullptr);
  g_assert_nonnull(directory);
  const std::string path = std::string(directory) + "/operation.lock";
  g_assert_cmpint(symlink("/dev/null", path.c_str()), ==, 0);
  {
    Manager manager({}, path);
    manager.Start();
    manager.Finish();
    g_assert_true(manager.result.status == ManagedCommandStatus::unavailable);
    g_assert_true(manager.properties.empty());
  }
  unlink(path.c_str());
  rmdir(directory);
  g_free(directory);
}
void test_exit(gconstpointer data) {
  Manager m;
  m.exit_status = GPOINTER_TO_INT(data);
  m.service_result = "exit-code";
  m.Start(35);
  m.Finish();
  g_assert_true(m.result.status == ManagedCommandStatus::commandFailed);
  g_assert_cmpint(m.result.exit_status, ==, m.exit_status);
  g_assert_cmpuint(g_variant_get_uint64(m.Property("RuntimeMaxUSec", "t")), ==,
                   35000000);
}
void test_pending_cancel() {
  Manager m;
  m.hold_start = true;
  m.state = "active";
  m.Start();
  until([&] { return m.start_reply != nullptr; });
  m.operation->Cancel();
  m.operation->Cancel();
  g_assert_cmpint(m.stops, ==, 0);
  g_assert_cmpint(m.calls, ==, 0);
  m.ReleaseStart();
  m.Finish();
  g_assert_cmpint(m.stops, ==, 1);
  g_assert_cmpint(m.unrefs, ==, 1);
  g_assert_true(m.result.status == ManagedCommandStatus::commandFailed);
}
void test_early_cancel_owned_callbacks() {
  Manager m;
  m.state = "active";
  m.Start();
  m.operation->Cancel();
  m.operation.reset();
  m.runner.reset();
  m.Finish();
  g_assert_true(m.result.status == ManagedCommandStatus::commandFailed);
  g_assert_cmpint(m.stops, ==, 1);
  g_assert_cmpint(m.unrefs, ==, 1);
}
void test_manager_unavailable() {
  Manager m;
  GError *error = nullptr;
  GVariant *reply = g_dbus_connection_call_sync(
      m.server, "org.freedesktop.DBus", "/org/freedesktop/DBus",
      "org.freedesktop.DBus", "ReleaseName",
      g_variant_new("(s)", "org.freedesktop.systemd1"), G_VARIANT_TYPE("(u)"),
      G_DBUS_CALL_FLAGS_NONE, 3000, nullptr, &error);
  g_assert_no_error(error);
  g_variant_unref(reply);
  m.Start();
  m.Finish();
  g_assert_true(m.result.status == ManagedCommandStatus::unavailable);
  g_assert_true(m.properties.empty());
}
void test_start_rejection(gconstpointer data) {
  Manager m;
  m.reject_start = true;
  m.start_error = static_cast<const char *>(data);
  m.Start();
  m.Finish();
  g_assert_true(m.result.status == ManagedCommandStatus::unavailable);
  g_assert_cmpint(m.stops, ==, 0);
  g_assert_cmpint(m.unrefs, ==, 1);
}
void test_uncertain_start() {
  Manager m;
  m.hold_start = true;
  m.Start();
  m.Finish();
  g_assert_true(m.result.status == ManagedCommandStatus::cleanupFailed);
  g_assert_cmpint(m.stops, ==, 0);
  m.ReleaseStart(); // Late replies cannot produce a second completion.
}
void test_timeout() {
  Manager m;
  m.state = "active";
  m.Start(0);
  m.Finish();
  g_assert_cmpint(m.stops, ==, 1);
  g_assert_cmpint(m.unrefs, ==, 1);
  g_assert_true(m.result.status == ManagedCommandStatus::timeout);
}
void test_manager_timeout() {
  Manager m;
  m.service_result = "timeout";
  m.state = "failed";
  m.Start();
  m.Finish();
  g_assert_true(m.result.status == ManagedCommandStatus::timeout);
}
void test_overflow() {
  Manager m;
  m.state = "active";
  m.payload.assign(70000, 'x');
  m.Start();
  m.Finish();
  g_assert_true(m.result.status == ManagedCommandStatus::outputLimit);
  g_assert_cmpuint(m.result.output.size(), ==, 65536);
  g_assert_cmpint(m.stops, ==, 1);
  g_assert_cmpint(m.unrefs, ==, 1);
}
void test_overflow_stop_timeout() {
  Manager m;
  m.state = "active";
  m.payload.assign(70000, 'x');
  m.service_result = "timeout";
  m.Start();
  m.Finish();
  g_assert_true(m.result.status == ManagedCommandStatus::outputLimit);
  g_assert_cmpuint(m.result.output.size(), ==, 65536);
  g_assert_cmpint(m.stops, ==, 1);
  g_assert_cmpint(m.unrefs, ==, 1);
}
void test_lost_manager() {
  Manager m;
  m.state = "active";
  m.Start();
  until([&] { return !m.properties.empty(); });
  g_dbus_connection_close_sync(m.server, nullptr, nullptr);
  m.Finish();
  g_assert_true(m.result.status == ManagedCommandStatus::cleanupFailed);
}
void test_unref_failure() {
  Manager m;
  m.reject_unref = true;
  m.Start();
  m.Finish();
  g_assert_true(m.result.status == ManagedCommandStatus::cleanupFailed);
}
void test_drain_deadline() {
  Manager m;
  m.keep_output = true;
  m.Start();
  m.Finish();
  g_assert_true(m.result.status == ManagedCommandStatus::cleanupFailed);
  g_assert_cmpint(m.unrefs, ==, 1);
}
void test_stop_deadline() {
  Manager m;
  m.state = "active";
  m.ignore_stop = true;
  m.Start();
  until([&] { return !m.properties.empty(); });
  m.operation->Cancel();
  m.Finish();
  g_assert_true(m.result.status == ManagedCommandStatus::cleanupFailed);
  g_assert_cmpint(m.unrefs, ==, 0);
}
void test_inactive_pending_job() {
  Manager m;
  m.job = 1;
  m.Start();
  until([&] { return m.unit_reads >= 2; });
  g_assert_cmpuint(m.service_reads, ==, 0);
  g_assert_cmpint(m.unrefs, ==, 0);
  g_assert_cmpint(m.calls, ==, 0);
  m.state = "active";
  m.job = 0;
  const auto reads = m.unit_reads;
  until([&] { return m.unit_reads >= reads + 2; });
  g_assert_cmpuint(m.service_reads, ==, 0);
  g_assert_cmpint(m.calls, ==, 0);
  m.state = "inactive";
  m.Finish();
  g_assert_true(m.result.status == ManagedCommandStatus::success);
  g_assert_cmpint(m.unrefs, ==, 1);
}
void test_failed_cgroup_drains() {
  Manager m;
  m.state = "failed";
  m.service_result = "exit-code";
  m.exit_status = 3;
  m.control_group = "/system.slice/legion-control-op-test.service";
  m.Start();
  until([&] { return m.service_reads >= 2; });
  g_assert_cmpint(m.unrefs, ==, 0);
  g_assert_cmpint(m.calls, ==, 0);
  m.control_group.clear();
  m.Finish();
  g_assert_true(m.result.status == ManagedCommandStatus::commandFailed);
  g_assert_cmpint(m.result.exit_status, ==, 3);
  g_assert_cmpint(m.unrefs, ==, 1);
}
void test_queued_start_deadline() {
  Manager m;
  m.job = 1;
  m.Start();
  m.Finish();
  g_assert_true(m.result.status == ManagedCommandStatus::timeout);
  g_assert_cmpint(m.stops, ==, 1);
  g_assert_cmpint(m.unrefs, ==, 1);
}
void test_failed_cgroup_deadline() {
  Manager m;
  m.state = "failed";
  m.service_result = "timeout";
  m.control_group = "/system.slice/legion-control-op-test.service";
  m.ignore_stop = true;
  m.Start();
  until([&] { return m.service_reads >= 2; });
  g_assert_cmpint(m.calls, ==, 0);
  m.operation->Cancel();
  m.Finish();
  g_assert_true(m.result.status == ManagedCommandStatus::cleanupFailed);
  g_assert_cmpint(m.unrefs, ==, 0);
  // GLib completes the stream-close task before its read worker necessarily
  // publishes the connection's closed state.
  until([&] { return g_dbus_connection_is_closed(m.client); });
}
void test_missing_cleanup_property(gconstpointer data) {
  Manager m;
  m.omit_job = GPOINTER_TO_INT(data) == 0;
  m.omit_control_group = !m.omit_job;
  m.Start();
  m.Finish();
  g_assert_true(m.result.status == ManagedCommandStatus::cleanupFailed);
  g_assert_cmpint(m.unrefs, ==, 0);
}
} // namespace
int main(int argc, char **argv) {
  g_test_init(&argc, &argv, nullptr);
  g_test_add_func("/managed/success-properties-literal-argv",
                  test_success_properties);
  g_test_add_func("/managed/persistent-state-directory",
                  test_persistent_state_directory);
  g_test_add_func("/managed/helpers-share-operation-lock",
                  test_helpers_share_operation_lock);
  g_test_add_func("/managed/manager-retains-operation-lock",
                  test_manager_retains_operation_lock);
  g_test_add_func("/managed/unsafe-operation-lock", test_unsafe_operation_lock);
  g_test_add_data_func("/managed/exit-2", GINT_TO_POINTER(2), test_exit);
  g_test_add_data_func("/managed/exit-3", GINT_TO_POINTER(3), test_exit);
  g_test_add_func("/managed/pending-start-cancel", test_pending_cancel);
  g_test_add_func("/managed/early-cancel-owned-callbacks",
                  test_early_cancel_owned_callbacks);
  g_test_add_func("/managed/manager-unavailable", test_manager_unavailable);
  g_test_add_data_func("/managed/start-rejection",
                       "org.freedesktop.DBus.Error.InvalidArgs",
                       test_start_rejection);
  g_test_add_data_func("/managed/unsupported-transient-property",
                       "org.freedesktop.DBus.Error.PropertyReadOnly",
                       test_start_rejection);
  g_test_add_func("/managed/uncertain-start", test_uncertain_start);
  g_test_add_func("/managed/timeout-stop", test_timeout);
  g_test_add_func("/managed/systemd-timeout", test_manager_timeout);
  g_test_add_func("/managed/output-limit-stop", test_overflow);
  g_test_add_func("/managed/output-limit-stop-timeout",
                  test_overflow_stop_timeout);
  g_test_add_func("/managed/lost-manager", test_lost_manager);
  g_test_add_func("/managed/unref-failure", test_unref_failure);
  g_test_add_func("/managed/drain-deadline", test_drain_deadline);
  g_test_add_func("/managed/stop-deadline", test_stop_deadline);
  g_test_add_func("/managed/inactive-pending-job", test_inactive_pending_job);
  g_test_add_func("/managed/queued-start-deadline", test_queued_start_deadline);
  g_test_add_func("/managed/failed-cgroup-drains", test_failed_cgroup_drains);
  g_test_add_func("/managed/failed-cgroup-deadline",
                  test_failed_cgroup_deadline);
  g_test_add_data_func("/managed/missing-job", GINT_TO_POINTER(0),
                       test_missing_cleanup_property);
  g_test_add_data_func("/managed/missing-control-group", GINT_TO_POINTER(1),
                       test_missing_cleanup_property);
  return g_test_run();
}
