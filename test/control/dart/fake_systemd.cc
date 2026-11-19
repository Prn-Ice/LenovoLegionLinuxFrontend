#include <gio/gio.h>
#include <gio/gunixfdlist.h>
#include <unistd.h>

#include <cstdio>
#include <cstring>

namespace {
GMainLoop* loop;
GDBusConnection* connection;
guint owner_id;
gint output_fd = -1;
gint input_fd = -1;
gboolean active = TRUE;
gboolean cgroup = TRUE;
gboolean reject = FALSE;

void line(const char* text) {
  std::printf("%s\n", text);
  std::fflush(stdout);
}

GVariant* dict_value(GVariant* properties, const char* name) {
  GVariantIter iter;
  g_variant_iter_init(&iter, properties);
  const gchar* key;
  GVariant* value;
  while (g_variant_iter_next(&iter, "(&sv)", &key, &value)) {
    gboolean match = std::strcmp(key, name) == 0;
    if (match) return value;
    g_variant_unref(value);
  }
  return nullptr;
}

gint receive_fd(GVariant* value, GDBusMessage* message) {
  if (value == nullptr) return -1;
  gint index = -1;
  g_variant_get(value, "h", &index);
  GUnixFDList* fds = g_dbus_message_get_unix_fd_list(message);
  if (fds == nullptr || index < 0) return -1;
  return g_unix_fd_list_get(fds, index, nullptr);
}

void close_output() {
  if (output_fd >= 0) {
    close(output_fd);
    output_fd = -1;
  }
}

void handle_command(const char* command) {
  if (std::strcmp(command, "complete") == 0 ||
      std::strcmp(command, "finish") == 0) {
    if (output_fd >= 0) {
      const char result[] = "ok";
      (void)write(output_fd, result, sizeof(result) - 1);
    }
    active = FALSE;
    if (std::strcmp(command, "complete") == 0) {
      cgroup = FALSE;
      close_output();
    }
  } else if (std::strcmp(command, "cgroup-empty") == 0) {
    cgroup = FALSE;
    close_output();
  } else if (std::strcmp(command, "release-name") == 0) {
    if (owner_id != 0) g_bus_unown_name(owner_id);
  } else if (std::strcmp(command, "exit") == 0) {
    g_main_loop_quit(loop);
  }
}

gboolean read_stdin(GIOChannel* channel, GIOCondition condition, gpointer) {
  if (condition & (G_IO_HUP | G_IO_ERR)) {
    g_main_loop_quit(loop);
    return G_SOURCE_REMOVE;
  }
  gchar* text = nullptr;
  gsize length = 0;
  if (g_io_channel_read_line(channel, &text, &length, nullptr, nullptr) ==
      G_IO_STATUS_NORMAL) {
    if (length > 0 && text[length - 1] == '\n') text[length - 1] = '\0';
    handle_command(text);
  }
  g_free(text);
  return G_SOURCE_CONTINUE;
}

void method_call(GDBusConnection*, const gchar*, const gchar*, const gchar*,
                 const gchar* method, GVariant* parameters,
                 GDBusMethodInvocation* invocation, gpointer) {
  if (std::strcmp(method, "StartTransientUnit") == 0) {
    GVariant* properties = g_variant_get_child_value(parameters, 2);
    GVariant* output = dict_value(properties, "StandardOutputFileDescriptor");
    GVariant* input = dict_value(properties, "StandardInputFileDescriptor");
    GDBusMessage* message = g_dbus_method_invocation_get_message(invocation);
    output_fd = receive_fd(output, message);
    input_fd = receive_fd(input, message);
    if (output != nullptr) g_variant_unref(output);
    if (input != nullptr) g_variant_unref(input);
    g_variant_unref(properties);
    line("STARTED");
    if (reject) {
      close_output();
      g_dbus_method_invocation_return_error(
          invocation, G_DBUS_ERROR, G_DBUS_ERROR_ACCESS_DENIED, "rejected");
    } else {
      g_dbus_method_invocation_return_value(
          invocation, g_variant_new("(o)", "/org/freedesktop/systemd1/job/1"));
    }
    return;
  }
  if (std::strcmp(method, "GetUnit") == 0) {
    g_dbus_method_invocation_return_value(
        invocation, g_variant_new("(o)", "/org/freedesktop/systemd1/unit/test"));
    return;
  }
  if (std::strcmp(method, "StopUnit") == 0) {
    active = FALSE;
    cgroup = FALSE;
    close_output();
    line("STOPPED");
    g_dbus_method_invocation_return_value(
        invocation, g_variant_new("(o)", "/org/freedesktop/systemd1/job/2"));
    return;
  }
  if (std::strcmp(method, "UnrefUnit") == 0) {
    line("UNREF");
    g_dbus_method_invocation_return_value(invocation, nullptr);
    return;
  }
  g_dbus_method_invocation_return_error(
      invocation, G_DBUS_ERROR, G_DBUS_ERROR_UNKNOWN_METHOD, "unknown method");
}

void get_property(GDBusConnection*, const gchar*, const gchar*, const gchar*,
                  const gchar*, GDBusMethodInvocation* invocation, gpointer) {
  g_dbus_method_invocation_return_error(
      invocation, G_DBUS_ERROR, G_DBUS_ERROR_UNKNOWN_METHOD, "not supported");
}

void properties_call(GDBusConnection*, const gchar*, const gchar*, const gchar*,
                     const gchar* method, GVariant* parameters,
                     GDBusMethodInvocation* invocation, gpointer) {
  if (std::strcmp(method, "GetAll") != 0) {
    get_property(nullptr, nullptr, nullptr, nullptr, nullptr, invocation, nullptr);
    return;
  }
  const gchar* interface;
  g_variant_get(parameters, "(&s)", &interface);
  GVariantBuilder values;
  g_variant_builder_init(&values, G_VARIANT_TYPE("a{sv}"));
  if (std::strcmp(interface, "org.freedesktop.systemd1.Unit") == 0) {
    g_variant_builder_add(&values, "{sv}", "ActiveState",
                          g_variant_new_string(active ? "active" : "inactive"));
    g_variant_builder_add(&values, "{sv}", "Job",
                          g_variant_new("(uo)", 0, "/"));
  } else {
    line("STATUS_READ");
    g_variant_builder_add(&values, "{sv}", "ExecMainCode",
                          g_variant_new_int32(1));
    g_variant_builder_add(&values, "{sv}", "ExecMainStatus",
                          g_variant_new_int32(0));
    g_variant_builder_add(&values, "{sv}", "Result",
                          g_variant_new_string("success"));
    g_variant_builder_add(&values, "{sv}", "ControlGroup",
                          g_variant_new_string(cgroup ? "/test" : ""));
  }
  g_dbus_method_invocation_return_value(
      invocation, g_variant_new("(a{sv})", &values));
}

const GDBusInterfaceVTable manager_vtable = {method_call, nullptr, nullptr};
const GDBusInterfaceVTable properties_vtable = {properties_call, nullptr, nullptr};

const gchar* xml =
    "<node><interface name='org.freedesktop.systemd1.Manager'>"
    "<method name='StartTransientUnit'><arg type='s' direction='in'/>"
    "<arg type='s' direction='in'/><arg type='a(sv)' direction='in'/>"
    "<arg type='a(sa(sv))' direction='in'/><arg type='o' direction='out'/>"
    "</method><method name='GetUnit'><arg type='s' direction='in'/>"
    "<arg type='o' direction='out'/></method><method name='StopUnit'>"
    "<arg type='s' direction='in'/><arg type='s' direction='in'/>"
    "<arg type='o' direction='out'/></method><method name='UnrefUnit'>"
    "<arg type='s' direction='in'/></method></interface>"
    "<interface name='org.freedesktop.DBus.Properties'><method name='GetAll'>"
    "<arg type='s' direction='in'/><arg type='a{sv}' direction='out'/>"
    "</method></interface></node>";

void acquired(GDBusConnection* bus, const gchar*, gpointer) {
  connection = bus;
  GDBusNodeInfo* info = g_dbus_node_info_new_for_xml(xml, nullptr);
  g_dbus_connection_register_object(bus, "/org/freedesktop/systemd1",
                                    info->interfaces[0], &manager_vtable, nullptr,
                                    nullptr, nullptr);
  g_dbus_connection_register_object(bus, "/org/freedesktop/systemd1/unit/test",
                                    info->interfaces[1], &properties_vtable, nullptr,
                                    nullptr, nullptr);
  g_dbus_node_info_unref(info);
  line("READY");
}
}  // namespace

