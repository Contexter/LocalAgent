#pragma once

// This shim header exposes the llama.cpp C API header to Swift via a
// system module. Ensure that the include path for llama.h is visible to the
// compiler (e.g. via Homebrew-installed llama.cpp or custom header path).

#include <llama.h>

