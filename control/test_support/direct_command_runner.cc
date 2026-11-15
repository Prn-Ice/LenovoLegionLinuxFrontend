#include "direct_command_runner.h"
#include <algorithm>
#include <unistd.h>

namespace legion_control {
namespace {
struct DirectOperation final : ManagedCommandOperation,
                               std::enable_shared_from_this<DirectOperation> {
  GSubprocess *process = nullptr;
  GCancellable *cancel = g_cancellable_new();
  ManagedCommandRunner::Completion completion;
  ManagedCommandResult result;
  bool waited = false, drained = false, cancelled = false;
  guint timer = 0;
  ~DirectOperation() override {
    g_clear_object(&process);
    g_object_unref(cancel);
  }
  void Cancel() override {
    cancelled = true;
    if (process)
      g_subprocess_force_exit(process);
  }
  void Finish() {
    if (!waited || !drained)
      return;
    if (timer) {
      g_source_remove(timer);
      timer = 0;
    }
    auto cb = std::move(completion);
    if (cb)
      cb(std::move(result));
  }
  void Read() {
    g_input_stream_read_bytes_async(
        g_subprocess_get_stdout_pipe(process), 4096, G_PRIORITY_DEFAULT, cancel,
        [](GObject *source, GAsyncResult *res, gpointer data) {
          std::unique_ptr<std::shared_ptr<DirectOperation>> hold(
              static_cast<std::shared_ptr<DirectOperation> *>(data));
          auto op = *hold;
          GError *error = nullptr;
          GBytes *bytes = g_input_stream_read_bytes_finish(
              G_INPUT_STREAM(source), res, &error);
          gsize size = 0;
          const char *text =
              bytes ? static_cast<const char *>(g_bytes_get_data(bytes, &size))
                    : nullptr;
          if (size) {
            const gsize available = 65536 - op->result.output.size();
            op->result.output.append(text, std::min(size, available));
            if (size > available) {
              op->result.status = ManagedCommandStatus::outputLimit;
              op->Cancel();
            }
            op->Read();
          } else
            op->drained = true;
          if (bytes)
            g_bytes_unref(bytes);
          g_clear_error(&error);
          op->Finish();
        },
        new std::shared_ptr<DirectOperation>(shared_from_this()));
  }
  void Begin(const std::string &exe, const std::vector<std::string> &args,
             unsigned runtime) {
    if (getuid() == 0 || geteuid() != getuid()) {
      result.status = ManagedCommandStatus::unavailable;
      result.error = "fixture runner requires an ordinary user";
      waited = drained = true;
      Finish();
      return;
    }
    std::vector<const char *> argv{exe.c_str()};
    for (const auto &arg : args)
      argv.push_back(arg.c_str());
    argv.push_back(nullptr);
    GError *error = nullptr;
    process = g_subprocess_newv(
        argv.data(),
        static_cast<GSubprocessFlags>(G_SUBPROCESS_FLAGS_STDOUT_PIPE |
                                      G_SUBPROCESS_FLAGS_STDERR_MERGE),
        &error);
    if (!process) {
      result.status = ManagedCommandStatus::unavailable;
      result.error = error->message;
      g_clear_error(&error);
      waited = drained = true;
      Finish();
      return;
    }
    if (cancelled)
      Cancel();
    timer = g_timeout_add_full(
        G_PRIORITY_DEFAULT, runtime * 1000,
        [](gpointer data) -> gboolean {
          auto op = *static_cast<std::shared_ptr<DirectOperation> *>(data);
          op->timer = 0;
          op->result.status = ManagedCommandStatus::timeout;
          op->Cancel();
          g_cancellable_cancel(op->cancel);
          return G_SOURCE_REMOVE;
        },
        new std::shared_ptr<DirectOperation>(shared_from_this()),
        [](gpointer data) {
          delete static_cast<std::shared_ptr<DirectOperation> *>(data);
        });
    Read();
    g_subprocess_wait_async(
        process, nullptr,
        [](GObject *source, GAsyncResult *res, gpointer data) {
          std::unique_ptr<std::shared_ptr<DirectOperation>> hold(
              static_cast<std::shared_ptr<DirectOperation> *>(data));
          auto op = *hold;
          GError *error = nullptr;
          if (g_subprocess_wait_finish(G_SUBPROCESS(source), res, &error)) {
            if (g_subprocess_get_if_exited(op->process))
              op->result.exit_status =
                  g_subprocess_get_exit_status(op->process);
            if (!op->cancelled && g_subprocess_get_successful(op->process))
              op->result.status = ManagedCommandStatus::success;
          }
          g_clear_error(&error);
          op->waited = true;
          op->Finish();
        },
        new std::shared_ptr<DirectOperation>(shared_from_this()));
  }
};
struct DirectRunner final : ManagedCommandRunner {
  struct StartData {
    std::shared_ptr<DirectOperation> op;
    std::string exe;
    std::vector<std::string> args;
    unsigned runtime;
  };
  std::shared_ptr<ManagedCommandOperation>
  Start(const std::string &exe, const std::vector<std::string> &args,
        unsigned runtime, Completion done) override {
    auto op = std::make_shared<DirectOperation>();
    op->completion = std::move(done);
    g_idle_add_full(
        G_PRIORITY_DEFAULT,
        [](gpointer data) -> gboolean {
          auto *start = static_cast<StartData *>(data);
          start->op->Begin(start->exe, start->args, start->runtime);
          return G_SOURCE_REMOVE;
        },
        new StartData{op, exe, args, runtime},
        [](gpointer data) { delete static_cast<StartData *>(data); });
    return op;
  }
};
} // namespace
std::shared_ptr<ManagedCommandRunner> CreateDirectCommandRunner() {
  return std::make_shared<DirectRunner>();
}
} // namespace legion_control
