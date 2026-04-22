#include "dinput8.h"
#include <windows.h>

typedef HRESULT(WINAPI *dinp8crt_t)(HINSTANCE, DWORD, REFIID, LPVOID *,
                                    LPUNKNOWN);

// Pointer to the original input 8 we are proxying
static dinp8crt_t OrigDirectInput8Create;

/**
 * Simple DirectInput8Create proxy. We don't do anything in there
 * but we need this otherwise the real dinput8 never loads and the
 * game crashes.
 */
__attribute__((dllexport)) HRESULT WINAPI DirectInput8Create(
    HINSTANCE inst, DWORD ver, REFIID id, LPVOID *pout, LPUNKNOWN outer) {
  return OrigDirectInput8Create(inst, ver, id, pout, outer);
}

/**
 * Before the entry point, get the pointer to the real
 * dinput8 create function, so that whenever the game
 * calls our code, we can proxy to real dinput later.
 */
void setup_d8proxy(void) {
  char syspath[320];
  GetSystemDirectoryA(syspath, 320);
  strcat(syspath, "\\dinput8.dll");
  HMODULE mod = LoadLibraryA(syspath);
  OrigDirectInput8Create =
      (dinp8crt_t)GetProcAddress(mod, "DirectInput8Create");
}
