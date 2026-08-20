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

#include <curl/curl.h>

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

static inline char *idris2curl_url_strerror(int code) {
    return (char *) curl_url_strerror((CURLUcode) code);
}

/* curl_url_get() writes its own result through a `char **` output
 * argument (allocated by libcurl, meant to be freed with curl_free()
 * once the caller's own done with it) rather than returning it
 * directly -- collapsed to a plain return value here for the same
 * reason as idris2curl_getinfo_string above. Unlike that one, this
 * leaks: the %foreign `String` return copies this pointer's own bytes
 * into a fresh Idris2-owned string right after this call returns (see
 * idris2rc2_mkString's own memcpy), but nothing downstream of that
 * copy ever gets the chance to curl_free() libcurl's own original
 * allocation -- there's no hook in a plain %foreign call for "do this
 * after the copy, before returning to Idris2 code". Deliberately
 * accepted for now: one URL part's worth of leaked bytes (rarely more
 * than a few dozen) per curl_url_get call, not unbounded, not
 * accumulating per network request the way a request-body buffer
 * would. Revisit (e.g. by splitting this into fetch/take/free step
 * functions coordinated from the Idris2 side, at the cost of thread-
 * unsafe global state) if a program ends up calling this often enough
 * for that to matter. */
static inline char *idris2curl_url_get(CURLU *u, int what, unsigned int flags) {
    char *part = NULL;
    CURLUcode rc = curl_url_get(u, (CURLUPart) what, &part, flags);
    return (rc == CURLUE_OK && part != NULL) ? part : (char *) "";
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

static inline char *idris2curl_version_info_ssl_version(void) {
    const char *v = curl_version_info(CURLVERSION_NOW)->ssl_version;
    return (char *) (v == NULL ? "" : v);
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

#endif
