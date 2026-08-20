module Network.Curl.Raw

-- Copyright 2026, Hattori,Hiroki. All rights reserved.
-- This module was licensed by BSD3.

-- Direct libcurl FFI declarations -- one `%foreign` per bound
-- function, no Struct/getField, no derived instances. Just enough to
-- exercise curl_easy's "init, setopt, perform, cleanup" lifecycle.

import System.FFI

import Network.Curl.Types

%foreign "C:curl_global_init,libcurl,curl/curl.h"
prim__curlGlobalInit : Int -> PrimIO Int

%foreign "C:curl_global_cleanup,libcurl,curl/curl.h"
prim__curlGlobalCleanup : PrimIO ()

%foreign "C:curl_easy_init,libcurl,curl/curl.h"
prim__curlEasyInit : PrimIO AnyPtr

%foreign "C:curl_easy_cleanup,libcurl,curl/curl.h"
prim__curlEasyCleanup : AnyPtr -> PrimIO ()

%foreign "C:curl_easy_setopt,libcurl,curl/curl.h"
prim__curlEasySetoptString : AnyPtr -> Int -> String -> PrimIO Int

%foreign "C:curl_easy_setopt,libcurl,curl/curl.h"
prim__curlEasySetoptLong : AnyPtr -> Int -> Int -> PrimIO Int

-- Same `curl_easy_setopt` C symbol, this overload's own third argument
-- typed for an object-pointer option (e.g. CURLOPT_HTTPHEADER) whose
-- value is a `curl_slist *`, not a `String`.
%foreign "C:curl_easy_setopt,libcurl,curl/curl.h"
prim__curlEasySetoptSlist : AnyPtr -> Int -> AnyPtr -> PrimIO Int

%foreign "C:curl_easy_perform,libcurl,curl/curl.h"
prim__curlEasyPerform : AnyPtr -> PrimIO Int

%foreign "C:curl_easy_duphandle,libcurl,curl/curl.h"
prim__curlEasyDuphandle : AnyPtr -> PrimIO AnyPtr

%foreign "C:curl_easy_reset,libcurl,curl/curl.h"
prim__curlEasyReset : AnyPtr -> PrimIO ()

%foreign "C:curl_slist_append,libcurl,curl/curl.h"
prim__curlSlistAppend : AnyPtr -> String -> PrimIO AnyPtr

%foreign "C:curl_slist_free_all,libcurl,curl/curl.h"
prim__curlSlistFreeAll : AnyPtr -> PrimIO ()

