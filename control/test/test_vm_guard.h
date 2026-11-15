#ifndef LEGION_CONTROL_TEST_VM_GUARD_H_
#define LEGION_CONTROL_TEST_VM_GUARD_H_

#include <fstream>
#include <string>
#include <sys/stat.h>

inline bool InControlTestVm() {
  constexpr char marker[] = "/etc/legion-control-lifecycle-test-vm";
  struct stat info{};
  if (stat(marker, &info) != 0 || !S_ISREG(info.st_mode) || info.st_uid != 0 ||
      (info.st_mode & (S_IWGRP | S_IWOTH)) != 0)
    return false;
  std::ifstream stream(marker);
  std::string contents;
  std::getline(stream, contents);
  return contents == "legion-control-disposable-lifecycle-vm";
}

#endif
