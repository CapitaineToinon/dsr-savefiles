#include "log.h"
#include <stdarg.h>
#include <stdio.h>

#define LOG_FILE "C:\\capitaine.log"
#define MAX_LINES 20000

/**
 * Shamelessly written by claude
 */
void debug_write(const char *fmt, ...) {
  static int line_count = -1;

  if (line_count < 0) {
    FILE *f = fopen(LOG_FILE, "r");
    line_count = 0;
    if (f) {
      int c;
      while ((c = fgetc(f)) != EOF)
        if (c == '\n')
          line_count++;
      fclose(f);
    }
  }

  if (line_count >= MAX_LINES) {
    FILE *f = fopen(LOG_FILE, "w");
    if (f)
      fclose(f);
    line_count = 0;
  }

  FILE *f = fopen(LOG_FILE, "a");
  if (f) {
    va_list args;
    va_start(args, fmt);
    vfprintf(f, fmt, args);
    va_end(args);
    fclose(f);
    line_count++;
  }
}
