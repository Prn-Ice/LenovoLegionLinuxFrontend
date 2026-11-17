#!/usr/bin/env bash
# Run systemd's sleep transition code with kernel I/O replaced by local fixtures.
# Usage: bash tool/test_graphics_s2h_guard.sh SYSTEMD_SLEEP_C
set -euo pipefail
root=$(mktemp -d -t legion-s2h-test-XXXXXX)
trap 'rm -rf -- "$root"' EXIT
guard="$root/guard"
printf '#!%s\n' "$(command -v sh)" > "$guard"
cat >> "$guard" <<'SH'
printf 'guard:check\n' >> "$TEST_EVENTS"
read -r result < "$TEST_GUARD_STATE" || :
exit "$result"
SH
chmod +x "$guard"
for name in execute execute_s2h; do
  awk -v name="$name" '
    index($0, "static int " name "(") == 1 { found=1 }
    found { print }
    found && /^}/ { exit }
    END { if (!found) exit 1 }
  ' "$1" > "$root/$name.c"
done
cat > "$root/harness.c" <<'C'
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/timerfd.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <poll.h>

typedef uint64_t usec_t;
typedef enum { SLEEP_SUSPEND, SLEEP_HIBERNATE, SLEEP_HYBRID_SLEEP,
               _SLEEP_OPERATION_CONFIG_MAX, SLEEP_SUSPEND_THEN_HIBERNATE } SleepOperation;
typedef struct {
    bool allow[5];
    char **states[3], **modes[3], **mem_modes;
    usec_t hibernate_delay_usec;
    bool hibernate_on_ac_power;
    usec_t suspend_estimation_usec;
} SleepConfig;
typedef struct { int devno; uint64_t offset; char *path; } HibernationDevice;
#define _cleanup_(x)
#define _cleanup_close_
#define SLEEP_OPERATION_IS_HIBERNATION(op) ((op) != SLEEP_SUSPEND)
#define SYNTHETIC_ERRNO(e) (-(e))
#define SYSTEM_SLEEP_PATH "/unused-system-sleep"
#define DEFAULT_TIMEOUT_USEC 90000000
#define USEC_PER_SEC 1000000
#define EXEC_DIR_PARALLEL 1
#define EXEC_DIR_IGNORE_ERRORS 2
#define FORK_RESET_SIGNALS 1
#define FORK_DEATHSIG_SIGTERM 2
#define FORK_CLOSE_ALL_FDS 4
#define FORK_LOG 8
#define FORK_WAIT 16
#define FLAGS_SET(v, f) (((v) & (f)) == (f))
#define FORMAT_TIMESPAN(...) "unused"
#define log_debug(...) ((void) 0)
#define log_notice(...) ((void) 0)
#define log_warning_errno(...) ((void) 0)
#define log_struct(...) ((void) 0)
#define log_struct_errno(...) ((void) 0)
#define log_error_errno(e, ...) (-abs(e))
#define log_debug_errno(e, ...) (-abs(e))

