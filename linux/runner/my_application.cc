#include "my_application.h"
#include "portable_control_channel.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  // Keep the engine alive until the main loop stops: flutter/flutter#193742.
  FlEngine* engine;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// One popup per main view, with no second engine or application window lifetime.
// GTK3 cannot promise desktop OSD placement on Wayland without layer-shell.
struct OsdHost {
  GtkWindow* parent;
  GtkWidget* popup = nullptr;
  GtkWidget* title = nullptr;
  GtkWidget* value = nullptr;
  FlMethodChannel* channel = nullptr;
  guint timeout = 0;
};

static gboolean osd_supported(OsdHost* host) {
#ifdef GDK_WINDOWING_X11
  return GDK_IS_X11_DISPLAY(gtk_widget_get_display(GTK_WIDGET(host->parent)));
#else
  return FALSE;
#endif
}

static void osd_hide(OsdHost* host) {
  if (host->timeout != 0) {
    g_source_remove(host->timeout);
    host->timeout = 0;
  }
  if (host->popup != nullptr) gtk_widget_hide(host->popup);
}

static gboolean osd_timeout(gpointer data) {
  auto* host = static_cast<OsdHost*>(data);
  host->timeout = 0;
  gtk_widget_hide(host->popup);
  return G_SOURCE_REMOVE;
}

static gboolean osd_draw(GtkWidget* widget, cairo_t* cr, gpointer) {
  cairo_save(cr);
  cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
  cairo_set_source_rgba(cr, 0, 0, 0, 0);
  cairo_paint(cr);
  cairo_restore(cr);
  GtkStyleContext* style = gtk_widget_get_style_context(widget);
  gtk_render_background(style, cr, 0, 0, gtk_widget_get_allocated_width(widget),
                         gtk_widget_get_allocated_height(widget));
  gtk_render_frame(style, cr, 0, 0, gtk_widget_get_allocated_width(widget),
                   gtk_widget_get_allocated_height(widget));
  return FALSE;  // Continue drawing the labels.
}

static void osd_destroy(gpointer data) {
  auto* host = static_cast<OsdHost*>(data);
  fl_method_channel_set_method_call_handler(host->channel, nullptr, nullptr,
                                           nullptr);
  osd_hide(host);
  if (host->popup != nullptr) gtk_widget_destroy(host->popup);
  g_clear_object(&host->channel);
  delete host;
}

