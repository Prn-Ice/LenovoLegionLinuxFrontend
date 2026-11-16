"""Guest-only core evidence for the isolated patched-engine package test."""

import shlex


def prepare_nixos_core(machine):
    machine.succeed("mkdir -m700 /root/engine-core-evidence")
    limits = machine.succeed("runuser -u approved -- sh -c 'ulimit -Sc; ulimit -Hc'")
    assert limits.splitlines() == ["unlimited", "unlimited"], limits
    machine.succeed(
        "{ uname -a; lscpu; runuser -u approved -- sh -c 'ulimit -Sc; ulimit -Hc'; "
        "sysctl kernel.core_pattern; } >/root/engine-core-evidence/environment.txt"
    )
    code, output = machine.execute(
        "runuser -u approved -- sh -c 'echo $$ >/tmp/core-fixture.pid; "
        'exec python3 -c "import os; os.abort()"\''
    )
    assert code == 134, (code, output)
    pid = machine.succeed("cat /tmp/core-fixture.pid").strip()
    machine.wait_until_succeeds("coredumpctl --no-pager info " + pid, timeout=30)
    machine.succeed(
        "timeout 60 coredumpctl --output=/root/engine-core-evidence/fixture.core dump "
        + pid
    )
    machine.succeed(
        "timeout 60 gdb -nx -batch -ex 'set debuginfod enabled off' "
        "-ex 'thread apply all bt' $(readlink -f $(command -v python3)) "
        "/root/engine-core-evidence/fixture.core "
        ">/root/engine-core-evidence/fixture-backtrace.txt 2>&1"
    )
    machine.succeed(
        "grep -F 'Program terminated with signal SIGABRT' "
        "/root/engine-core-evidence/fixture-backtrace.txt"
    )
    print("PASS: NixOS approved-user core fixture and GDB capture")


def collect_nixos_core(machine, failed):
    # Collection must not replace an earlier test failure.
    try:
        machine.succeed("mkdir -p /root/engine-core-evidence")
        machine.succeed(
            "journalctl -b --no-pager >/root/engine-core-evidence/journal.log; "
            "coredumpctl --no-pager list >/root/engine-core-evidence/core-list.txt || true"
        )
        if failed:
            match = "COREDUMP_COMM=legion_frontend COREDUMP_UID=1000"
            code, output = machine.execute(
                "timeout 60 coredumpctl --no-pager -1 info " + match
                + " >/root/engine-core-evidence/app-info.txt"
            )
            if code == 0:
                executable = machine.succeed(
                    "find /home/approved/.cache/appimage-run -type f "
                    "-path '*/usr/lib/legion_frontend/legion_frontend' | head -n1"
                ).strip()
                assert executable, "The matching AppImage executable was not retained"
                bundle = executable.rsplit("/", 1)[0]
                machine.succeed(
                    "timeout 90 coredumpctl --output=/root/engine-core-evidence/legion.core dump "
                    + match
                )
                machine.succeed(
                    "timeout 180 gdb -nx -batch -ex 'set pagination off' "
                    "-ex 'set debuginfod enabled off' "
                    "-ex " + shlex.quote("set solib-search-path " + bundle + "/lib")
                    + " -ex 'info threads' -ex 'thread apply all bt full' "
                    "-ex 'info sharedlibrary' -ex 'info proc mappings' "
                    + shlex.quote(executable)
                    + " /root/engine-core-evidence/legion.core "
                    ">/root/engine-core-evidence/app-backtrace.txt 2>&1"
                )
                machine.succeed(
                    "find " + shlex.quote(bundle)
                    + " -type f -name '*.so' -exec readelf -n {} + "
                    ">/root/engine-core-evidence/build-ids.txt 2>&1"
                )
        for path in [
            "/root/engine-core-evidence", "/home/approved/gui.log",
            "/home/approved/display.log", "/home/approved/app.exit",
        ]:
            code, _ = machine.execute("test -e " + shlex.quote(path))
            if code == 0:
                machine.copy_from_machine(path)
    except Exception as error:
        print("Core collection failed:", error)
        if not failed:
            raise
