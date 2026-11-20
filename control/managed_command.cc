// Run one fixed backend command as a transient systemd service.
//
// A helper process must not leave hardware writes behind when the app exits,
// so systemd owns the command and its process tree. The operation:
//   1. creates a transient unit with stdout/stderr connected to a pipe,
//   2. drains the pipe and watches the unit until it stops,
//   3. reads the service result and releases the unit's AddRef reference.
// The completion callback runs after every GLib callback has finished. If the
// service cannot prove cleanup, it reports cleanupFailed and the caller closes
// its private manager connection to drop any remaining AddRef references.

#include "managed_command.h"
#include <algorithm>
#include <cerrno>
#include <fcntl.h>
#include <gio/gunixfdlist.h>
#include <gio/gunixinputstream.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

namespace legion_control {
namespace {
constexpr char manager_path[] = "/org/freedesktop/systemd1";
constexpr char manager_interface[] = "org.freedesktop.systemd1.Manager";
constexpr gsize output_limit = 64 * 1024;
constexpr gint64 microseconds_per_second = 1000000;
constexpr gint64 stop_grace = 6 * microseconds_per_second;
constexpr gint64 drain_grace = 2 * microseconds_per_second;
constexpr gint64 startup_limit = 5 * microseconds_per_second;
// Extra time beyond the requested runtime for systemd startup and shutdown.
constexpr gint64 runtime_margin_seconds = 5;
constexpr gint64 overall_margin_seconds = 16;
constexpr guint call_timeout_ms = 3000;
constexpr guint poll_interval_ms = 100;

// One transient unit and its pending GLib callbacks. shared_from_this keeps the
// operation alive until the last callback releases it.
struct Operation final : ManagedCommandOperation,
                         std::enable_shared_from_this<Operation> {
  GDBusConnection *bus;
  std::string parent, lock_path, executable, owner, unit, unit_path;
  std::vector<std::string> args;
  unsigned runtime;
  ManagedCommandRunner::Completion completion;
  ManagedCommandResult result;

  // Output pipe and the callbacks that may still use it.
  GInputStream *stream = nullptr;
  GCancellable *read_cancel = g_cancellable_new();
  guint timer = 0, watch = 0;
  gulong closed = 0;
  int pending = 0;
  int operation_lock = -1;

  // Lifecycle flags. `ending` means no new work may start; `delivered` means
  // the completion callback has run exactly once.
  bool ending = false, delivered = false, reading = false, eof = false;
  bool cancelled = false, started = false, stopping = false, polling = false;
  bool unreferenced = false;

  // Monotonic deadlines in microseconds. The overall deadline is a safety net
  // for the whole operation; the others bound individual phases.
  gint64 deadline = 0, startup_deadline = 0, runtime_deadline = 0,
         drain_deadline = 0;

  // A random unit name keeps concurrent helpers from colliding. The operation
  // holds its own reference to the manager connection.
  Operation(GDBusConnection *b, std::string p, std::string lock, std::string e,
            std::vector<std::string> a, unsigned r,
            ManagedCommandRunner::Completion cb)
      : bus(G_DBUS_CONNECTION(g_object_ref(b))),
        parent(std::move(p)),
        lock_path(std::move(lock)),
        executable(std::move(e)),
        args(std::move(a)),
        runtime(r),
        completion(std::move(cb)) {
    gchar *uuid = g_uuid_string_random();
    unit = std::string("legion-control-op-") + uuid + ".service";
    g_free(uuid);
  }

  ~Operation() override {
    if (operation_lock >= 0)
      close(operation_lock);
    g_clear_object(&stream);
    g_clear_object(&read_cancel);
    g_object_unref(bus);
  }

  using Reply = std::function<void(GVariant *, GError *)>;

  struct CallData {
    std::shared_ptr<Operation> op;
    Reply reply;
  };

  // Start an asynchronous D-Bus call. `pending` keeps Deliver from running
  // before this callback has finished.
  void Call(const char *destination, const char *path, const char *interface,
            const char *method, GVariant *parameters, const GVariantType *type,
            Reply reply, GUnixFDList *fds = nullptr) {
    ++pending;
    g_dbus_connection_call_with_unix_fd_list(
        bus, destination, path, interface, method, parameters, type,
        G_DBUS_CALL_FLAGS_NO_AUTO_START, call_timeout_ms, fds, nullptr,
        [](GObject *source, GAsyncResult *res, gpointer data) {
          std::unique_ptr<CallData> call(static_cast<CallData *>(data));
          auto op = call->op;
          GError *error = nullptr;
          GVariant *value = g_dbus_connection_call_with_unix_fd_list_finish(
              G_DBUS_CONNECTION(source), nullptr, res, &error);
          --op->pending;
          if (!op->ending)
            call->reply(value, error);
          if (value)
            g_variant_unref(value);
          g_clear_error(&error);
          op->Deliver();
        },
        new CallData{shared_from_this(), std::move(reply)});
  }

  // Call the systemd manager on the bus name found in Begin.
  void Manager(const char *method, GVariant *parameters,
               const GVariantType *type, Reply reply) {
    Call(owner.c_str(), manager_path, manager_interface, method, parameters,
         type, std::move(reply));
  }

  // Run the completion exactly once, after the operation ended and every
  // callback and read has finished. Closing the lock here keeps it held until
  // systemd has stopped the command's process tree.
  void Deliver() {
    if (!ending || delivered || pending || reading)
      return;
    delivered = true;
    if (operation_lock >= 0) {
      close(operation_lock);
      operation_lock = -1;
    }
    auto cb = std::move(completion);
    cb(std::move(result));
  }

  // Mark the operation finished once. Stop timers and reads, then let pending
  // callbacks release their references before Deliver runs.
  void End(ManagedCommandStatus status, const std::string &error = {}) {
    if (ending)
      return;
    ending = true;
    result.status = status;
    result.error = error;
    if (timer) {
      g_source_remove(timer);
      timer = 0;
    }
    if (watch) {
      g_dbus_connection_signal_unsubscribe(bus, watch);
      watch = 0;
    }
    if (closed) {
      g_signal_handler_disconnect(bus, closed);
      closed = 0;
    }
    g_cancellable_cancel(read_cancel);
    if (status == ManagedCommandStatus::cleanupFailed &&
        !g_dbus_connection_is_closed(bus)) {
      // Dropping this dedicated connection also drops AddRef references when a
      // lost start reply prevents us from knowing whether a unit was created.
      ++pending;
      g_dbus_connection_close(
          bus, nullptr,
          [](GObject *source, GAsyncResult *res, gpointer data) {
            std::unique_ptr<std::shared_ptr<Operation>> hold(
                static_cast<std::shared_ptr<Operation> *>(data));
            auto op = *hold;
            GError *error = nullptr;
            g_dbus_connection_close_finish(G_DBUS_CONNECTION(source), res,
                                           &error);
            g_clear_error(&error);
            --op->pending;
            op->Deliver();
          },
          new std::shared_ptr<Operation>(shared_from_this()));
    }
    Deliver();
  }

  // We cannot prove that the backend stopped. The service refuses new work
  // until it restarts, because a leftover process could still touch hardware.
  void Uncertain(const std::string &message) {
    End(ManagedCommandStatus::cleanupFailed, message);
  }

  // The caller no longer needs the result. Stop a unit that already started;
  // a unit that never started has nothing to clean up.
  void Cancel() override {
    cancelled = true;
    if (started && !ending && !unreferenced)
      Stop();
  }

  // Ask systemd to stop the unit and shorten the deadline so cleanup cannot
  // hang forever.
  void Stop() {
    if (stopping)
      return;
    stopping = true;
    deadline = std::min(deadline, g_get_monotonic_time() + stop_grace);
    Manager("StopUnit", g_variant_new("(ss)", unit.c_str(), "replace"),
            G_VARIANT_TYPE("(o)"), [this](GVariant *v, GError *) {
              if (!v)
                Uncertain("could not confirm stop request");
            });
  }

  // Drain stdout/stderr in 4 KiB chunks. Stop reading once the output limit is
  // reached; the caller receives outputLimit instead of unbounded data.
  void Read() {
    reading = true;
    g_input_stream_read_bytes_async(
        stream, 4096, G_PRIORITY_DEFAULT, read_cancel,
        [](GObject *source, GAsyncResult *res, gpointer data) {
          std::unique_ptr<std::shared_ptr<Operation>> hold(
              static_cast<std::shared_ptr<Operation> *>(data));
          auto op = *hold;
          op->reading = false;
          GError *error = nullptr;
          GBytes *bytes = g_input_stream_read_bytes_finish(
              G_INPUT_STREAM(source), res, &error);
          if (!op->ending) {
            if (!bytes)
              op->Uncertain("could not drain backend output");
            else {
              gsize size = 0;
              const char *text =
                  static_cast<const char *>(g_bytes_get_data(bytes, &size));
              if (!size) {
                op->eof = true;
                if (op->unreferenced)
                  op->End(op->result.status);
              } else {
                const auto available = output_limit - op->result.output.size();
                op->result.output.append(text, std::min(size, available));
                if (size > available) {
                  op->result.status = ManagedCommandStatus::outputLimit;
                  op->Cancel();
                }
                op->Read();
              }
            }
          }
          if (bytes)
            g_bytes_unref(bytes);
          g_clear_error(&error);
          op->Deliver();
        },
        new std::shared_ptr<Operation>(shared_from_this()));
  }

  // Ask systemd whether the unit has stopped. An inactive unit with no job is
  // terminal; an inactive unit with a queued job may still be waiting for its
  // ordering dependencies.
  void Poll() {
    if (polling || unreferenced)
      return;
    polling = true;
    Call(owner.c_str(), unit_path.c_str(), "org.freedesktop.DBus.Properties",
         "GetAll", g_variant_new("(s)", "org.freedesktop.systemd1.Unit"),
         G_VARIANT_TYPE("(a{sv})"), [this](GVariant *v, GError *) {
           polling = false;
           if (!v) {
             Uncertain("could not observe command unit");
             return;
           }
           GVariant *props = nullptr;
           g_variant_get(v, "(@a{sv})", &props);
           const char *state = nullptr, *job_path = nullptr;
           guint32 job = 0;
           const bool valid =
               g_variant_lookup(props, "ActiveState", "&s", &state) &&
               g_variant_lookup(props, "Job", "(u&o)", &job, &job_path);
           // StartTransientUnit acknowledges a queued job. An inactive unit
           // can still be waiting for its ordering dependencies to start.
           const bool terminal =
               valid && job == 0 &&
               (g_str_equal(state, "inactive") || g_str_equal(state, "failed"));
           const bool queued =
               valid && job != 0 && g_str_equal(state, "inactive");
           g_variant_unref(props);
           if (!valid) {
             Uncertain("incomplete command unit state");
             return;
           }
           if (terminal)
             Status();
           else if (queued && !stopping &&
                    g_get_monotonic_time() >= startup_deadline) {
             result.status = ManagedCommandStatus::timeout;
             Cancel();
           }
         });
  }

  // Read the final service result. systemd may report `failed` after sending
  // SIGKILL while tasks are still alive, so wait until ControlGroup is empty
  // before releasing the unit.
  void Status() {
    polling = true;
    Call(owner.c_str(), unit_path.c_str(), "org.freedesktop.DBus.Properties",
         "GetAll", g_variant_new("(s)", "org.freedesktop.systemd1.Service"),
         G_VARIANT_TYPE("(a{sv})"), [this](GVariant *v, GError *) {
           if (!v) {
             Uncertain("could not retrieve command status");
             return;
           }
           GVariant *props = nullptr;
           g_variant_get(v, "(@a{sv})", &props);
           gint code = 0, status = -1;
           const char *service_result = nullptr, *control_group = nullptr;
           const bool valid =
               g_variant_lookup(props, "ExecMainCode", "i", &code) &&
               g_variant_lookup(props, "ExecMainStatus", "i", &status) &&
               g_variant_lookup(props, "Result", "&s", &service_result) &&
               g_variant_lookup(props, "ControlGroup", "&s", &control_group);
           // systemd can enter failed after final SIGKILL with tasks still
           // alive. It releases ControlGroup only after confirming recursive
           // emptiness (service.c / cgroup.c, systemd v252).
           if (valid && *control_group) {
             g_variant_unref(props);
             polling = false;
             return;
           }
           if (valid) {
             // ExecMainCode 1 means the main process exited normally; any
             // other code (signal, dump) has no useful exit status.
             result.exit_status = code == 1 ? status : -1;
             if (g_str_equal(service_result, "timeout") &&
                 result.status != ManagedCommandStatus::outputLimit)
               result.status = ManagedCommandStatus::timeout;
             else if (result.status != ManagedCommandStatus::timeout &&
                      result.status != ManagedCommandStatus::outputLimit)
               result.status = !cancelled && code == 1 && status == 0 &&
                                       g_str_equal(service_result, "success")
                                   ? ManagedCommandStatus::success
                                   : ManagedCommandStatus::commandFailed;
           }
           g_variant_unref(props);
           if (!valid) {
             Uncertain("incomplete command status");
             return;
           }
           // AddRef retains stdout. Retrieve status before releasing that
           // reference.
           Manager("UnrefUnit", g_variant_new("(s)", unit.c_str()),
                   G_VARIANT_TYPE("()"), [this](GVariant *reply, GError *) {
                     if (!reply) {
                       Uncertain("could not release command unit");
                       return;
                     }
                     unreferenced = true;
                     drain_deadline = g_get_monotonic_time() + drain_grace;
                     if (eof)
                       End(result.status);
                   });
         });
  }

  // Build and start the transient unit. This is the only place that knows the
  // systemd properties and the file descriptors passed to the backend.
  void StartUnit() {
    // The lock serializes hardware changes across app sessions. systemd
    // receives the locked descriptor as stdin, so the lock stays held even if
    // this helper dies while the backend is still running.
    if (!lock_path.empty()) {
      operation_lock = open(lock_path.c_str(),
                            O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0600);
      struct stat info{};
      if (operation_lock < 0 || fstat(operation_lock, &info) != 0 ||
          !S_ISREG(info.st_mode) || info.st_uid != geteuid() ||
          (info.st_mode & 0777) != 0600 || info.st_nlink != 1 ||
          info.st_size != 0) {
        End(ManagedCommandStatus::unavailable,
            "operation lock is unavailable or has unsafe permissions");
        return;
      }
      if (flock(operation_lock, LOCK_EX | LOCK_NB) != 0) {
        End(errno == EWOULDBLOCK ? ManagedCommandStatus::busy
                                 : ManagedCommandStatus::unavailable,
            "another helper is running a control operation");
        return;
      }
    }
    // The unit writes both output streams to this pipe; Read drains it.
    int pipe_fds[2];
    if (pipe2(pipe_fds, O_CLOEXEC) != 0) {
      End(ManagedCommandStatus::unavailable, "could not create output pipe");
      return;
    }
    stream = g_unix_input_stream_new(pipe_fds[0], TRUE);
    GUnixFDList *fds = g_unix_fd_list_new();
    const int handle = g_unix_fd_list_append(fds, pipe_fds[1], nullptr);
    close(pipe_fds[1]);
    if (handle < 0) {
      g_object_unref(fds);
      End(ManagedCommandStatus::unavailable, "could not pass output pipe");
      return;
    }
    GVariantBuilder props;
    g_variant_builder_init(&props, G_VARIANT_TYPE("a(sv)"));
    auto property = [&props](const char *name, GVariant *value) {
      g_variant_builder_add(&props, "(sv)", name, value);
    };
    auto strings = [](const std::vector<std::string> &values) {
      GVariantBuilder b;
      g_variant_builder_init(&b, G_VARIANT_TYPE("as"));
      for (const auto &value : values)
        g_variant_builder_add(&b, "s", value.c_str());
      return g_variant_builder_end(&b);
    };
    // Run one command, keep the unit after it exits so Status can read the
    // result, and stop the whole cgroup rather than only the main process.
    property("Type", g_variant_new_string("exec"));
    property("CollectMode", g_variant_new_string("inactive-or-failed"));
    property("KillMode", g_variant_new_string("control-group"));
    property("Restart", g_variant_new_string("no"));
    if (operation_lock >= 0) {
      const int lock_handle =
          g_unix_fd_list_append(fds, operation_lock, nullptr);
      if (lock_handle < 0) {
        g_variant_builder_clear(&props);
        g_object_unref(fds);
        End(ManagedCommandStatus::unavailable, "could not pass operation lock");
        return;
      }
      property("StandardInputFileDescriptor",
               g_variant_new_handle(lock_handle));
    } else
      property("StandardInput", g_variant_new_string("null"));
    property("StandardOutputFileDescriptor", g_variant_new_handle(handle));
    property("StandardErrorFileDescriptor", g_variant_new_handle(handle));
    // Bound each phase so a stuck backend cannot hold the session forever.
    property("TimeoutStartUSec", g_variant_new_uint64(startup_limit));
    // systemd v252 and v262's transient setter rejects JobTimeoutUSec.
    // Bound running jobs here; Poll bounds an acknowledged, still-queued start.
    property("JobRunningTimeoutUSec", g_variant_new_uint64(startup_limit));
    property("RuntimeMaxUSec",
             g_variant_new_uint64(guint64(runtime) * microseconds_per_second));
    property("TimeoutStopUSec", g_variant_new_uint64(drain_grace));
    // Keep the unit referenced and give the backend the same containment
    // settings as the helper.
    for (const char *name :
         {"AddRef", "SendSIGKILL", "NoNewPrivileges", "PrivateTmp",
          "ProtectHostname", "ProtectClock", "ProtectControlGroups",
          "ProtectKernelLogs", "ProtectKernelModules"})
      property(name, g_variant_new_boolean(TRUE));
    property("ProtectHome", g_variant_new_string("yes"));
    property("ProtectSystem", g_variant_new_string("strict"));
    property("RestrictNamespaces", g_variant_new_uint64(0));
    property("RestrictAddressFamilies",
             g_variant_new("(b@as)", TRUE, strings({"AF_UNIX"})));
    property("SystemCallArchitectures", strings({"native"}));
    property("SystemCallErrorNumber", g_variant_new_int32(EPERM));
    property("SystemCallFilter",
             g_variant_new("(b@as)", TRUE, strings({"@system-service"})));
    for (const char *name : {"BindsTo", "After", "JoinsNamespaceOf"})
      property(name, strings({parent}));
    // The backend gets a fixed working directory and a minimal environment.
    // It must not depend on the helper's shell or Python settings.
    const char *path = g_getenv("PATH");
    property("WorkingDirectory", g_variant_new_string("/"));
    property("Environment",
             strings({std::string("PATH=") +
                          (path ? path : "/usr/sbin:/usr/bin:/sbin:/bin"),
                      "LC_ALL=C", "HOME=/var/empty", "PYTHONNOUSERSITE=1",
                      "PYTHONSAFEPATH=1"}));
    std::vector<std::string> argv{executable};
    argv.insert(argv.end(), args.begin(), args.end());
    GVariantBuilder commands;
    g_variant_builder_init(&commands, G_VARIANT_TYPE("a(sasas)"));
    g_variant_builder_add(&commands, "(s@as@as)", executable.c_str(),
                          strings(argv), strings({"no-env-expand"}));
    property("ExecStartEx", g_variant_builder_end(&commands));
    startup_deadline = g_get_monotonic_time() + startup_limit;
    Read();
    Call(
        owner.c_str(), manager_path, manager_interface, "StartTransientUnit",
        g_variant_new(
            "(ss@a(sv)@a(sa(sv)))", unit.c_str(), "fail",
            g_variant_builder_end(&props),
            g_variant_new_array(G_VARIANT_TYPE("(sa(sv))"), nullptr, 0)),
        G_VARIANT_TYPE("(o)"),
        [this](GVariant *reply, GError *error) {
          if (!reply) {
            // An explicit rejection proves no start job was accepted. systemd
            // may already have created and referenced the transient unit.
            gchar *remote =
                error ? g_dbus_error_get_remote_error(error) : nullptr;
            const bool rejected =
                remote &&
                (g_str_has_prefix(remote, "org.freedesktop.systemd1.") ||
                 g_str_equal(remote,
                             "org.freedesktop.DBus.Error.InvalidArgs") ||
                 g_str_equal(remote,
                             "org.freedesktop.DBus.Error.AccessDenied") ||
                 g_str_equal(remote,
                             "org.freedesktop.DBus.Error.PropertyReadOnly") ||
                 g_str_equal(remote,
                             "org.freedesktop.DBus.Error.UnknownProperty"));
            g_free(remote);
            const std::string message =
                error ? error->message : "uncertain command start";
            if (!rejected) {
              Uncertain(message);
              return;
            }
            Manager(
                "UnrefUnit", g_variant_new("(s)", unit.c_str()),
                G_VARIANT_TYPE("()"),
                [this, message](GVariant *value, GError *unref_error) {
                  gchar *name = unref_error
                                    ? g_dbus_error_get_remote_error(unref_error)
                                    : nullptr;
                  const bool released =
                      value ||
                      (name &&
                       (g_str_equal(name,
                                    "org.freedesktop.systemd1.NoSuchUnit") ||
                        g_str_equal(name,
                                    "org.freedesktop.systemd1.NotReferenced")));
                  g_free(name);
                  if (released)
                    End(ManagedCommandStatus::unavailable, message);
                  else
                    Uncertain("could not release rejected command unit");
                });
            return;
          }
          started = true;
          runtime_deadline = g_get_monotonic_time() +
                             (gint64(runtime) + runtime_margin_seconds) *
                                 microseconds_per_second;
          if (cancelled)
            Stop();
          Manager("GetUnit", g_variant_new("(s)", unit.c_str()),
                  G_VARIANT_TYPE("(o)"), [this](GVariant *v, GError *) {
                    if (!v) {
                      Uncertain("could not locate command unit");
                      return;
                    }
                    const char *path;
                    g_variant_get(v, "(&o)", &path);
                    unit_path = path;
                    Poll();
                  });
        },
        fds);
    g_object_unref(fds);
  }

  // First step: resolve the systemd bus name, watch for it changing, then
  // start the unit. The overall deadline includes the start, run, and cleanup
  // phases so no single phase can hang the operation.
  void Begin() {
    deadline =
        g_get_monotonic_time() +
        (gint64(runtime) + overall_margin_seconds) * microseconds_per_second;
    // One timer drives every deadline check. It removes itself when the
    // operation ends.
    timer = g_timeout_add_full(
        G_PRIORITY_DEFAULT, poll_interval_ms,
        [](gpointer data) -> gboolean {
          auto op = *static_cast<std::shared_ptr<Operation> *>(data);
          const auto now = g_get_monotonic_time();
          if (now >= op->deadline ||
              (op->unreferenced && now >= op->drain_deadline))
            op->Uncertain("command cleanup deadline exceeded");
          else if (op->started && !op->unreferenced) {
            if (now >= op->runtime_deadline && !op->stopping) {
              op->result.status = ManagedCommandStatus::timeout;
              op->Cancel();
            }
            if (!op->unit_path.empty())
              op->Poll();
          }
          return op->ending ? G_SOURCE_REMOVE : G_SOURCE_CONTINUE;
        },
        new std::shared_ptr<Operation>(shared_from_this()),
        [](gpointer data) {
          delete static_cast<std::shared_ptr<Operation> *>(data);
        });
    closed = g_signal_connect(
        bus, "closed",
        G_CALLBACK(+[](GDBusConnection *, gboolean, GError *, gpointer data) {
          auto op = static_cast<Operation *>(data)->shared_from_this();
          op->Uncertain("manager connection closed");
        }),
        this);
    Call(
        "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
        "GetNameOwner", g_variant_new("(s)", "org.freedesktop.systemd1"),
        G_VARIANT_TYPE("(s)"), [this](GVariant *v, GError *) {
          if (!v) {
            End(ManagedCommandStatus::unavailable, "systemd unavailable");
            return;
          }
          const char *name;
          g_variant_get(v, "(&s)", &name);
          owner = name;
          watch = g_dbus_connection_signal_subscribe(
              bus, "org.freedesktop.DBus", "org.freedesktop.DBus",
              "NameOwnerChanged", "/org/freedesktop/DBus",
              "org.freedesktop.systemd1", G_DBUS_SIGNAL_FLAGS_NONE,
              [](GDBusConnection *, const gchar *, const gchar *, const gchar *,
                 const gchar *, GVariant *value, gpointer data) {
                auto op = static_cast<Operation *>(data)->shared_from_this();
                const char *name, *old, *now;
                g_variant_get(value, "(&s&s&s)", &name, &old, &now);
                if (op->owner != now)
                  op->Uncertain("systemd owner changed");
              },
              this, nullptr);
          StartUnit();
        });
  }
};

// Creates operations that share the service's manager connection and parent
// unit. Start returns immediately; Begin runs on the next main-loop idle.
struct Runner final : ManagedCommandRunner {
  GDBusConnection *bus;
  std::string parent, lock_path;

