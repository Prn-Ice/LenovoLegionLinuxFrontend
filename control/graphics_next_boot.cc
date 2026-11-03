#include "control_commands.h"
#include <cstdio>
#include <gio/gio.h>
#include <string>

// Keep authorization and the request on one connection: authorization is bound
// to its unique bus name and is revoked when this process disconnects.
int main(int argc, char **argv) {
  const std::string action = argc == 2 ? argv[1] : "";
  std::string error;
  if (action == "--help" || action == "-h") {
    std::puts("Usage: legion-graphics-next-boot "
              "hybrid-igpu-only|hybrid|status|cancel\n"
              "Queues a later-boot change only. Does not change hardware or "
              "reboot now.");
    return 0;
  }
  if (action != "status" && action != "cancel" &&
      !legion_control::ValidateBootGraphicsMode(action, &error)) {
    std::fputs("Usage: legion-graphics-next-boot "
               "hybrid-igpu-only|hybrid|status|cancel\n",
               stderr);
    return 2;
  }
  GError *failure = nullptr;
  GDBusConnection *connection =
      g_bus_get_sync(G_BUS_TYPE_SYSTEM, nullptr, &failure);
  if (!connection) {
    std::fprintf(stderr, "Cannot connect to system bus: %s\n",
                 failure->message);
    g_clear_error(&failure);
    return 1;
  }
  auto call = [&](const char *method, GVariant *parameters,
                  const GVariantType *reply) {
    return g_dbus_connection_call_sync(
        connection, "io.github.prnice.LegionControl1",
        "/io/github/prnice/LegionControl1", "io.github.prnice.LegionControl1",
        method, parameters, reply,
        G_DBUS_CALL_FLAGS_ALLOW_INTERACTIVE_AUTHORIZATION, 120000, nullptr,
        &failure);
  };
  GVariant *reply = call("Authorize", nullptr, G_VARIANT_TYPE_UNIT);
  if (reply) {
    g_variant_unref(reply);
    const char *method = action == "status"   ? "GetGraphicsBootRequest"
                         : action == "cancel" ? "CancelGraphicsModeAtBoot"
                                              : "RequestGraphicsModeAtBoot";
    GVariant *parameters = action == "status" || action == "cancel"
                               ? nullptr
                               : g_variant_new("(s)", action.c_str());
    reply = call(method, parameters, G_VARIANT_TYPE("(s)"));
  }
  if (!reply) {
    std::fprintf(stderr, "Next-boot request failed: %s\n",
                 failure ? failure->message : "no response");
    g_clear_error(&failure);
    g_object_unref(connection);
    return 1;
  }
  const gchar *status = nullptr;
  g_variant_get(reply, "(&s)", &status);
  std::puts(status);
  if (action == "hybrid" || action == "hybrid-igpu-only")
    std::puts("Request saved. Nothing changed now. Reboot when you are ready.");
  g_variant_unref(reply);
  g_object_unref(connection);
  return 0;
}
