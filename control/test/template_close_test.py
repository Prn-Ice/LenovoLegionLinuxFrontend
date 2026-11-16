"""Observe normal WM close delivery before requiring each untouched template exit."""

import json
import os
import pwd
import re
import stat
import subprocess
import sys
import time
from pathlib import Path


HOME = Path.home()


def output(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT, timeout=10)


def capture(name, *args):
    result = subprocess.run(args, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=10)
    (HOME / name).write_text(f'status={result.returncode}\n{result.stdout}')
    return result


def wait_for(check, timeout, message):
    deadline = time.monotonic() + timeout
    while not check():
        assert time.monotonic() < deadline, message
        time.sleep(0.05)


def snapshot(prefix, window):
    capture(f'{prefix}-geometry.txt', 'xdotool', 'getwindowgeometry', '--shell', window)
    capture(f'{prefix}-tree.txt', 'xwininfo', '-root', '-tree')
    capture(f'{prefix}-window.txt', 'xwininfo', '-id', window, '-all')
    capture(f'{prefix}-properties.txt', 'xprop', '-id', window, 'WM_PROTOCOLS',
            '_NET_WM_PID', '_NET_FRAME_EXTENTS', '_NET_WM_STATE', '_NET_WM_ALLOWED_ACTIONS')
    capture(f'{prefix}-clients.txt', 'wmctrl', '-lGp')
    subprocess.run(['import', '-window', 'root', str(HOME / f'{prefix}-root.png')],
                   check=True, timeout=10)


def delivered(window, since=0):
    path = HOME / 'close-events.jsonl'
    if not path.exists():
        return []
    return [event for line in path.read_text().splitlines()
            if (event := json.loads(line))['window'] == int(window)
            and event['event'] == 'WM_DELETE_WINDOW' and event['monotonic'] >= since]


def managed_window(process):
    result = subprocess.run(['xdotool', 'search', '--onlyvisible', '--pid', str(process.pid)],
                            text=True, capture_output=True, timeout=10)
    for window in result.stdout.splitlines() if result.returncode == 0 else []:
        properties = output('xprop', '-id', window, '_NET_FRAME_EXTENTS', 'WM_PROTOCOLS')
        if 'WM_DELETE_WINDOW' in properties and re.search(r'_NET_FRAME_EXTENTS.*=\s*\d', properties):
            return window
    return None


def close_normally(process, window, prefix):
    assert output('xdotool', 'getwindowpid', window).strip() == str(process.pid)
    assert 'WM_DELETE_WINDOW' in output('xprop', '-id', window, 'WM_PROTOCOLS')
    snapshot(f'{prefix}-before', window)
    requested_at = time.monotonic()
    print(f'REQUEST prefix={prefix} pid={process.pid} window={window} method=wmctrl_NET_CLOSE_WINDOW', flush=True)
    subprocess.run(['wmctrl', '-ic', hex(int(window))], check=True, timeout=10)
    # RECORD observes server delivery to the client, independently of its exit.
    wait_for(lambda: delivered(window, requested_at), 5, 'WM_DELETE_WINDOW was not observed')
    event = delivered(window, requested_at)[0]
    (HOME / f'{prefix}-delivery.json').write_text(json.dumps(event, indent=2) + '\n')
    print(f'DELIVERED prefix={prefix} pid={process.pid} window={window}', flush=True)
    try:
        status = process.wait(timeout=15)
    except subprocess.TimeoutExpired:
        snapshot(f'{prefix}-hang', window)
        if prefix == 'gtk-fixture':
            raise AssertionError('GTK close preflight hung after observed delivery')
        (HOME / 'template-hang-request.json').write_text(json.dumps({
            'pid': process.pid, 'window': window, 'prefix': prefix,
            'close_delivered': True,
        }) + '\n')
        wait_for(lambda: (HOME / 'template-hang-collected').exists(), 90,
                 'Root hang collector did not finish')
        raise AssertionError(f'Process {process.pid} hung after verified WM_DELETE_WINDOW delivery')
    snapshot(f'{prefix}-after', window)
    print(f'CLOSE prefix={prefix} status={status}', flush=True)
    assert status == 0, (prefix, status)


def check_log(path):
    text = path.read_text()
    for diagnostic in ['-CRITICAL', 'g_mutex_clear() called']:
        assert diagnostic not in text, (path.name, text)


