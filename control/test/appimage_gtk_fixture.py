"""Use bundled GTK to confirm the normal WM close reaches delete-event."""

import ctypes
from pathlib import Path


gtk = ctypes.CDLL("libgtk-3.so.0")
gobject = ctypes.CDLL("libgobject-2.0.so.0")


def bind(library, name, result, *arguments):
    function = getattr(library, name)
    function.restype = result
    function.argtypes = list(arguments)
    return function


pointer = ctypes.c_void_p
integer = ctypes.c_int
bind(gtk, "gtk_init", None, pointer, pointer)(None, None)
window = bind(gtk, "gtk_window_new", pointer, integer)(0)
bind(gtk, "gtk_window_set_title", None, pointer, ctypes.c_char_p)(
    window, b"GTK close preflight")
bind(gtk, "gtk_window_set_default_size", None, pointer, integer, integer)(window, 400, 160)
label = bind(gtk, "gtk_label_new", pointer, ctypes.c_char_p)(b"Ordinary GTK close preflight")
bind(gtk, "gtk_container_add", None, pointer, pointer)(window, label)


@ctypes.CFUNCTYPE(integer, pointer, pointer, pointer)
def received_delete(widget, event, user_data):
    (Path.home() / "gtk-delete-received").write_text("delete-event\n")
    return 0


@ctypes.CFUNCTYPE(None, pointer, pointer)
def destroyed(widget, user_data):
    gtk.gtk_main_quit()


bind(gobject, "g_signal_connect_data", ctypes.c_ulong, pointer, ctypes.c_char_p,
     pointer, pointer, pointer, integer)(window, b"delete-event",
                                       ctypes.cast(received_delete, pointer), None, None, 0)
gobject.g_signal_connect_data(window, b"destroy", ctypes.cast(destroyed, pointer), None, None, 0)
bind(gtk, "gtk_widget_show_all", None, pointer)(window)
gtk.gtk_main()
