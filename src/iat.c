#include "iat.h"
#include "log.h"
#include <stdint.h>
#include <string.h>
#include <windows.h>
#include <winnt.h>

void *iat_patch(void *call_site, void *detour) {
  BYTE *site = (BYTE *)call_site;

  if (site[0] != 0xFF || site[1] != 0x15) {
    DEBUG("iat_patch: unexpected instruction at %p (%02X %02X)\n", call_site,
          site[0], site[1]);
    exit(-1);
  }

  int32_t offset;
  memcpy(&offset, site + 2, 4);
  void **slot = (void **)(site + 6 + offset);
  void *orig = *slot;

  DWORD old;
  VirtualProtect(slot, sizeof(void *), PAGE_READWRITE, &old);
  *slot = detour;
  VirtualProtect(slot, sizeof(void *), old, &old);

  return orig;
}
