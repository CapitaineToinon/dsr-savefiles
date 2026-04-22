#include "dearxan/include/dearxan.h"
#include <debugapi.h>
#include <libloaderapi.h>
#include <memoryapi.h>
#include <minwindef.h>
#include <stdint.h>
#include <stdio.h>
#include <windows.h>
#include <winnt.h>

#define DEBUG(fmt, ...)                                                        \
  do {                                                                         \
    FILE *_debug_f = fopen("C:\\capitaine.log", "a");                          \
    if (_debug_f) {                                                            \
      fprintf(_debug_f, "[CAPITAINE] " fmt "", ##__VA_ARGS__);                 \
      fclose(_debug_f);                                                        \
    }                                                                          \
  } while (0)

static WINBOOL(WINAPI *OrigReadFile)(HANDLE, LPVOID, DWORD, LPDWORD,
                                     LPOVERLAPPED);
static void **hookPtr;

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
  OrigReadFile = *(WINBOOL(WINAPI **)(HANDLE, LPVOID, DWORD, LPDWORD,
                                      LPOVERLAPPED))(callSite + 6 + origOffset);

  void **nearPtr = NULL;
  for (uintptr_t addr = (uintptr_t)callSite - 0x40000000;
       addr < (uintptr_t)callSite; addr += 0x10000) {
    nearPtr = VirtualAlloc((void *)addr, sizeof(void *),
                           MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (nearPtr)
      break;
  }

  if (!nearPtr) {
    DEBUG("failed to allocate near memory\n");
    return;
  }

  *nearPtr = detour_ReadFile;
  hookPtr = nearPtr;

  int64_t diff = (int64_t)nearPtr - (int64_t)(callSite + 6);
  DEBUG("diff: %lld\n", diff);

  if (diff < INT32_MIN || diff > INT32_MAX) {
    DEBUG("nearPtr still out of 32-bit range\n");
    return;
  }

  int32_t newOffset = (int32_t)diff;
  DWORD old;
  VirtualProtect(callSite + 2, 4, PAGE_EXECUTE_READWRITE, &old);
  memcpy(callSite + 2, &newOffset, 4);
  VirtualProtect(callSite + 2, 4, old, &old);

  DEBUG("attach_hook done\n");
}

/**
 * Patching method from
 * https://github.com/CapitaineToinon/DarkSoulsOfflineLogoSkip/blob/master/introoffline.c
 */

typedef HRESULT(WINAPI *dinp8crt_t)(HINSTANCE, DWORD, REFIID, LPVOID *,
                                    LPUNKNOWN);
dinp8crt_t oDirectInput8Create;

__attribute__((dllexport)) HRESULT WINAPI DirectInput8Create(
    HINSTANCE inst, DWORD ver, REFIID id, LPVOID *pout, LPUNKNOWN outer) {
  return oDirectInput8Create(inst, ver, id, pout, outer);
}

void setup_d8proxy(void) {
  char syspath[320];
  GetSystemDirectoryA(syspath, 320);
  strcat(syspath, "\\dinput8.dll");
  HMODULE mod = LoadLibraryA(syspath);
  oDirectInput8Create = (dinp8crt_t)GetProcAddress(mod, "DirectInput8Create");
}

void callback(const DearxanResult *result, void *opaque) {
  if (result->status == DearxanSuccess) {
    DEBUG("Arxan disabled!\n");
  } else {
    DEBUG("%.*s\nFailed to disable Arxan!\n", (int)result->error_msg_size,
          result->error_msg);
  }
}

BOOL APIENTRY DllMain(HMODULE mod, DWORD reason, LPVOID reserved) {
  switch (reason) {
  case DLL_PROCESS_ATTACH:
    DEBUG("--------- DllMain attach ---------\n");
    dearxan_neuter_arxan(callback, NULL);
    setup_d8proxy();
    attach_hook(mod);
    break;
  }

  return TRUE;
}