  Runner(GDBusConnection *b, std::string p, std::string lock)
      : bus(G_DBUS_CONNECTION(g_object_ref(b))),
        parent(std::move(p)),
        lock_path(std::move(lock)) {}

  ~Runner() override {
    g_object_unref(bus);
  }

  std::shared_ptr<ManagedCommandOperation> Start(
      const std::string &exe, const std::vector<std::string> &args,
      unsigned runtime, Completion done) override {
    auto op = std::make_shared<Operation>(bus, parent, lock_path, exe, args,
                                          runtime, std::move(done));
    g_idle_add_full(
        G_PRIORITY_DEFAULT,
        [](gpointer data) -> gboolean {
          auto op = *static_cast<std::shared_ptr<Operation> *>(data);
          op->Begin();
          return G_SOURCE_REMOVE;
        },
        new std::shared_ptr<Operation>(op),
        [](gpointer data) {
          delete static_cast<std::shared_ptr<Operation> *>(data);
        });
    return op;
  }
};
}  // namespace

std::shared_ptr<ManagedCommandRunner> CreateManagedCommandRunner(
    GDBusConnection *bus, const std::string &parent,
    const std::string &operation_lock_path) {
  return std::make_shared<Runner>(bus, parent, operation_lock_path);
}
}  // namespace legion_control
