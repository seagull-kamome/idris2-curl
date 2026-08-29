#ifndef IDRIS2CURL_COMPAT_H
#define IDRIS2CURL_COMPAT_H

/* rc2/RefC's own %foreign lowering treats a foreign function name as
 * a bare C identifier, never a C expression -- see
 * idris2-rc-cg/TODO.md's own "CFString's hardcoded char * return
 * type" entry. Every libcurl function returning `const char *` needs
 * a same-signature `static inline` shim here (never a real function,
 * to keep the cast free of any call overhead) that discards the
 * qualifier explicitly, instead of tripping -Werror's own
 * -Wdiscarded-qualifiers on a direct %foreign binding. */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <curl/curl.h>
#include <curl/header.h>

static inline char *idris2curl_easy_strerror(int code) {
    return (char *) curl_easy_strerror((CURLcode) code);
}

/* curl_easy_getinfo() is variadic (its own real signature takes a
 * write-through output pointer whose type depends on `info`), which
 * %foreign can't express -- these collapse it to a plain by-value
 * return per output type instead, so a caller never has to manage the
 * output pointer itself. Only reachable under a statically-linked
 * backend (see doc/const-char-ffi.md's own reasoning for why -- the
 * same argument applies to any `static inline` shim here); Chez isn't
 * offered a "C:" target for these at all, so it fails cleanly at the
 * one call site that actually needs one, rather than at every build.
 * Errors from curl_easy_getinfo() itself are silently discarded (a
 * default/empty value comes back instead) -- acceptable for now since
 * every `CURLINFO` this repo currently binds is always retrievable
 * once curl_easy_perform() has returned, per curl_easy_getinfo(3)'s
 * own contract; revisit if a future CURLINFO doesn't hold that. */
static inline long idris2curl_getinfo_long(CURL *h, int info) {
    long v = 0;
    curl_easy_getinfo(h, (CURLINFO) info, &v);
    return v;
}

static inline char *idris2curl_getinfo_string(CURL *h, int info) {
    char *v = NULL;
    curl_easy_getinfo(h, (CURLINFO) info, &v);
    return v == NULL ? (char *) "" : v;
}

static inline double idris2curl_getinfo_double(CURL *h, int info) {
    double v = 0;
    curl_easy_getinfo(h, (CURLINFO) info, &v);
    return v;
}

/* CURLINFO_OFF_T-tagged infos write through a `curl_off_t *` --
 * `curl_off_t` is always a real 64-bit signed integer in libcurl
 * itself (curl/system.h), independent of the host platform's own
 * `long` width, so the shim returns `int64_t` (Idris2's own `Int64`
 * %foreign marshaling convention -- Compiler.RefC.RefC's own
 * `cTypeOfCFType CFInt64 = "int64_t"`) rather than `long`. */
static inline int64_t idris2curl_getinfo_offt(CURL *h, int info) {
    curl_off_t v = 0;
    curl_easy_getinfo(h, (CURLINFO) info, &v);
    return (int64_t) v;
}

/* CURLINFO_SLIST-tagged infos (e.g. CURLINFO_COOKIELIST) write
 * through a `struct curl_slist **` -- handed back as an opaque
 * pointer, same "collapse to a scalar return, read fields via
 * idris2curl_slist_data/_next below" idea as idris2curl_multi_info_read
 * above. Per curl_easy_getinfo(3), the caller owns the returned list
 * and must release it with curl_slist_free_all() once done -- unlike
 * every other getinfo tag here, whose value is owned internally by
 * libcurl and never freed by the caller. */
static inline void *idris2curl_getinfo_slist(CURL *h, int info) {
    struct curl_slist *v = NULL;
    curl_easy_getinfo(h, (CURLINFO) info, &v);
    return (void *) v;
}

/* struct curl_slist's own two fields, one shim each, same "one shim
 * per field" idea as idris2curl_version_info_/idris2curl_multimsg_
 * above. `data` is read through Data.String.FFI's own `ptrToString`
 * on the Idris side -- a bare copy, no curl_free/GC registration,
 * since ownership of every node's own `data` belongs to the list as a
 * whole (released in one shot by curl_slist_free_all(), never per
 * node). */
static inline char *idris2curl_slist_data(void *node) {
    return node == NULL ? NULL : ((struct curl_slist *) node)->data;
}

static inline void *idris2curl_slist_next(void *node) {
    return node == NULL ? NULL : (void *) ((struct curl_slist *) node)->next;
}

/* CURLINFO_SOCKET-tagged infos (e.g. CURLINFO_ACTIVESOCKET) write
 * through a `curl_socket_t *` -- `curl_socket_t` is a plain C `int` on
 * every non-Windows platform (curl/curl.h's own typedef), so this
 * collapses the same way idris2curl_getinfo_long does, no width
 * decision needed unlike off_t above. `CURL_SOCKET_BAD` (libcurl's own
 * "no such socket" sentinel, `-1` cast to `curl_socket_t`) survives
 * this cast unchanged, so a caller can still recognize it. */
