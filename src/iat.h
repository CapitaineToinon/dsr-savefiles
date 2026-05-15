#pragma once
#include <windows.h>

// Patches the IAT slot read by the FF 15 call at `call_site`, replacing the
// function pointer with `detour`. Returns the original function pointer.
void *iat_patch(void *call_site, void *detour);

// Patches a vtable slot at `vtable_addr[slot]`, replacing the function pointer
// with `detour`. Returns the original function pointer.
void *vtable_patch(void *vtable_addr, int slot, void *detour);