int main(int argc, char** argv) {
  if (argc < 3) return 2;
  reject = std::strcmp(argv[2], "reject") == 0;
  GError* error = nullptr;
  GDBusConnection* bus = g_dbus_connection_new_for_address_sync(
      argv[1], static_cast<GDBusConnectionFlags>(
          G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT |
          G_DBUS_CONNECTION_FLAGS_MESSAGE_BUS_CONNECTION), nullptr, nullptr,
      &error);
  if (bus == nullptr) return 3;
  loop = g_main_loop_new(nullptr, FALSE);
  GIOChannel* stdin_channel = g_io_channel_unix_new(STDIN_FILENO);
  g_io_add_watch(stdin_channel, static_cast<GIOCondition>(
      G_IO_IN | G_IO_HUP | G_IO_ERR), read_stdin, nullptr);
  owner_id = g_bus_own_name_on_connection(bus, "org.freedesktop.systemd1",
                                          G_BUS_NAME_OWNER_FLAGS_NONE, acquired,
                                          nullptr, nullptr, nullptr);
  g_main_loop_run(loop);
  if (input_fd >= 0) close(input_fd);
  close_output();
  g_bus_unown_name(owner_id);
  g_io_channel_unref(stdin_channel);
  g_object_unref(bus);
  g_main_loop_unref(loop);
}