static inline int idris2curl_getinfo_socket(CURL *h, int info) {
    curl_socket_t v = 0;
    curl_easy_getinfo(h, (CURLINFO) info, &v);
    return (int) v;
}

static inline char *idris2curl_url_strerror(int code) {
    return (char *) curl_url_strerror((CURLUcode) code);
}

/* curl_url_get() writes its own result through a `char **` output
 * argument (allocated by libcurl, meant to be freed with curl_free()
 * once the caller's own done with it) rather than returning it
 * directly -- collapsed to a plain return value here for the same
 * reason as idris2curl_getinfo_string above. NULL on failure, so a
 * non-NULL result is always a genuine libcurl allocation, distinct
 * from "part is genuinely empty" (CURLUE_OK, non-NULL, empty string)
 * -- Network.Curl.Raw's own curlUrlGet reads this back two different
 * ways depending on backend (rc2: `curlReadAndFree`'s GCAnyPtr, leak-
 * free; RefC: `Data.String.FFI.ptrToString`'s bare copy, since real
 * upstream RefC's own createCFunctions has a packCFType-vs-argument-
 * drop ordering bug -- see idris2-rc-cg's TODO.md, commit 2aa9b90,
 * which fixed the same bug on rc2 -- that makes reading a GCAnyPtr-
 * wrapped pointer back unsafe there), but both share this one shim:
 * unlike idris2curl_getinfo_string above, there's no backend where a
 * `char *`-returning %foreign target would even type-check here (the
 * output-pointer collapse still needs a shim; a raw AnyPtr return
 * doesn't need a *per-backend* one, so only one shim, not a Leaky/Raw
 * pair, exists for this call). One URL part's worth of leaked bytes
 * (rarely more than a few dozen) per call on RefC only, not
 * unbounded, not accumulating per network request. */
static inline void *idris2curl_url_get_raw(CURLU *u, int what, unsigned int flags) {
    char *part = NULL;
    CURLUcode rc = curl_url_get(u, (CURLUPart) what, &part, flags);
    return (rc == CURLUE_OK) ? (void *) part : NULL;
}

/* curl_version_info() returns curl_version_info_data*, a real C
 * struct with ~20 fields (curl/curl.h) -- not a scalar %foreign can
 * hand back directly. Rather than bind System.FFI's own Struct/
 * getField (Chez supports it, but upstream RefC itself doesn't --
 * rc2/doc/c-struct-support.md's own "What's confirmed" section; only
 * rc2's later addition does -- so it wouldn't build under plain
 * RefC), these shims read one field each off the same struct pointer,
 * same "collapse to a scalar return" idea as idris2curl_getinfo_*
 * above. Only the handful of fields actually useful without also
 * binding curl_version_info_data's own `protocols`/`feature_names`
 * (NULL-terminated string arrays -- no Idris-side array-of-CFString
 * binding exists yet) are covered: version string, numeric version,
 * build host triple, the feature bitmask, and the SSL backend's own
 * version string. curl_version_info(CURLVERSION_NOW) itself returns a
 * pointer to a static, library-owned struct (never freed, never
 * reallocated) -- calling it repeatedly, once per field read here, is
 * cheap and never invalidates a previous shim's own return value. */
static inline char *idris2curl_version_info_version(void) {
    const char *v = curl_version_info(CURLVERSION_NOW)->version;
    return (char *) (v == NULL ? "" : v);
}

static inline unsigned int idris2curl_version_info_version_num(void) {
    return curl_version_info(CURLVERSION_NOW)->version_num;
}

static inline char *idris2curl_version_info_host(void) {
    const char *v = curl_version_info(CURLVERSION_NOW)->host;
    return (char *) (v == NULL ? "" : v);
}

static inline int idris2curl_version_info_features(void) {
    return curl_version_info(CURLVERSION_NOW)->features;
}

/* Unlike version/host above, `ssl_version` genuinely can be NULL --
 * per curl_version_info(3), it's set only when libcurl was built with
 * SSL support, NULL otherwise -- so this one hands back the raw
 * pointer (NULL passthrough, no "" substitution) for
 * Network.Curl.Raw's own curlVersionInfoSslVersion to read via
 * Data.String.FFI.ptrToString, distinguishing "no SSL backend" from a
 * (never actually occurring) empty name. */
static inline char *idris2curl_version_info_ssl_version(void) {
    return (char *) curl_version_info(CURLVERSION_NOW)->ssl_version;
}

static inline char *idris2curl_multi_strerror(int code) {
    return (char *) curl_multi_strerror((CURLMcode) code);
}

