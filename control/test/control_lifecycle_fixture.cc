#include "test_vm_guard.h"
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <fcntl.h>
#include <signal.h>
#include <string>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

namespace {
constexpr char directory[] = "/tmp/legion-fixture";

bool WriteAll(int fd, const void *data, size_t size) {
  const auto *bytes = static_cast<const char *>(data);
  size_t written = 0;
  while (written < size) {
    const ssize_t count = write(fd, bytes + written, size - written);
    if (count < 0 && errno == EINTR)
      continue;
    if (count <= 0)
      return false;
    written += static_cast<size_t>(count);
  }
  return true;
}

bool WriteFile(const char *name, const std::string &value) {
  const std::string path = std::string(directory) + "/" + name;
  const int fd =
      open(path.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
  if (fd < 0)
    return false;
  const bool written = WriteAll(fd, value.data(), value.size());
  const bool closed = close(fd) == 0;
  return written && closed;
}

[[noreturn]] void WaitForKill() {
  for (;;)
    pause();
}

// Both surviving descendants leave the original process group. The immediate
// child exits, so the grandchildren are also reparented away from the backend.
bool StartDetachedTree(bool resist_termination) {
  int ready[2];
  if (pipe2(ready, O_CLOEXEC) != 0)
    return false;
  signal(SIGTERM, resist_termination ? SIG_IGN : SIG_DFL);
  signal(SIGPIPE, SIG_IGN);
  const pid_t child = fork();
  if (child == -1) {
    close(ready[0]);
    close(ready[1]);
    return false;
  }
  if (child == 0) {
    close(ready[0]);
    if (setsid() == -1)
      _exit(70);
    const pid_t grandchild = fork();
    if (grandchild == -1)
      _exit(70);
    if (grandchild != 0)
      _exit(0);
    const pid_t leaf = fork();
    if (leaf == -1)
      _exit(70);
    const pid_t pid = getpid();
    if (!WriteAll(ready[1], &pid, sizeof(pid)))
      _exit(70);
    close(ready[1]);
    WaitForKill();
  }
  close(ready[1]);
  pid_t descendants[2] = {};
  size_t received = 0;
  while (received < sizeof(descendants)) {
    const ssize_t count =
        read(ready[0], reinterpret_cast<char *>(descendants) + received,
             sizeof(descendants) - received);
    if (count < 0 && errno == EINTR)
      continue;
    if (count <= 0)
      break;
    received += static_cast<size_t>(count);
  }
  close(ready[0]);
  int status = 0;
  while (waitpid(child, &status, 0) == -1 && errno == EINTR) {
  }
  if (received != sizeof(descendants) || !WIFEXITED(status) ||
      WEXITSTATUS(status) != 0)
    return false;
  const std::string pids = std::to_string(getpid()) + "\n" +
                           std::to_string(descendants[0]) + "\n" +
                           std::to_string(descendants[1]) + "\n";
  return WriteFile("pids", pids) && WriteFile("ready", "ready\n");
}
} // namespace

int main(int argc, char **argv) {
  if (!InControlTestVm()) {
    fprintf(stderr,
            "This backend runs only in the disposable control test VM.\n");
    return 2;
  }
  const bool toggle = argc == 3 &&
                      std::string(argv[1]) == "--donotexpecthwmon" &&
                      (std::string(argv[2]) == "batteryconservation-enable" ||
                       std::string(argv[2]) == "batteryconservation-disable");
  const bool graphics = argc == 6 &&
                        std::string(argv[1]) == "--donotexpecthwmon" &&
                        std::string(argv[2]) == "graphics-mode" &&
                        std::string(argv[3]) == "set" &&
                        std::string(argv[4]) == "hybrid-igpu-only" &&
                        std::string(argv[5]) == "--json";
  const bool fan =
      argc == 3 && std::string(argv[1]) == "fancurve-write-file-to-hw";
  if (!toggle && !graphics && !fan)
    return 64;

  std::ifstream mode_file(std::string(directory) + "/mode");
  std::string mode;
  std::getline(mode_file, mode);
  if (fan) {
    struct stat info{};
    if (stat(argv[2], &info) != 0 || info.st_uid != 0 ||
        (info.st_mode & 0777) != 0600)
      return 65;
    std::ifstream file(argv[2]);
    const std::string payload((std::istreambuf_iterator<char>(file)),
                              std::istreambuf_iterator<char>());
    if (payload != "synthetic fan data\n" ||
        !WriteFile("payload-read", payload))
      return 65;
    if (mode == "success")
      return 0;
  }
  if (mode == "success") {
    if (toggle &&
        !WriteFile("battery-conservation",
                   std::string(argv[2]) == "batteryconservation-enable"
                       ? "enabled\n"
                       : "disabled\n"))
      return 65;
    puts("synthetic backend completed");
    return 0;
  }
  if (mode == "graphics-blocked")
    return 2;
  if (mode == "graphics-pending")
    return 3;
  if (mode != "tree" && mode != "orphan-stdout" && mode != "flood")
    return 64;
  if (!StartDetachedTree(mode != "orphan-stdout"))
    return 70;
  if (mode == "orphan-stdout")
    return 0;
  if (mode == "flood") {
    const std::string output(4096, 'x');
    for (int index = 0; index < 64; ++index) {
      if (!WriteAll(STDOUT_FILENO, output.data(), output.size()))
        break;
    }
  }
  WaitForKill();
}
