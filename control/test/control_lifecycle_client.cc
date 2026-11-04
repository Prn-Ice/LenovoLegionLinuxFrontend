#include "test_vm_guard.h"
#include <cstdio>
#include <gio/gio.h>
#include <string>

namespace {
constexpr char bus[] = "io.github.prnice.LegionControl1";
constexpr char path[] = "/io/github/prnice/LegionControl1";

bool Call(GDBusConnection *connection, const char *method, GVariant *arguments,
          bool returns_output = false) {
  GError *error = nullptr;
  GVariant *reply = g_dbus_connection_call_sync(
      connection, bus, path, bus, method, arguments,
      returns_output ? G_VARIANT_TYPE("(s)") : G_VARIANT_TYPE("()"),
      G_DBUS_CALL_FLAGS_NONE, 60000, nullptr, &error);
  if (!reply) {
    gchar *name = error ? g_dbus_error_get_remote_error(error) : nullptr;
    fprintf(stderr, "%s: %s\n", name ? name : "transport error",
            error ? error->message : "missing reply");
    g_free(name);
    g_clear_error(&error);
    return false;
  }
  if (returns_output) {
    const char *output;
    g_variant_get(reply, "(&s)", &output);
    puts(output);
  }
  g_variant_unref(reply);
  return true;
}
} // namespace

int main(int argc, char **argv) {
  if (!InControlTestVm()) {
    fprintf(stderr,
            "This client runs only in the disposable control test VM.\n");
    return 2;
  }
  if (argc != 2)
    return 2;
  const std::string operation = argv[1];
  const bool boot_operation = operation == "boot-request" ||
                              operation == "boot-status" ||
                              operation == "boot-cancel";
  if (operation != "toggle" && operation != "graphics" && operation != "fan" &&
      !boot_operation)
    return 2;

  GError *error = nullptr;
  GDBusConnection *connection =
      g_bus_get_sync(G_BUS_TYPE_SYSTEM, nullptr, &error);
  if (!connection) {
    fprintf(stderr, "%s\n", error ? error->message : "no system bus");
    g_clear_error(&error);
    return 1;
  }
  bool success = Call(connection, "Authorize", nullptr);
  if (success) {
    if (operation == "toggle")
      success = Call(connection, "SetToggle",
                     g_variant_new("(sb)", "battery-conservation", TRUE));
    else if (operation == "graphics")
      success = Call(connection, "SetGraphicsMode",
                     g_variant_new("(s)", "hybrid-igpu-only"));
    else if (operation == "fan") {
      constexpr char payload[] = "synthetic fan data\n";
      GVariant *bytes = g_variant_new_fixed_array(
          G_VARIANT_TYPE_BYTE, payload, sizeof(payload) - 1, sizeof(guint8));
      success =
          Call(connection, "ApplyFanCurve", g_variant_new("(@ay)", bytes));
    } else if (operation == "boot-request")
      success = Call(connection, "RequestGraphicsModeAtBoot",
                     g_variant_new("(s)", "hybrid-igpu-only"), true);
    else
      success = Call(connection,
                     operation == "boot-status" ? "GetGraphicsBootRequest"
                                                : "CancelGraphicsModeAtBoot",
                     nullptr, true);
  }
  g_dbus_connection_close_sync(connection, nullptr, nullptr);
  g_object_unref(connection);
  if (success && !boot_operation)
    puts("OK");
  return success ? 0 : 1;
}
