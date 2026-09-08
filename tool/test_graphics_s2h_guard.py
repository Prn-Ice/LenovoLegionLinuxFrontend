#!/usr/bin/env python3
"""Run systemd's actual sleep transition code with kernel I/O replaced.

Usage: test_graphics_s2h_guard.py SYSTEMD_SLEEP_C
The input may be upstream (expected to fail) or the Nix-patched sleep.c.
No real sleep, hardware inspection, or privileged operation is performed.
"""

import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


def function(source, name):
    start = source.index(f"static int {name}(")
    end = source.index("\n}\n", start) + 3
    return source[start:end]


HARNESS = r'''
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
    char **states[3], **modes[3], **mem_modes;
    usec_t hibernate_delay_usec;
    bool hibernate_on_ac_power;
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
'''


def main():
    source = Path(sys.argv[1]).read_text()
    with tempfile.TemporaryDirectory(prefix="legion-s2h-test-") as directory:
        root = Path(directory)
        guard = root / "guard"
        guard.write_text(
            f'#!{shutil.which("sh")}\n'
            'printf "guard:check\\n" >> "$TEST_EVENTS"\n'
            'read -r result < "$TEST_GUARD_STATE" || :\n'
            'exit "$result"\n'
        )
        guard.chmod(0o755)
        c_source = HARNESS.replace("@EXECUTE@", function(source, "execute"))
        c_source = c_source.replace("@EXECUTE_S2H@", function(source, "execute_s2h"))
        # The guard path is immutable in production and local only in this harness.
        c_source = re.sub(r'"(?:@legionHibernatePreflight@|/nix/store/[^"\n]*legion-graphics-s2h-preflight)"',
                          f'"{guard}"', c_source)
        (root / "test.c").write_text(c_source)
        subprocess.run([os.environ.get("CC", "cc"), "-std=gnu11", "-o", str(root / "test"),
                        str(root / "test.c")], check=True)

        suspend = ["pre:suspend", "homes:lock", "write:mem", "post:suspend"]
        pre = ["pre:hibernate", "homes:lock"]
        fallback = ["pre:suspend-after-failed-hibernate", "homes:lock", "write:mem",
                    "post:suspend-after-failed-hibernate"]
        cases = [
            ("state changes after entry", "s2h", "2", {},
             suspend + pre + ["guard:check", "post:hibernate", "efi:clear"] + fallback),
            ("safe transition", "s2h", "0", {},
             suspend + pre + ["guard:check", "write:disk", "post:hibernate"]),
            ("inspection fails", "s2h", "1", {},
             suspend + pre + ["guard:check", "post:hibernate", "efi:clear"] + fallback),
            ("guard times out", "s2h", "124", {},
             suspend + pre + ["guard:check", "post:hibernate", "efi:clear"] + fallback),
            ("cannot fork guard", "s2h", "0", {"TEST_FORK_FAIL": "1"},
             suspend + pre + ["post:hibernate", "efi:clear"] + fallback),
            ("manual wake", "s2h", "2", {"TEST_MANUAL_WAKE": "1"}, suspend),
            ("ordinary suspend", "suspend", "2", {}, suspend),
            ("direct hibernate unchanged", "hibernate", "2", {},
             pre + ["write:disk", "post:hibernate"]),
        ]
        cases.append(("missing guard", "s2h", "0", {},
                      suspend + pre + ["post:hibernate", "efi:clear"] + fallback))
        for name, operation, result, extra, expected in cases:
            if name == "missing guard":
                guard.unlink()
            events = root / "events"
            events.write_text("")
            state = root / "state"
            state.write_text("0")  # Initial entry preflight would succeed.
            env = dict(os.environ, TEST_EVENTS=str(events), TEST_GUARD_STATE=str(state),
                       TEST_GUARD_RESULT=result, **extra)
            subprocess.run([str(root / "test"), operation], env=env, check=True, timeout=5)
            actual = events.read_text().splitlines()
            assert actual == expected, f"{name}: expected {expected}, got {actual}"
            print(f"PASS: {name}")


if __name__ == "__main__":
    main()