/* curl_multi_perform()'s own second argument is a write-through
 * `int *running_handles` output pointer -- collapsed to a plain
 * return value here, same idea as idris2curl_getinfo_long above.
 * curl_multi_perform()'s own CURLMcode result (errors regarding the
 * whole multi stack, not any individual transfer -- see its own doc
 * comment in curl/multi.h) is folded into the same return: -1 on
 * anything but CURLM_OK, the running-handle count otherwise (always
 * >= 0, so -1 is unambiguous). */
static inline int idris2curl_multi_perform(CURLM *m) {
    int running = 0;
    CURLMcode rc = curl_multi_perform(m, &running);
    return rc == CURLM_OK ? running : -1;
}

/* curl_multi_wait()'s own extra_fds/extra_nfds (additional,
 * non-easy-handle sockets to also watch) aren't bound -- nothing this
 * repo does yet needs to watch anything outside the multi handle's own
 * easy handles. Its own `int *ret` (how many fds were actually
 * signalled) is collapsed the same way idris2curl_multi_perform above
 * collapses running_handles. */
static inline int idris2curl_multi_wait(CURLM *m, int timeout_ms) {
    int numfds = 0;
    CURLMcode rc = curl_multi_wait(m, NULL, 0, timeout_ms, &numfds);
    return rc == CURLM_OK ? numfds : -1;
}

/* curl_multi_info_read() returns CURLMsg* (NULL once the queue is
 * empty) rather than a scalar, and its own second argument
 * (`int *msgs_in_queue`, how many messages remain queued after this
 * read) is another write-through output pointer -- discarded here
 * (not currently useful: this repo's own call sites just loop calling
 * curl_multi_info_read until it returns NULL, never needing to know
 * the remaining count up front). The CURLMsg* itself is handed back
 * as an opaque pointer; idris2curl_multimsg_msg/easy_handle/result
 * below read one field each off it, same "one shim per field" idea as
 * curl_version_info's own shims. Per curl_multi_info_read(3), the
 * struct it points to remains valid only until curl_multi_cleanup() or
 * the next curl_multi_info_read() call -- callers must read every
 * field they need before either happens. */
static inline void *idris2curl_multi_info_read(CURLM *m) {
    int n = 0;
    return (void *) curl_multi_info_read(m, &n);
}

static inline int idris2curl_multimsg_msg(void *msg) {
    return msg == NULL ? -1 : (int) ((CURLMsg *) msg)->msg;
}

static inline void *idris2curl_multimsg_easy_handle(void *msg) {
    return msg == NULL ? NULL : (void *) ((CURLMsg *) msg)->easy_handle;
}

/* `data.result` is only meaningful when `msg == CURLMSG_DONE` (per
 * curl/multi.h's own CURLMsg doc comment) -- reading it for any other
 * `msg` value reads the union's own other member (`data.whatever`,
 * a `void *`) reinterpreted as a `CURLcode`, meaningless but not
 * undefined behavior (same union, no uninitialized read). */
static inline int idris2curl_multimsg_result(void *msg) {
    return msg == NULL ? -1 : (int) ((CURLMsg *) msg)->data.result;
}

static inline char *idris2curl_share_strerror(int code) {
    return (char *) curl_share_strerror((CURLSHcode) code);
}

/* curl_easy_header()'s own last argument is a write-through
 * `struct curl_header **` output pointer -- collapsed to a plain
 * return value (NULL on any CURLHcode other than CURLHE_OK, same
 * "small non-negative or unambiguous sentinel" shape every other
 * collapsed-output shim here uses) the same way idris2curl_getinfo_*
 * collapses curl_easy_getinfo's own output pointer. `nameindex` (which
 * same-named header to read, when more than one exists) is hard-coded
 * to `0` (the first/only one) -- no concrete need yet to read a
 * specific later occurrence. `request` (which numbered request this
 * concerns, relevant across redirects/multi-stage auth) is exposed as
 * a real parameter since which request a caller wants is genuinely
 * call-site-specific, unlike nameindex. */
static inline void *idris2curl_easy_header(CURL *h, const char *name, unsigned int origin, int request) {
    struct curl_header *hout = NULL;
    CURLHcode rc = curl_easy_header(h, name, 0, origin, request, &hout);
    return (rc == CURLHE_OK) ? (void *) hout : NULL;
}

/* curl_header's own fields, read the same "one shim per field" way
 * idris2curl_version_info_ and idris2curl_multimsg_ above do, rather
 * than System.FFI's own Struct/getField (upstream RefC doesn't
 * implement it at all, same reasoning as doc/version-info-struct.md).
 * `amount`/`index` (both `size_t`) aren't exposed -- no concrete need
 * yet to distinguish "which occurrence of a repeated header" beyond
 * always reading the first (see idris2curl_easy_header's own
 * `nameindex = 0` above). */