def exercise(fixture=False, attempt=0):
    prefix = 'gtk-fixture' if fixture else f'template-{attempt:02}'
    path = HOME / f'{prefix}.log'
    command = [sys.executable, '/opt/template-tests/template_gtk_fixture.py'] if fixture else [
        '/opt/shutdown-template/shutdown_template']
    with path.open('w') as log:
        process = subprocess.Popen(command, stdout=log, stderr=log, cwd=HOME)
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline:
            assert process.poll() is None, (prefix, process.returncode, path.read_text())
            window = managed_window(process)
            if window is None:
                time.sleep(0.1)
                continue
            frame = HOME / f'{prefix}-client.png'
            subprocess.run(['import', '-window', window, str(frame)], check=True, timeout=10)
            if not fixture:
                text = output('tesseract', str(frame), 'stdout', '--psm', '11').lower()
                if not ('pushed' in text and 'button' in text and re.search(r'\b0\b', text)):
                    time.sleep(0.1)
                    continue
                maps = Path(f'/proc/{process.pid}/maps').read_text()
                (HOME / f'{prefix}-maps.txt').write_text(maps)
                assert 'libLLVM-15.so.1' in maps and 'swrast_dri.so' in maps
            print(f'VISIBLE prefix={prefix} pid={process.pid} window={window}', flush=True)
            close_normally(process, window, prefix)
            check_log(path)
            if fixture:
                assert (HOME / 'gtk-delete-received').read_text() == 'delete-event\n'
            return
        raise AssertionError(f'Initial content was not visible: {prefix}')


def validate_session():
    uid = os.getuid()
    assert uid != 0
    assert str(HOME) == pwd.getpwuid(uid).pw_dir == os.environ['HOME']
    runtime = Path(os.environ['XDG_RUNTIME_DIR'])
    info = runtime.stat()
    assert info.st_uid == uid and stat.S_IMODE(info.st_mode) == 0o700
    assert os.environ['DBUS_SESSION_BUS_ADDRESS']
    output('gdbus', 'call', '--session', '--dest', 'org.freedesktop.DBus',
           '--object-path', '/org/freedesktop/DBus', '--method', 'org.freedesktop.DBus.GetId')
    (HOME / 'launch-environment.json').write_text(json.dumps({
        key: os.environ.get(key) for key in ['HOME', 'USER', 'LOGNAME', 'XDG_RUNTIME_DIR',
        'GSETTINGS_BACKEND', 'GDK_BACKEND', 'LIBGL_ALWAYS_SOFTWARE', 'DISPLAY',
        'DBUS_SESSION_BUS_ADDRESS']}, indent=2) + '\n')


def main():
    validate_session()
    with (HOME / 'close-observer.log').open('w') as observer_log, (HOME / 'openbox.log').open('w') as wm_log:
        observer = subprocess.Popen([sys.executable, '/opt/template-tests/template_close_observer.py'],
                                    stdout=observer_log, stderr=observer_log)
        wm = subprocess.Popen(['openbox'], stdout=wm_log, stderr=wm_log)
        try:
            wait_for(lambda: (HOME / 'close-observer-ready').exists(), 10, 'RECORD observer was not ready')
            wait_for(lambda: '_NET_SUPPORTING_WM_CHECK(WINDOW)' in output(
                'xprop', '-root', '_NET_SUPPORTING_WM_CHECK'), 15, 'Openbox did not register')
            exercise(fixture=True)
            output('gdbus', 'call', '--session', '--dest', 'org.a11y.Bus',
                   '--object-path', '/org/a11y/bus', '--method', 'org.a11y.Bus.GetAddress')
            check_log(HOME / 'gtk-fixture.log')
            check_log(HOME / 'close-observer.log')
            check_log(HOME / 'openbox.log')
            session_log = HOME / 'template-session.log'
            if session_log.exists():
                check_log(session_log)
            print('PASS: clean user session, GTK delete-event, and independently observed WM close delivery', flush=True)
            if sys.argv[1:] == ['--preflight-only']:
                return
            for attempt in range(1, 21):
                exercise(attempt=attempt)
                if session_log.exists():
                    check_log(session_log)
            print('PASS: 20/20 rendered template normal-WM-close checks with verified delivery', flush=True)
        finally:
            # Only diagnostic helpers are signalled, never the application under test.
            for helper in [observer, wm]:
                if helper.poll() is None:
                    helper.terminate()
                    helper.wait(timeout=5)


if __name__ == '__main__':
    main()
