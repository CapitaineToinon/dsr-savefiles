#include "log.h"
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>

#define LOG_FILE "C:\\capitaine.log"
#define MAX_LINES 20000

bool has_reset = false;

/**
 * Shamelessly written by claude
 */
void debug_write(const char *fmt, ...) {
  if (!has_reset) {
    FILE *f = fopen(LOG_FILE, "w");
    if (f)
      fclose(f);
    has_reset = true;
  }

  FILE *f = fopen(LOG_FILE, "a");
  if (f) {
    va_list args;
    va_start(args, fmt);
    vfprintf(f, fmt, args);
    va_end(args);
    fclose(f);
  }
}
