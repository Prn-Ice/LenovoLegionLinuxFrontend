#include "executable_snapshot.h"
#include "test/test_vm_guard.h"

#include <cstring>
#include <elf.h>
#include <fcntl.h>
#include <glib.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <vector>

namespace {
template <typename T>
void Put(std::vector<unsigned char> &bytes, size_t offset, const T &value) {
  memcpy(bytes.data() + offset, &value, sizeof(value));
}

std::vector<unsigned char> Executable(bool dynamic = false,
                                      const std::string &library = "libc.so.6",
                                      Elf64_Sxword tag = DT_NEEDED) {
  std::vector<unsigned char> bytes(4096);
  Elf64_Ehdr header{};
  memcpy(header.e_ident, ELFMAG, SELFMAG);
  header.e_ident[EI_CLASS] = ELFCLASS64;
  header.e_ident[EI_DATA] = ELFDATA2LSB;
  header.e_ident[EI_VERSION] = EV_CURRENT;
  header.e_type = ET_EXEC;
  header.e_machine = EM_X86_64;
  header.e_version = EV_CURRENT;
  header.e_entry = 0x400000 + 384;
  header.e_ehsize = sizeof(header);
  header.e_phoff = sizeof(header);
  header.e_phentsize = sizeof(Elf64_Phdr);
  header.e_phnum = dynamic ? 3 : 1;
  Put(bytes, 0, header);
  Elf64_Phdr load{};
  load.p_type = PT_LOAD;
  load.p_flags = PF_R | PF_X;
  load.p_vaddr = 0x400000;
  load.p_filesz = load.p_memsz = bytes.size();
  load.p_align = 4096;
  Put(bytes, sizeof(header), load);
  // x86-64 exit(23), with no libc or filesystem access.
  const unsigned char code[] = {0xb8, 60, 0, 0, 0,    0xbf,
                                23,   0,  0, 0, 0x0f, 0x05};
  memcpy(bytes.data() + 384, code, sizeof(code));
  if (!dynamic)
    return bytes;
  constexpr char loader[] = "/bin/sh";
  memcpy(bytes.data() + 512, loader, sizeof(loader));
  Elf64_Phdr interp{};
  interp.p_type = PT_INTERP;
  interp.p_offset = 512;
  interp.p_filesz = sizeof(loader);
  Put(bytes, sizeof(header) + sizeof(load), interp);
  Elf64_Phdr dyn{};
  dyn.p_type = PT_DYNAMIC;
  dyn.p_offset = 768;
  dyn.p_vaddr = 0x400000 + 768;
  dyn.p_filesz = 4 * sizeof(Elf64_Dyn);
  Put(bytes, sizeof(header) + 2 * sizeof(load), dyn);
  const Elf64_Dyn entries[] = {
      {DT_STRTAB, {0x400000 + 1024}},
      {DT_STRSZ, {library.size() + 1}},
      {tag, {0}},
      {DT_NULL, {0}},
  };
  memcpy(bytes.data() + 768, entries, sizeof(entries));
  memcpy(bytes.data() + 1024, library.c_str(), library.size() + 1);
  return bytes;
}

int Source(const std::vector<unsigned char> &bytes) {
  char *name = nullptr;
  GError *error = nullptr;
  const int fd = g_file_open_tmp("legion-snapshot-test-XXXXXX", &name, &error);
  g_assert_no_error(error);
  g_assert_cmpint(unlink(name), ==, 0);
  g_free(name);
  g_assert_cmpint(write(fd, bytes.data(), bytes.size()), ==,
                  static_cast<ssize_t>(bytes.size()));
  return fd;
}

void Reject(const std::vector<unsigned char> &bytes, const char *reason) {
  const int fd = Source(bytes);
  std::string error;
  g_assert_cmpint(legion_control::CreateExecutableSnapshot(fd, &error), ==, -1);
  g_test_message("rejected helper: %s", error.c_str());
  g_assert_nonnull(strstr(error.c_str(), reason));
  close(fd);
}

void test_snapshot_exec_and_mutation() {
  const auto bytes = Executable();
  const int source = Source(bytes);
  std::string error;
  const int snapshot = legion_control::CreateExecutableSnapshot(source, &error);
  g_assert_cmpstr(error.c_str(), ==, "");
  g_assert_cmpint(snapshot, >=, 0);
  // Simulate source mutation during the authorization wait.
  g_assert_cmpint(ftruncate(source, 0), ==, 0);
  close(source);
  g_assert_cmpint(pwrite(snapshot, "x", 1, 0), ==, -1);
  g_assert_cmpint(errno, ==, EPERM);
  g_assert_cmpint(ftruncate(snapshot, 0), ==, -1);
  g_assert_cmpint(errno, ==, EPERM);
  g_assert_cmpint(ftruncate(snapshot, bytes.size() + 1), ==, -1);
  g_assert_cmpint(errno, ==, EPERM);
  void *writable = mmap(nullptr, bytes.size(), PROT_READ | PROT_WRITE,
                        MAP_SHARED, snapshot, 0);
  g_assert_true(writable == MAP_FAILED);
  g_assert_cmpint(errno, ==, EPERM);
  const pid_t child = fork();
  g_assert_cmpint(child, >=, 0);
  if (child == 0) {
    char name[] = "snapshot-fixture";
    char *argv[] = {name, nullptr};
    char *environment[] = {nullptr};
    fexecve(snapshot, argv, environment);
    _exit(127);
  }
  int status;
  g_assert_cmpint(waitpid(child, &status, 0), ==, child);
  g_assert_true(WIFEXITED(status));
  g_assert_cmpint(WEXITSTATUS(status), ==, 23);
  close(snapshot);
}

void test_invalid_headers() {
  Reject({'#', '!', '/', 'b', 'i', 'n', '/', 's', 'h', '\n'}, "complete ELF");
  auto bytes = Executable();
  bytes[EI_CLASS] = ELFCLASS32;
  Reject(bytes, "x86-64");
  bytes = Executable();
  bytes.resize(sizeof(Elf64_Ehdr));
  Reject(bytes, "x86-64");
  bytes = Executable();
  Elf64_Off outside = UINT64_MAX;
  Put(bytes, offsetof(Elf64_Ehdr, e_phoff), outside);
  Reject(bytes, "x86-64");
  bytes = Executable();
  Elf64_Xword too_long = UINT64_MAX;
  Put(bytes, sizeof(Elf64_Ehdr) + offsetof(Elf64_Phdr, p_filesz), too_long);
  Reject(bytes, "incomplete ELF segment");
}

void test_dynamic_paths() {
  struct stat root{};
  g_assert_cmpint(stat("/", &root), ==, 0);
  if (root.st_uid != 0) {
    g_test_skip("Root ownership is remapped here; this check also runs inside "
                "the disposable VM.");
    return;
  }
  // Validate a safe dynamic layout before checking its unsafe variants. This
  // synthetic interpreter path is inspected only; the execution test is static.
  for (auto bytes : {Executable(true), Executable(true, "/", DT_RUNPATH)}) {
    const int source = Source(bytes);
    std::string error;
    const int snapshot =
        legion_control::CreateExecutableSnapshot(source, &error);
    g_assert_cmpstr(error.c_str(), ==, "");
    g_assert_cmpint(snapshot, >=, 0);
    close(snapshot);
    close(source);
  }
  for (const auto &value : {"$ORIGIN", "relative/lib", "", "/tmp", "/usr/lib:"})
    Reject(Executable(true, value, DT_RUNPATH), "controlled by root");
  char *directory = g_dir_make_tmp("legion-untrusted-loader-XXXXXX", nullptr);
  g_assert_nonnull(directory);
  Reject(Executable(true, directory, DT_RPATH), "controlled by root");
  // Also reject a user-owned symlink pointing to a root-controlled directory.
  const std::string alias = std::string(directory) + "/root";
  g_assert_cmpint(symlink("/", alias.c_str()), ==, 0);
  Reject(Executable(true, alias, DT_RUNPATH), "controlled by root");
  unlink(alias.c_str());
  rmdir(directory);
  g_free(directory);
  for (const auto &value : {"/tmp/lib.so", "$ORIGIN/lib.so", ""})
    Reject(Executable(true, value), "host library names");
  for (const auto tag :
       {DT_CONFIG, DT_AUDIT, DT_DEPAUDIT, DT_FILTER, DT_AUXILIARY})
    Reject(Executable(true, "lib.so", tag), "audit or filter");
}

void test_dynamic_strings() {
  struct stat root{};
  g_assert_cmpint(stat("/", &root), ==, 0);
  if (root.st_uid != 0) {
    g_test_skip("Root ownership is remapped here; this check also runs inside "
                "the disposable VM.");
    return;
  }
  auto bytes = Executable(true);
  Elf64_Dyn outside{DT_STRTAB, {UINT64_MAX}};
  Put(bytes, 768, outside);
  Reject(bytes, "outside its load segments");
  bytes = Executable(true);
  const Elf64_Addr wrong_address = 0x400000 + 2048;
  Put(bytes,
      sizeof(Elf64_Ehdr) + 2 * sizeof(Elf64_Phdr) +
          offsetof(Elf64_Phdr, p_vaddr),
      wrong_address);
  Reject(bytes, "inconsistent load address");
  bytes = Executable(true);
  bytes[1024 + strlen("libc.so.6")] = 'x';
  Reject(bytes, "invalid dynamic string");
  bytes = Executable(true);
  Elf64_Dyn no_end{DT_DEBUG, {0}};
  Put(bytes, 768 + 3 * sizeof(Elf64_Dyn), no_end);
  Reject(bytes, "incomplete");
}

void test_root_alias_crossing_user_directory() {
  g_assert_true(getuid() == 0 && InControlTestVm());
  char directory[] = "/run/legion-snapshot-path-XXXXXX";
  g_assert_nonnull(mkdtemp(directory));
  const std::string user = std::string(directory) + "/user";
  g_assert_cmpint(mkdir(user.c_str(), 0755), ==, 0);
  const std::string selection = user + "/lib";
  g_assert_cmpint(symlink("/", selection.c_str()), ==, 0);
  const std::string alias = std::string(directory) + "/alias";
  g_assert_cmpint(symlink("user/lib", alias.c_str()), ==, 0);
  g_assert_cmpint(chown(user.c_str(), 1000, 1000), ==, 0);
  Reject(Executable(true, alias, DT_RUNPATH), "controlled by root");
  unlink(alias.c_str());
  unlink(selection.c_str());
  rmdir(user.c_str());
  rmdir(directory);
}
void test_nonregular_source() {
  int descriptors[2];
  g_assert_cmpint(pipe(descriptors), ==, 0);
  std::string error;
  g_assert_cmpint(
      legion_control::CreateExecutableSnapshot(descriptors[0], &error), ==, -1);
  close(descriptors[0]);
  close(descriptors[1]);
}
} // namespace

int main(int argc, char **argv) {
  g_test_init(&argc, &argv, nullptr);
  g_test_add_func("/snapshot/exec-after-source-mutation",
                  test_snapshot_exec_and_mutation);
  g_test_add_func("/snapshot/invalid-headers", test_invalid_headers);
  g_test_add_func("/snapshot/untrusted-dynamic-paths", test_dynamic_paths);
  g_test_add_func("/snapshot/malformed-dynamic-strings", test_dynamic_strings);
  g_test_add_func("/snapshot/nonregular-source", test_nonregular_source);
  if (getuid() == 0 && InControlTestVm())
    g_test_add_func("/snapshot/root-alias-crossing-user-directory",
                    test_root_alias_crossing_user_directory);
  return g_test_run();
}
