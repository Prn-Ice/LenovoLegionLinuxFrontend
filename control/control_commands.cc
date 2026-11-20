// The allow-list that turns typed control requests into legion_cli commands.
//
// The desktop app cannot run arbitrary commands as root. It sends a feature,
// toggle, preset, or payload to the control service, and this file checks the
// request and builds the fixed legion_cli command that performs it. Keep every
// accepted name and range here so the service and its tests share one list.

#include "control_commands.h"

#include <algorithm>
#include <map>
#include <set>

namespace legion_control {
namespace {

// Platform profiles accepted by `legion_cli set-feature
// PlatformProfileFeature`.
const std::set<std::string> platform_profiles = {
    "quiet",    "low-power",   "power-saver",
    "balanced", "performance", "balanced-performance",
    "custom",   "max-power"};

// Boolean features accept only "0" or "1".
const std::set<std::string> boolean_features = {
    "OverdriveFeature", "WinkeyFeature", "CPUOverclock",
    "GPUOverclock",     "YLogoLight",    "IOPortLight"};

// Integer features and their inclusive ranges. legion_cli rejects values
// outside these bounds, so the service rejects them first.
const std::map<std::string, std::pair<int, int>> integer_features = {
    {"CPULongtermPowerLimit", {5, 200}},
    {"CPUShorttermPowerLimit", {5, 200}},
    {"CPUPeakPowerLimit", {1, 200}},
    {"CPUCrossLoadingPowerLimit", {1, 100}},
    {"CPUAPUSPPTPowerLimit", {1, 100}},
    {"GPUCTGPPowerLimit", {1, 200}},
    {"GPUPPABPowerLimit", {1, 200}},
    {"GPUBoostClock", {1, 10000}},
    {"GPUTemperatureLimit", {1, 120}}};

// Fan-curve presets that the frontend offers.
const std::set<std::string> fan_presets = {"quiet-battery",
                                           "balanced-battery",
                                           "performance-battery",
                                           "balanced-performance-battery",
                                           "quiet-ac",
                                           "balanced-ac",
                                           "performance-ac",
                                           "balanced-performance-ac"};

// Frontend toggle names mapped to the matching legion_cli command suffix.
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

// Services that the installed helper may start or stop.
const std::map<std::string, std::vector<std::string>> service_units = {
    {"power_profiles_daemon", {"power-profiles-daemon.service"}},
    {"legiond_stack",
     {"legiond.service", "legiond-onresume.service", "legiond-cpuset.service",
      "legiond-cpuset.timer"}}};

const std::set<std::string> graphics_modes = {"hybrid", "hybrid-igpu-only",
                                              "discrete"};

// Matches the decimal format accepted by legion_cli: "0" or a number without
// a leading zero.
bool IsDecimal(const std::string &value) {
  if (value.empty())
    return false;
  if (value.size() > 1 && value.front() == '0')
    return false;
  return std::all_of(value.begin(), value.end(), [](unsigned char character) {
    return character >= '0' && character <= '9';
  });
}

}  // namespace

bool ValidateFeature(const std::string &feature, const std::string &value,
                     std::string *error) {
  if (feature == "PlatformProfileFeature") {
    if (platform_profiles.count(value))
      return true;
  } else if (boolean_features.count(feature)) {
    if (value == "0" || value == "1")
      return true;
  } else {
    const auto range = integer_features.find(feature);
    if (range != integer_features.end() && IsDecimal(value)) {
      try {
        const long number = std::stol(value);
        if (number >= range->second.first && number <= range->second.second)
          return true;
      } catch (...) {
        // std::stol can throw for a value too large to represent. The caller
        // gets the same rejection as any other out-of-range value.
      }
    }
  }
  *error = "unsupported feature or value";
  return false;
}

bool ValidateToggle(const std::string &capability, std::string *error) {
  if (toggle_commands.count(capability))
    return true;
  *error = "unsupported capability";
  return false;
}

bool ValidatePreset(const std::string &preset, std::string *error) {
  if (fan_presets.count(preset))
    return true;
  *error = "unsupported fan preset";
  return false;
}

bool ValidateConservation(uint32_t lower, uint32_t upper, std::string *error) {
  if (lower <= 100 && upper <= 100 && lower <= upper)
    return true;
  *error = "invalid conservation limits";
  return false;
}

Command FeatureCommand(const std::string &feature, const std::string &value) {
  return {{"--donotexpecthwmon", "set-feature", feature, value}};
}

Command ToggleCommand(const std::string &capability, bool enabled) {
  const std::string command =
      toggle_commands.at(capability) + (enabled ? "-enable" : "-disable");

  // The fan-controller commands need the hwmon interface, so they do not pass
  // --donotexpecthwmon. The other toggles can run without it.
  if (capability == "mini-fan-curve" || capability == "lock-fan-controller" ||
      capability == "maximum-fan-speed")
    return {{command}};
  return {{"--donotexpecthwmon", command}};
}

Command PresetCommand(const std::string &preset) {
  return {{"fancurve-write-preset-to-hw", preset}};
}

// Every command that portable CLI qualification expects the installed
// legion_cli --help output to advertise.
std::vector<std::string> InteractiveCliCommands() {
  std::vector<std::string> commands = {"set-feature",
                                       "graphics-mode",
                                       "boot-logo",
                                       "fancurve-write-preset-to-hw",
                                       "fancurve-write-current-preset-to-hw",
                                       "fancurve-write-file-to-hw",
                                       "custom-conservation-mode-apply"};
  for (const auto &toggle : toggle_commands)
    for (const bool enabled : {false, true})
      commands.push_back(toggle.second + (enabled ? "-enable" : "-disable"));
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
  if (service_units.count(service_id))
    return true;
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
  if (graphics_modes.count(mode))
    return true;
  *error = "unsupported graphics mode";
  return false;
}

Command GraphicsModeCommand(const std::string &mode) {
  return {{"--donotexpecthwmon", "graphics-mode", "set", mode, "--json"}};
}

// legion_cli uses these exit codes to distinguish a blocked change from a
// change that is still settling.
GraphicsExit ClassifyGraphicsExit(int exit_status) {
  if (exit_status == 0)
    return GraphicsExit::kSuccess;
  if (exit_status == 2)
    return GraphicsExit::kBlocked;
  if (exit_status == 3)
    return GraphicsExit::kPending;
  return GraphicsExit::kFailed;
}

// legion_cli uses exit code 2 when a capability is unavailable and 3 when the
// installed version does not support the feature.
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
  if (mode == "hybrid" || mode == "hybrid-igpu-only")
    return true;
  *error = "only hybrid and hybrid-igpu-only can be requested for next boot";
  return false;
}

Command BootGraphicsRequestCommand(const std::string &mode) {
  return {{"request", mode}};
}

}  // namespace legion_control
