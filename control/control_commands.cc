// Validate control requests and build command arguments for the native service.
// The service handles authorization and execution.
#include "control_commands.h"
#include <map>
#include <regex>
#include <set>

namespace legion_control {
namespace {

// Feature names and values the control service accepts from the app.
const std::set<std::string> platform_profiles = {
    "quiet",    "low-power",   "power-saver",
    "balanced", "performance", "balanced-performance",
    "custom",   "max-power"};

const std::set<std::string> boolean_features = {
    "OverdriveFeature", "WinkeyFeature", "CPUOverclock",
    "GPUOverclock",     "YLogoLight",    "IOPortLight"};

const std::map<std::string, std::pair<int, int>> integer_feature_limits = {
    {"CPULongtermPowerLimit", {5, 200}},
    {"CPUShorttermPowerLimit", {5, 200}},
    {"CPUPeakPowerLimit", {1, 200}},
    {"CPUCrossLoadingPowerLimit", {1, 100}},
    {"CPUAPUSPPTPowerLimit", {1, 100}},
    {"GPUCTGPPowerLimit", {1, 200}},
    {"GPUPPABPowerLimit", {1, 200}},
    {"GPUBoostClock", {1, 10000}},
    {"GPUTemperatureLimit", {1, 120}}};

// Fan presets supported by the CLI, for battery and AC power.
const std::set<std::string> fan_presets = {"quiet-battery",
                                           "balanced-battery",
                                           "performance-battery",
                                           "balanced-performance-battery",
                                           "quiet-ac",
                                           "balanced-ac",
                                           "performance-ac",
                                           "balanced-performance-ac"};

// Translate app capability names to CLI command prefixes.
const std::map<std::string, std::string> toggle_commands = {
    {"hybrid-mode", "hybrid-mode"},
    {"battery-conservation", "batteryconservation"},
    {"rapid-charging", "rapid-charging"},
    {"always-on-usb-charging", "always-on-usb-charging"},
    {"touchpad", "touchpad"},
    {"fn-lock", "fnlock"},
    {"mini-fan-curve", "minifancurve"},
    {"lock-fan-controller", "lockfancontroller"},
    {"maximum-fan-speed", "maximumfanspeed"}};

// Each service choice controls only these systemd units.
const std::map<std::string, std::vector<std::string>> service_units = {
    {"power_profiles_daemon", {"power-profiles-daemon.service"}},
    {"legiond_stack",
     {"legiond.service", "legiond-onresume.service", "legiond-cpuset.service",
      "legiond-cpuset.timer"}}};

const std::set<std::string> graphics_modes = {"hybrid", "hybrid-igpu-only",
                                              "discrete"};

// Accept digits without a sign, whitespace, or extra leading zeroes.
bool IsUnsignedDecimal(const std::string &value) {
  return !value.empty() &&
         std::regex_match(value, std::regex("(0|[1-9][0-9]*)"));
}

} // namespace

// Check profile names, on/off values, and integer limits before a feature
// write.
bool ValidateFeature(const std::string &feature, const std::string &value,
                     std::string *error) {
  if (feature == "PlatformProfileFeature") {
    if (platform_profiles.count(value)) {
      return true;
    }
  } else if (boolean_features.count(feature)) {
    if (value == "0" || value == "1") {
      return true;
    }
  } else {
    const auto limits = integer_feature_limits.find(feature);
    if (limits != integer_feature_limits.end() && IsUnsignedDecimal(value)) {
      try {
        const long number = std::stol(value);
        const int lower = limits->second.first;
        const int upper = limits->second.second;
        if (number >= lower && number <= upper) {
          return true;
        }
      } catch (...) {
        // Values outside the parser's range are rejected below.
      }
    }
  }
  *error = "Cannot set " + feature + " to " + value +
           ": unsupported feature or value.";
  return false;
}

// Only known capabilities can be switched on or off.
bool ValidateToggle(const std::string &capability, bool, std::string *error) {
  if (toggle_commands.count(capability)) {
    return true;
  }
  *error = "unsupported capability";
  return false;
}

// Reject fan preset names outside the supported list.
bool ValidatePreset(const std::string &preset, std::string *error) {
  if (fan_presets.count(preset)) {
    return true;
  }
  *error = "unsupported fan preset";
  return false;
}

// Charging thresholds are percentages, ordered from lower to upper.
bool ValidateConservation(uint32_t lower, uint32_t upper, std::string *error) {
  if (lower <= 100 && upper <= 100 && lower <= upper) {
    return true;
  }
  *error = "invalid conservation limits";
  return false;
}

// Reject empty uploads and uploads larger than the operation allows.
bool ValidateBytes(const std::vector<uint8_t> &bytes, std::size_t maximum_size,
                   std::string *error) {
  if (bytes.empty()) {
    *error = "payload must not be empty";
    return false;
  }
  if (bytes.size() > maximum_size) {
    *error = "payload exceeds maximum size";
    return false;
  }
  return true;
}

// Build a feature-write command without requiring a hwmon device.
Command FeatureCommand(const std::string &feature, const std::string &value) {
  return {{"--donotexpecthwmon", "set-feature", feature, value}};
}

// Fan-controller commands require hwmon; other toggles can run without it.
Command ToggleCommand(const std::string &capability, bool enabled) {
  const std::string command =
      toggle_commands.at(capability) + (enabled ? "-enable" : "-disable");
  if (capability == "mini-fan-curve" || capability == "lock-fan-controller" ||
      capability == "maximum-fan-speed") {
    return {{command}};
  }
  return {{"--donotexpecthwmon", command}};
}

// Apply a named fan preset to the hardware.
Command PresetCommand(const std::string &preset) {
  return {{"fancurve-write-preset-to-hw", preset}};
}

// CLI discovery requires all these commands before accepting an installation.
std::vector<std::string> InteractiveCliCommands() {
  std::vector<std::string> commands = {"set-feature",
                                       "graphics-mode",
                                       "boot-logo",
                                       "fancurve-write-preset-to-hw",
                                       "fancurve-write-current-preset-to-hw",
                                       "fancurve-write-file-to-hw",
                                       "custom-conservation-mode-apply"};
  for (const auto &toggle : toggle_commands) {
    for (const bool enabled : {false, true}) {
      commands.push_back(toggle.second + (enabled ? "-enable" : "-disable"));
    }
  }
  return commands;
}

// Apply the CLI's current fan preset.
Command CurrentPresetCommand() {
  return {{"fancurve-write-current-preset-to-hw"}};
}

// Load a fan curve from the supplied file.
Command FileCommand(const std::string &path) {
  return {{"fancurve-write-file-to-hw", path}};
}

// Use the supplied image as the boot logo.
Command BootLogoCommand(const std::string &path) {
  return {{"--donotexpecthwmon", "boot-logo", "enable", path}};
}

// Restore the original boot logo.
Command RestoreBootLogoCommand() {
  return {{"--donotexpecthwmon", "boot-logo", "restore"}};
}

// Apply the lower and upper battery charging thresholds.
Command ConservationCommand(uint32_t lower, uint32_t upper) {
  return {{"--donotexpecthwmon", "custom-conservation-mode-apply",
           std::to_string(lower), std::to_string(upper)}};
}

// Reject service choices outside the supported systemd groups.
bool ValidateService(const std::string &service_id, std::string *error) {
  if (service_units.count(service_id)) {
    return true;
  }
  *error = "unsupported service id";
  return false;
}

// Enable or disable the group's units and start or stop them immediately.
Command ServiceCommand(const std::string &service_id, bool enabled) {
  Command command{{enabled ? "enable" : "disable", "--now"}};
  const auto &units = service_units.at(service_id);
  command.argv.insert(command.argv.end(), units.begin(), units.end());
  return command;
}

// Check that the requested graphics mode is supported.
bool ValidateGraphicsMode(const std::string &mode, std::string *error) {
  if (graphics_modes.count(mode)) {
    return true;
  }
  *error = "unsupported graphics mode";
  return false;
}

// Request a graphics mode change and ask the CLI for a JSON result.
Command GraphicsModeCommand(const std::string &mode) {
  return {{"--donotexpecthwmon", "graphics-mode", "set", mode, "--json"}};
}

// Translate CLI exit codes into graphics outcomes for the app.
GraphicsExit ClassifyGraphicsExit(int exit_status) {
  if (exit_status == 0) {
    return GraphicsExit::kSuccess;
  }
  if (exit_status == 2) {
    return GraphicsExit::kBlocked;
  }
  if (exit_status == 3) {
    return GraphicsExit::kPending;
  }
  return GraphicsExit::kFailed;
}
CliExit ClassifyCliExit(int exit_status) {
  if (exit_status == 0)
    return CliExit::kSuccess;
  if (exit_status == 2)
    return CliExit::kUnavailable;
  if (exit_status == 3)
    return CliExit::kFeatureNotFound;
  return CliExit::kFailed;
}

// Next-boot requests support only the two hybrid graphics modes.
bool ValidateBootGraphicsMode(const std::string &mode, std::string *error) {
  if (mode == "hybrid" || mode == "hybrid-igpu-only") {
    return true;
  }
  *error = "only hybrid and hybrid-igpu-only can be requested for next boot";
  return false;
}

// Build the request sent to the next-boot graphics tool.
Command BootGraphicsRequestCommand(const std::string &mode) {
  return {{"request", mode}};
}

} // namespace legion_control
