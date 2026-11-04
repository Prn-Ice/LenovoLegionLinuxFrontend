#include "executable_snapshot.h"

#include <cerrno>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <elf.h>
#include <fcntl.h>
#include <linux/memfd.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <vector>

namespace legion_control {
namespace {
constexpr size_t maximum_size = 64 * 1024 * 1024;

bool Fail(std::string *error, const char *message) {
  *error = message;
  return false;
}

bool Range(size_t size, Elf64_Off offset, Elf64_Xword length) {
  return offset <= size && length <= size - offset;
}

// Check both the named path and its canonical target: a user-owned symlink to
// a trusted directory could otherwise be replaced during authorization.
bool RootControlled(const std::string &path, bool directory) {
  if (path.empty() || path.front() != '/' ||
      path.find('$') != std::string::npos)
    return false;
  for (size_t end = 1; end <= path.size(); ++end) {
    if (end != path.size() && path[end] != '/')
      continue;
    const auto prefix = path.substr(0, end);
    const auto slash = prefix.rfind('/');
    const auto component = prefix.substr(slash + 1);
    if (component == "." || component == "..")
      return false;
    struct stat info{};
    if (lstat(prefix.c_str(), &info) != 0 || info.st_uid != 0)
      return false;
    if (!S_ISLNK(info.st_mode) &&
        ((info.st_mode & S_IWOTH) ||
         ((info.st_mode & S_IWGRP) &&
          !(S_ISDIR(info.st_mode) && (info.st_mode & S_ISVTX)))))
      return false;
  }
  struct stat info{};
  if (stat(path.c_str(), &info) != 0)
    return false;
  if (directory ? !S_ISDIR(info.st_mode)
                : (!S_ISREG(info.st_mode) || !(info.st_mode & 0111)))
    return false;
  char *resolved = realpath(path.c_str(), nullptr);
  if (!resolved)
    return false;
  const std::string canonical = resolved;
  free(resolved);
  return canonical == path || RootControlled(canonical, directory);
}

bool SearchPath(const std::string &paths) {
  size_t start = 0;
  while (true) {
    const auto end = paths.find(':', start);
    if (!RootControlled(paths.substr(start, end - start), true))
      return false;
    if (end == std::string::npos)
      return true;
    start = end + 1;
  }
}

bool Validate(const std::vector<unsigned char> &bytes, std::string *error) {
  if (bytes.size() < sizeof(Elf64_Ehdr))
    return Fail(error, "helper is not a complete ELF executable");
  Elf64_Ehdr header;
  memcpy(&header, bytes.data(), sizeof(header));
  if (memcmp(header.e_ident, ELFMAG, SELFMAG) ||
      header.e_ident[EI_CLASS] != ELFCLASS64 ||
      header.e_ident[EI_DATA] != ELFDATA2LSB ||
      header.e_ident[EI_VERSION] != EV_CURRENT ||
      header.e_version != EV_CURRENT || header.e_machine != EM_X86_64 ||
      (header.e_type != ET_EXEC && header.e_type != ET_DYN) ||
      header.e_ehsize != sizeof(header) ||
      header.e_phentsize != sizeof(Elf64_Phdr) || !header.e_phnum ||
      header.e_phnum == PN_XNUM ||
      !Range(bytes.size(), header.e_phoff,
             size_t(header.e_phnum) * sizeof(Elf64_Phdr)))
    return Fail(error, "helper must be an x86-64 Linux ELF executable");

  std::vector<Elf64_Phdr> segments(header.e_phnum);
  memcpy(segments.data(), bytes.data() + header.e_phoff,
         segments.size() * sizeof(Elf64_Phdr));
  const Elf64_Phdr *dynamic = nullptr;
  bool interpreter = false, executable_segment = false;
  for (const auto &segment : segments) {
    if (!Range(bytes.size(), segment.p_offset, segment.p_filesz))
      return Fail(error, "helper contains an incomplete ELF segment");
    if (segment.p_type == PT_LOAD) {
      if (segment.p_memsz < segment.p_filesz ||
          segment.p_memsz > UINT64_MAX - segment.p_vaddr)
        return Fail(error, "helper contains an invalid load segment");
      for (const auto &other : segments) {
        if (&other != &segment && other.p_type == PT_LOAD &&
            other.p_vaddr <= segment.p_vaddr &&
            segment.p_vaddr - other.p_vaddr < other.p_memsz)
          return Fail(error, "helper contains overlapping load segments");
      }
      if (segment.p_flags & PF_X)
        executable_segment = true;
    }
    if (segment.p_type == PT_INTERP) {
      if (interpreter || !segment.p_filesz ||
          bytes[segment.p_offset + segment.p_filesz - 1] != 0)
        return Fail(error, "helper contains an invalid ELF interpreter");
      const char *path =
          reinterpret_cast<const char *>(bytes.data() + segment.p_offset);
      if (strlen(path) + 1 != segment.p_filesz || !RootControlled(path, false))
        return Fail(error, "helper interpreter must be controlled by root");
      interpreter = true;
    }
    if (segment.p_type == PT_DYNAMIC) {
      if (dynamic || segment.p_filesz % sizeof(Elf64_Dyn))
        return Fail(error, "helper contains an invalid dynamic section");
      dynamic = &segment;
    }
  }
  if (!executable_segment || interpreter != bool(dynamic))
    return Fail(error, "helper executable layout is unsupported");
  if (!dynamic)
    return true;
  bool mapped_dynamic = false;
  for (const auto &segment : segments) {
    if (segment.p_type != PT_LOAD || dynamic->p_vaddr < segment.p_vaddr)
      continue;
    const auto offset = dynamic->p_vaddr - segment.p_vaddr;
    if (offset <= segment.p_filesz &&
        dynamic->p_filesz <= segment.p_filesz - offset &&
        dynamic->p_offset == segment.p_offset + offset)
      mapped_dynamic = true;
  }
  if (!mapped_dynamic)
    return Fail(error,
                "helper dynamic section has an inconsistent load address");

  std::vector<Elf64_Dyn> entries;
  Elf64_Addr strings_address = 0;
  Elf64_Xword strings_size = 0;
  bool terminated = false;
  for (size_t offset = 0; offset < dynamic->p_filesz;
       offset += sizeof(Elf64_Dyn)) {
    Elf64_Dyn entry;
    memcpy(&entry, bytes.data() + dynamic->p_offset + offset, sizeof(entry));
    if (entry.d_tag == DT_NULL) {
      terminated = true;
      break;
    }
    if (entry.d_tag == DT_STRTAB) {
      if (strings_address)
        return Fail(error, "helper contains duplicate dynamic string tables");
      strings_address = entry.d_un.d_ptr;
    }
    if (entry.d_tag == DT_STRSZ) {
      if (strings_size)
        return Fail(error, "helper contains duplicate dynamic string sizes");
      strings_size = entry.d_un.d_val;
    }
    if (entry.d_tag == DT_CONFIG || entry.d_tag == DT_AUDIT ||
        entry.d_tag == DT_DEPAUDIT || entry.d_tag == DT_FILTER ||
        entry.d_tag == DT_AUXILIARY)
      return Fail(
          error,
          "helper may not load ELF configuration, audit or filter objects");
    entries.push_back(entry);
  }
  if (!terminated || !strings_address || !strings_size)
    return Fail(error, "helper dynamic string table is incomplete");
  const char *strings = nullptr;
  for (const auto &segment : segments) {
    if (segment.p_type == PT_LOAD && strings_address >= segment.p_vaddr) {
      const auto offset = strings_address - segment.p_vaddr;
      if (offset <= segment.p_filesz &&
          strings_size <= segment.p_filesz - offset)
        strings = reinterpret_cast<const char *>(bytes.data() +
                                                 segment.p_offset + offset);
    }
  }
  if (!strings)
    return Fail(error,
                "helper dynamic string table is outside its load segments");
  for (const auto &entry : entries) {
    if (entry.d_tag != DT_NEEDED && entry.d_tag != DT_RPATH &&
        entry.d_tag != DT_RUNPATH)
      continue;
    const auto offset = entry.d_un.d_val;
    if (offset >= strings_size ||
        !memchr(strings + offset, 0, strings_size - offset))
      return Fail(error, "helper contains an invalid dynamic string");
    const std::string value = strings + offset;
    if (entry.d_tag == DT_NEEDED) {
      if (value.empty() || value.find_first_of("/$") != std::string::npos)
        return Fail(error, "helper dependencies must use host library names");
    } else if (!SearchPath(value))
      return Fail(error,
                  "helper library search paths must be controlled by root");
  }
  return true;
}
} // namespace

int CreateExecutableSnapshot(int source_fd, std::string *error) {
  struct stat info{};
  if (fstat(source_fd, &info) != 0 || !S_ISREG(info.st_mode) ||
      info.st_size <= 0 || static_cast<uint64_t>(info.st_size) > maximum_size) {
    Fail(error, "helper must be a regular executable smaller than 64 MiB");
    return -1;
  }
  std::vector<unsigned char> bytes(static_cast<size_t>(info.st_size));
  size_t offset = 0;
  while (offset < bytes.size()) {
    const auto count =
        pread(source_fd, bytes.data() + offset, bytes.size() - offset, offset);
    if (count < 0 && errno == EINTR)
      continue;
    if (count <= 0) {
      Fail(error, "could not read the complete helper executable");
      return -1;
    }
    offset += count;
  }
  if (!Validate(bytes, error))
    return -1;

  unsigned flags = MFD_CLOEXEC | MFD_ALLOW_SEALING;
#ifdef MFD_EXEC
  flags |= MFD_EXEC;
#endif
  int snapshot = syscall(SYS_memfd_create, "legion-portable-helper", flags);
#ifdef MFD_EXEC
  if (snapshot < 0 && errno == EINVAL)
    snapshot = syscall(SYS_memfd_create, "legion-portable-helper",
                       MFD_CLOEXEC | MFD_ALLOW_SEALING);
#endif
  if (snapshot < 0) {
    Fail(error, "this host could not create an executable snapshot");
    return -1;
  }
  offset = 0;
  while (offset < bytes.size()) {
    const auto count =
        write(snapshot, bytes.data() + offset, bytes.size() - offset);
    if (count < 0 && errno == EINTR)
      continue;
    if (count <= 0)
      break;
    offset += count;
  }
  constexpr int seals =
      F_SEAL_WRITE | F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_SEAL;
  if (offset != bytes.size() || fchmod(snapshot, 0500) != 0 ||
      fcntl(snapshot, F_ADD_SEALS, seals) != 0 ||
      fcntl(snapshot, F_GET_SEALS) < 0 ||
      (fcntl(snapshot, F_GET_SEALS) & seals) != seals) {
    close(snapshot);
    Fail(error, "could not seal the complete helper executable");
    return -1;
  }
  return snapshot;
}
} // namespace legion_control
