#include "control_commands.h"
#include <array>
#include <glib.h>
#include <tuple>
#include <utility>

using namespace legion_control;

static void test_profiles() {
  const std::array<const char *, 8> values = {
      "quiet",    "low-power",   "power-saver",
      "balanced", "performance", "balanced-performance",
      "custom",   "max-power"};
  for (const char *value : values) {
    std::string error;
    g_assert_true(ValidateFeature("PlatformProfileFeature", value, &error));
  }
  std::string error;
  g_assert_false(ValidateFeature("PlatformProfileFeature", "invalid", &error));
}

static void test_features() {
  const std::array<const char *, 6> booleans = {
      "OverdriveFeature", "WinkeyFeature", "CPUOverclock",
      "GPUOverclock",     "YLogoLight",    "IOPortLight"};
  for (const char *feature : booleans) {
    std::string error;
    g_assert_true(ValidateFeature(feature, "0", &error));
    g_assert_true(ValidateFeature(feature, "1", &error));
    g_assert_false(ValidateFeature(feature, "2", &error));
  }
  const std::array<std::tuple<const char *, int, int>, 10> integers = {
      {{"CPULongtermPowerLimit", 5, 200},
       {"CPUShorttermPowerLimit", 5, 200},
       {"CPUPeakPowerLimit", 1, 200},
       {"CPUCrossLoadingPowerLimit", 1, 100},
       {"CPUAPUSPPTPowerLimit", 1, 100},
       {"CPUDefaultPowerLimit", 1, 100},
       {"GPUCTGPPowerLimit", 1, 200},
       {"GPUPPABPowerLimit", 1, 200},
       {"GPUBoostClock", 1, 10000},
       {"GPUTemperatureLimit", 1, 120}}};
  for (const auto &feature : integers) {
    std::string error;
    g_assert_true(ValidateFeature(
        std::get<0>(feature), std::to_string(std::get<1>(feature)), &error));
    g_assert_true(ValidateFeature(
        std::get<0>(feature), std::to_string(std::get<2>(feature)), &error));
    g_assert_false(ValidateFeature(std::get<0>(feature),
                                   std::to_string(std::get<1>(feature) - 1),
                                   &error));
    g_assert_false(ValidateFeature(std::get<0>(feature),
                                   std::to_string(std::get<2>(feature) + 1),
                                   &error));
    g_assert_false(ValidateFeature(std::get<0>(feature), "01", &error));
  }
}

static void test_toggles_and_presets() {
  const std::array<std::pair<const char *, const char *>, 9> toggles = {
      {{"hybrid-mode", "hybrid-mode"},
       {"battery-conservation", "batteryconservation"},
       {"rapid-charging", "rapid-charging"},
       {"always-on-usb-charging", "always-on-usb-charging"},
       {"touchpad", "touchpad"},
       {"fn-lock", "fnlock"},
       {"mini-fan-curve", "minifancurve"},
       {"lock-fan-controller", "lockfancontroller"},
       {"maximum-fan-speed", "maximumfanspeed"}}};
  for (const auto &toggle : toggles) {
    std::string error;
    g_assert_true(ValidateToggle(toggle.first, true, &error));
    g_assert_true(ValidateToggle(toggle.first, false, &error));
    const auto on = ToggleCommand(toggle.first, true);
    const auto off = ToggleCommand(toggle.first, false);
    const std::string expected_on = std::string(toggle.second) + "-enable";
    const std::string expected_off = std::string(toggle.second) + "-disable";
    g_assert_cmpstr(on.argv.back().c_str(), ==, expected_on.c_str());
    g_assert_cmpstr(off.argv.back().c_str(), ==, expected_off.c_str());
    const std::string id = toggle.first;
    const bool requires_hwmon = id == "mini-fan-curve" ||
                                id == "lock-fan-controller" ||
                                id == "maximum-fan-speed";
    g_assert_cmpint(on.argv.size(), ==, requires_hwmon ? 1 : 2);
    if (!requires_hwmon)
      g_assert_cmpstr(on.argv[0].c_str(), ==, "--donotexpecthwmon");
  }
  const std::array<const char *, 8> presets = {"quiet-battery",
                                               "balanced-battery",
                                               "performance-battery",
                                               "balanced-performance-battery",
                                               "quiet-ac",
                                               "balanced-ac",
                                               "performance-ac",
                                               "balanced-performance-ac"};
  for (const char *preset : presets) {
    std::string error;
    g_assert_true(ValidatePreset(preset, &error));
  }
}

