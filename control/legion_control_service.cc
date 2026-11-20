// The installed D-Bus service. It owns the control bus name, checks polkit
// authorization, and runs the fixed legion_cli or systemctl commands through
// managed transient systemd units.

#include "control_protocol.h"
#include "control_service_runtime.h"
#include "trusted_executable.h"

#include <cstring>

namespace {
using legion_control::ControlContext;
constexpr const char *bus_name = legion_control::control_bus_name;
constexpr const char *object_path = legion_control::control_object_path;
constexpr const char *introspection_xml = legion_control::control_xml;

// A client that disconnects loses its authorization and any pending prompt.
// If it owned the running operation, cancel the operation so it cannot outlive
// the caller.
void NameOwnerChanged(GDBusConnection *, const gchar *, const gchar *,
                      const gchar *, const gchar *, GVariant *parameters,
                      gpointer data) {
  auto *context = static_cast<ControlContext *>(data);
  const char *name = nullptr;
  const char *old_owner = nullptr;
  const char *new_owner = nullptr;
  g_variant_get(parameters, "(&s&s&s)", &name, &old_owner, &new_owner);
  (void)old_owner;

  if (*new_owner)
    return;

  context->authorized_senders.erase(name);
  if (context->active && context->active->sender == name) {
    context->active->disconnected = true;
    context->active->command->Cancel();
  }

  auto pending = context->pending_authorizations.find(name);
  if (pending != context->pending_authorizations.end()) {
    g_cancellable_cancel(pending->second);
    g_object_unref(pending->second);
    context->pending_authorizations.erase(pending);
  }
}

void BusAcquired(GDBusConnection *connection, const gchar *, gpointer data) {
  auto *context = static_cast<ControlContext *>(data);
  g_set_object(&context->connection, connection);

  GError *error = nullptr;
  context->registration_id = g_dbus_connection_register_object(
      connection, object_path, context->info->interfaces[0],
      &legion_control::control_vtable, context, nullptr, &error);
  if (context->registration_id == 0) {
    g_warning("Could not export LegionControl1: %s",
              error ? error->message : "unknown error");
    g_clear_error(&error);
    g_main_loop_quit(context->loop);
    return;
  }

  context->name_watch_id = g_dbus_connection_signal_subscribe(
      connection, "org.freedesktop.DBus", "org.freedesktop.DBus",
      "NameOwnerChanged", "/org/freedesktop/DBus", nullptr,
      G_DBUS_SIGNAL_FLAGS_NONE, NameOwnerChanged, context, nullptr);
  if (context->name_watch_id == 0) {
    g_warning("Could not subscribe to D-Bus owner changes");
    g_main_loop_quit(context->loop);
  }
}

void BusLost(GDBusConnection *, const gchar *, gpointer data) {
  g_main_loop_quit(static_cast<ControlContext *>(data)->loop);
}

// Release the objects that main created, in the order that keeps callbacks
// from using them after they are gone.
void ShutDown(ControlContext *context) {
  if (context->name_watch_id != 0 && context->connection)
    g_dbus_connection_signal_unsubscribe(context->connection,
                                         context->name_watch_id);
  if (context->registration_id != 0 && context->connection)
    g_dbus_connection_unregister_object(context->connection,
                                        context->registration_id);

  if (context->active) {
    context->active->disconnected = true;
    context->active->command->Cancel();
    while (context->active)
      g_main_context_iteration(nullptr, TRUE);
  }

  for (auto &entry : context->pending_authorizations)
    g_cancellable_cancel(entry.second);
  while (context->authorization_callbacks != 0)
    g_main_context_iteration(nullptr, TRUE);

  g_bus_unown_name(context->owner_id);
  g_clear_object(&context->connection);
  g_clear_object(&context->polkit_authority);
  g_clear_pointer(&context->info, g_dbus_node_info_unref);
  g_main_loop_unref(context->loop);
}
}  // namespace

int main(int argc, char **argv) {
  std::string cli;
  std::string systemctl;
  std::string graphics_boot_helper;

  for (int index = 1; index < argc; ++index) {
    if (index + 1 < argc && std::string(argv[index]) == "--cli")
      cli = argv[++index];
    else if (index + 1 < argc && std::string(argv[index]) == "--systemctl")
      systemctl = argv[++index];
    else if (index + 1 < argc &&
             std::string(argv[index]) == "--graphics-boot-helper")
      graphics_boot_helper = argv[++index];
    else
      return 2;
  }

  if (cli.empty() || systemctl.empty() || cli[0] != '/' ||
      systemctl[0] != '/' || !legion_control::TrustedExecutable(cli, &cli) ||
      !legion_control::TrustedExecutable(systemctl, &systemctl))
    return 2;
  if (!graphics_boot_helper.empty() &&
      (graphics_boot_helper[0] != '/' ||
       !legion_control::TrustedExecutable(graphics_boot_helper,
                                          &graphics_boot_helper)))
    return 2;

  ControlContext context{};
  context.loop = g_main_loop_new(nullptr, FALSE);
  context.cli_path = cli;
  context.systemctl_path = systemctl;
  context.graphics_boot_path = graphics_boot_helper;

  GError *error = nullptr;
  gchar *manager_address =
      g_dbus_address_get_for_bus_sync(G_BUS_TYPE_SYSTEM, nullptr, &error);
  GDBusConnection *manager_connection =
      manager_address ? g_dbus_connection_new_for_address_sync(
                            manager_address,
                            static_cast<GDBusConnectionFlags>(
                                G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT |
                                G_DBUS_CONNECTION_FLAGS_MESSAGE_BUS_CONNECTION),
                            nullptr, nullptr, &error)
                      : nullptr;
  g_free(manager_address);
  if (!manager_connection) {
    g_clear_error(&error);
    g_main_loop_unref(context.loop);
    return 1;
  }

  context.runner = legion_control::CreateManagedCommandRunner(
      manager_connection, "legion-control.service",
      graphics_boot_helper.empty() ? "" : "legion-graphics-boot",
      "/run/legion-control/operation.lock");
  g_object_unref(manager_connection);

  context.polkit_authority = polkit_authority_get_sync(nullptr, &error);
  if (!context.polkit_authority) {
    g_clear_error(&error);
    g_main_loop_unref(context.loop);
    return 1;
  }

  context.info = g_dbus_node_info_new_for_xml(introspection_xml, &error);
  if (!context.info) {
    g_clear_error(&error);
    g_clear_object(&context.polkit_authority);
    g_main_loop_unref(context.loop);
    return 1;
  }

  context.owner_id =
      g_bus_own_name(G_BUS_TYPE_SYSTEM, bus_name, G_BUS_NAME_OWNER_FLAGS_NONE,
                     BusAcquired, nullptr, BusLost, &context, nullptr);

  g_main_loop_run(context.loop);
  ShutDown(&context);
  return 0;
}
