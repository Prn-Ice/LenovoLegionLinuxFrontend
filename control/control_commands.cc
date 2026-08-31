#include "control_commands.h"
#include <map>
#include <regex>
#include <set>

namespace legion_control {
namespace {
const std::set<std::string> profiles = {"quiet",       "low-power",
                                        "power-saver", "balanced",
                                        "performance", "balanced-performance",
                                        "custom",      "max-power"};
const std::set<std::string> bools = {"OverdriveFeature", "WinkeyFeature",
                                     "CPUOverclock",     "GPUOverclock",
                                     "YLogoLight",       "IOPortLight"};
const std::map<std::string, std::pair<int, int>> ints = {
    {"CPULongtermPowerLimit", {5, 200}},
    {"CPUShorttermPowerLimit", {5, 200}},
    {"CPUPeakPowerLimit", {1, 200}},
    {"CPUCrossLoadingPowerLimit", {1, 100}},
    {"CPUAPUSPPTPowerLimit", {1, 100}},
    {"CPUDefaultPowerLimit", {1, 100}},
    {"GPUCTGPPowerLimit", {1, 200}},
    {"GPUPPABPowerLimit", {1, 200}},
    {"GPUBoostClock", {1, 10000}},
    {"GPUTemperatureLimit", {1, 120}}};
const std::set<std::string> presets = {"quiet-battery",
                                       "balanced-battery",
                                       "performance-battery",
                                       "balanced-performance-battery",
                                       "quiet-ac",
                                       "balanced-ac",
                                       "performance-ac",
                                       "balanced-performance-ac"};
const std::map<std::string, std::string> toggles = {
    {"hybrid-mode", "hybrid-mode"},
    {"battery-conservation", "batteryconservation"},
    {"rapid-charging", "rapid-charging"},
    {"always-on-usb-charging", "always-on-usb-charging"},
    {"touchpad", "touchpad"},
    {"fn-lock", "fnlock"},
    {"mini-fan-curve", "minifancurve"},
    {"lock-fan-controller", "lockfancontroller"},
    {"maximum-fan-speed", "maximumfanspeed"}};
const std::map<std::string, std::vector<std::string>> services = {
    {"power_profiles_daemon", {"power-profiles-daemon.service"}},
    {"legiond_stack",
      {"legiond.service", "legiond-onresume.service", "legiond-cpuset.service",
       "legiond-cpuset.timer"}}};
const std::set<std::string> graphics_modes = {
    "hybrid", "hybrid-igpu-only", "discrete"};
bool decimal(const std::string &s) {
  return !s.empty() && std::regex_match(s, std::regex("(0|[1-9][0-9]*)"));
}
} // namespace
bool ValidateFeature(const std::string &f, const std::string &v,
                     std::string *e) {
  if (f == "PlatformProfileFeature") {
    if (profiles.count(v))
      return true;
  } else if (bools.count(f)) {
    if (v == "0" || v == "1")
      return true;
  } else {
    auto i = ints.find(f);
    if (i != ints.end() && decimal(v)) {
      try {
        long n = std::stol(v);
        if (n >= i->second.first && n <= i->second.second)
          return true;
      } catch (...) {
      }
    }
  }
  *e = "unsupported feature or value";
  return false;
}
bool ValidateToggle(const std::string &c, bool, std::string *e) {
  if (toggles.count(c))
    return true;
  *e = "unsupported capability";
  return false;
}
bool ValidatePreset(const std::string &p, std::string *e) {
  if (presets.count(p))
    return true;
  *e = "unsupported fan preset";
  return false;
}
bool ValidateConservation(uint32_t l, uint32_t u, std::string *e) {
  if (l <= 100 && u <= 100 && l <= u)
    return true;
  *e = "invalid conservation limits";
  return false;
}
bool ValidateBytes(const std::vector<uint8_t> &b, std::size_t max,
                   std::string *e) {
  if (b.empty()) {
    *e = "payload must not be empty";
    return false;
  }
  if (b.size() > max) {
    *e = "payload exceeds maximum size";
    return false;
  }
  return true;
}
Command FeatureCommand(const std::string &f, const std::string &v) {
  return {{"--donotexpecthwmon", "set-feature", f, v}};
}
Command ToggleCommand(const std::string &c, bool on) {
  const std::string command = toggles.at(c) + (on ? "-enable" : "-disable");
  if (c == "mini-fan-curve" || c == "lock-fan-controller" ||
      c == "maximum-fan-speed")
    return {{command}};
  return {{"--donotexpecthwmon", command}};
}
Command PresetCommand(const std::string &p) {
  return {{"fancurve-write-preset-to-hw", p}};
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
Command ConservationCommand(uint32_t l, uint32_t u) {
  return {{"--donotexpecthwmon", "custom-conservation-mode-apply",
           std::to_string(l), std::to_string(u)}};
}
bool ValidateService(const std::string &id, std::string *e) {
  if (services.count(id))
    return true;
  *e = "unsupported service id";
  return false;
}
Command ServiceCommand(const std::string &id, bool on) {
  Command command{{on ? "enable" : "disable", "--now"}};
  const auto &units = services.at(id);
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
GraphicsExit ClassifyGraphicsExit(int exit_status) {
  if (exit_status == 0)
    return GraphicsExit::kSuccess;
  if (exit_status == 2)
    return GraphicsExit::kBlocked;
  if (exit_status == 3)
    return GraphicsExit::kPending;
  return GraphicsExit::kFailed;
}
} // namespace legion_control
