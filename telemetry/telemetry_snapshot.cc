#include "telemetry_snapshot.h"

namespace {

constexpr char kProtocolVersion[] = "1";

}  // namespace

GVariant* BuildTelemetrySnapshot(const PackagePowerReading& reading) {
  GVariantBuilder builder;
  g_variant_builder_init(&builder, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&builder, "{sv}", "Available",
                        g_variant_new_boolean(reading.available));
  g_variant_builder_add(&builder, "{sv}", "PackagePowerWatts",
                        g_variant_new_double(reading.watts));
  g_variant_builder_add(&builder, "{sv}", "Domain",
                        g_variant_new_string(reading.domain.c_str()));
  g_variant_builder_add(&builder, "{sv}", "Version",
                        g_variant_new_string(kProtocolVersion));
  if (!reading.error.empty()) {
    g_variant_builder_add(&builder, "{sv}", "Error",
                          g_variant_new_string(reading.error.c_str()));
  }
  return g_variant_builder_end(&builder);
}
