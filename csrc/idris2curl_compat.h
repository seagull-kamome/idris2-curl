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

#endif
