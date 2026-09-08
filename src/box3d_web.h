// What the shim takes from hl.h, for the same file compiled by Emscripten.
// Primitives are plain C functions, exported by EMSCRIPTEN_KEEPALIVE as _box3d_<name>.
// DEFINE_PRIM is HashLink registration and means nothing here. The web has one
// thread, so the log lock is a word that is never contended.
#include <stdint.h>
#include <stdbool.h>
#include <emscripten.h>

typedef unsigned char vbyte;

#define HL_PRIM EMSCRIPTEN_KEEPALIVE
#define DEFINE_PRIM(...)
#define _NO_ARG

typedef int hl_mutex;
static inline hl_mutex *hl_mutex_alloc(bool global) { static hl_mutex lock; (void)global; return &lock; }
static inline void hl_mutex_acquire(hl_mutex *lock) { (void)lock; }
static inline void hl_mutex_release(hl_mutex *lock) { (void)lock; }
static inline void hl_add_root(void *root) { (void)root; }
