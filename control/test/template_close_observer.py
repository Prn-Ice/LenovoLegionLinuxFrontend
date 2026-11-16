"""Observe server-delivered WM_DELETE_WINDOW messages without changing the client."""

import json
import sys
import time
from pathlib import Path

from Xlib import X, display
from Xlib.ext import record
from Xlib.protocol import rq


def main():
    home = Path.home()
    names = display.Display()
    connection = display.Display()
    assert connection.has_extension('RECORD'), 'X server lacks RECORD'
    protocols = names.intern_atom('WM_PROTOCOLS')
    delete = names.intern_atom('WM_DELETE_WINDOW')
    close = names.intern_atom('_NET_CLOSE_WINDOW')
    context = connection.record_create_context(0, [record.AllClients], [{
        'core_requests': (0, 0), 'core_replies': (0, 0),
        'ext_requests': (0, 0, 0, 0), 'ext_replies': (0, 0, 0, 0),
        'delivered_events': (X.ClientMessage, X.ClientMessage),
        'device_events': (0, 0), 'errors': (0, 0),
        'client_started': False, 'client_died': False,
    }])
    with (home / 'close-events.jsonl').open('w', buffering=1) as log:
        def received(reply):
            if reply.category == record.StartOfData:
                (home / 'close-observer-ready').write_text('ready\n')
                return
            if reply.category != record.FromServer or reply.client_swapped:
                return
            data = reply.data
            while data:
                event, data = rq.EventField(None).parse_binary_value(
                    data, connection.display, None, None)
                if event.type != X.ClientMessage:
                    continue
                fmt, values = event.data
                kind = None
                if event.client_type == protocols and fmt == 32 and values[0] == delete:
                    kind = 'WM_DELETE_WINDOW'
                elif event.client_type == close:
                    kind = '_NET_CLOSE_WINDOW'
                if kind:
                    log.write(json.dumps({
                        'event': kind, 'window': event.window.id,
                        'monotonic': time.monotonic(), 'recipient_id_base': reply.id_base,
                        'send_event': event.send_event,
                    }) + '\n')
        connection.record_enable_context(context, received)


if __name__ == '__main__':
    main()
