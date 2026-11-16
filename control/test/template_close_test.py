"""Require 20 rendered counter-template windows to close through their visible X."""

import json
import os
import re
import subprocess
import time
from pathlib import Path


def output(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL, timeout=10)


def stop(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


def close_once(attempt, environment):
    home = Path.home()
    log_path = home / f'template-{attempt:02}.log'
    frame = home / f'template-{attempt:02}.png'
    with log_path.open('w') as log:
        process = subprocess.Popen(['/opt/shutdown-template/shutdown_template'],
                                   env=environment, stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + 90
            while time.monotonic() < deadline:
                assert process.poll() is None, (attempt, process.returncode, log_path.read_text())
                found = subprocess.run(['xdotool', 'search', '--onlyvisible', '--pid', str(process.pid)],
                                       text=True, capture_output=True, timeout=10)
                windows = found.stdout.splitlines() if found.returncode == 0 else []
                if not windows:
                    time.sleep(0.1)
                    continue
                window = windows[-1]
                subprocess.run(['import', '-window', window, str(frame)], check=True, timeout=10)
                text = output('tesseract', str(frame), 'stdout', '--psm', '11').lower()
                if not ('pushed' in text and 'button' in text and re.search(r'\b0\b', text)):
                    time.sleep(0.1)
                    continue
                geometry = dict(line.split('=', 1) for line in
                                output('xdotool', 'getwindowgeometry', '--shell', window).splitlines())
                extents = output('xprop', '-id', window, '_NET_FRAME_EXTENTS')
                match = re.search(r'=\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+)', extents)
                if not match:
                    time.sleep(0.1)
                    continue
                left, right, top, bottom = map(int, match.groups())
                assert top >= 10, extents
                assert output('xdotool', 'getwindowpid', window).strip() == str(process.pid)
                maps = Path(f'/proc/{process.pid}/maps').read_text()
                (home / f'template-{attempt:02}-maps.txt').write_text(maps)
                assert 'libLLVM-15.so.1' in maps and 'swrast_dri.so' in maps, maps
                print(f'VISIBLE attempt={attempt} pid={process.pid} extents={left,right,top,bottom}', flush=True)
                # Openbox provides the default window decoration; click its visible X.
                x = int(geometry['X']) + int(geometry['WIDTH']) - 10
                y = int(geometry['Y']) - top // 2
                subprocess.run(['xdotool', 'mousemove', str(x), str(y), 'click', '1'],
                               check=True, timeout=10)
                status = process.wait(timeout=15)
                print(f'CLOSE attempt={attempt} status={status}', flush=True)
                assert status == 0, (attempt, status, log_path.read_text())
                text = log_path.read_text()
                for diagnostic in ['Pango-CRITICAL', 'GLib-CRITICAL', 'GLib-GObject-CRITICAL']:
                    assert diagnostic not in text, (attempt, diagnostic, text)
                return
            raise AssertionError(f'Counter content did not render on attempt {attempt}: {log_path.read_text()}')
        finally:
            stop(process)


def main():
    assert os.getuid() != 0
    environment = dict(os.environ, GSETTINGS_BACKEND='memory', GDK_BACKEND='x11',
                       LIBGL_ALWAYS_SOFTWARE='1')
    for key in ['JAVA_HOME', 'LD_LIBRARY_PATH']:
        environment.pop(key, None)
    wm_log = (Path.home() / 'openbox.log').open('w')
    wm = subprocess.Popen(['openbox'], env=environment, stdout=wm_log, stderr=wm_log)
    try:
        deadline = time.monotonic() + 15
        while '_NET_SUPPORTING_WM_CHECK(WINDOW)' not in output('xprop', '-root', '_NET_SUPPORTING_WM_CHECK'):
            assert wm.poll() is None
            assert time.monotonic() < deadline, 'Openbox did not register'
            time.sleep(0.1)
        (Path.home() / 'launch-environment.json').write_text(json.dumps({
            key: environment.get(key) for key in ['GSETTINGS_BACKEND', 'GDK_BACKEND',
            'LIBGL_ALWAYS_SOFTWARE', 'DISPLAY', 'DBUS_SESSION_BUS_ADDRESS']}, indent=2) + '\n')
        for attempt in range(1, 21):
            close_once(attempt, environment)
        print('PASS: 20/20 visible template close-button checks', flush=True)
    finally:
        stop(wm)
        wm_log.close()


if __name__ == '__main__':
    main()