static void osd_method_call(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  auto* host = static_cast<OsdHost*>(data);
  const gchar* method = fl_method_call_get_name(call);
  g_autoptr(FlValue) result = nullptr;
  if (g_str_equal(method, "capabilities")) {
    result = fl_value_new_bool(osd_supported(host));
  } else if (g_str_equal(method, "hide")) {
    osd_hide(host);
  } else if (g_str_equal(method, "show")) {
    FlValue* args = fl_method_call_get_args(call);
    FlValue* title = nullptr;
    FlValue* value = nullptr;
    FlValue* duration = nullptr;
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      title = fl_value_lookup_string(args, "title");
      value = fl_value_lookup_string(args, "value");
      duration = fl_value_lookup_string(args, "durationMs");
    }
    if (title == nullptr || fl_value_get_type(title) != FL_VALUE_TYPE_STRING ||
        value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING ||
        duration == nullptr || fl_value_get_type(duration) != FL_VALUE_TYPE_INT ||
        g_utf8_strlen(fl_value_get_string(title), -1) > 80 ||
        g_utf8_strlen(fl_value_get_string(value), -1) > 240 ||
        fl_value_get_int(duration) < 500 || fl_value_get_int(duration) > 5000) {
      fl_method_call_respond_error(call, "invalid-arguments",
                                   "Invalid OSD content or timeout", nullptr,
                                   nullptr);
      return;
    }
    if (!osd_supported(host)) {
      result = fl_value_new_bool(FALSE);
    } else {
      osd_hide(host);
      if (host->popup == nullptr) {
        host->popup = gtk_window_new(GTK_WINDOW_POPUP);
        GtkWindow* popup = GTK_WINDOW(host->popup);
        gtk_window_set_accept_focus(popup, FALSE);
        gtk_window_set_focus_on_map(popup, FALSE);
        gtk_window_set_decorated(popup, FALSE);
        gtk_window_set_resizable(popup, FALSE);
        gtk_window_set_skip_taskbar_hint(popup, TRUE);
        gtk_window_set_skip_pager_hint(popup, TRUE);
        gtk_window_set_keep_above(popup, TRUE);
        gtk_window_set_type_hint(popup, GDK_WINDOW_TYPE_HINT_NOTIFICATION);
        gtk_widget_set_name(host->popup, "legion-osd");
        GdkVisual* visual = gdk_screen_get_rgba_visual(
            gtk_widget_get_screen(host->popup));
        if (visual != nullptr) gtk_widget_set_visual(host->popup, visual);
        gtk_widget_set_app_paintable(host->popup, TRUE);
        g_signal_connect(host->popup, "draw", G_CALLBACK(osd_draw), nullptr);
        GtkWidget* box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
        gtk_container_set_border_width(GTK_CONTAINER(box), 18);
        gtk_container_add(GTK_CONTAINER(popup), box);
        host->title = gtk_label_new(nullptr);
        host->value = gtk_label_new(nullptr);
        gtk_label_set_line_wrap(GTK_LABEL(host->value), TRUE);
        gtk_label_set_line_wrap_mode(GTK_LABEL(host->value), PANGO_WRAP_WORD_CHAR);
        gtk_label_set_max_width_chars(GTK_LABEL(host->value), 36);
        gtk_box_pack_start(GTK_BOX(box), host->title, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(box), host->value, FALSE, FALSE, 0);
        // Native theme colors/type, not a second hardcoded Flutter palette.
        gtk_style_context_add_class(gtk_widget_get_style_context(host->popup),
                                    "osd");
        g_autoptr(GtkCssProvider) css = gtk_css_provider_new();
        gtk_css_provider_load_from_data(
            css, "#legion-osd { border-radius: 16px; }", -1, nullptr);
        gtk_style_context_add_provider(
            gtk_widget_get_style_context(host->popup), GTK_STYLE_PROVIDER(css),
            GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
        gtk_widget_realize(host->popup);
        // The readout must not intercept clicks on the application underneath.
        cairo_region_t* empty = cairo_region_create();
        gdk_window_input_shape_combine_region(
            gtk_widget_get_window(host->popup), empty, 0, 0);
        cairo_region_destroy(empty);
      }
      // Plain text only: no markup interpretation of event descriptions.
      gtk_label_set_text(GTK_LABEL(host->title), fl_value_get_string(title));
      gtk_label_set_text(GTK_LABEL(host->value), fl_value_get_string(value));
      GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(host->parent));
      GdkMonitor* monitor = gdk_display_get_monitor_at_window(
          display, gtk_widget_get_window(GTK_WIDGET(host->parent)));
      if (monitor == nullptr) monitor = gdk_display_get_primary_monitor(display);
      GdkRectangle area;
      if (monitor != nullptr) {
        gdk_monitor_get_workarea(monitor, &area);
        GtkRequisition size;
        gtk_widget_show_all(gtk_bin_get_child(GTK_BIN(host->popup)));
        gtk_widget_get_preferred_size(host->popup, nullptr, &size);
        gtk_window_move(GTK_WINDOW(host->popup),
                        area.x + (area.width - size.width) / 2,
                        area.y + area.height - size.height - 48);
      }
      // Never present(), grab focus, or register as an application window.
      gtk_widget_show(host->popup);
      host->timeout = g_timeout_add(static_cast<guint>(fl_value_get_int(duration)),
                                    osd_timeout, host);
      result = fl_value_new_bool(TRUE);
    }
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  fl_method_call_respond_success(call, result, nullptr);
}

static void osd_register(GtkWindow* window, FlView* view) {
  auto* host = new OsdHost();
  host->parent = window;
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  host->channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "io.github.prnice.legion/platform_osd", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(host->channel, osd_method_call, host,
                                           nullptr);
  g_object_set_data_full(G_OBJECT(view), "legion-osd-host", host, osd_destroy);
  // Release on widget destruction, not only eventual GObject finalization.
  g_signal_connect(view, "destroy", G_CALLBACK(+[](GtkWidget* widget, gpointer) {
                     g_object_set_data(G_OBJECT(widget), "legion-osd-host",
                                       nullptr);
                   }), nullptr);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar under GNOME and Wayland. Use a traditional title bar on
  // X11 when not using GNOME to support tiling window managers.
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "legion_frontend");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "legion_frontend");
  }

  gtk_window_set_default_size(window, 1280, 720);
  gtk_window_set_icon_name(window, APPLICATION_ID);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  g_set_object(&self->engine, fl_view_get_engine(view));
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // handy_window: register plugins before showing the view so the Handy
  // rounded-corner window is applied.
  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  osd_register(window, view);
  RegisterPortableControlChannel(view);
  gtk_widget_show(GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->engine);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set program name to the application ID so desktop environments map the
  // running application to its .desktop file.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
