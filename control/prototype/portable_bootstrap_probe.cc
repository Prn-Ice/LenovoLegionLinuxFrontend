// A fixed, hardware-free administrator-startup experiment. Both entry points
// require the disposable VM marker; this executable is never installed.
#include "../executable_snapshot.h"
#include "../portable_lifetime.h"
#include "../test/test_vm_guard.h"
#include "portable_control_helper.h"

#include <cerrno>
#include <climits>
#include <cstdio>
#include <cstdlib>
#include <fcntl.h>
#include <gio/gio.h>
#include <gio/gunixfdlist.h>
#include <glib-unix.h>
#include <initializer_list>
#include <poll.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <unistd.h>

namespace {
constexpr char manager_path[] = "/org/freedesktop/systemd1";
constexpr char manager_interface[] = "org.freedesktop.systemd1.Manager";

bool ApprovedSnapshot() {
  if (getuid() != 0 || geteuid() != 0)
    return false;
  for (const char *name :
       {"LD_PRELOAD", "LD_LIBRARY_PATH", "GIO_EXTRA_MODULES", "GCONV_PATH",
        "PYTHONPATH", "DBUS_SYSTEM_BUS_ADDRESS"}) {
    if (getenv(name)) {
      return false;
    }
  }
  const int executable = open("/proc/self/exe", O_RDONLY | O_CLOEXEC);
  constexpr int seals =
      F_SEAL_WRITE | F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_SEAL;
  const int actual_seals = executable < 0 ? -1 : fcntl(executable, F_GET_SEALS);
  const bool sealed = actual_seals >= 0 && (actual_seals & seals) == seals;
  if (executable >= 0)
    close(executable);
  return sealed;
}

bool StopStartupDeadline(const std::string &unit) {
  if (!ValidPortableProbeUnit(unit))
    return false;
  GError *error = nullptr;
  auto *connection = g_dbus_connection_new_for_address_sync(
      "unix:path=/run/dbus/system_bus_socket",
      static_cast<GDBusConnectionFlags>(
          G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT |
          G_DBUS_CONNECTION_FLAGS_MESSAGE_BUS_CONNECTION),
      nullptr, nullptr, &error);
  auto *reply =
      connection ? g_dbus_connection_call_sync(
                       connection, "org.freedesktop.systemd1", manager_path,
                       manager_interface, "StopUnit",
                       g_variant_new(
                           "(ss)",
                           (unit.substr(0, unit.size() - 8) + "-cleanup.timer")
                               .c_str(),
                           "replace"),
                       G_VARIANT_TYPE("(o)"), G_DBUS_CALL_FLAGS_NO_AUTO_START,
                       2000, nullptr, &error)
                 : nullptr;
  const bool stopped = reply != nullptr;
  if (reply)
    g_variant_unref(reply);
  if (connection) {
    g_dbus_connection_close_sync(connection, nullptr, nullptr);
    g_object_unref(connection);
  }
  g_clear_error(&error);
  return stopped;
}

bool ReceiveLifetime(legion_control::PortableLifetime *lifetime) {
  GError *error = nullptr;
  const bool received = legion_control::ReceivePortableLifetimeMessage(
      STDERR_FILENO, lifetime, &error);
  g_clear_error(&error);
  if (!received || lifetime->owner == 0)
    return false;
  const int sink = open("/dev/null", O_WRONLY | O_CLOEXEC);
  if (sink < 0)
    return false;
  const bool restored = dup2(sink, STDERR_FILENO) >= 0;
  close(sink);
  return restored;
}

int Helper(const char *launcher_text, const std::string &unit) {
  if (!ApprovedSnapshot())
    return 2;
  char *end;
  const long launcher = strtol(launcher_text, &end, 10);
  if (!*launcher_text || *end || launcher <= 1 || launcher > INT_MAX)
    return 2;
  legion_control::PortableLifetime lifetime;
  if (!ReceiveLifetime(&lifetime) || !StopStartupDeadline(unit))
    return 1;
  printf("ROOT_HELPER uid=%u pid=%d sealed=yes\n", unsigned(getuid()),
         getpid());
  fflush(stdout);
  pollfd state{lifetime.launcher, POLLIN, 0};
  int result;
  do {
    result = poll(&state, 1, 12000);
  } while (result < 0 && errno == EINTR);
  // The fixture performs no hardware operations. Its only task is to prove
  // root execution of sealed bytes and bounded launcher-death observation.
  return result > 0 ? 0 : 1;
}

struct Launch {
  GMainLoop *loop = g_main_loop_new(nullptr, FALSE);
  GCancellable *cancel = g_cancellable_new();
  GDBusConnection *connection = nullptr;
  GVariant *reply = nullptr;
  GError *error = nullptr;
  std::string unit, owner;
  std::string unit_path;
  bool start_finished = false, cancelled = false, observing = false;
  guint unit_watch = 0;
};

gboolean Cancel(gpointer data) {
  auto *launch = static_cast<Launch *>(data);
  launch->cancelled = true;
  g_cancellable_cancel(launch->cancel);
  g_main_loop_quit(launch->loop);
  return G_SOURCE_CONTINUE;
}

GVariant *Manager(Launch *launch, const char *method, GVariant *parameters,
                  const GVariantType *type) {
  if (launch->owner.empty()) {
    g_variant_unref(g_variant_ref_sink(parameters));
    return nullptr;
  }
  return g_dbus_connection_call_sync(
      launch->connection, launch->owner.c_str(), manager_path,
      manager_interface, method, parameters, type,
      G_DBUS_CALL_FLAGS_NO_AUTO_START, 2000, nullptr, &launch->error);
}

gboolean ObserveControlUnit(gpointer data) {
  auto *launch = static_cast<Launch *>(data);
  if (launch->observing)
    return G_SOURCE_CONTINUE;
  launch->observing = true;
  g_dbus_connection_call(
      launch->connection, launch->owner.c_str(), launch->unit_path.c_str(),
      "org.freedesktop.DBus.Properties", "GetAll",
      g_variant_new("(s)", "org.freedesktop.systemd1.Unit"),
      G_VARIANT_TYPE("(a{sv})"), G_DBUS_CALL_FLAGS_NO_AUTO_START, 2000,
      launch->cancel,
      [](GObject *source, GAsyncResult *result, gpointer data) {
        auto *launch = static_cast<Launch *>(data);
        launch->observing = false;
        GError *error = nullptr;
        auto *reply = g_dbus_connection_call_finish(G_DBUS_CONNECTION(source),
                                                    result, &error);
        if (!reply) {
          if (!launch->cancelled)
            launch->error = error;
          else
            g_clear_error(&error);
          g_main_loop_quit(launch->loop);
          return;
        }
        GVariant *properties;
        g_variant_get(reply, "(@a{sv})", &properties);
        const char *state = nullptr, *job_path = nullptr;
        guint32 job;
        const bool valid =
            g_variant_lookup(properties, "ActiveState", "&s", &state) &&
            g_variant_lookup(properties, "Job", "(u&o)", &job, &job_path);
        if (!valid || (job == 0 && (g_str_equal(state, "inactive") ||
                                    g_str_equal(state, "failed"))))
          g_main_loop_quit(launch->loop);
        g_variant_unref(properties);
        g_variant_unref(reply);
      },
      launch);
  return G_SOURCE_CONTINUE;
}

int Launcher(bool wait_before_start, bool queued, bool control = false) {
  if (getuid() == 0 || geteuid() != getuid() || prctl(PR_SET_DUMPABLE, 0) != 0)
    return 2;
  const pid_t parent_pid = getppid();
  const int parent = syscall(SYS_pidfd_open, parent_pid, 0);
  if (parent < 0 || getppid() != parent_pid) {
    if (parent >= 0)
      close(parent);
    return 1;
  }
  const int source = open("/proc/self/exe", O_RDONLY | O_CLOEXEC);
  std::string error;
  const int snapshot = legion_control::CreateExecutableSnapshot(source, &error);
  if (source >= 0)
    close(source);
  if (snapshot < 0) {
    fprintf(stderr, "%s\n", error.c_str());
    close(parent);
    return 1;
  }
  Launch launch;
  char *uuid = g_uuid_string_random();
  launch.unit = std::string("legion-bootstrap-probe-") + uuid + ".service";
  g_free(uuid);
  printf("SNAPSHOT_READY launcher=%d unit=%s\n", getpid(), launch.unit.c_str());
  fflush(stdout);
  if (wait_before_start) {
    pollfd descriptors[] = {{STDIN_FILENO, POLLIN, 0}, {parent, POLLIN, 0}};
    const int ready = poll(descriptors, 2, 10000);
    char start;
    if (ready <= 0 || descriptors[1].revents ||
        !(descriptors[0].revents & POLLIN) ||
        read(STDIN_FILENO, &start, 1) != 1 || start != 's') {
      close(snapshot);
      close(parent);
      g_object_unref(launch.cancel);
      g_main_loop_unref(launch.loop);
      return 1;
    }
  }
  // The AppImage environment cannot choose the privileged service manager.
  launch.connection = g_dbus_connection_new_for_address_sync(
      "unix:path=/run/dbus/system_bus_socket",
      static_cast<GDBusConnectionFlags>(
          G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT |
          G_DBUS_CONNECTION_FLAGS_MESSAGE_BUS_CONNECTION),
      nullptr, nullptr, &launch.error);
  if (!launch.connection) {
    fprintf(stderr, "%s\n", launch.error->message);
    g_clear_error(&launch.error);
    close(snapshot);
    close(parent);
    g_object_unref(launch.cancel);
    g_main_loop_unref(launch.loop);
    return 1;
  }
  const guint terminate = g_unix_signal_add(SIGTERM, Cancel, &launch);
  const guint interrupt = g_unix_signal_add(SIGINT, Cancel, &launch);
  const guint parent_watch = g_unix_fd_add(
      parent, G_IO_IN,
      [](gint, GIOCondition, gpointer data) -> gboolean {
        return Cancel(data);
      },
      &launch);
  const guint deadline =
      g_timeout_add(control ? 60000 : 20000, Cancel, &launch);

  GVariant *owner = g_dbus_connection_call_sync(
      launch.connection, "org.freedesktop.DBus", "/org/freedesktop/DBus",
      "org.freedesktop.DBus", "GetNameOwner",
      g_variant_new("(s)", "org.freedesktop.systemd1"), G_VARIANT_TYPE("(s)"),
      G_DBUS_CALL_FLAGS_NO_AUTO_START, 2000, nullptr, &launch.error);
  if (owner) {
    const char *name;
    g_variant_get(owner, "(&s)", &name);
    launch.owner = name;
    g_variant_unref(owner);
    GVariantBuilder properties;
    g_variant_builder_init(&properties, G_VARIANT_TYPE("a(sv)"));
    auto property = [&properties](const char *name, GVariant *value) {
      g_variant_builder_add(&properties, "(sv)", name, value);
    };
    property("Description",
             g_variant_new_string("Legion portable bootstrap probe"));
    property("Type", g_variant_new_string("exec"));
    property("CollectMode", g_variant_new_string("inactive-or-failed"));
    property("KillMode", g_variant_new_string("control-group"));
    property("TimeoutStartUSec", g_variant_new_uint64(3000000));
    property("JobRunningTimeoutUSec", g_variant_new_uint64(3000000));
    property("TimeoutStopUSec", g_variant_new_uint64(1000000));
    property("RuntimeMaxUSec",
             g_variant_new_uint64(control ? 60000000 : 15000000));
    for (const char *name :
         {"AddRef", "NoNewPrivileges", "PrivateTmp", "SendSIGKILL"})
      property(name, g_variant_new_boolean(TRUE));
    property("ProtectHome", g_variant_new_string("yes"));
    property("ProtectSystem", g_variant_new_string("strict"));
    GUnixFDList *fds = g_unix_fd_list_new();
    const int handle = g_unix_fd_list_append(fds, STDOUT_FILENO, &launch.error);
    const int image_handle =
        handle >= 0 ? g_unix_fd_list_append(fds, snapshot, &launch.error) : -1;
    const int lifetime = image_handle >= 0
                             ? legion_control::CreatePortableLifetimeMessage(
                                   parent, &launch.error)
                             : -1;
    const int lifetime_handle =
        lifetime >= 0 ? g_unix_fd_list_append(fds, lifetime, &launch.error)
                      : -1;
    if (lifetime >= 0)
      close(lifetime);
    if (handle >= 0 && image_handle >= 0 && lifetime_handle >= 0) {
      property("StandardOutputFileDescriptor", g_variant_new_handle(handle));
      property("StandardInputFileDescriptor",
               g_variant_new_handle(image_handle));
      property("StandardErrorFileDescriptor",
               g_variant_new_handle(lifetime_handle));
      // systemd owns the executable descriptor before authorization finishes.
      // Its executor resolves its own stdin after setting up the supplied fds.
      const std::string executable = "/proc/self/fd/0";
      const std::string pid = std::to_string(getpid());
      const std::string app_pid = std::to_string(parent_pid);
      const std::string app_uid = std::to_string(getuid());
      const char *arguments[] = {executable.c_str(), "--helper", pid.c_str(),
                                 launch.unit.c_str(), nullptr};
      const char *control_arguments[] = {
          executable.c_str(), "--control-helper",  app_pid.c_str(),
          app_uid.c_str(),    launch.unit.c_str(), nullptr};
      const std::string runtime_directory =
          launch.unit.substr(0, launch.unit.size() - 8);
      if (control) {
        for (const char *name :
             {"ProtectHostname", "ProtectClock", "ProtectControlGroups",
              "ProtectKernelLogs", "ProtectKernelModules"})
          property(name, g_variant_new_boolean(TRUE));
        property("RestrictNamespaces", g_variant_new_uint64(0));
        const char *families[] = {"AF_UNIX", nullptr};
        property("RestrictAddressFamilies",
                 g_variant_new("(b^as)", TRUE, families));
        const char *architectures[] = {"native", nullptr};
        property("SystemCallArchitectures",
                 g_variant_new_strv(architectures, -1));
        property("SystemCallErrorNumber", g_variant_new_int32(EPERM));
        const char *syscalls[] = {"@system-service", nullptr};
        property("SystemCallFilter", g_variant_new("(b^as)", TRUE, syscalls));
        const char *directories[] = {"legion-control",
                                     runtime_directory.c_str(), nullptr};
        property("RuntimeDirectory", g_variant_new_strv(directories, -1));
        property("RuntimeDirectoryMode", g_variant_new_uint32(0711));
        property("RuntimeDirectoryPreserve", g_variant_new_string("yes"));
      }
      const char *flags[] = {"no-env-expand", nullptr};
      GVariantBuilder commands;
      g_variant_builder_init(&commands, G_VARIANT_TYPE("a(sasas)"));
      g_variant_builder_add(&commands, "(s^as^as)", executable.c_str(),
                            control ? control_arguments : arguments, flags);
      property("ExecStartEx", g_variant_builder_end(&commands));
      const std::string base = launch.unit.substr(0, launch.unit.size() - 8);
      const std::string timer_unit = base + "-cleanup.timer";
      const std::string cleanup = base + "-cleanup.service";
      const char *startup[] = {timer_unit.c_str(), nullptr};
      property("Wants", g_variant_new_strv(startup, -1));
      property("After", g_variant_new_strv(startup, -1));
      const char *cleanup_units[] = {cleanup.c_str(), nullptr};
      for (const char *name : {"OnSuccess", "OnFailure"})
        property(name, g_variant_new_strv(cleanup_units, -1));
      for (const char *name : {"OnSuccessJobMode", "OnFailureJobMode"})
        property(name, g_variant_new_string("replace"));
      if (queued) {
        const char *gate[] = {"legion-bootstrap-gate.service", nullptr};
        property("Requires", g_variant_new_strv(gate, -1));
        property("After", g_variant_new_strv(gate, -1));
      }
      GVariantBuilder timer_properties, auxiliaries;
      g_variant_builder_init(&timer_properties, G_VARIANT_TYPE("a(sv)"));
      GVariantBuilder deadlines;
      g_variant_builder_init(&deadlines, G_VARIANT_TYPE("a(st)"));
      g_variant_builder_add(&deadlines, "(st)", "OnActiveSec",
                            guint64(5000000));
      g_variant_builder_add(&timer_properties, "(sv)", "TimersMonotonic",
                            g_variant_builder_end(&deadlines));
      g_variant_builder_add(&timer_properties, "(sv)", "AccuracyUSec",
                            g_variant_new_uint64(1000));
      g_variant_builder_add(&timer_properties, "(sv)", "RemainAfterElapse",
                            g_variant_new_boolean(FALSE));
      g_variant_builder_add(&timer_properties, "(sv)", "CollectMode",
                            g_variant_new_string("inactive-or-failed"));
      g_variant_builder_init(&auxiliaries, G_VARIANT_TYPE("a(sa(sv))"));
      g_variant_builder_add(&auxiliaries, "(s@a(sv))", timer_unit.c_str(),
                            g_variant_builder_end(&timer_properties));
      GVariantBuilder cleanup_properties;
      g_variant_builder_init(&cleanup_properties, G_VARIANT_TYPE("a(sv)"));
      const char *helper_units[] = {launch.unit.c_str(), nullptr};
      const char *conflicts[] = {launch.unit.c_str(), timer_unit.c_str(),
                                 nullptr};
      g_variant_builder_add(&cleanup_properties, "(sv)", "Conflicts",
                            g_variant_new_strv(conflicts, -1));
      g_variant_builder_add(&cleanup_properties, "(sv)", "Before",
                            g_variant_new_strv(helper_units, -1));
      g_variant_builder_add(&cleanup_properties, "(sv)", "DefaultDependencies",
                            g_variant_new_boolean(FALSE));
      g_variant_builder_add(&cleanup_properties, "(sv)", "CollectMode",
                            g_variant_new_string("inactive-or-failed"));
      g_variant_builder_add(&cleanup_properties, "(sv)", "Type",
                            g_variant_new_string("oneshot"));
      g_variant_builder_add(&cleanup_properties, "(sv)", "TimeoutStartUSec",
                            g_variant_new_uint64(3000000));
      g_variant_builder_add(&cleanup_properties, "(sv)", "NoNewPrivileges",
                            g_variant_new_boolean(TRUE));
      if (control) {
        const char *directories[] = {runtime_directory.c_str(), nullptr};
        g_variant_builder_add(&cleanup_properties, "(sv)", "RuntimeDirectory",
                              g_variant_new_strv(directories, -1));
        g_variant_builder_add(&cleanup_properties, "(sv)",
                              "RuntimeDirectoryMode",
                              g_variant_new_uint32(0711));
      }
      // Completing this fixed no-op lets systemd collect the cleanup unit after
      // its Conflicts dependency has replaced the helper's queued start job.
      constexpr char no_op[] = "/run/current-system/sw/bin/true";
      const char *cleanup_arguments[] = {no_op, nullptr};
      GVariantBuilder cleanup_commands;
      g_variant_builder_init(&cleanup_commands, G_VARIANT_TYPE("a(sasas)"));
      g_variant_builder_add(&cleanup_commands, "(s^as^as)", no_op,
                            cleanup_arguments, flags);
      g_variant_builder_add(&cleanup_properties, "(sv)", "ExecStartEx",
                            g_variant_builder_end(&cleanup_commands));
      g_variant_builder_add(&auxiliaries, "(s@a(sv))", cleanup.c_str(),
                            g_variant_builder_end(&cleanup_properties));
      g_dbus_connection_call_with_unix_fd_list(
          launch.connection, launch.owner.c_str(), manager_path,
          manager_interface, "StartTransientUnit",
          g_variant_new("(ss@a(sv)@a(sa(sv)))", launch.unit.c_str(), "fail",
                        g_variant_builder_end(&properties),
                        g_variant_builder_end(&auxiliaries)),
          G_VARIANT_TYPE("(o)"),
          static_cast<GDBusCallFlags>(
              G_DBUS_CALL_FLAGS_NO_AUTO_START |
              G_DBUS_CALL_FLAGS_ALLOW_INTERACTIVE_AUTHORIZATION),
          15000, fds, launch.cancel,
          [](GObject *source, GAsyncResult *result, gpointer data) {
            auto *launch = static_cast<Launch *>(data);
            launch->reply = g_dbus_connection_call_with_unix_fd_list_finish(
                G_DBUS_CONNECTION(source), nullptr, result, &launch->error);
            launch->start_finished = true;
            g_main_loop_quit(launch->loop);
          },
          &launch);
      g_main_loop_run(launch.loop);
      // Drain the callback before its stack-owned context is destroyed.
      while (!launch.start_finished)
        g_main_context_iteration(nullptr, TRUE);
      if (launch.reply && !launch.cancelled) {
        g_variant_unref(launch.reply);
        launch.reply = nullptr;
        printf("START_ACKNOWLEDGED\n");
        fflush(stdout);
        if (control) {
          auto *location = Manager(&launch, "GetUnit",
                                   g_variant_new("(s)", launch.unit.c_str()),
                                   G_VARIANT_TYPE("(o)"));
          if (location) {
            const char *path;
            g_variant_get(location, "(&o)", &path);
            launch.unit_path = path;
            g_variant_unref(location);
            launch.unit_watch = g_timeout_add(100, ObserveControlUnit, &launch);
          }
        }
        // Observe the session until the helper ends, this launcher or its
        // parent exits, or the independent lifetime bound fires.
        if (!launch.error)
          g_main_loop_run(launch.loop);
      }
    } else
      g_variant_builder_clear(&properties);
    g_object_unref(fds);
  }
  launch.cancelled = true;
  g_cancellable_cancel(launch.cancel);
  if (launch.unit_watch)
    g_source_remove(launch.unit_watch);
  while (launch.observing)
    g_main_context_iteration(nullptr, TRUE);
  const bool failed = launch.error != nullptr;
  if (launch.error)
    fprintf(stderr, "%s\n", launch.error->message);
  g_clear_error(&launch.error);
  g_clear_pointer(&launch.reply, g_variant_unref);
  // systemd retains its sealed executable and pinned lifetime message. A late
  // start must reject dead handles; the independent timer cancels queued jobs.
  close(snapshot);
  GVariant *release =
      Manager(&launch, "UnrefUnit", g_variant_new("(s)", launch.unit.c_str()),
              G_VARIANT_TYPE("()"));
  if (release)
    g_variant_unref(release);
  g_clear_error(&launch.error);
  g_dbus_connection_close_sync(launch.connection, nullptr, nullptr);
  g_object_unref(launch.connection);
  for (guint watch : {terminate, interrupt, parent_watch, deadline})
    g_source_remove(watch);
  close(parent);
  g_object_unref(launch.cancel);
  g_main_loop_unref(launch.loop);
  return failed ? 1 : 0;
}
} // namespace

