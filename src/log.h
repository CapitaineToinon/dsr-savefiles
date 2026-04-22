#pragma once

void debug_write(const char *fmt, ...);

#define DEBUG(fmt, ...) debug_write("[CAPITAINE] " fmt, ##__VA_ARGS__)
