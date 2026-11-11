#include "trusted_executable.h"

#include <cerrno>
#include <climits>
#include <deque>
#include <fcntl.h>
#include <sstream>
#include <sys/stat.h>
#include <unistd.h>
#include <utility>

namespace legion_control {
namespace {
struct Descriptor {
  int value;
  explicit Descriptor(int fd) : value(fd) {}
  Descriptor(const Descriptor &) = delete;
  ~Descriptor() {
    if (value >= 0)
      close(value);
  }
};

void Prepend(const std::string &path, std::deque<std::string> *parts) {
  std::deque<std::string> prefix;
  std::istringstream input(path);
  std::string part;
  while (std::getline(input, part, '/'))
    if (!part.empty() && part != ".")
      prefix.push_back(part);
  parts->insert(parts->begin(), prefix.begin(), prefix.end());
}

bool SafeDirectory(const struct stat &info) {
  return info.st_uid == 0 && S_ISDIR(info.st_mode) &&
         !(info.st_mode & S_IWOTH) &&
         (!(info.st_mode & S_IWGRP) || (info.st_mode & S_ISVTX));
}
bool CanonicalPath(int descriptor, std::string *resolved) {
  char canonical[PATH_MAX];
  const std::string path = "/proc/self/fd/" + std::to_string(descriptor);
  const auto length = readlink(path.c_str(), canonical, sizeof(canonical));
  if (length <= 0 || length >= PATH_MAX || canonical[0] != '/')
    return false;
  *resolved = std::string(canonical, static_cast<size_t>(length));
  return true;
}
enum class PathKind { executable, directory };

bool TrustedPath(const std::string &input, std::string *resolved,
                 PathKind kind) {
  const std::string requested = input;
  resolved->clear();
  if (requested.empty() || requested[0] != '/' ||
      requested.size() >= PATH_MAX || requested.find('\0') != std::string::npos)
    return false;
  Descriptor directory(open("/", O_PATH | O_DIRECTORY | O_CLOEXEC));
  struct stat info{};
  if (directory.value < 0 || fstat(directory.value, &info) != 0 ||
      !SafeDirectory(info))
    return false;
  std::deque<std::string> parts;
  Prepend(requested, &parts);
  unsigned links = 0;
  while (!parts.empty()) {
    const std::string part = parts.front();
    parts.pop_front();
    Descriptor next(
        openat(directory.value, part.c_str(), O_PATH | O_NOFOLLOW | O_CLOEXEC));
    if (next.value < 0 || fstat(next.value, &info) != 0 || info.st_uid != 0)
      return false;
    if (S_ISLNK(info.st_mode)) {
      if (++links > 40)
        return false;
      char target[PATH_MAX];
      const auto length = readlinkat(next.value, "", target, sizeof(target));
      if (length <= 0 || length >= PATH_MAX)
        return false;
      const std::string link(target, static_cast<size_t>(length));
      if (link[0] == '/') {
        Descriptor root(open("/", O_PATH | O_DIRECTORY | O_CLOEXEC));
        if (root.value < 0)
          return false;
        std::swap(directory.value, root.value);
      }
      Prepend(link, &parts);
    } else if (S_ISDIR(info.st_mode)) {
      if (!SafeDirectory(info))
        return false;
      std::swap(directory.value, next.value);
    } else {
      if (kind != PathKind::executable || !parts.empty() ||
          !S_ISREG(info.st_mode) || !info.st_nlink ||
          (info.st_mode & (S_IWGRP | S_IWOTH)) ||
          !(info.st_mode & (S_IXUSR | S_IXGRP | S_IXOTH)))
        return false;
      std::string path;
      if (!CanonicalPath(next.value, &path) || access(path.c_str(), X_OK) != 0)
        return false;
      *resolved = path;
      return true;
    }
  }
  return kind == PathKind::directory &&
         CanonicalPath(directory.value, resolved);
}
} // namespace

bool TrustedExecutable(const std::string &input, std::string *resolved) {
  return TrustedPath(input, resolved, PathKind::executable);
}
bool TrustedDirectory(const std::string &input, std::string *resolved) {
  return TrustedPath(input, resolved, PathKind::directory);
}

std::string FindHostLegionCli(std::string *error) {
  error->clear();
  for (const char *candidate :
       {"/run/current-system/sw/bin/legion_cli",
        "/nix/var/nix/profiles/default/bin/legion_cli", "/usr/bin/legion_cli",
        "/usr/local/bin/legion_cli"}) {
    struct stat info{};
    if (lstat(candidate, &info) != 0 && (errno == ENOENT || errno == ENOTDIR))
      continue;
    std::string resolved;
    if (TrustedExecutable(candidate, &resolved))
      return resolved;
    *error = std::string("Installed CLI path is unsafe or inaccessible: ") +
             candidate;
    return {};
  }
  *error = "Install legion_cli in an administrator-controlled host location.";
  return {};
}
} // namespace legion_control