int main(int argc, char **argv) {
  if (!InControlTestVm()) {
    fprintf(stderr,
            "This bootstrap probe runs only in the disposable test VM.\n");
    return 2;
  }
  if (argc == 4 && std::string(argv[1]) == "--helper")
    return Helper(argv[2], argv[3]);
  if (argc == 5 && std::string(argv[1]) == "--control-helper") {
    char *pid_end, *uid_end;
    const long pid = strtol(argv[2], &pid_end, 10);
    const unsigned long uid = strtoul(argv[3], &uid_end, 10);
    if (!ApprovedSnapshot() || !*argv[2] || *pid_end || pid <= 1 ||
        pid > INT_MAX || !*argv[3] || *uid_end || uid == 0 || uid > UINT_MAX)
      return 2;
    legion_control::PortableLifetime lifetime;
    if (!ValidPortableProbeUnit(argv[4]) || !ReceiveLifetime(&lifetime) ||
        lifetime.owner != uid || !StopStartupDeadline(argv[4]) ||
        dup2(lifetime.app, STDIN_FILENO) < 0)
      return 2;
    return RunPortableControlProbe(static_cast<pid_t>(pid),
                                   static_cast<uid_t>(uid), argv[4],
                                   lifetime.launcher);
  }
  if (argc == 2 && std::string(argv[1]) == "--control")
    return Launcher(false, false, true);
  if (argc == 1)
    return Launcher(false, false);
  if (argc == 2 && std::string(argv[1]) == "--wait-before-start")
    return Launcher(true, false);
  if (argc == 2 && std::string(argv[1]) == "--queue-behind-gate")
    return Launcher(false, true);
  return 2;
}
