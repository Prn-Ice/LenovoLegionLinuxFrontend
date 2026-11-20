#ifndef LEGION_CONTROL_COMMANDS_H_
#define LEGION_CONTROL_COMMANDS_H_

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace legion_control {
// A command line for legion_cli, systemctl, or the next-boot graphics helper.
struct Command {
  std::vector<std::string> argv;
};

// Exit-code groups used to turn a backend failure into a useful D-Bus error.
enum class GraphicsExit { kSuccess, kBlocked, kPending, kFailed };
enum class CliExit { kSuccess, kFailed, kUnavailable, kFeatureNotFound };

// Validation functions return false and set error when a request is outside
// the allow-list in control_commands.cc.
bool ValidateFeature(const std::string &feature, const std::string &value,
                     std::string *error);
bool ValidateToggle(const std::string &capability, std::string *error);
bool ValidatePreset(const std::string &preset, std::string *error);
bool ValidateConservation(uint32_t lower, uint32_t upper, std::string *error);

// Command builders. Call the matching validator first.
Command FeatureCommand(const std::string &feature, const std::string &value);
Command ToggleCommand(const std::string &capability, bool enabled);
Command PresetCommand(const std::string &preset);
Command CurrentPresetCommand();
std::vector<std::string> InteractiveCliCommands();
Command FileCommand(const std::string &path);
Command BootLogoCommand(const std::string &path);
Command RestoreBootLogoCommand();
Command ConservationCommand(uint32_t lower, uint32_t upper);
bool ValidateService(const std::string &service_id, std::string *error);
Command ServiceCommand(const std::string &service_id, bool enabled);
bool ValidateGraphicsMode(const std::string &mode, std::string *error);
Command GraphicsModeCommand(const std::string &mode);
GraphicsExit ClassifyGraphicsExit(int exit_status);
CliExit ClassifyCliExit(int exit_status);
bool ValidateBootGraphicsMode(const std::string &mode, std::string *error);
Command BootGraphicsRequestCommand(const std::string &mode);
}  // namespace legion_control
#endif
