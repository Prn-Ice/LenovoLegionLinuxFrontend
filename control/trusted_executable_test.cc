#include "test/test_vm_guard.h"
#include "trusted_executable.h"

#include <cstdlib>
#include <fstream>
#include <gio/gio.h>
#include <sys/stat.h>
#include <unistd.h>

namespace {
void test_rejects_user_selector() {
  char *directory = g_dir_make_tmp("legion-cli-selector-XXXXXX", nullptr);
  g_assert_nonnull(directory);
  const std::string link = std::string(directory) + "/cli";
  g_assert_cmpint(symlink("/bin/true", link.c_str()), ==, 0);
  std::string resolved;
  g_assert_false(legion_control::TrustedExecutable(link, &resolved));
  g_assert_true(resolved.empty());
  unlink(link.c_str());
  rmdir(directory);
  g_free(directory);
}

bool RootVm() {
  if (getuid() == 0 && InControlTestVm())
    return true;
  g_test_skip("Root-owned fixtures run in the disposable control VM.");
  return false;
}

void test_root_links_and_permissions() {
  if (!RootVm())
    return;
  // Ubuntu mounts /run with noexec; this fixture needs an executable directory.
  char directory[] = "/var/lib/legion-trusted-cli-XXXXXX";
  g_assert_nonnull(mkdtemp(directory));
  const std::string executable = std::string(directory) + "/cli";
  std::ofstream(executable) << "#!/bin/sh\nexit 0\n";
  g_assert_cmpint(chmod(executable.c_str(), 0755), ==, 0);
  const std::string alias = std::string(directory) + "/alias";
  g_assert_cmpint(symlink("cli", alias.c_str()), ==, 0);
  std::string resolved;
  g_assert_true(legion_control::TrustedExecutable(alias, &resolved));
  g_assert_cmpstr(resolved.c_str(), ==, executable.c_str());
  g_assert_cmpint(chmod(executable.c_str(), 0775), ==, 0);
  g_assert_false(legion_control::TrustedExecutable(alias, &resolved));
  g_assert_cmpint(chmod(executable.c_str(), 0755), ==, 0);
  const std::string user_directory = std::string(directory) + "/user";
  g_assert_cmpint(mkdir(user_directory.c_str(), 0755), ==, 0);
  const std::string user_link = user_directory + "/selection";
  g_assert_cmpint(symlink("../cli", user_link.c_str()), ==, 0);
  g_assert_cmpint(chown(user_directory.c_str(), 1000, 1000), ==, 0);
  const std::string indirect = std::string(directory) + "/indirect";
  g_assert_cmpint(symlink("user/selection", indirect.c_str()), ==, 0);
  g_assert_false(legion_control::TrustedExecutable(indirect, &resolved));
  const std::string loop = std::string(directory) + "/loop";
  g_assert_cmpint(symlink("loop", loop.c_str()), ==, 0);
  g_assert_false(legion_control::TrustedExecutable(loop, &resolved));
  unlink(loop.c_str());
  unlink(indirect.c_str());
  unlink(user_link.c_str());
  rmdir(user_directory.c_str());
  unlink(alias.c_str());
  unlink(executable.c_str());
  rmdir(directory);
}

void test_fixed_host_discovery() {
  if (!RootVm())
    return;
  std::string error;
  const auto cli = legion_control::FindHostLegionCli(&error);
  g_assert_false(cli.empty());
  g_assert_true(error.empty());
  std::string resolved;
  g_assert_true(legion_control::TrustedExecutable(cli, &resolved));
  g_assert_cmpstr(resolved.c_str(), ==, cli.c_str());
}

void test_read_only_discovery() {
  std::string error;
  const auto cli = legion_control::FindHostLegionCli(
      &error, legion_control::CliAccess::readOnly);
  if (cli.empty()) {
    g_test_skip("No fixed-location CLI is available for read-only discovery.");
    return;
  }
  g_assert_true(error.empty());
  struct stat info{};
  g_assert_cmpint(stat(cli.c_str(), &info), ==, 0);
  g_assert_true(S_ISREG(info.st_mode));
  g_assert_cmpint(access(cli.c_str(), X_OK), ==, 0);
  g_test_message("READ_CLI %s", cli.c_str());
}
} // namespace

int main(int argc, char **argv) {
  g_test_init(&argc, &argv, nullptr);
  g_test_add_func("/trusted-executable/reject-user-selector",
                  test_rejects_user_selector);
  g_test_add_func("/trusted-executable/root-links",
                  test_root_links_and_permissions);
  g_test_add_func("/trusted-executable/host-cli", test_fixed_host_discovery);
  g_test_add_func("/trusted-executable/read-cli", test_read_only_discovery);
  return g_test_run();
}
