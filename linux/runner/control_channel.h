#pragma once

#include <flutter_linux/flutter_linux.h>

// Owns the private control connection for this Flutter view's lifetime.
void RegisterControlChannel(FlView *view);
