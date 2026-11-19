#include "bundled_dart_runtime.h"

#include <cstdio>
#include <cstdlib>
#include <signal.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <unistd.h>

namespace {
void Require(bool condition, const char *message) {
  if (!condition) {
    fprintf(stderr, "bundled runtime test: %s\n", message);
    exit(1);
  }
}

void MakeDirectory(const std::string &path, mode_t mode) {
  Require(mkdir(path.c_str(), mode) == 0, "could not create test directory");
  Require(chmod(path.c_str(), mode) == 0, "could not set test directory mode");
}

void RemoveRuntime(const std::string &runtime) {
  const char *names[] = {"dartaotruntime", "helper.aot"};
  for (const char *name : names)
    Require(unlink((runtime + "/" + name).c_str()) == 0,
            "could not remove staged executable");
  const char *libraries[] = {"ld-linux-x86-64.so.2", "libc.so.6", "libm.so.6",
                             "libdl.so.2", "libpthread.so.0"};
  for (const char *name : libraries)
    Require(unlink((runtime + "/lib/" + name).c_str()) == 0,
            "could not remove staged library");
  Require(rmdir((runtime + "/lib").c_str()) == 0,
          "could not remove staged library directory");
  Require(rmdir(runtime.c_str()) == 0, "could not remove staged directory");
}
}  // namespace

int main() {
  char temporary[] = "/tmp/legion-bundled-dart-XXXXXX";
  Require(mkdtemp(temporary) != nullptr, "could not create temporary directory");
  const std::string parent = temporary;
  Require(chmod(parent.c_str(), 0755) == 0, "could not set parent mode");
  const uid_t owner = getuid();
  const uid_t wrong_owner = owner == 0 ? 1 : 0;
  const std::string unit =
      "legion-bootstrap-probe-00000000-0000-4000-8000-000000000000.service";
  const std::string unit_directory =
      parent + "/legion-bootstrap-probe-00000000-0000-4000-8000-000000000000";
  MakeDirectory(unit_directory, 0711);

  std::string runtime, error;
  Require(legion_control::bundled_dart::StageForTest(
              parent, unit, owner, &runtime, &error),
          "valid unit did not stage");
  struct stat info {};
  Require(stat((runtime + "/dartaotruntime").c_str(), &info) == 0,
          "staged executable is missing");
  Require((info.st_mode & 0777) == 0500, "staged executable has wrong mode");
  Require(stat((runtime + "/lib/ld-linux-x86-64.so.2").c_str(), &info) == 0,
          "staged loader is missing");
  Require((info.st_mode & 0777) == 0500, "staged loader is not executable");
  error.clear();
  Require(!legion_control::bundled_dart::StageForTest(
              parent, unit, owner, &runtime, &error),
          "pre-existing runtime was replaced");
  RemoveRuntime(runtime);

  Require(chmod(parent.c_str(), 0700) == 0, "could not set bad parent mode");
  error.clear();
  Require(!legion_control::bundled_dart::StageForTest(
              parent, unit, owner, &runtime, &error),
          "bad parent mode was accepted");
  Require(chmod(parent.c_str(), 0755) == 0, "could not restore parent mode");
  error.clear();
  Require(!legion_control::bundled_dart::StageForTest(
              parent, unit, wrong_owner, &runtime, &error),
          "wrong parent owner was accepted");

  const std::string bad_unit_directory =
      parent + "/legion-bootstrap-probe-00000000-0000-4000-8000-000000000001";
  MakeDirectory(bad_unit_directory, 0700);
  error.clear();
  Require(!legion_control::bundled_dart::StageForTest(
              parent,
              "legion-bootstrap-probe-00000000-0000-4000-8000-000000000001.service",
              owner, &runtime, &error),
          "bad unit mode was accepted");
  Require(rmdir(bad_unit_directory.c_str()) == 0,
          "could not remove bad unit directory");

  error.clear();
  Require(!legion_control::bundled_dart::StageForTest(
              parent, "../escape.service", owner, &runtime, &error),
          "traversal unit was accepted");

  const std::string symlink_unit_directory =
      parent + "/legion-bootstrap-probe-00000000-0000-4000-8000-000000000002";
  const std::string sentinel = parent + "/sentinel";
  MakeDirectory(symlink_unit_directory, 0711);
  MakeDirectory(sentinel, 0700);
  Require(symlink("../sentinel", (symlink_unit_directory + "/dart").c_str()) == 0,
          "could not create dart symlink");
  error.clear();
  Require(!legion_control::bundled_dart::StageForTest(
              parent,
              "legion-bootstrap-probe-00000000-0000-4000-8000-000000000002.service",
              owner, &runtime, &error),
          "pre-existing dart symlink was accepted");
  Require(access((sentinel + "/dartaotruntime").c_str(), F_OK) != 0,
          "dart symlink target was modified");
  Require(unlink((symlink_unit_directory + "/dart").c_str()) == 0,
          "could not remove dart symlink");
  Require(rmdir(symlink_unit_directory.c_str()) == 0,
          "could not remove symlink unit directory");
  Require(rmdir(sentinel.c_str()) == 0, "could not remove sentinel");

  const std::string partial_unit_directory =
      parent + "/legion-bootstrap-probe-00000000-0000-4000-8000-000000000003";
  MakeDirectory(partial_unit_directory, 0711);
  const std::string preserved = partial_unit_directory + "/preserved";
  FILE *file = fopen(preserved.c_str(), "w");
  Require(file != nullptr, "could not create preserved file");
  Require(fputs("keep", file) >= 0 && fclose(file) == 0,
          "could not write preserved file");
  struct rlimit old_limit {};
  Require(getrlimit(RLIMIT_FSIZE, &old_limit) == 0,
          "could not read file-size limit");
  struct rlimit limited = old_limit;
  limited.rlim_cur = 1;
  Require(setrlimit(RLIMIT_FSIZE, &limited) == 0,
          "could not set file-size limit");
  signal(SIGXFSZ, SIG_IGN);
  error.clear();
  const bool staged_partial = legion_control::bundled_dart::StageForTest(
      parent,
      "legion-bootstrap-probe-00000000-0000-4000-8000-000000000003.service",
      owner, &runtime, &error);
  Require(setrlimit(RLIMIT_FSIZE, &old_limit) == 0,
          "could not restore file-size limit");
  Require(!staged_partial, "partial file write was accepted");
  Require(access((partial_unit_directory + "/dart").c_str(), F_OK) != 0,
          "partial runtime directory was not removed");
  Require(access(preserved.c_str(), F_OK) == 0,
          "pre-existing file was removed");
  Require(unlink(preserved.c_str()) == 0 &&
              rmdir(partial_unit_directory.c_str()) == 0,
          "could not remove partial test directory");

  Require(rmdir(unit_directory.c_str()) == 0,
          "could not remove initial unit directory");
  Require(rmdir(parent.c_str()) == 0, "could not remove temporary directory");
  return 0;
}
