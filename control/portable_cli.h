#pragma once

#include "managed_command.h"

namespace legion_control {
// Checks the command syntax advertised by --help, without hardware operations.
// Hardware support and CLI package provenance require separate qualification.
bool ValidatePortableCliHelp(const std::string &help, std::string *error);

// Runs --help in the same contained backend environment used for writes.
// App or launcher death cancels the operation and waits for backend cleanup.
bool QualifyPortableCli(std::shared_ptr<ManagedCommandRunner> runner,
                        const std::string &cli, int app, int launcher,
                        GError **error);
} // namespace legion_control