static void event(const char *kind, const char *value) {
    FILE *f = fopen(getenv("TEST_EVENTS"), "a");
    assert(f);
    fprintf(f, "%s:%s\n", kind, value);
    fclose(f);
}
static const char *sleep_operation_to_string(SleepOperation op) {
    const char *names[] = {"suspend", "hibernate", "hybrid-sleep", "invalid", "suspend-then-hibernate"};
    return names[op];
}
static bool strv_isempty(char *const *v) { return !v || !*v; }
static int fake_open(const char *path, int flags) { return 42; }
#define open fake_open
static bool sleep_needs_mem_sleep(const SleepConfig *c, SleepOperation op) { return false; }
static int write_mode(const char *p, char *const *v) { return 0; }
static int find_suitable_hibernation_device(HibernationDevice *d) { return 1; }
static int write_efi_hibernate_location(const HibernationDevice *d, bool required) { return 0; }
static int write_resume_config(int d, uint64_t o, const char *p) { return 0; }
static int clear_efi_hibernate_location_and_warn(void) { event("efi", "clear"); return 0; }
static int lock_all_homes(void) { event("homes", "lock"); return 0; }
static int write_state(int fd, char *const *states) { event("write", *states); return 0; }
static int execute_directories(const char *name, const char *const *dirs,
        usec_t timeout, void *callbacks, void *args, char **argv, char **env, int flags) {
    const char *action = getenv("SYSTEMD_SLEEP_ACTION");
    event(argv[1], action);
    if (!strcmp(argv[1], "pre") && !strcmp(action, "hibernate")) {
        /* Simulate topology becoming unsafe after the initial entry check. */
        FILE *f = fopen(getenv("TEST_GUARD_STATE"), "w");
        assert(f);
        fputs(getenv("TEST_GUARD_RESULT"), f);
        fclose(f);
    }
    return 0;
}
static int pidref_safe_fork(const char *name, int flags, void *ret) {
    assert(flags & FORK_WAIT);
    if (getenv("TEST_FORK_FAIL")) return -EAGAIN;
    pid_t pid = fork();
    if (pid <= 0) return pid < 0 ? -errno : 0;
    int status;
    assert(waitpid(pid, &status, 0) == pid);
    return WIFEXITED(status) && WEXITSTATUS(status) == 0 ? 1 : -EPROTO;
}
static int check_wakeup_type(void) { return 0; }
static int battery_trip_point_alarm_exists(void) { return 0; }
static bool timestamp_is_set(usec_t t) { return t != 0; }
static usec_t usec_add(usec_t a, usec_t b) { return a+b; }
static usec_t usec_sub_unsigned(usec_t a, usec_t b) { return a > b ? a-b : 0; }
static usec_t now(clockid_t c) { return 0; }
static int on_ac_power(void) { return 0; }
static void timespec_store(struct timespec *ts, usec_t t) {}
static int fd_wait_for_event(int fd, int events, usec_t timeout) { return 0; }
@EXECUTE@
static int custom_timer_suspend(const SleepConfig *c, SleepOperation main_op) {
    int r = execute(c, main_op, SLEEP_SUSPEND, NULL);
    if (r < 0) return r;
    return getenv("TEST_MANUAL_WAKE") ? 0 : 1;
}
@EXECUTE_S2H@
int main(int argc, char **argv) {
    char *mem[] = { "mem", NULL }, *disk[] = { "disk", NULL };
    SleepConfig c = { .states = {mem, disk, disk}, .modes = {mem, disk, disk} };
    int r;
    if (!strcmp(argv[1], "s2h"))
        r = execute_s2h(&c, SLEEP_SUSPEND_THEN_HIBERNATE);
    else if (!strcmp(argv[1], "hibernate"))
        r = execute(&c, SLEEP_HIBERNATE, SLEEP_HIBERNATE, NULL);
    else
        r = execute(&c, SLEEP_SUSPEND, SLEEP_SUSPEND, NULL);
    return r < 0 ? 1 : 0;
}
C
sed -e "/@EXECUTE@/r $root/execute.c" -e '/@EXECUTE@/d' \
  -e "/@EXECUTE_S2H@/r $root/execute_s2h.c" -e '/@EXECUTE_S2H@/d' "$root/harness.c" |
  sed -E "s#\"(@legionHibernatePreflight@|/nix/store/[^\"]*legion-graphics-s2h-preflight)\"#\"$guard\"#g" > "$root/test.c"
"${CC:-cc}" -std=gnu11 -o "$root/test" "$root/test.c"

export TEST_EVENTS="$root/events" TEST_GUARD_STATE="$root/state"
suspend=$'pre:suspend\nhomes:lock\nwrite:mem\npost:suspend'
pre=$'pre:hibernate\nhomes:lock'
fallback=$'pre:suspend-after-failed-hibernate\nhomes:lock\nwrite:mem\npost:suspend-after-failed-hibernate'
rejected="$suspend"$'\n'"$pre"$'\nguard:check\npost:hibernate\nefi:clear\n'"$fallback"
run_case() {
  local name=$1 operation=$2 expected=$3
  : > "$TEST_EVENTS"
  printf '0' > "$TEST_GUARD_STATE"
  timeout 5s "$root/test" "$operation"
  printf '%s\n' "$expected" > "$root/expected"
  diff -u "$root/expected" "$TEST_EVENTS"
  printf 'PASS: %s\n' "$name"
}
export TEST_GUARD_RESULT=2
run_case 'state changes after entry' s2h "$rejected"
export TEST_GUARD_RESULT=0
run_case 'safe transition' s2h "$suspend"$'\n'"$pre"$'\nguard:check\nwrite:disk\npost:hibernate'
export TEST_GUARD_RESULT=1
run_case 'inspection fails' s2h "$rejected"
export TEST_GUARD_RESULT=124
run_case 'guard times out' s2h "$rejected"
export TEST_GUARD_RESULT=0 TEST_FORK_FAIL=1
run_case 'cannot fork guard' s2h "$suspend"$'\n'"$pre"$'\npost:hibernate\nefi:clear\n'"$fallback"
unset TEST_FORK_FAIL
export TEST_GUARD_RESULT=2 TEST_MANUAL_WAKE=1
run_case 'manual wake' s2h "$suspend"
unset TEST_MANUAL_WAKE
run_case 'ordinary suspend' suspend "$suspend"
run_case 'direct hibernate unchanged' hibernate "$pre"$'\nwrite:disk\npost:hibernate'
rm "$guard"
run_case 'missing guard' s2h "$suspend"$'\n'"$pre"$'\npost:hibernate\nefi:clear\n'"$fallback"
