#include "portable_cli.h"
#include "test_support/cli_help_fixture.h"
#include <gio/gio.h>
#include <unistd.h>

namespace {
struct PendingOperation final : legion_control::ManagedCommandOperation {
  legion_control::ManagedCommandRunner::Completion completion;
  unsigned cancels = 0, completions = 0;
  void Cancel() override {
    ++cancels;
    g_idle_add(
        [](gpointer data) -> gboolean {
          auto *operation = static_cast<PendingOperation *>(data);
          ++operation->completions;
          legion_control::ManagedCommandResult result;
          result.error = "cancelled";
          operation->completion(std::move(result));
          return G_SOURCE_REMOVE;
        },
        this);
  }
};
struct PendingRunner final : legion_control::ManagedCommandRunner {
  int signal;
  unsigned starts = 0;
  std::shared_ptr<PendingOperation> pending;
  explicit PendingRunner(int descriptor) : signal(descriptor) {}
  std::shared_ptr<legion_control::ManagedCommandOperation>
  Start(const std::string &executable,
        const std::vector<std::string> &arguments, unsigned runtime,
        Completion completion) override {
    ++starts;
    g_assert_cmpstr(executable.c_str(), ==, "/trusted/legion_cli");
    g_assert_cmpuint(arguments.size(), ==, 1);
    g_assert_cmpstr(arguments.front().c_str(), ==, "--help");
    g_assert_cmpuint(runtime, ==, 3);
    pending = std::make_shared<PendingOperation>();
    pending->completion = std::move(completion);
    g_idle_add(
        [](gpointer data) -> gboolean {
          auto *runner = static_cast<PendingRunner *>(data);
          g_assert_cmpint(write(runner->signal, "x", 1), ==, 1);
          return G_SOURCE_REMOVE;
        },
        this);
    return pending;
  }
};
void test_lifetime_cancels_and_drains() {
  for (const bool app_exits : {true, false}) {
    int app[2], launcher[2];
    g_assert_cmpint(pipe(app), ==, 0);
    g_assert_cmpint(pipe(launcher), ==, 0);
    auto runner =
        std::make_shared<PendingRunner>(app_exits ? app[1] : launcher[1]);
    GError *error = nullptr;
    g_assert_false(legion_control::QualifyPortableCli(
        runner, "/trusted/legion_cli", app[0], launcher[0], &error));
    g_assert_nonnull(error);
    g_clear_error(&error);
    g_assert_cmpuint(runner->starts, ==, 1);
    g_assert_cmpuint(runner->pending->cancels, ==, 1);
    g_assert_cmpuint(runner->pending->completions, ==, 1);
    close(app[0]);
    close(app[1]);
    close(launcher[0]);
    close(launcher[1]);
  }
};
void test_dead_session_never_starts_cli() {
  auto runner = std::make_shared<PendingRunner>(-1);
  GError *error = nullptr;
  g_assert_false(legion_control::QualifyPortableCli(
      runner, "/trusted/legion_cli", -1, -1, &error));
  g_assert_error(error, G_IO_ERROR, G_IO_ERROR_CLOSED);
  g_clear_error(&error);
  g_assert_cmpuint(runner->starts, ==, 0);
};
void test_supported_help() {
  std::string error;
  g_assert_true(
      legion_control::ValidatePortableCliHelp(cli_help_fixture, &error));
  g_assert_true(error.empty());
}
void test_missing_command() {
  std::string help(cli_help_fixture), error;
  const auto position = help.find("graphics-mode");
  help.replace(position, strlen("graphics-mode"), "graphics-mode-extra");
  g_assert_false(legion_control::ValidatePortableCliHelp(help, &error));
  g_assert_nonnull(strstr(error.c_str(), "graphics-mode"));
}
void test_missing_flag_and_choices() {
  std::string help(cli_help_fixture), error;
  help.replace(help.find("--donotexpecthwmon"), strlen("--donotexpecthwmon"),
               "--donotexpecthwmon-extra");
  g_assert_false(legion_control::ValidatePortableCliHelp(help, &error));
  g_assert_false(legion_control::ValidatePortableCliHelp(
      "--donotexpecthwmon {set-feature} graphics-mode", &error));
  g_assert_false(
      legion_control::ValidatePortableCliHelp(std::string(65537, 'x'), &error));
}
} // namespace

int main(int argc, char **argv) {
  g_test_init(&argc, &argv, nullptr);
  g_test_add_func("/portable-cli/supported-help", test_supported_help);
  g_test_add_func("/portable-cli/exact-command", test_missing_command);
  g_test_add_func("/portable-cli/missing-syntax",
                  test_missing_flag_and_choices);
  g_test_add_func("/portable-cli/lifetime-cancellation",
                  test_lifetime_cancels_and_drains);
  g_test_add_func("/portable-cli/ended-session",
                  test_dead_session_never_starts_cli);
  return g_test_run();
}
