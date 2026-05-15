#include "../dearxan/include/dearxan.h"
#include "antidebug.h"
#include "dinput8.h"
#include "iat.h"
#include "log.h"
#include <debugapi.h>
#include <memoryapi.h>
#include <minwindef.h>
#include <stdint.h>
#include <windef.h>
#include <windows.h>
#include <winnt.h>

bool key_read = false;

static WINBOOL(WINAPI *OrigReadFile)(HANDLE, LPVOID, DWORD, LPDWORD,
                                     LPOVERLAPPED);

static WINBOOL(WINAPI *OrigWriteFile)(HANDLE hFile, LPCVOID lpBuffer,
                                      DWORD nNumberOfBytesToWrite,
                                      LPDWORD lpNumberOfBytesWritten,
                                      LPOVERLAPPED lpOverlapped);

// Polls until the SaveLoad2 config struct is allocated, then zeros the
// encryption flag at config+0xa0. Both FUN_1410da100 (read) and FUN_1410da3f0
// (write) skip AES when that flag is 0. We modify heap data only — no .text
// patching — so code integrity checks don't fire.
static DWORD WINAPI disable_encryption_thread(LPVOID param) {
  uintptr_t base = (uintptr_t)GetModuleHandleA(NULL);
  uintptr_t *config_ptr = (uintptr_t *)(base + 0x1d053c0);

  for (;;) {
    Sleep(10);
    if (!*config_ptr)
      continue;
    uint8_t *flag = (uint8_t *)(*config_ptr + 0xa0);
    if (*flag) {
      *flag = 0;
      DEBUG("SL2 encryption flag cleared\n");
    }
  }
  return 0;
}

static void disable_sl2_encryption(void) {
  HANDLE t = CreateThread(NULL, 0, disable_encryption_thread, NULL, 0, NULL);
  if (t)
    CloseHandle(t);
  DEBUG("SL2 encryption disabler thread started\n");
}

void read_key() {
  if (key_read) {
    return;
  }

  uintptr_t base = (uintptr_t)GetModuleHandleA(NULL);
  uintptr_t *config_ptr = (uintptr_t *)(base + 0x1d053c0);
  if (*config_ptr) {
    BYTE *key = (BYTE *)(*config_ptr + 0x90);
    DEBUG("AES key: %02X%02X%02X%02X %02X%02X%02X%02X %02X%02X%02X%02X "
          "%02X%02X%02X%02X\n",
          key[0], key[1], key[2], key[3], key[4], key[5], key[6], key[7],
          key[8], key[9], key[10], key[11], key[12], key[13], key[14], key[15]);
  }
}

static void log_callstack(void) {
  void *stack[32];
  USHORT frames = RtlCaptureStackBackTrace(0, 32, stack, NULL);
  uintptr_t base = (uintptr_t)GetModuleHandleA(NULL);

  for (USHORT i = 0; i < frames; i++) {
    uintptr_t addr = (uintptr_t)stack[i];
    if (addr >= base)
      DEBUG("  [%2d] +0x%llx\n", i, addr);
    else
      DEBUG("  [%2d] %p (outside DSR)\n", i, stack[i]);
  }
}

DWORD is_sl2(HANDLE hFile) {

  char path[MAX_PATH];
  return GetFinalPathNameByHandleA(hFile, path, MAX_PATH,
                                   FILE_NAME_NORMALIZED) &&
         strstr(path, ".sl2");
}

static WINBOOL WINAPI detour_ReadFile(HANDLE hFile, LPVOID lpBuffer,
                                      DWORD nNumberOfBytesToRead,
                                      LPDWORD lpNumberOfBytesRead,
                                      LPOVERLAPPED lpOverlapped) {

  read_key();

  WINBOOL result = OrigReadFile(hFile, lpBuffer, nNumberOfBytesToRead,
                                lpNumberOfBytesRead, lpOverlapped);
  if (is_sl2(hFile)) {
    BYTE *buf = (BYTE *)lpBuffer;
    DEBUG("sl2 read %lu bytes: %02X %02X %02X %02X %02X %02X %02X %02X\n",
          *lpNumberOfBytesRead, buf[0], buf[1], buf[2], buf[3], buf[4], buf[5],
          buf[6], buf[7]);
    log_callstack();
  }

  return result;
}

static WINBOOL WINAPI detour_WriteFile(HANDLE hFile, LPCVOID lpBuffer,
                                       DWORD nNumberOfBytesToWrite,
                                       LPDWORD lpNumberOfBytesWritten,
                                       LPOVERLAPPED lpOverlapped) {

  WINBOOL result = OrigWriteFile(hFile, lpBuffer, nNumberOfBytesToWrite,
                                 lpNumberOfBytesWritten, lpOverlapped);
  if (is_sl2(hFile)) {
    BYTE *buf = (BYTE *)lpBuffer;
    DEBUG("sl2 written %lu bytes: %02X %02X %02X %02X %02X %02X %02X %02X\n",
          *lpNumberOfBytesWritten, buf[0], buf[1], buf[2], buf[3], buf[4],
          buf[5], buf[6], buf[7]);
    log_callstack();
  }

  return result;
}

static void attach_hooks(void) {
  OrigReadFile = iat_patch((void *)0x140d08781, detour_ReadFile);
  // OrigWriteFile = iat_patch((void *)0x1409a1b46, detour_WriteFile);
  disable_sl2_encryption();
}

BOOL APIENTRY DllMain(HMODULE mod, DWORD reason, LPVOID reserved) {
  switch (reason) {
  case DLL_PROCESS_ATTACH:
    DEBUG("--------- DllMain attach ---------\n");
    // setup_antidebug();
    setup_d8proxy();
    attach_hooks();
    break;
  }

  return TRUE;
}
