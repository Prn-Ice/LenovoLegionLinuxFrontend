#include "control_protocol.h"
#include "control_service_runtime.h"
#include "trusted_executable.h"

#include <cstring>

namespace {
using legion_control::ControlContext;
constexpr const char *bus = legion_control::control_bus_name,
                     *path = legion_control::control_object_path,
                     *xml = legion_control::control_xml;
} // namespace
int main(int argc, char **argv) {
  std::string cli, sys, graphics_boot;
  for (int n = 1; n < argc; n++) {
    if (n + 1 < argc && std::string(argv[n]) == "--cli")
      cli = argv[++n];
    else if (n + 1 < argc && std::string(argv[n]) == "--systemctl")
      sys = argv[++n];
    else if (n + 1 < argc && std::string(argv[n]) == "--graphics-boot-helper")
      graphics_boot = argv[++n];
    else
      return 2;
  }
  if (cli.empty() || sys.empty() || cli[0] != '/' || sys[0] != '/' ||
      !legion_control::TrustedExecutable(cli, &cli) ||
      !legion_control::TrustedExecutable(sys, &sys))
    return 2;
  if (!graphics_boot.empty() &&
      (graphics_boot[0] != '/' ||
       !legion_control::TrustedExecutable(graphics_boot, &graphics_boot)))
    return 2;
  ControlContext c{};
  c.loop = g_main_loop_new(nullptr, FALSE);
  c.cli = cli;
  c.systemctl = sys;
  c.graphics_boot = graphics_boot;
  GError *e = nullptr;
  gchar *manager_address =
      g_dbus_address_get_for_bus_sync(G_BUS_TYPE_SYSTEM, nullptr, &e);
  GDBusConnection *manager_connection =
      manager_address ? g_dbus_connection_new_for_address_sync(
                            manager_address,
                            static_cast<GDBusConnectionFlags>(
                                G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT |
                                G_DBUS_CONNECTION_FLAGS_MESSAGE_BUS_CONNECTION),
                            nullptr, nullptr, &e)
                      : nullptr;
  g_free(manager_address);
  if (!manager_connection) {
    g_clear_error(&e);
    g_main_loop_unref(c.loop);
    return 1;
  }
  c.runner = legion_control::CreateManagedCommandRunner(
      manager_connection, "legion-control.service",
      graphics_boot.empty() ? "" : "legion-graphics-boot",
      "/run/legion-control/operation.lock");
  g_object_unref(manager_connection);
  c.authority = polkit_authority_get_sync(nullptr, &e);
  if (!c.authority) {
    g_clear_error(&e);
    g_main_loop_unref(c.loop);
    return 1;
  }
  c.info = g_dbus_node_info_new_for_xml(xml, &e);
  if (!c.info) {
    g_clear_error(&e);
    g_clear_object(&c.authority);
    g_main_loop_unref(c.loop);
    return 1;
  }
  c.owner = g_bus_own_name(
      G_BUS_TYPE_SYSTEM, bus, G_BUS_NAME_OWNER_FLAGS_NONE,
      [](GDBusConnection *x, const gchar *, gpointer d) {
        auto *c = static_cast<ControlContext *>(d);
        g_set_object(&c->conn, x);
        GError *error = nullptr;
        c->reg = g_dbus_connection_register_object(
            x, path, c->info->interfaces[0], &legion_control::control_vtable, c,
            nullptr, &error);
        if (c->reg == 0) {
          g_warning("Could not export LegionControl1: %s",
                    error ? error->message : "unknown error");
          g_clear_error(&error);
          g_main_loop_quit(c->loop);
          return;
        }
        c->names = g_dbus_connection_signal_subscribe(
            x, "org.freedesktop.DBus", "org.freedesktop.DBus",
            "NameOwnerChanged", "/org/freedesktop/DBus", nullptr,
            G_DBUS_SIGNAL_FLAGS_NONE,
            [](GDBusConnection *, const gchar *, const gchar *, const gchar *,
               const gchar *, GVariant *v, gpointer d) {
              auto *c = static_cast<ControlContext *>(d);
              const char *n;
              const char *old;
              const char *now;
              g_variant_get(v, "(&s&s&s)", &n, &old, &now);
              if (!*now) {
                c->auth.erase(n);
                if (c->active && c->active->sender == n) {
                  c->active->disconnected = true;
                  c->active->command->Cancel();
                }
                auto pending = c->pending.find(n);
                if (pending != c->pending.end()) {
                  g_cancellable_cancel(pending->second);
                  g_object_unref(pending->second);
                  c->pending.erase(pending);
                }
              }
            },
            c, nullptr);
        if (c->names == 0) {
          g_warning("Could not subscribe to D-Bus owner changes");
          g_main_loop_quit(c->loop);
        }
      },
      nullptr,
      [](GDBusConnection *, const gchar *, gpointer d) {
        g_main_loop_quit(static_cast<ControlContext *>(d)->loop);
      },
      &c, nullptr);
  g_main_loop_run(c.loop);
  if (c.names != 0 && c.conn != nullptr)
    g_dbus_connection_signal_unsubscribe(c.conn, c.names);
  if (c.reg != 0 && c.conn != nullptr)
    g_dbus_connection_unregister_object(c.conn, c.reg);
  if (c.active) {
    c.active->disconnected = true;
    c.active->command->Cancel();
    while (c.active)
      g_main_context_iteration(nullptr, TRUE);
  }
  for (auto &entry : c.pending)
    g_cancellable_cancel(entry.second);
  while (c.authorization_callbacks != 0)
    g_main_context_iteration(nullptr, TRUE);
  g_bus_unown_name(c.owner);
  g_clear_object(&c.conn);
  g_clear_object(&c.authority);
  g_clear_pointer(&c.info, g_dbus_node_info_unref);
  g_main_loop_unref(c.loop);
  return 0;
}