static void test_conservation_and_payloads() {
  std::string error;
  g_assert_true(ValidateConservation(0, 0, &error));
  g_assert_true(ValidateConservation(0, 100, &error));
  g_assert_true(ValidateConservation(100, 100, &error));
  g_assert_false(ValidateConservation(101, 100, &error));
  g_assert_false(ValidateConservation(0, 101, &error));
  g_assert_false(ValidateConservation(80, 70, &error));
  g_assert_false(ValidateBytes({}, 64 * 1024, &error));
  g_assert_cmpstr(error.c_str(), ==, "payload must not be empty");
  std::vector<uint8_t> bytes(64 * 1024);
  g_assert_true(ValidateBytes(bytes, 64 * 1024, &error));
  bytes.push_back(0);
  g_assert_false(ValidateBytes(bytes, 64 * 1024, &error));
  g_assert_cmpstr(error.c_str(), ==, "payload exceeds maximum size");
}

static void test_commands() {
  const auto feature = FeatureCommand("x", "1");
  g_assert_cmpint(feature.argv.size(), ==, 4);
  g_assert_cmpstr(feature.argv[0].c_str(), ==, "--donotexpecthwmon");
  const auto on = ToggleCommand("hybrid-mode", true);
  const auto off = ToggleCommand("hybrid-mode", false);
  g_assert_cmpstr(on.argv[1].c_str(), ==, "hybrid-mode-enable");
  g_assert_cmpstr(off.argv[1].c_str(), ==, "hybrid-mode-disable");
  const auto preset = PresetCommand("quiet-ac");
  const auto current = CurrentPresetCommand();
  const auto file = FileCommand("/tmp/x");
  const auto logo = BootLogoCommand("/tmp/x");
  const auto restore = RestoreBootLogoCommand();
  const auto conservation = ConservationCommand(20, 80);
  g_assert_cmpstr(preset.argv[1].c_str(), ==, "quiet-ac");
  g_assert_cmpstr(current.argv[0].c_str(), ==,
                  "fancurve-write-current-preset-to-hw");
  g_assert_cmpstr(file.argv[1].c_str(), ==, "/tmp/x");
  g_assert_cmpstr(logo.argv[1].c_str(), ==, "boot-logo");
  g_assert_cmpstr(restore.argv[2].c_str(), ==, "restore");
  g_assert_cmpstr(conservation.argv[3].c_str(), ==, "80");
}

static void test_services() {
  std::string error;
  g_assert_true(ValidateService("power_profiles_daemon", &error));
  g_assert_true(ValidateService("legiond_stack", &error));
  g_assert_false(ValidateService("unknown", &error));
  for (bool enabled : {false, true}) {
    const auto command = ServiceCommand("legiond_stack", enabled).argv;
    const std::vector<std::string> expected = {enabled ? "enable" : "disable",
                                               "--now",
                                               "legiond.service",
                                               "legiond-onresume.service",
                                               "legiond-cpuset.service",
                                               "legiond-cpuset.timer"};
    g_assert_cmpint(command.size(), ==, expected.size());
    g_assert_true(command == expected);
  }
}

static void test_graphics_modes() {
  const std::array<const char *, 3> allowed = {
      "hybrid", "hybrid-igpu-only", "discrete"};
  for (const char *mode : allowed) {
    std::string error;
    g_assert_true(ValidateGraphicsMode(mode, &error));
    const auto command = GraphicsModeCommand(mode).argv;
    const std::vector<std::string> expected = {
        "--donotexpecthwmon", "graphics-mode", "set", mode, "--json"};
    g_assert_true(command == expected);
  }

  for (const char *mode : {"", "hybrid-auto", "integrated", "HYBRID"}) {
    std::string error;
    g_assert_false(ValidateGraphicsMode(mode, &error));
    g_assert_cmpstr(error.c_str(), ==, "unsupported graphics mode");
  }

  g_assert_true(ClassifyGraphicsExit(0) == GraphicsExit::kSuccess);
  g_assert_true(ClassifyGraphicsExit(2) == GraphicsExit::kBlocked);
  g_assert_true(ClassifyGraphicsExit(3) == GraphicsExit::kPending);
  g_assert_true(ClassifyGraphicsExit(1) == GraphicsExit::kFailed);
}

int main(int argc, char **argv) {
  g_test_init(&argc, &argv, nullptr);
  g_test_add_func("/control/profiles", test_profiles);
  g_test_add_func("/control/features", test_features);
  g_test_add_func("/control/toggles-and-presets", test_toggles_and_presets);
  g_test_add_func("/control/conservation-and-payloads",
                  test_conservation_and_payloads);
  g_test_add_func("/control/commands", test_commands);
  g_test_add_func("/control/services", test_services);
  g_test_add_func("/control/graphics-modes", test_graphics_modes);
  return g_test_run();
}
