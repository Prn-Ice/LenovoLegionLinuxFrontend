#ifndef LEGION_CONTROL_COMMANDS_H_
#define LEGION_CONTROL_COMMANDS_H_

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace legion_control {
struct Command {
  std::vector<std::string> argv;
};

enum class GraphicsExit { kSuccess, kBlocked, kPending, kFailed };
enum class CliExit { kSuccess, kFailed, kUnavailable, kFeatureNotFound };

bool ValidateFeature(const std::string &feature, const std::string &value,
                     std::string *error);
bool ValidateToggle(const std::string &capability, bool enabled,
                    std::string *error);
bool ValidatePreset(const std::string &preset, std::string *error);
bool ValidateConservation(uint32_t lower, uint32_t upper, std::string *error);
bool ValidateBytes(const std::vector<uint8_t> &bytes, std::size_t maximum_size,
                   std::string *error);
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
CliExit ClassifyCliExit(int);
bool ValidateBootGraphicsMode(const std::string &mode, std::string *error);
Command BootGraphicsRequestCommand(const std::string &mode);
} // namespace legion_control
#endif
