#include <gio/gio.h>

#include <cstdint>
#include <memory>
#include <string>

#include "package_power_sampler.h"
#include "telemetry_snapshot.h"

namespace {

constexpr char kBusName[] = "io.github.prnice.LegionTelemetry1";
constexpr char kObjectPath[] = "/io/github/prnice/LegionTelemetry1";
constexpr char kInterfaceName[] = "io.github.prnice.LegionTelemetry1";

constexpr char kIntrospectionXml[] = R"XML(
<node>
  <interface name="io.github.prnice.LegionTelemetry1">
    <method name="GetSnapshot">
      <arg name="snapshot" type="a{sv}" direction="out"/>
    </method>
  </interface>
</node>
)XML";

struct ServiceContext {
  explicit ServiceContext(std::string powercap_root)
      : sampler(std::move(powercap_root)) {}

  PackagePowerSampler sampler;
  GMainLoop* loop = nullptr;
  GDBusNodeInfo* introspection = nullptr;
  guint registration_id = 0;
  bool name_acquired = false;
};

gboolean SamplePower(gpointer user_data) {
  auto* context = static_cast<ServiceContext*>(user_data);
  context->sampler.Sample(g_get_monotonic_time());
  return G_SOURCE_CONTINUE;
}

void HandleMethodCall(GDBusConnection*, const gchar*, const gchar*,
                      const gchar* interface_name, const gchar* method_name,
                      GVariant*, GDBusMethodInvocation* invocation,
                      gpointer user_data) {
  auto* context = static_cast<ServiceContext*>(user_data);
  if (g_strcmp0(interface_name, kInterfaceName) != 0 ||
      g_strcmp0(method_name, "GetSnapshot") != 0) {
    g_dbus_method_invocation_return_error(
        invocation, G_DBUS_ERROR, G_DBUS_ERROR_UNKNOWN_METHOD,
        "Unknown telemetry method");
    return;
  }

  const auto& reading = context->sampler.reading();
  g_dbus_method_invocation_return_value(
      invocation, g_variant_new("(@a{sv})", BuildTelemetrySnapshot(reading)));
}

const GDBusInterfaceVTable kInterfaceVTable = {HandleMethodCall, nullptr,
                                               nullptr, {nullptr}};

void OnBusAcquired(GDBusConnection* connection, const gchar*,
                   gpointer user_data) {
  auto* context = static_cast<ServiceContext*>(user_data);
  GError* error = nullptr;
  context->registration_id = g_dbus_connection_register_object(
      connection, kObjectPath, context->introspection->interfaces[0],
      &kInterfaceVTable, context, nullptr, &error);
  if (context->registration_id == 0) {
    g_printerr("Failed to register telemetry object: %s\n", error->message);
    g_clear_error(&error);
    g_main_loop_quit(context->loop);
  }
}

void OnNameAcquired(GDBusConnection*, const gchar*, gpointer user_data) {
  auto* context = static_cast<ServiceContext*>(user_data);
  context->name_acquired = true;
}

void OnNameLost(GDBusConnection*, const gchar*, gpointer user_data) {
  auto* context = static_cast<ServiceContext*>(user_data);
  g_printerr("Failed to own D-Bus name %s\n", kBusName);
  g_main_loop_quit(context->loop);
}

}  // namespace

int main(int argc, char** argv) {
  std::string powercap_root = "/sys/class/powercap";
  if (argc == 3 && std::string(argv[1]) == "--sysfs-root") {
    powercap_root = argv[2];
  } else if (argc != 1) {
    g_printerr("Usage: %s [--sysfs-root PATH]\n", argv[0]);
    return 2;
  }

  ServiceContext context(powercap_root);
  context.loop = g_main_loop_new(nullptr, FALSE);

  GError* error = nullptr;
  context.introspection =
      g_dbus_node_info_new_for_xml(kIntrospectionXml, &error);
  if (context.introspection == nullptr) {
    g_printerr("Invalid telemetry introspection XML: %s\n", error->message);
    g_clear_error(&error);
    g_main_loop_unref(context.loop);
    return 1;
  }

  SamplePower(&context);
  const guint timer_id = g_timeout_add_seconds(1, SamplePower, &context);
  const guint owner_id = g_bus_own_name(
      G_BUS_TYPE_SYSTEM, kBusName, G_BUS_NAME_OWNER_FLAGS_NONE, OnBusAcquired,
      OnNameAcquired, OnNameLost, &context, nullptr);

  g_main_loop_run(context.loop);

  g_bus_unown_name(owner_id);
  g_source_remove(timer_id);
  g_dbus_node_info_unref(context.introspection);
  g_main_loop_unref(context.loop);
  return context.name_acquired ? 0 : 1;
}