static inline char *idris2curl_header_name(void *h) {
    return h == NULL ? (char *) "" : ((struct curl_header *) h)->name;
}

static inline char *idris2curl_header_value(void *h) {
    return h == NULL ? (char *) "" : ((struct curl_header *) h)->value;
}

/* Captures a response body into memory without ever binding
 * CURLOPT_WRITEFUNCTION (still not bound -- see TODO.md's own
 * "callback options" entry, and idris2-rc-cg's Chan-based design note
 * for when it eventually is). libcurl's own *default* write callback
 * -- always in effect when CURLOPT_WRITEFUNCTION is left unset -- is
 * just `fwrite(ptr, size, nmemb, (FILE *) CURLOPT_WRITEDATA)`.
 * CURLOPT_WRITEDATA is an ordinary object-pointer option (no callback
 * of our own to hand libcurl), so pointing it at an in-memory stream
 * from POSIX's own open_memstream(3) redirects the existing default
 * writer into a growable heap buffer instead of the process's real
 * stdout -- see doc/memstream-capture.md for the full design. */
struct idris2curl_memstream {
    FILE *fp;
    char *buf;
    size_t len;
};

/* NULL on allocation/open_memstream(3) failure. */
static inline void *idris2curl_memstream_open(void) {
    struct idris2curl_memstream *m = malloc(sizeof *m);
    if (m == NULL) return NULL;
    m->buf = NULL;
    m->len = 0;
    m->fp = open_memstream(&m->buf, &m->len);
    if (m->fp == NULL) {
        free(m);
        return NULL;
    }
    return (void *) m;
}

/* The FILE* to hand to curlEasySetoptPointer h curlopt_WRITEDATA. */
static inline void *idris2curl_memstream_filep(void *m) {
    return m == NULL ? NULL : (void *) ((struct idris2curl_memstream *) m)->fp;
}

/* Flushes and finalizes buf/len -- call exactly once, after
 * curl_easy_perform returns, before any _data/_size/_free call below.
 * open_memstream(3) guarantees buf is NUL-terminated on close (the
 * NUL itself isn't counted in len), so a NUL-terminated read (
 * Data.String.FFI.ptrToString, idris2rc2_String_to_TextBuffer) is
 * always safe here even without threading len through -- only the
 * exact-byte-count Buffer path (idris2curl_memstream_copy_into below)
 * actually needs len, for embedded-NUL-safety. */
static inline void idris2curl_memstream_close(void *m) {
    if (m != NULL) fclose(((struct idris2curl_memstream *) m)->fp);
}

/* NULL only if idris2curl_memstream_open itself already returned NULL
 * -- open_memstream(3) always leaves buf non-NULL (even for a
 * zero-byte body) once fp itself opened successfully. */
static inline void *idris2curl_memstream_data(void *m) {
    return m == NULL ? NULL : (void *) ((struct idris2curl_memstream *) m)->buf;
}

static inline long idris2curl_memstream_size(void *m) {
    return m == NULL ? -1 : (long) ((struct idris2curl_memstream *) m)->len;
}

/* Releases both the handle struct and the captured buffer itself
 * (plain free(), not curl_free() -- open_memstream's own buffer is a
 * regular glibc malloc allocation, unrelated to libcurl's allocator).
 * Call only after every _data/_size read is done. */
static inline void idris2curl_memstream_free(void *m) {
    if (m != NULL) {
        struct idris2curl_memstream *ms = (struct idris2curl_memstream *) m;
        free(ms->buf);
        free(ms);
    }
}

/* Idris2's own `Buffer` type -- RefC's support/refc/buffer.c and
 * idris2-rc-cg's rc2/support/rc2/buffer.c (explicitly "ported from
 * RefC's support/refc/buffer.c", operating on "purely the raw
 * malloc'd buffer") both deliberately share this exact layout, so a
 * `Buffer`-returning/-taking %foreign value reaching this shim as a
 * bare AnyPtr on either backend is safe to reinterpret this way. Not
 * reachable from Chez, whose own `Buffer` has no such C struct at all
 * (`blodwen-buffer-*` operate on a Scheme-native bytevector) -- no
 * `"C:..."` target below, RefC/rc2-only like every other struct-layout
 * shim in this file. The one length-bounded, embedded-NUL-safe copy
 * path in this whole capture design: every other read here
 * (ptrToString, idris2rc2_String_to_TextBuffer) is NUL-terminated. */
struct idris2curl_Buffer {
    int size;
    char data[];
};

static inline void idris2curl_memstream_copy_into_buffer(void *m, void *buf) {
    struct idris2curl_memstream *ms = (struct idris2curl_memstream *) m;
    memcpy(((struct idris2curl_Buffer *) buf)->data, ms->buf, ms->len);
}

#endif
