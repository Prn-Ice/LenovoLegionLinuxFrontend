// A bounded cleanup image: no loader, libraries, backend commands, or file
// writes.
#include <fcntl.h>
#include <sys/syscall.h>

namespace {
long Call(long number, long first = 0, long second = 0, long third = 0) {
  long result;
  asm volatile("syscall"
               : "=a"(result)
               : "a"(number), "D"(first), "S"(second), "d"(third)
               : "rcx", "r11", "cc", "memory");
  return result;
}
} // namespace

extern "C" [[noreturn]] void CleanupMain() {
  int status = 2;
  if (Call(SYS_getuid) == 0 && Call(SYS_geteuid) == 0) {
    constexpr char executable[] = "/proc/self/exe";
    const long fd = Call(SYS_openat, AT_FDCWD,
                         reinterpret_cast<long>(executable), O_RDONLY);
    constexpr int required =
        F_SEAL_WRITE | F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_SEAL;
    const long seals = fd < 0 ? -1 : Call(SYS_fcntl, fd, F_GET_SEALS);
    if (fd >= 0)
      Call(SYS_close, fd);
    if (seals >= 0 && (seals & required) == required) {
      constexpr char message[] = "Legion control cleanup complete.\n";
      status =
          Call(SYS_write, 1, reinterpret_cast<long>(message),
               sizeof(message) - 1) == static_cast<long>(sizeof(message) - 1)
              ? 0
              : 1;
    }
  }
  Call(SYS_exit_group, status);
  __builtin_unreachable();
}

extern "C" __attribute__((naked, noreturn)) void _start() {
  asm volatile("andq $-16, %rsp\n\tcall CleanupMain\n\tud2");
}
