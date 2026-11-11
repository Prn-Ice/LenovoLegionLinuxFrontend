#pragma once

// Synthetic argparse output for the command syntax the frontend requires.
constexpr char cli_help_fixture[] = R"help(usage: legion_cli [--donotexpecthwmon] [--loglevel {DEBUG,INFO}]
{set-feature,graphics-mode,boot-logo,fancurve-write-preset-to-hw,fancurve-write-current-preset-to-hw,fancurve-write-file-to-hw,custom-conservation-mode-apply,hybrid-mode-enable,hybrid-mode-disable,batteryconservation-enable,batteryconservation-disable,rapid-charging-enable,rapid-charging-disable,always-on-usb-charging-enable,always-on-usb-charging-disable,touchpad-enable,touchpad-disable,fnlock-enable,fnlock-disable,minifancurve-enable,minifancurve-disable,lockfancontroller-enable,lockfancontroller-disable,maximumfanspeed-enable,maximumfanspeed-disable}
)help";
