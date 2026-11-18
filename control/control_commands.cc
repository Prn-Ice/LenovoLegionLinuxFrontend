#include "control_commands.h"
#include <map>
#include <regex>
#include <set>

namespace legion_control {
namespace {
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
const std::set<std::string> fan_presets = {"quiet-battery",
                                           "balanced-battery",
                                           "performance-battery",
                                           "balanced-performance-battery",
                                           "quiet-ac",
                                           "balanced-ac",
                                           "performance-ac",
                                           "balanced-performance-ac"};
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
const std::map<std::string, std::vector<std::string>> service_units = {
    {"power_profiles_daemon", {"power-profiles-daemon.service"}},
    {"legiond_stack",
     {"legiond.service", "legiond-onresume.service", "legiond-cpuset.service",
      "legiond-cpuset.timer"}}};
const std::set<std::string> graphics_modes = {"hybrid", "hybrid-igpu-only",
                                              "discrete"};
bool IsUnsignedDecimal(const std::string &value) {
  return !value.empty() &&
         std::regex_match(value, std::regex("(0|[1-9][0-9]*)"));
}
} // namespace

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
        const auto [lower, upper] = limits->second;
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

bool ValidateToggle(const std::string &capability, bool, std::string *error) {
  if (toggle_commands.count(capability)) {
    return true;
  }
  *error = "unsupported capability";
  return false;
}

bool ValidatePreset(const std::string &preset, std::string *error) {
  if (fan_presets.count(preset)) {
    return true;
  }
  *error = "unsupported fan preset";
  return false;
}

bool ValidateConservation(uint32_t lower, uint32_t upper, std::string *error) {
  if (lower <= 100 && upper <= 100 && lower <= upper) {
    return true;
  }
  *error = "invalid conservation limits";
  return false;
}

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

Command FeatureCommand(const std::string &feature, const std::string &value) {
  return {{"--donotexpecthwmon", "set-feature", feature, value}};
}

Command ToggleCommand(const std::string &capability, bool enabled) {
  const std::string command =
      toggle_commands.at(capability) + (enabled ? "-enable" : "-disable");
  if (capability == "mini-fan-curve" || capability == "lock-fan-controller" ||
      capability == "maximum-fan-speed") {
    return {{command}};
  }
  return {{"--donotexpecthwmon", command}};
}

Command PresetCommand(const std::string &preset) {
  return {{"fancurve-write-preset-to-hw", preset}};
}

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
Command CurrentPresetCommand() {
  return {{"fancurve-write-current-preset-to-hw"}};
}
Command FileCommand(const std::string &path) {
  return {{"fancurve-write-file-to-hw", path}};
}
Command BootLogoCommand(const std::string &path) {
  return {{"--donotexpecthwmon", "boot-logo", "enable", path}};
}
Command RestoreBootLogoCommand() {
  return {{"--donotexpecthwmon", "boot-logo", "restore"}};
}
Command ConservationCommand(uint32_t lower, uint32_t upper) {
  return {{"--donotexpecthwmon", "custom-conservation-mode-apply",
           std::to_string(lower), std::to_string(upper)}};
}

bool ValidateService(const std::string &service_id, std::string *error) {
  if (service_units.count(service_id)) {
    return true;
  }
  *error = "unsupported service id";
  return false;
}

Command ServiceCommand(const std::string &service_id, bool enabled) {
  Command command{{enabled ? "enable" : "disable", "--now"}};
  const auto &units = service_units.at(service_id);
  command.argv.insert(command.argv.end(), units.begin(), units.end());
  return command;
}
bool ValidateGraphicsMode(const std::string &mode, std::string *error) {
  if (graphics_modes.count(mode)) {
    return true;
  }
  *error = "unsupported graphics mode";
  return false;
}
Command GraphicsModeCommand(const std::string &mode) {
  return {{"--donotexpecthwmon", "graphics-mode", "set", mode, "--json"}};
}
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
bool ValidateBootGraphicsMode(const std::string &mode, std::string *error) {
  if (mode == "hybrid" || mode == "hybrid-igpu-only") {
    return true;
  }
  *error = "only hybrid and hybrid-igpu-only can be requested for next boot";
  return false;
}
Command BootGraphicsRequestCommand(const std::string &mode) {
  return {{"request", mode}};
}
} // namespace legion_control
