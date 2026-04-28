/*
 * Minimal Lua bindings for libbzip2.
 *
 * Exposes a one-shot compress / decompress API:
 *
 *   local bzip2 = require("bzip2")
 *   local compressed   = bzip2.compress(plain, 9)   -- level 1..9
 *   local decompressed = bzip2.decompress(compressed)
 *
 * This is intentionally simpler than lua-zlib's streaming interface: the
 * `tar` applet already stages its archive contents in a Lua string, so a
 * one-shot API is sufficient. If a streaming interface is needed in the
 * future, the bzip2 BZ_RUN / BZ_FINISH state machine can be exposed
 * here as a closure-based API mirroring lua-zlib.
 *
 * SPDX-License-Identifier: BSD-2-Clause-like (see LICENSE in this dir).
 */

#include <stdlib.h>
#include <string.h>

#include "bzlib.h"

#include "lua.h"
#include "lauxlib.h"

#if LUA_VERSION_NUM < 502
/* luaL_setfuncs is 5.2+; fake it for 5.1 by registering directly. */
#define luaL_setfuncs(L, R, NUP) luaL_register(L, NULL, R)
#endif

#define BZ_GROW_CHUNK (64 * 1024)

static int lbz_compress(lua_State *L) {
    size_t in_len;
    const char *in = luaL_checklstring(L, 1, &in_len);
    int level = (int)luaL_optinteger(L, 2, 9);
    if (level < 1) level = 1;
    if (level > 9) level = 9;

    bz_stream bz;
    memset(&bz, 0, sizeof(bz));
    int rc = BZ2_bzCompressInit(&bz, level, 0, 0);
    if (rc != BZ_OK) {
        return luaL_error(L, "BZ2_bzCompressInit failed: %d", rc);
    }

    size_t cap = (in_len + BZ_GROW_CHUNK > BZ_GROW_CHUNK)
                 ? in_len + BZ_GROW_CHUNK
                 : BZ_GROW_CHUNK;
    char *out = (char *)malloc(cap);
    if (!out) {
        BZ2_bzCompressEnd(&bz);
        return luaL_error(L, "out of memory");
    }

    bz.next_in = (char *)in;
    bz.avail_in = (unsigned int)in_len;
    bz.next_out = out;
    bz.avail_out = (unsigned int)cap;

    /* Single BZ_FINISH pass; loop while we still have output buffer. */
    while (1) {
        rc = BZ2_bzCompress(&bz, BZ_FINISH);
        if (rc == BZ_STREAM_END) break;
        if (rc != BZ_FINISH_OK) {
            free(out);
            BZ2_bzCompressEnd(&bz);
            return luaL_error(L, "BZ2_bzCompress failed: %d", rc);
        }
        /* Need more output space. */
        size_t produced = cap - bz.avail_out;
        size_t new_cap = cap * 2;
        char *new_out = (char *)realloc(out, new_cap);
        if (!new_out) {
            free(out);
            BZ2_bzCompressEnd(&bz);
            return luaL_error(L, "out of memory");
        }
        out = new_out;
        bz.next_out = out + produced;
        bz.avail_out = (unsigned int)(new_cap - produced);
        cap = new_cap;
    }

    size_t produced = cap - bz.avail_out;
    BZ2_bzCompressEnd(&bz);
    lua_pushlstring(L, out, produced);
    free(out);
    return 1;
}

static int lbz_decompress(lua_State *L) {
    size_t in_len;
    const char *in = luaL_checklstring(L, 1, &in_len);

    bz_stream bz;
    memset(&bz, 0, sizeof(bz));
    int rc = BZ2_bzDecompressInit(&bz, 0, 0);
    if (rc != BZ_OK) {
        return luaL_error(L, "BZ2_bzDecompressInit failed: %d", rc);
    }

    size_t cap = (in_len * 4 > BZ_GROW_CHUNK) ? in_len * 4 : BZ_GROW_CHUNK;
    char *out = (char *)malloc(cap);
    if (!out) {
        BZ2_bzDecompressEnd(&bz);
        return luaL_error(L, "out of memory");
    }

    bz.next_in = (char *)in;
    bz.avail_in = (unsigned int)in_len;
    bz.next_out = out;
    bz.avail_out = (unsigned int)cap;

    while (1) {
        rc = BZ2_bzDecompress(&bz);
        if (rc == BZ_STREAM_END) break;
        if (rc != BZ_OK) {
            free(out);
            BZ2_bzDecompressEnd(&bz);
            lua_pushnil(L);
            lua_pushfstring(L, "BZ2_bzDecompress failed: %d", rc);
            return 2;
        }
        if (bz.avail_out == 0) {
            size_t produced = cap;
            size_t new_cap = cap * 2;
            char *new_out = (char *)realloc(out, new_cap);
            if (!new_out) {
                free(out);
                BZ2_bzDecompressEnd(&bz);
                return luaL_error(L, "out of memory");
            }
            out = new_out;
            bz.next_out = out + produced;
            bz.avail_out = (unsigned int)(new_cap - produced);
            cap = new_cap;
        }
    }

    size_t produced = cap - bz.avail_out;
    BZ2_bzDecompressEnd(&bz);
    lua_pushlstring(L, out, produced);
    free(out);
    return 1;
}

static const luaL_Reg bzip2_funcs[] = {
    {"compress",   lbz_compress},
    {"decompress", lbz_decompress},
    {NULL, NULL}
};

int luaopen_bzip2(lua_State *L) {
    lua_newtable(L);
    luaL_setfuncs(L, bzip2_funcs, 0);
    lua_pushliteral(L, "1.0.8");
    lua_setfield(L, -2, "_VERSION");
    return 1;
}
