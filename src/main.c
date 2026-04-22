#include "antidebug.h"
#include "dinput8.h"
#include "log.h"
#include <debugapi.h>
#include <memoryapi.h>
#include <minwindef.h>
#include <stdint.h>
#include <windows.h>
#include <winnt.h>

static WINBOOL(WINAPI *OrigReadFile)(HANDLE, LPVOID, DWORD, LPDWORD,
                                     LPOVERLAPPED);

static void log_callstack(void) {
  void *stack[32];
  USHORT frames = RtlCaptureStackBackTrace(0, 32, stack, NULL);
  uintptr_t base = (uintptr_t)GetModuleHandleA(NULL);

  for (USHORT i = 0; i < frames; i++) {
    uintptr_t addr = (uintptr_t)stack[i];
    if (addr >= base)
      DEBUG("  [%2d] +0x%llx\n", i, addr - base);
    else
      DEBUG("  [%2d] %p (outside DSR)\n", i, stack[i]);
  }
}

WINBOOL detour_ReadFile(HANDLE hFile, LPVOID lpBuffer,
                        DWORD nNumberOfBytesToRead, LPDWORD lpNumberOfBytesRead,
                        LPOVERLAPPED lpOverlapped) {
  char path[MAX_PATH];

  if (GetFinalPathNameByHandleA(hFile, path, MAX_PATH, FILE_NAME_NORMALIZED) &&
      strstr(path, ".sl2")) {
    DEBUG("ReadFile on save file: %s\n", path);
    log_callstack();
  }

  return OrigReadFile(hFile, lpBuffer, nNumberOfBytesToRead,
                      lpNumberOfBytesRead, lpOverlapped);
}

void attach_hook(HMODULE mod) {
  DEBUG("attach_hook start\n");

  BYTE *callSite = (BYTE *)0x140d08781;

  int32_t origOffset;
  memcpy(&origOffset, callSite + 2, 4);
  void **iatSlot = (void **)(callSite + 6 + origOffset);
  OrigReadFile =
      (WINBOOL(WINAPI *)(HANDLE, LPVOID, DWORD, LPDWORD, LPOVERLAPPED)) *
      iatSlot;

  DWORD old;
  VirtualProtect(iatSlot, sizeof(void *), PAGE_READWRITE, &old);
  *iatSlot = detour_ReadFile;
  VirtualProtect(iatSlot, sizeof(void *), old, &old);

  DEBUG("attach_hook done\n");
}

BOOL APIENTRY DllMain(HMODULE mod, DWORD reason, LPVOID reserved) {
  switch (reason) {
  case DLL_PROCESS_ATTACH:
    DEBUG("--------- DllMain attach ---------\n");
    setup_antidebug();
    setup_d8proxy();
    attach_hook(mod);
    break;
  }

  return TRUE;
}
