#pragma once

#include <gio/gio.h>

#include "package_power_sampler.h"

GVariant* BuildTelemetrySnapshot(const PackagePowerReading& reading);
