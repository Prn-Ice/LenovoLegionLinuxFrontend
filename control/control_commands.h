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

bool ValidateFeature(const std::string &, const std::string &, std::string *);
bool ValidateToggle(const std::string &, bool, std::string *);
bool ValidatePreset(const std::string &, std::string *);
bool ValidateConservation(uint32_t, uint32_t, std::string *);
bool ValidateBytes(const std::vector<uint8_t> &, std::size_t, std::string *);
Command FeatureCommand(const std::string &, const std::string &);
Command ToggleCommand(const std::string &, bool);
Command PresetCommand(const std::string &);
Command CurrentPresetCommand();
Command FileCommand(const std::string &);
Command BootLogoCommand(const std::string &);
Command RestoreBootLogoCommand();
Command ConservationCommand(uint32_t, uint32_t);
bool ValidateService(const std::string &, std::string *);
Command ServiceCommand(const std::string &, bool);
bool ValidateGraphicsMode(const std::string &, std::string *);
Command GraphicsModeCommand(const std::string &);
GraphicsExit ClassifyGraphicsExit(int);
} // namespace legion_control
#endif