-- curl_easy_strerror returns `const char *`; rc2/RefC's own %foreign
-- lowering hardcodes CFString as non-const `char *`, which collides
-- with both backends' own -Werror -Wdiscarded-qualifiers on a direct
-- binding (confirmed directly against upstream RefC too, not just
-- rc2 -- see idris2-rc-cg/TODO.md's "CFString's hardcoded char *
-- return type" entry). Chez has no such issue -- dynamically typed, no
-- C-level qualifier to discard -- so only the two static-linking
-- backends route through idris2curl_compat.h's `static inline` shim
-- (zero call overhead: the cast, not a real wrapper call, is the
-- point); Chez keeps calling curl_easy_strerror directly, since the
-- shim only exists as a real symbol under static linking, never in
-- libcurl.so's own dynamic-load table. Both static backends need
-- IDRIS2_LDLIBS="-lcurl" set by hand under plain upstream RefC (only
-- rc2 derives -l<lib> automatically from the lib field, see
-- Compiler.RC2.CC's own compileCFile).
--
-- Three %foreign targets pick the right one per backend: rc2's own FFI
-- target tags are `["RC2", "RefC", "C"]` (`Compiler.RC2.Emit`'s own
-- `ffiTags`, checked in that order) so `"RC2:..."` wins there;
-- upstream RefC's own tags are `["RefC", "C"]` so `"RefC:..."` wins
-- there; Chez's own target list (`["scheme,chez", "scheme", ..., "C"]`)
-- matches neither and falls through to the plain `"C:..."` entry.
%foreign "C:curl_easy_strerror,libcurl,curl/curl.h"
         "RefC:idris2curl_easy_strerror,libcurl,idris2curl_compat.h"
         "RC2:idris2curl_easy_strerror,libcurl,idris2curl_compat.h"
prim__curlEasyStrerror : Int -> PrimIO String

-- curl_easy_getinfo() is variadic (the real C signature takes a
-- write-through output pointer whose type depends on the CURLINFO);
-- %foreign can't express that at all, so there's no plain "C:..."
-- target here -- Chez has no shim to fall back to (see
-- idris2curl_compat.h's own doc comment on why these three shims can
-- only exist under static linking), and fails cleanly with "was not
-- accepted by any backend" at the one call site that actually needs
-- one, rather than breaking every Chez build of this library.
%foreign "RefC:idris2curl_getinfo_long,libcurl,idris2curl_compat.h"
         "RC2:idris2curl_getinfo_long,libcurl,idris2curl_compat.h"
prim__curlEasyGetinfoLong : AnyPtr -> Int -> PrimIO Int

%foreign "RefC:idris2curl_getinfo_string,libcurl,idris2curl_compat.h"
         "RC2:idris2curl_getinfo_string,libcurl,idris2curl_compat.h"
prim__curlEasyGetinfoString : AnyPtr -> Int -> PrimIO String

%foreign "RefC:idris2curl_getinfo_double,libcurl,idris2curl_compat.h"
         "RC2:idris2curl_getinfo_double,libcurl,idris2curl_compat.h"
prim__curlEasyGetinfoDouble : AnyPtr -> Int -> PrimIO Double

-- curl_easy_escape/curl_easy_unescape/curl_free: all return/take a
-- plain (non-const) `char *`/`void *`, so no const-cast shim is
-- needed here unlike curl_easy_strerror above. The escaped/unescaped
-- result is libcurl's own fresh allocation, meant to be released with
-- curl_free() once read -- but %foreign's own String return already
-- copies the bytes out before this binding gets a chance to call
-- curl_free() on the original, so (like idris2curl_url_get, see
-- idris2curl_compat.h's own doc comment) this leaks libcurl's own
-- allocation on every call. Deliberately accepted for the same
-- "small, bounded, not accumulating per request" reasoning.
-- curl_easy_unescape's own fourth argument (`int *outlength`) is
-- passed NULL -- always safe per curl_easy_unescape(3) when the
-- caller only needs the NUL-terminated string result, not a decoded
-- length that could itself embed a NUL byte.
%foreign "C:curl_easy_escape,libcurl,curl/curl.h"
prim__curlEasyEscape : AnyPtr -> String -> Int -> PrimIO String

%foreign "C:curl_easy_unescape,libcurl,curl/curl.h"
prim__curlEasyUnescape : AnyPtr -> String -> Int -> AnyPtr -> PrimIO String

%foreign "C:curl_free,libcurl,curl/curl.h"
prim__curlFree : AnyPtr -> PrimIO ()

%foreign "C:curl_version,libcurl,curl/curl.h"
prim__curlVersion : PrimIO String

%foreign "C:curl_url,libcurl,curl/curl.h"
prim__curlUrl : PrimIO AnyPtr

%foreign "C:curl_url_cleanup,libcurl,curl/curl.h"
prim__curlUrlCleanup : AnyPtr -> PrimIO ()

%foreign "C:curl_url_dup,libcurl,curl/curl.h"
prim__curlUrlDup : AnyPtr -> PrimIO AnyPtr

%foreign "C:curl_url_set,libcurl,curl/curl.h"
prim__curlUrlSet : AnyPtr -> Int -> String -> Int -> PrimIO Int

-- curl_url_get() writes its own result through a `char **` output
-- argument rather than returning it -- see idris2curl_url_get's own
-- doc comment (idris2curl_compat.h) for both why it needs a shim at
-- all and the leak this shares with curl_easy_escape/unescape above.
%foreign "RefC:idris2curl_url_get,libcurl,idris2curl_compat.h"
         "RC2:idris2curl_url_get,libcurl,idris2curl_compat.h"
prim__curlUrlGet : AnyPtr -> Int -> Int -> PrimIO String

-- curl_url_strerror() returns `const char *`, same const-cast
-- reasoning as curl_easy_strerror above.
%foreign "C:curl_url_strerror,libcurl,curl/curl.h"
         "RefC:idris2curl_url_strerror,libcurl,idris2curl_compat.h"
         "RC2:idris2curl_url_strerror,libcurl,idris2curl_compat.h"
prim__curlUrlStrerror : Int -> PrimIO String

||| `CURL_GLOBAL_ALL`, per curl/curl.h.
curlGlobalAll : Int
curlGlobalAll = 3

export
curlGlobalInit : HasIO io => io CURLcode
curlGlobalInit = MkCURLcode <$> primIO (prim__curlGlobalInit curlGlobalAll)

export
curlGlobalCleanup : HasIO io => io ()
curlGlobalCleanup = primIO prim__curlGlobalCleanup

||| `Nothing` if libcurl itself reports allocation failure -- see
||| curl_easy_init(3), never expected to fire on any of this repo's
||| own examples but always possible per the documented contract.
export
curlEasyInit : HasIO io => io (Maybe AnyPtr)
curlEasyInit = do
    h <- primIO prim__curlEasyInit
    pure $ if prim__nullAnyPtr h /= 0 then Nothing else Just h

export
curlEasyCleanup : HasIO io => AnyPtr -> io ()
curlEasyCleanup h = primIO (prim__curlEasyCleanup h)

export
curlEasySetoptString : HasIO io => AnyPtr -> CURLoption -> String -> io CURLcode
curlEasySetoptString h (MkCURLoption o) v = MkCURLcode <$> primIO (prim__curlEasySetoptString h o v)

export
curlEasySetoptLong : HasIO io => AnyPtr -> CURLoption -> Int -> io CURLcode
curlEasySetoptLong h (MkCURLoption o) v = MkCURLcode <$> primIO (prim__curlEasySetoptLong h o v)

export
curlEasyPerform : HasIO io => AnyPtr -> io CURLcode
curlEasyPerform h = MkCURLcode <$> primIO (prim__curlEasyPerform h)

export
curlEasyStrerror : HasIO io => CURLcode -> io String
curlEasyStrerror (MkCURLcode c) = primIO (prim__curlEasyStrerror c)

export
curlEasySetoptSlist : HasIO io => AnyPtr -> CURLoption -> AnyPtr -> io CURLcode
curlEasySetoptSlist h (MkCURLoption o) v = MkCURLcode <$> primIO (prim__curlEasySetoptSlist h o v)

||| `Nothing` on the same allocation-failure contract as `curlEasyInit`
||| (`curl_easy_duphandle(3)`).
export
curlEasyDuphandle : HasIO io => AnyPtr -> io (Maybe AnyPtr)
curlEasyDuphandle h = do
    h' <- primIO (prim__curlEasyDuphandle h)
    pure $ if prim__nullAnyPtr h' /= 0 then Nothing else Just h'

export
curlEasyReset : HasIO io => AnyPtr -> io ()
curlEasyReset h = primIO (prim__curlEasyReset h)

export
curlEasyGetinfoLong : HasIO io => AnyPtr -> CURLINFO -> io Int
curlEasyGetinfoLong h (MkCURLINFO i) = primIO (prim__curlEasyGetinfoLong h i)

export
curlEasyGetinfoString : HasIO io => AnyPtr -> CURLINFO -> io String
curlEasyGetinfoString h (MkCURLINFO i) = primIO (prim__curlEasyGetinfoString h i)

export
curlEasyGetinfoDouble : HasIO io => AnyPtr -> CURLINFO -> io Double
curlEasyGetinfoDouble h (MkCURLINFO i) = primIO (prim__curlEasyGetinfoDouble h i)

||| An empty header list, per `curl_slist_append(3)`'s own contract
||| that a `NULL` first argument starts a fresh one -- `System.FFI`'s
||| own `prim__getNullAnyPtr` (`idris2_getNull()`, already provided by
||| every backend's shared support runtime) gives one directly, no
||| `csrc/` shim needed for this unlike `curlEasyGetinfo*` above.
export
curlSlistEmpty : AnyPtr
curlSlistEmpty = prim__getNullAnyPtr

||| `list` may itself be `curlSlistEmpty` -- see `curlSlistEmpty`'s own
||| doc comment. Always returns the (possibly new) list head; the
||| original `list` handle must not be reused after this call (per
||| `curl_slist_append(3)`, `list` may have been freed and replaced on
||| allocation failure).
export
curlSlistAppend : HasIO io => AnyPtr -> String -> io AnyPtr
curlSlistAppend list s = primIO (prim__curlSlistAppend list s)

export
curlSlistFreeAll : HasIO io => AnyPtr -> io ()
curlSlistFreeAll list = primIO (prim__curlSlistFreeAll list)

||| `Nothing` on the same "libcurl itself reports an error" contract as
||| `curl_easy_escape(3)` (`Nothing` for both allocation failure and a
||| `length` too large to represent as the underlying `int`).
export
curlEasyEscape : HasIO io => AnyPtr -> String -> io (Maybe String)
curlEasyEscape h s = do
    r <- primIO (prim__curlEasyEscape h s 0)
    pure $ if r == "" then Nothing else Just r

export
curlEasyUnescape : HasIO io => AnyPtr -> String -> io (Maybe String)
curlEasyUnescape h s = do
    r <- primIO (prim__curlEasyUnescape h s 0 prim__getNullAnyPtr)
    pure $ if r == "" then Nothing else Just r

export
curlVersion : HasIO io => io String
curlVersion = primIO prim__curlVersion

||| `Nothing` on the same allocation-failure contract as
||| `curlEasyInit` (`curl_url(3)`).
export
curlUrl : HasIO io => io (Maybe AnyPtr)
curlUrl = do
    u <- primIO prim__curlUrl
    pure $ if prim__nullAnyPtr u /= 0 then Nothing else Just u

export
curlUrlCleanup : HasIO io => AnyPtr -> io ()
curlUrlCleanup u = primIO (prim__curlUrlCleanup u)

||| `Nothing` on the same allocation-failure contract as `curlUrl`
||| (`curl_url_dup(3)`).
export
curlUrlDup : HasIO io => AnyPtr -> io (Maybe AnyPtr)
curlUrlDup u = do
    u' <- primIO (prim__curlUrlDup u)
    pure $ if prim__nullAnyPtr u' /= 0 then Nothing else Just u'

||| `flags` -- see curl/urlapi.h's own `CURLU_*` bit flags
||| (`CURLU_URLENCODE`, `CURLU_DEFAULT_SCHEME`, ...); `0` for none.
export
curlUrlSet : HasIO io => AnyPtr -> CURLUPart -> String -> Int -> io CURLUcode
curlUrlSet u (MkCURLUPart p) s flags = MkCURLUcode <$> primIO (prim__curlUrlSet u p s flags)

||| RefC/rc2-only, no Chez binding -- see `Network.Curl.Raw`'s own doc
||| comment on `prim__curlUrlGet` and `doc/variadic-getinfo.md`-style
||| reasoning (the underlying shim is `static inline`, unreachable
||| under Chez's own dynamic FFI). `flags` -- see `curlUrlSet`'s own
||| doc comment. Empty string on either a `curl_url_get` failure or a
||| part that's genuinely empty -- `CURLUcode` isn't threaded back
||| through `idris2curl_url_get`'s own collapsed return, so the two
||| aren't distinguishable here yet.
export
curlUrlGet : HasIO io => AnyPtr -> CURLUPart -> Int -> io String
curlUrlGet u (MkCURLUPart p) flags = primIO (prim__curlUrlGet u p flags)

export
curlUrlStrerror : HasIO io => CURLUcode -> io String
curlUrlStrerror (MkCURLUcode c) = primIO (prim__curlUrlStrerror c)
