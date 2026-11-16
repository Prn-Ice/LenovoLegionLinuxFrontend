"""A normal GTK window confirms the close request reaches delete-event."""

from pathlib import Path

import gi

gi.require_version('Gtk', '3.0')
from gi.repository import Gtk


def received_delete(window, event):
    (Path.home() / 'gtk-delete-received').write_text('delete-event\n')
    return False


window = Gtk.Window(title='GTK close preflight')
window.set_default_size(1280, 720)
window.add(Gtk.Label(label='Ordinary GTK close preflight'))
window.connect('delete-event', received_delete)
window.connect('destroy', Gtk.main_quit)
window.show_all()
Gtk.main()
