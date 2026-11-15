#include "portable_cli.h"
#include "control_commands.h"

#include <glib-unix.h>
#include <poll.h>
#include <set>

namespace legion_control {
namespace {
bool Alive(int fd) {
  pollfd process{fd, POLLIN, 0};
  return fd >= 0 && poll(&process, 1, 0) == 0;
}
std::set<std::string> Tokens(const std::string &text) {
  std::set<std::string> result;
  std::string token;
  for (const unsigned char character : text) {
    if (g_ascii_isalnum(character) || character == '-' || character == '_')
      token += character;
    else if (!token.empty()) {
      result.insert(token);
      token.clear();
    }
  }
  if (!token.empty())
    result.insert(token);
  return result;
}
} // namespace

bool ValidatePortableCliHelp(const std::string &help, std::string *error) {
  error->clear();
  if (help.size() > 64 * 1024 || help.find('\0') != std::string::npos) {
    *error =
        "Installed legion_cli --help returned invalid or excessive output.";
    return false;
  }
  if (!Tokens(help).count("--donotexpecthwmon")) {
    *error = "Installed legion_cli did not advertise --donotexpecthwmon.";
    return false;
  }
  // argparse also puts choices such as log levels in braces. Select its
  // command group, and require exact names rather than substring matches.
  size_t begin = help.find('{');
  while (begin != std::string::npos) {
    const auto end = help.find('}', begin + 1);
    if (end == std::string::npos)
      break;
    const auto commands = Tokens(help.substr(begin + 1, end - begin - 1));
    begin = help.find('{', end + 1);
    if (!commands.count("set-feature"))
      continue;
    for (const auto &command : InteractiveCliCommands()) {
      if (!commands.count(command)) {
        *error = "Installed legion_cli is missing command: " + command;
        return false;
      }
    }
    return true;
  }
  *error = "Installed legion_cli did not report its supported commands.";
  return false;
}

bool QualifyPortableCli(std::shared_ptr<ManagedCommandRunner> runner,
                        const std::string &cli, int app, int launcher,
                        GError **error) {
  if (!Alive(app) || !Alive(launcher)) {
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_CLOSED,
                        "The app session ended before CLI qualification.");
    return false;
  }
  struct Qualification {
    GMainLoop *loop = g_main_loop_new(nullptr, FALSE);
    std::shared_ptr<ManagedCommandOperation> operation;
    ManagedCommandResult result;
    bool ended = false;
    guint app_watch = 0, launcher_watch = 0;
  } check;
  check.operation =
      runner->Start(cli, {"--help"}, 3, [&check](ManagedCommandResult result) {
        check.result = std::move(result);
        g_main_loop_quit(check.loop);
      });
  auto cancel = [](gint, GIOCondition, gpointer data) -> gboolean {
    auto *check = static_cast<Qualification *>(data);
    check->ended = true;
    check->operation->Cancel();
    for (guint *watch : {&check->app_watch, &check->launcher_watch}) {
      if (*watch) {
        g_source_remove(*watch);
        *watch = 0;
      }
    }
    return G_SOURCE_REMOVE;
  };
  check.app_watch = g_unix_fd_add(app, G_IO_IN, cancel, &check);
  check.launcher_watch = g_unix_fd_add(launcher, G_IO_IN, cancel, &check);
  g_main_loop_run(check.loop);
  if (check.app_watch)
    g_source_remove(check.app_watch);
  if (check.launcher_watch)
    g_source_remove(check.launcher_watch);
  g_main_loop_unref(check.loop);
  std::string reason;
  if (check.ended || !Alive(app) || !Alive(launcher))
    reason = "The app session ended during CLI qualification.";
  else if (check.result.status != ManagedCommandStatus::success ||
           check.result.exit_status != 0)
    reason = "Installed legion_cli --help failed: " +
             (check.result.error.empty()
                  ? "exit status " + std::to_string(check.result.exit_status)
                  : check.result.error);
  else if (ValidatePortableCliHelp(check.result.output, &reason))
    return true;
  g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_FAILED, reason.c_str());
  return false;
}
} // namespace legion_control
