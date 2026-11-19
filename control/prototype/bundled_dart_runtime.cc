#include "bundled_dart_runtime.h"
#include "../portable_unit.h"

#include <cerrno>
#include <cstddef>
#include <cstring>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

extern const unsigned char _binary_dartaotruntime_start[];
extern const unsigned char _binary_dartaotruntime_end[];
extern const unsigned char _binary_helper_aot_start[];
extern const unsigned char _binary_helper_aot_end[];
extern const unsigned char _binary_lib_ld_linux_x86_64_so_2_start[];
extern const unsigned char _binary_lib_ld_linux_x86_64_so_2_end[];
extern const unsigned char _binary_lib_libc_so_6_start[];
extern const unsigned char _binary_lib_libc_so_6_end[];
extern const unsigned char _binary_lib_libm_so_6_start[];
extern const unsigned char _binary_lib_libm_so_6_end[];
extern const unsigned char _binary_lib_libdl_so_2_start[];
extern const unsigned char _binary_lib_libdl_so_2_end[];
extern const unsigned char _binary_lib_libpthread_so_0_start[];
extern const unsigned char _binary_lib_libpthread_so_0_end[];

namespace legion_control {
namespace bundled_dart {
namespace {
struct File {
  const char *name;
  const unsigned char *start;
  const unsigned char *end;
  mode_t mode;
};

const File files[] = {
    {"dartaotruntime", _binary_dartaotruntime_start,
     _binary_dartaotruntime_end, 0500},
    {"helper.aot", _binary_helper_aot_start, _binary_helper_aot_end, 0400},
    {"lib/ld-linux-x86-64.so.2", _binary_lib_ld_linux_x86_64_so_2_start,
     _binary_lib_ld_linux_x86_64_so_2_end, 0500},
    {"lib/libc.so.6", _binary_lib_libc_so_6_start,
     _binary_lib_libc_so_6_end, 0400},
    {"lib/libm.so.6", _binary_lib_libm_so_6_start,
     _binary_lib_libm_so_6_end, 0400},
    {"lib/libdl.so.2", _binary_lib_libdl_so_2_start,
     _binary_lib_libdl_so_2_end, 0400},
    {"lib/libpthread.so.0", _binary_lib_libpthread_so_0_start,
     _binary_lib_libpthread_so_0_end, 0400},
};

bool Fail(std::string *error, const char *message) {
  *error = message;
  return false;
}

bool OwnedDirectory(int fd, mode_t expected, uid_t owner, std::string *error) {
  struct stat info {};
  if (fstat(fd, &info) != 0 || info.st_uid != owner || !S_ISDIR(info.st_mode) ||
      (info.st_mode & 0777) != expected)
    return Fail(error, "runtime directory is not root-owned with the expected mode");
  return true;
}

// Write one fixed embedded file without following or replacing an existing path.
bool WriteFile(int directory, const File &file, std::vector<std::string> *made,
               std::string *error) {
  const int fd = openat(directory, file.name, O_WRONLY | O_CREAT | O_EXCL |
                                             O_CLOEXEC | O_NOFOLLOW,
                        file.mode);
  if (fd < 0)
    return Fail(error, "runtime file already exists or is unsafe");
  const size_t size = static_cast<size_t>(file.end - file.start);
  size_t offset = 0;
  while (offset < size) {
    const ssize_t count =
        write(fd, file.start + offset, size - offset);
    if (count < 0 && errno == EINTR)
      continue;
    if (count <= 0) {
      close(fd);
      unlinkat(directory, file.name, 0);
      return Fail(error, "could not write bundled runtime file");
    }
    offset += static_cast<size_t>(count);
  }
  const bool mode_set = fchmod(fd, file.mode) == 0;
  const bool closed = close(fd) == 0;
  if (!mode_set || !closed) {
    unlinkat(directory, file.name, 0);
    return Fail(error, "could not set bundled runtime file mode");
  }
  made->push_back(file.name);
  return true;
}
}  // namespace

bool StageAt(const std::string &parent, const std::string &unit, uid_t owner,
             std::string *runtime, std::string *error) {
  // Validate the complete unit name before turning it into a filesystem path.
  if (!legion_control::ValidPortableUnit(unit))
    return Fail(error, "invalid bundled runtime unit");
  const std::string base = unit.substr(0, unit.size() - 8);
  const std::string path = parent + "/" + base + "/dart";
  const int run =
      open(parent.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  if (run < 0)
    return Fail(error, "could not open the runtime parent directory");
  if (!OwnedDirectory(run, 0755, owner, error)) {
    close(run);
    return false;
  }
  const int unit_directory =
      openat(run, base.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  close(run);
  if (unit_directory < 0)
    return Fail(error, "could not open the service runtime directory");
  if (!OwnedDirectory(unit_directory, 0711, owner, error)) {
    close(unit_directory);
    return false;
  }
  if (mkdirat(unit_directory, "dart", 0700) != 0) {
    close(unit_directory);
    return Fail(error, "bundled runtime directory already exists or is unsafe");
  }
  const int dart = openat(unit_directory, "dart",
                          O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  if (dart < 0 || !OwnedDirectory(dart, 0700, owner, error)) {
    if (dart >= 0)
      close(dart);
    unlinkat(unit_directory, "dart", AT_REMOVEDIR);
    close(unit_directory);
    return false;
  }
  if (mkdirat(dart, "lib", 0700) != 0) {
    close(dart);
    unlinkat(unit_directory, "dart", AT_REMOVEDIR);
    close(unit_directory);
    return Fail(error, "could not create bundled runtime library directory");
  }
  const int library = openat(dart, "lib",
                             O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  if (library < 0 || !OwnedDirectory(library, 0700, owner, error)) {
    if (library >= 0)
      close(library);
    unlinkat(dart, "lib", AT_REMOVEDIR);
    unlinkat(unit_directory, "dart", AT_REMOVEDIR);
    close(dart);
    close(unit_directory);
    return false;
  }
  close(library);

  std::vector<std::string> made;
  for (const auto &file : files) {
    if (!WriteFile(dart, file, &made, error)) {
      for (const auto &name : made)
        unlinkat(dart, name.c_str(), 0);
      unlinkat(dart, "lib", AT_REMOVEDIR);
      close(dart);
      unlinkat(unit_directory, "dart", AT_REMOVEDIR);
      close(unit_directory);
      return false;
    }
  }
  close(dart);
  close(unit_directory);
  *runtime = path;
  return true;
}

// Stage the sealed bundle below the systemd-owned unit directory.
bool Stage(const std::string &unit, std::string *runtime, std::string *error) {
  return StageAt("/run", unit, 0, runtime, error);
}

#ifdef LEGION_BUNDLED_DART_TEST
bool StageForTest(const std::string &parent, const std::string &unit,
                  uid_t owner, std::string *runtime, std::string *error) {
  return StageAt(parent, unit, owner, runtime, error);
}
#endif
}  // namespace bundled_dart
}  // namespace legion_control
