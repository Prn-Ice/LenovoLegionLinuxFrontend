// A fixed, hardware-free administrator-startup experiment. Both entry points
// require the disposable VM marker; this executable is never installed.
#include "../executable_snapshot.h"
#include "../test/test_vm_guard.h"

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

int Helper(const char *launcher_text) {
  if (getuid() != 0 || geteuid() != 0)
    return 2;
  char *end;
  const long launcher = strtol(launcher_text, &end, 10);
  if (!*launcher_text || *end || launcher <= 1 || launcher > INT_MAX)
    return 2;
  for (const char *name :
       {"LD_PRELOAD", "LD_LIBRARY_PATH", "GIO_EXTRA_MODULES", "GCONV_PATH",
        "PYTHONPATH", "DBUS_SYSTEM_BUS_ADDRESS"}) {
    if (getenv(name)) {
      fprintf(stderr, "helper inherited unsafe environment: %s\n", name);
      return 1;
    }
  }
  const int executable = open("/proc/self/exe", O_RDONLY | O_CLOEXEC);
  constexpr int seals =
      F_SEAL_WRITE | F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_SEAL;
  const int actual_seals = executable < 0 ? -1 : fcntl(executable, F_GET_SEALS);
  const bool sealed = actual_seals >= 0 && (actual_seals & seals) == seals;
  if (executable >= 0)
    close(executable);
  if (!sealed)
    return 2;
  const int parent = syscall(SYS_pidfd_open, launcher, 0);
  if (parent < 0)
    return 1;
  printf("ROOT_HELPER uid=%u pid=%d sealed=yes\n", unsigned(getuid()),
         getpid());
  fflush(stdout);
  pollfd lifetime{parent, POLLIN, 0};
  int result;
  do {
    result = poll(&lifetime, 1, 12000);
  } while (result < 0 && errno == EINTR);
  close(parent);
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
  bool start_finished = false, cancelled = false;
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

int Launcher(bool wait_before_start, bool queued) {
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
  const guint deadline = g_timeout_add(20000, Cancel, &launch);

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
    property("RuntimeMaxUSec", g_variant_new_uint64(15000000));
    for (const char *name :
         {"AddRef", "NoNewPrivileges", "PrivateTmp", "SendSIGKILL"})
      property(name, g_variant_new_boolean(TRUE));
    property("ProtectHome", g_variant_new_string("yes"));
    property("ProtectSystem", g_variant_new_string("strict"));
    property("StandardInput", g_variant_new_string("null"));
    property("StandardError", g_variant_new_string("journal"));
    GUnixFDList *fds = g_unix_fd_list_new();
    const int handle = g_unix_fd_list_append(fds, STDOUT_FILENO, &launch.error);
    if (handle >= 0) {
      property("StandardOutputFileDescriptor", g_variant_new_handle(handle));
      const std::string executable = "/proc/" + std::to_string(getpid()) +
                                     "/fd/" + std::to_string(snapshot);
      const std::string pid = std::to_string(getpid());
      const char *arguments[] = {executable.c_str(), "--helper", pid.c_str(),
                                 nullptr};
      const char *flags[] = {"no-env-expand", nullptr};
      GVariantBuilder commands;
      g_variant_builder_init(&commands, G_VARIANT_TYPE("a(sasas)"));
      g_variant_builder_add(&commands, "(s^as^as)", executable.c_str(),
                            arguments, flags);
      property("ExecStartEx", g_variant_builder_end(&commands));
      // The manager observes launcher death even while the helper's start job
      // waits for another unit. RuntimeMaxUSec alone does not bound that wait.
      const std::string scope =
          launch.unit.substr(0, launch.unit.size() - 8) + ".scope";
      const char *lifetime[] = {scope.c_str(), nullptr};
      property("BindsTo", g_variant_new_strv(lifetime, -1));
      property("After", g_variant_new_strv(lifetime, -1));
      if (queued) {
        const char *gate[] = {"legion-bootstrap-gate.service", nullptr};
        property("Requires", g_variant_new_strv(gate, -1));
        property("After", g_variant_new_strv(gate, -1));
      }
      GVariantBuilder scope_properties, auxiliaries;
      g_variant_builder_init(&scope_properties, G_VARIANT_TYPE("a(sv)"));
      GVariantBuilder pids;
      g_variant_builder_init(&pids, G_VARIANT_TYPE("au"));
      g_variant_builder_add(&pids, "u", guint32(getpid()));
      g_variant_builder_add(&scope_properties, "(sv)", "PIDs",
                            g_variant_builder_end(&pids));
      g_variant_builder_add(&scope_properties, "(sv)", "CollectMode",
                            g_variant_new_string("inactive-or-failed"));
      // BindsTo handles a running helper. A cleanup service with Conflicts
      // replaces an inactive, queued start when the launcher's scope becomes
      // empty.
      const std::string cleanup =
          scope.substr(0, scope.size() - 6) + "-cleanup.service";
      const char *cleanup_units[] = {cleanup.c_str(), nullptr};
      for (const char *name : {"OnSuccess", "OnFailure"})
        g_variant_builder_add(&scope_properties, "(sv)", name,
                              g_variant_new_strv(cleanup_units, -1));
      // OnSuccess defaults to "fail", which refuses to replace the helper's
      // queued start with the stop required by the cleanup unit's Conflicts.
      for (const char *name : {"OnSuccessJobMode", "OnFailureJobMode"})
        g_variant_builder_add(&scope_properties, "(sv)", name,
                              g_variant_new_string("replace"));
      g_variant_builder_init(&auxiliaries, G_VARIANT_TYPE("a(sa(sv))"));
      g_variant_builder_add(&auxiliaries, "(s@a(sv))", scope.c_str(),
                            g_variant_builder_end(&scope_properties));
      GVariantBuilder cleanup_properties;
      g_variant_builder_init(&cleanup_properties, G_VARIANT_TYPE("a(sv)"));
      const char *helper_units[] = {launch.unit.c_str(), nullptr};
      for (const char *name : {"Conflicts", "Before"})
        g_variant_builder_add(&cleanup_properties, "(sv)", name,
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
        // Remain alive to retain the immutable executable until the VM kills
        // this launcher or its parent, or the independent lifetime bound fires.
        g_main_loop_run(launch.loop);
      }
    } else
      g_variant_builder_clear(&properties);
    g_object_unref(fds);
  }
  const bool failed = launch.error != nullptr;
  if (launch.error)
    fprintf(stderr, "%s\n", launch.error->message);
  g_clear_error(&launch.error);
  g_clear_pointer(&launch.reply, g_variant_unref);
  // Closing the descriptor revokes any queued execution path. The running
  // helper independently observes this launcher's lifetime with a pidfd.
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
  if (argc == 3 && std::string(argv[1]) == "--helper")
    return Helper(argv[2]);
  if (argc == 1)
    return Launcher(false, false);
  if (argc == 2 && std::string(argv[1]) == "--wait-before-start")
    return Launcher(true, false);
  if (argc == 2 && std::string(argv[1]) == "--queue-behind-gate")
    return Launcher(false, true);
  return 2;
}
