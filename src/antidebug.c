#include "antidebug.h"
#include "../dearxan/include/dearxan.h"
#include "log.h"

/**
 * Callback once Arxan is done patching, either successfully or not
 */
void callback(const DearxanResult *result, void *opaque) {
  if (result->status == DearxanSuccess) {
    DEBUG("Arxan disabled!\n");
  } else {
    DEBUG("%.*s\nFailed to disable Arxan!\n", (int)result->error_msg_size,
          result->error_msg);
  }
}

/**
 * Setup dearxan, an anti anti debug for DSR
 */
void setup_antidebug() { dearxan_neuter_arxan(callback, NULL); }
