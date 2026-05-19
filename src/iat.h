#pragma once
#include <windows.h>

// Patches the IAT slot read by the FF 15 call at `call_site`, replacing the
// function pointer with `detour`. Returns the original function pointer.
void *iat_patch(void *call_site, void *detour);
