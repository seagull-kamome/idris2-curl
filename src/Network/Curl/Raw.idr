module Network.Curl.Raw

-- Copyright 2026, Hattori,Hiroki. All rights reserved.
-- This module was licensed by BSD3.

-- Direct libcurl FFI declarations -- one `%foreign` per bound
-- function, no Struct/getField, no derived instances. Just enough to
-- exercise curl_easy's "init, setopt, perform, cleanup" lifecycle.

import Data.Buffer
import Data.String.FFI
import System.FFI
import System.Info

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

-- `Int64`, not `Int` -- `curl_off_t` is always a real 64-bit signed
-- integer in libcurl, regardless of the host platform's own `long`
-- width; see idris2curl_getinfo_offt's own doc comment
-- (idris2curl_compat.h) for the matching `int64_t` C-side return type.
-- rc2-only, no `"RefC:..."` target -- confirmed directly that real
-- upstream RefC's own C backend crashes lowering any `Int64`-returning
-- %foreign call ("INTERNAL ERROR: Unknown FFI type in C backend:
-- Int_64", Core.CompileExpr's own `show CFInt64 = "Int_64"`), even
-- though `Compiler.RefC.RefC.cTypeOfCFType`/`extractValue`/
-- `packCFType` do each have their own `CFInt64` case -- some other,
-- unidentified stage still fails to route it there against the
-- nixpkgs-packaged idris2 build used here. idris2-rc-cg's own rc2
-- backend has no such gap.
%foreign "RC2:idris2curl_getinfo_offt,libcurl,idris2curl_compat.h"
prim__curlEasyGetinfoOfft : AnyPtr -> Int -> PrimIO Int64

-- Opaque `struct curl_slist *` handle -- read via curlSlistToList
-- below, released via curlSlistFreeAll once done (see
-- idris2curl_getinfo_slist's own doc comment, idris2curl_compat.h, for
-- why this tag's value is caller-owned unlike every other getinfo tag
-- here).
%foreign "RefC:idris2curl_getinfo_slist,libcurl,idris2curl_compat.h"
         "RC2:idris2curl_getinfo_slist,libcurl,idris2curl_compat.h"
prim__curlEasyGetinfoSlist : AnyPtr -> Int -> PrimIO AnyPtr

-- `struct curl_slist`'s own two fields, one shim each, same "one shim
-- per field" idea as prim__curlVersionInfo*/prim__curlMultimsg* below.
%foreign "RefC:idris2curl_slist_data,libcurl,idris2curl_compat.h"
         "RC2:idris2curl_slist_data,libcurl,idris2curl_compat.h"
prim__curlSlistData : AnyPtr -> PrimIO AnyPtr

%foreign "RefC:idris2curl_slist_next,libcurl,idris2curl_compat.h"
         "RC2:idris2curl_slist_next,libcurl,idris2curl_compat.h"
prim__curlSlistNext : AnyPtr -> PrimIO AnyPtr

-- `curl_socket_t` is a plain C `int` on every non-Windows platform
-- (curl/curl.h's own typedef), an exact fit for Idris2's `Int`.
%foreign "RefC:idris2curl_getinfo_socket,libcurl,idris2curl_compat.h"
         "RC2:idris2curl_getinfo_socket,libcurl,idris2curl_compat.h"
prim__curlEasyGetinfoSocket : AnyPtr -> Int -> PrimIO Int

-- curl_easy_escape/curl_easy_unescape/curl_free: all return/take a
-- plain (non-const) `char *`/`void *`, so no const-cast shim is
-- needed here unlike curl_easy_strerror above. The escaped/unescaped
-- result is libcurl's own fresh allocation, meant to be released with
-- curl_free() once read.
--
-- Two bindings per function: the `Leaky` one lets %foreign's own
-- String-return marshalling copy the bytes out immediately and never
-- frees the original (a small, bounded, per-call leak -- see
-- idris2curl_url_get's own doc comment, idris2curl_compat.h, for the
-- same reasoning); the `Raw` one hands back the untouched AnyPtr so
-- curlReadAndFree below can wrap it in a GCAnyPtr keyed to curl_free
-- and read it back leak-free. `curlEasyEscape`/`curlEasyUnescape`
-- pick between them based on `codegen`: real upstream RefC's own
-- createCFunctions still has the packCFType-vs-argument-drop ordering
-- bug that makes reading a GCAnyPtr back unsafe there (see
-- idris2-rc-cg's TODO.md, commit 2aa9b90, which fixed the identical
-- bug on rc2) -- RefC keeps the leaky path, Chez and rc2 both use the
-- leak-free one.
-- curl_easy_unescape's own fourth argument (`int *outlength`) is
-- passed NULL -- always safe per curl_easy_unescape(3) when the
-- caller only needs the NUL-terminated string result, not a decoded
-- length that could itself embed a NUL byte.
%foreign "C:curl_easy_escape,libcurl,curl/curl.h"
prim__curlEasyEscapeLeaky : AnyPtr -> String -> Int -> PrimIO String

%foreign "C:curl_easy_escape,libcurl,curl/curl.h"
prim__curlEasyEscapeRaw : AnyPtr -> String -> Int -> PrimIO AnyPtr

%foreign "C:curl_easy_unescape,libcurl,curl/curl.h"
prim__curlEasyUnescapeLeaky : AnyPtr -> String -> Int -> AnyPtr -> PrimIO String

%foreign "C:curl_easy_unescape,libcurl,curl/curl.h"
prim__curlEasyUnescapeRaw : AnyPtr -> String -> Int -> AnyPtr -> PrimIO AnyPtr

%foreign "C:curl_free,libcurl,curl/curl.h"
prim__curlFree : AnyPtr -> PrimIO ()

-- idris2_getString(void *p) { return (char *)p; } (idris_support.c,
-- part of every backend's own runtime support library) -- the same
-- no-copy passthrough upstream Prelude.IO's own prim__getString binds
-- as `Ptr String -> String`, retyped here to read through a GCAnyPtr
-- directly instead. See curlReadAndFree's own doc comment below.
%foreign "C:idris2_getString,libidris2_support,idris_support.h"
prim__curlGetStringGC : GCAnyPtr -> PrimIO String

%foreign "C:curl_version,libcurl,curl/curl.h"
prim__curlVersion : PrimIO String

-- curl_version_info() returns a real C struct, not a scalar -- see
-- idris2curl_version_info_version's own doc comment
-- (idris2curl_compat.h) for why these route through per-field shims
-- (RefC/rc2-only, no Chez binding, same "static inline, static
-- linking only" reasoning as curl_easy_getinfo) rather than
-- System.FFI's own Struct/getField.
%foreign "RefC:idris2curl_version_info_version,libcurl,idris2curl_compat.h"
         "RC2:idris2curl_version_info_version,libcurl,idris2curl_compat.h"
prim__curlVersionInfoVersion : PrimIO String

%foreign "RefC:idris2curl_version_info_version_num,libcurl,idris2curl_compat.h"
         "RC2:idris2curl_version_info_version_num,libcurl,idris2curl_compat.h"
prim__curlVersionInfoVersionNum : PrimIO Int

%foreign "RefC:idris2curl_version_info_host,libcurl,idris2curl_compat.h"
         "RC2:idris2curl_version_info_host,libcurl,idris2curl_compat.h"
prim__curlVersionInfoHost : PrimIO String

%foreign "RefC:idris2curl_version_info_features,libcurl,idris2curl_compat.h"
         "RC2:idris2curl_version_info_features,libcurl,idris2curl_compat.h"
prim__curlVersionInfoFeatures : PrimIO Int

-- Unlike prim__curlVersionInfoVersion/Host above, this returns a raw
-- AnyPtr rather than a String directly -- ssl_version genuinely can be
-- NULL (see idris2curl_version_info_ssl_version's own doc comment,
-- idris2curl_compat.h), so curlVersionInfoSslVersion below reads it
-- through Data.String.FFI.ptrToString to preserve that distinction.
%foreign "RefC:idris2curl_version_info_ssl_version,libcurl,idris2curl_compat.h"
         "RC2:idris2curl_version_info_ssl_version,libcurl,idris2curl_compat.h"
prim__curlVersionInfoSslVersion : PrimIO AnyPtr

%foreign "C:curl_url,libcurl,curl/curl.h"
prim__curlUrl : PrimIO AnyPtr

%foreign "C:curl_url_cleanup,libcurl,curl/curl.h"
prim__curlUrlCleanup : AnyPtr -> PrimIO ()

%foreign "C:curl_url_dup,libcurl,curl/curl.h"
prim__curlUrlDup : AnyPtr -> PrimIO AnyPtr

%foreign "C:curl_url_set,libcurl,curl/curl.h"
prim__curlUrlSet : AnyPtr -> Int -> String -> Int -> PrimIO Int

-- curl_url_get() writes its own result through a `char **` output
-- argument rather than returning it -- see idris2curl_url_get_raw's
-- own doc comment (idris2curl_compat.h) for why it needs a shim at
-- all. Unlike curl_easy_escape/unescape above, only one shim/binding
-- here (not a per-backend Leaky/Raw pair): curlUrlGet reads the same
-- raw AnyPtr back two different ways depending on `codegen` instead.
-- RefC/rc2-only, no Chez binding -- see doc/variadic-getinfo.md-style
-- reasoning, `prim__curlEasyGetinfoString`'s own doc comment above.
%foreign "RefC:idris2curl_url_get_raw,libcurl,idris2curl_compat.h"
         "RC2:idris2curl_url_get_raw,libcurl,idris2curl_compat.h"
prim__curlUrlGetRaw : AnyPtr -> Int -> Int -> PrimIO AnyPtr

-- curl_url_strerror() returns `const char *`, same const-cast
-- reasoning as curl_easy_strerror above.
%foreign "C:curl_url_strerror,libcurl,curl/curl.h"
         "RefC:idris2curl_url_strerror,libcurl,idris2curl_compat.h"
         "RC2:idris2curl_url_strerror,libcurl,idris2curl_compat.h"
prim__curlUrlStrerror : Int -> PrimIO String

%foreign "C:curl_multi_init,libcurl,curl/multi.h"
prim__curlMultiInit : PrimIO AnyPtr

%foreign "C:curl_multi_cleanup,libcurl,curl/multi.h"
prim__curlMultiCleanup : AnyPtr -> PrimIO Int

%foreign "C:curl_multi_add_handle,libcurl,curl/multi.h"
prim__curlMultiAddHandle : AnyPtr -> AnyPtr -> PrimIO Int

%foreign "C:curl_multi_remove_handle,libcurl,curl/multi.h"
prim__curlMultiRemoveHandle : AnyPtr -> AnyPtr -> PrimIO Int

-- curl_multi_strerror() returns `const char *`, same const-cast
-- reasoning as curl_easy_strerror above.
%foreign "C:curl_multi_strerror,libcurl,curl/multi.h"
         "RefC:idris2curl_multi_strerror,libcurl,idris2curl_compat.h"
         "RC2:idris2curl_multi_strerror,libcurl,idris2curl_compat.h"
prim__curlMultiStrerror : Int -> PrimIO String

-- curl_multi_perform()/curl_multi_wait()/curl_multi_info_read() each
-- take a write-through output-pointer argument %foreign can't express
-- cleanly (an int count, or -- for info_read -- a CURLMsg* result
-- alongside a count) -- see idris2curl_multi_perform/multi_wait/
-- multi_info_read's own doc comments (idris2curl_compat.h) for how
-- each is collapsed to a plain return. RefC/rc2-only, no Chez binding,
-- same reasoning as curl_easy_getinfo (doc/variadic-getinfo.md).
%foreign "RefC:idris2curl_multi_perform,libcurl,idris2curl_compat.h"
         "RC2:idris2curl_multi_perform,libcurl,idris2curl_compat.h"
prim__curlMultiPerform : AnyPtr -> PrimIO Int

%foreign "RefC:idris2curl_multi_wait,libcurl,idris2curl_compat.h"
         "RC2:idris2curl_multi_wait,libcurl,idris2curl_compat.h"
prim__curlMultiWait : AnyPtr -> Int -> PrimIO Int

%foreign "RefC:idris2curl_multi_info_read,libcurl,idris2curl_compat.h"
         "RC2:idris2curl_multi_info_read,libcurl,idris2curl_compat.h"
prim__curlMultiInfoRead : AnyPtr -> PrimIO AnyPtr

%foreign "RefC:idris2curl_multimsg_msg,libcurl,idris2curl_compat.h"
         "RC2:idris2curl_multimsg_msg,libcurl,idris2curl_compat.h"
prim__curlMultimsgMsg : AnyPtr -> PrimIO Int

%foreign "RefC:idris2curl_multimsg_easy_handle,libcurl,idris2curl_compat.h"
         "RC2:idris2curl_multimsg_easy_handle,libcurl,idris2curl_compat.h"
prim__curlMultimsgEasyHandle : AnyPtr -> PrimIO AnyPtr

%foreign "RefC:idris2curl_multimsg_result,libcurl,idris2curl_compat.h"
         "RC2:idris2curl_multimsg_result,libcurl,idris2curl_compat.h"
prim__curlMultimsgResult : AnyPtr -> PrimIO Int

%foreign "C:curl_share_init,libcurl,curl/curl.h"
prim__curlShareInit : PrimIO AnyPtr

%foreign "C:curl_share_cleanup,libcurl,curl/curl.h"
prim__curlShareCleanup : AnyPtr -> PrimIO Int

-- curl_share_setopt() is variadic like curl_easy_setopt() above, but
-- (unlike curl_easy_getinfo/curl_multi_perform's own output-pointer
-- trouble) every argument here is a plain input value libcurl reads,
-- never a pointer libcurl writes through -- the same shape
-- curl_easy_setopt's own three overloads already bind directly and
-- run correctly on all three backends. Only CURLSHOPT_SHARE/
-- CURLSHOPT_UNSHARE (an int curl_lock_data value) are bound;
-- CURLSHOPT_LOCKFUNC/CURLSHOPT_UNLOCKFUNC/CURLSHOPT_USERDATA need a
-- callback, not bound (see TODO.md).
%foreign "C:curl_share_setopt,libcurl,curl/curl.h"
prim__curlShareSetoptInt : AnyPtr -> Int -> Int -> PrimIO Int

-- curl_share_strerror() returns `const char *`, same const-cast
-- reasoning as curl_easy_strerror above.
%foreign "C:curl_share_strerror,libcurl,curl/curl.h"
         "RefC:idris2curl_share_strerror,libcurl,idris2curl_compat.h"
         "RC2:idris2curl_share_strerror,libcurl,idris2curl_compat.h"
prim__curlShareStrerror : Int -> PrimIO String

%foreign "C:curl_mime_init,libcurl,curl/curl.h"
prim__curlMimeInit : AnyPtr -> PrimIO AnyPtr

%foreign "C:curl_mime_free,libcurl,curl/curl.h"
prim__curlMimeFree : AnyPtr -> PrimIO ()

%foreign "C:curl_mime_addpart,libcurl,curl/curl.h"
prim__curlMimeAddpart : AnyPtr -> PrimIO AnyPtr

%foreign "C:curl_mime_name,libcurl,curl/curl.h"
prim__curlMimeName : AnyPtr -> String -> PrimIO Int

%foreign "C:curl_mime_filename,libcurl,curl/curl.h"
prim__curlMimeFilename : AnyPtr -> String -> PrimIO Int

%foreign "C:curl_mime_type,libcurl,curl/curl.h"
prim__curlMimeType : AnyPtr -> String -> PrimIO Int

-- curl_mime_data()'s own `datasize` (`size_t`, 64-bit) does NOT get
-- curl/curl.h's own CURL_ZERO_TERMINATED sentinel (`(size_t)-1`) --
-- deliberately: `-1 : Int` maps to a 32-bit C `int` under the Chez
-- backend specifically (`Compiler.Scheme.Chez`'s own `cftySpec CFInt
-- = "int"`; RefC/rc2 both treat `Int` as 64-bit, so this only bites
-- Chez), and a 32-bit `-1` doesn't sign-extend into a 64-bit
-- `(size_t)-1` consistently across calling conventions, landing on
-- some huge-but-wrong value instead -- confirmed directly: this
-- crashed with "invalid memory reference" under Chez specifically
-- (libcurl reading `datasize` bytes past a 5-byte string). Switching
-- the type to `Int64` "fixes" Chez (its own 64-bit two's-complement
-- bit pattern for -1 is genuinely all-ones everywhere) but isn't
-- viable either: RefC's own FFI type table has no `Int64` case at
-- all, crashing with "Unknown FFI type in C backend" at compile time.
-- `curlMimeData` (Network.Curl.Raw below) sidesteps both problems by
-- always passing the string's own real byte length
-- (`Data.Buffer.stringByteLength`) instead of the sentinel -- a small
-- positive value reads identically whether the backend treats it as
-- a 32-bit or 64-bit integer, so which one `Int` happens to map to
-- here stops mattering.
%foreign "C:curl_mime_data,libcurl,curl/curl.h"
prim__curlMimeData : AnyPtr -> String -> Int -> PrimIO Int

%foreign "C:curl_mime_filedata,libcurl,curl/curl.h"
prim__curlMimeFiledata : AnyPtr -> String -> PrimIO Int

%foreign "C:curl_mime_headers,libcurl,curl/curl.h"
prim__curlMimeHeaders : AnyPtr -> AnyPtr -> Int -> PrimIO Int

%foreign "C:curl_easy_pause,libcurl,curl/curl.h"
prim__curlEasyPause : AnyPtr -> Int -> PrimIO Int

%foreign "C:curl_easy_upkeep,libcurl,curl/curl.h"
prim__curlEasyUpkeep : AnyPtr -> PrimIO Int

-- curl_easy_header()'s own last argument is a write-through output
-- pointer -- see idris2curl_easy_header's own doc comment
-- (idris2curl_compat.h) for why it's collapsed via a csrc/ shim,
-- RefC/rc2-only, same reasoning as curl_easy_getinfo
-- (doc/variadic-getinfo.md).
%foreign "RefC:idris2curl_easy_header,libcurl,idris2curl_compat.h"
         "RC2:idris2curl_easy_header,libcurl,idris2curl_compat.h"
prim__curlEasyHeader : AnyPtr -> String -> Int -> Int -> PrimIO AnyPtr

-- curl_easy_nextheader() itself takes only plain input
-- arguments/returns a pointer directly (no output-pointer trouble),
-- so -- unlike curl_easy_header just above -- this binds directly on
-- all three backends. Reading the curl_header* it returns still needs
-- idris2curl_header_name/value below (RefC/rc2-only, same struct-field
-- reasoning as curl_version_info/CURLMsg).
%foreign "C:curl_easy_nextheader,libcurl,curl/curl.h"
prim__curlEasyNextheader : AnyPtr -> Int -> Int -> AnyPtr -> PrimIO AnyPtr

%foreign "RefC:idris2curl_header_name,libcurl,idris2curl_compat.h"
         "RC2:idris2curl_header_name,libcurl,idris2curl_compat.h"
prim__curlHeaderName : AnyPtr -> PrimIO String

%foreign "RefC:idris2curl_header_value,libcurl,idris2curl_compat.h"
         "RC2:idris2curl_header_value,libcurl,idris2curl_compat.h"
prim__curlHeaderValue : AnyPtr -> PrimIO String

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

export
curlEasyGetinfoOfft : HasIO io => AnyPtr -> CURLINFO -> io Int64
curlEasyGetinfoOfft h (MkCURLINFO i) = primIO (prim__curlEasyGetinfoOfft h i)

||| Opaque `struct curl_slist *` -- read via `curlSlistToList`,
||| released via `curlSlistFreeAll` once done (caller-owned, unlike
||| every other `curlEasyGetinfo*` tag here -- see
||| `idris2curl_getinfo_slist`'s own doc comment, idris2curl_compat.h).
export
curlEasyGetinfoSlist : HasIO io => AnyPtr -> CURLINFO -> io AnyPtr
curlEasyGetinfoSlist h (MkCURLINFO i) = primIO (prim__curlEasyGetinfoSlist h i)

export
curlEasyGetinfoSocket : HasIO io => AnyPtr -> CURLINFO -> io Int
curlEasyGetinfoSocket h (MkCURLINFO i) = primIO (prim__curlEasyGetinfoSocket h i)

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

||| Copies each node's own `data` field into a fresh `List String` via
||| `Data.String.FFI.ptrToString`'s bare copy -- see
||| `idris2curl_slist_data`'s own doc comment (idris2curl_compat.h) for
||| why no `curl_free`/GC registration happens per node here (ownership
||| belongs to the list as a whole). Does not consume or free `list`
||| itself -- release it with `curlSlistFreeAll` once done reading.
export
curlSlistToList : HasIO io => AnyPtr -> io (List String)
curlSlistToList list =
    if prim__nullAnyPtr list /= 0
       then pure []
       else do
           d <- primIO (prim__curlSlistData list)
           n <- primIO (prim__curlSlistNext list)
           rest <- curlSlistToList n
           pure $ case ptrToString d of
                       Nothing => rest
                       Just s => s :: rest

||| Wraps a non-NULL libcurl-allocated `char *` in a `GCAnyPtr` keyed
||| to `curl_free`, then reads it back leak-free through
||| `prim__curlGetStringGC`. Only safe on backends where a %foreign
||| call's own return value is packed into a boxed Idris value
||| *before* that same call's GCPtr-typed arguments are dropped --
||| true for Chez (tracing GC, no synchronous mid-call finalizer to
||| begin with) and rc2 (idris2-rc-cg commit 2aa9b90), not yet for
||| real upstream RefC. Callers branch on `codegen` themselves rather
||| than this function doing it, since the *whole* alternative call
||| (a differently-typed %foreign binding, not just this read step)
||| differs per backend -- see `curlEasyEscape`.
export
curlReadAndFree : HasIO io => AnyPtr -> io String
curlReadAndFree raw = do
    gcptr <- onCollectAny raw (\p => primIO (prim__curlFree p))
    primIO (prim__curlGetStringGC gcptr)

||| `Nothing` on the same "libcurl itself reports an error" contract as
||| `curl_easy_escape(3)` (`Nothing` for both allocation failure and a
||| `length` too large to represent as the underlying `int`). Leak-free
||| on Chez/rc2, small bounded leak on RefC -- see
||| `prim__curlEasyEscapeLeaky`'s own doc comment.
export
curlEasyEscape : HasIO io => AnyPtr -> String -> io (Maybe String)
curlEasyEscape h s =
    if codegen == "refc"
       then do
           r <- primIO (prim__curlEasyEscapeLeaky h s 0)
           pure $ if r == "" then Nothing else Just r
       else do
           raw <- primIO (prim__curlEasyEscapeRaw h s 0)
           if prim__nullAnyPtr raw /= 0
              then pure Nothing
              else Just <$> curlReadAndFree raw

||| Same leak-free-on-Chez/rc2, leaky-on-RefC split as `curlEasyEscape`.
export
curlEasyUnescape : HasIO io => AnyPtr -> String -> io (Maybe String)
curlEasyUnescape h s =
    if codegen == "refc"
       then do
           r <- primIO (prim__curlEasyUnescapeLeaky h s 0 prim__getNullAnyPtr)
           pure $ if r == "" then Nothing else Just r
       else do
           raw <- primIO (prim__curlEasyUnescapeRaw h s 0 prim__getNullAnyPtr)
           if prim__nullAnyPtr raw /= 0
              then pure Nothing
              else Just <$> curlReadAndFree raw

export
curlVersion : HasIO io => io String
curlVersion = primIO prim__curlVersion

||| RefC/rc2-only, no Chez binding -- see `prim__curlVersionInfoVersion`'s
||| own doc comment.
export
curlVersionInfoVersion : HasIO io => io String
curlVersionInfoVersion = primIO prim__curlVersionInfoVersion

||| RefC/rc2-only, same as `curlVersionInfoVersion`.
export
curlVersionInfoVersionNum : HasIO io => io Int
curlVersionInfoVersionNum = primIO prim__curlVersionInfoVersionNum

||| RefC/rc2-only, same as `curlVersionInfoVersion`.
export
curlVersionInfoHost : HasIO io => io String
curlVersionInfoHost = primIO prim__curlVersionInfoHost

||| RefC/rc2-only, same as `curlVersionInfoVersion`. See
||| curl/curl.h's own `CURL_VERSION_*` bit flags (`CURL_VERSION_SSL`,
||| `CURL_VERSION_HTTP2`, ...) to test against the result.
export
curlVersionInfoFeatures : HasIO io => io Int
curlVersionInfoFeatures = primIO prim__curlVersionInfoFeatures

||| RefC/rc2-only, same as `curlVersionInfoVersion`. `Nothing` when
||| libcurl was built without SSL support -- a genuine, documented
||| `NULL` (`curl_version_info(3)`), not collapsed away like
||| `curlVersionInfoVersion`/`Host` above.
export
curlVersionInfoSslVersion : HasIO io => io (Maybe String)
curlVersionInfoSslVersion = do
    raw <- primIO prim__curlVersionInfoSslVersion
    pure (ptrToString raw)

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
||| comment on `prim__curlUrlGetRaw` and `doc/variadic-getinfo.md`-style
||| reasoning (the underlying shim is `static inline`, unreachable
||| under Chez's own dynamic FFI). `flags` -- see `curlUrlSet`'s own
||| doc comment. `Nothing` on a `curl_url_get` failure, `Just` (with a
||| possibly-empty `String`) otherwise -- distinguishable because
||| `idris2curl_url_get_raw` hands back NULL only on failure. Read back
||| leak-free via `curlReadAndFree`'s GCAnyPtr on rc2; on RefC, via
||| `Data.String.FFI.ptrToString`'s bare (non-GC, non-freeing) copy
||| instead, since real upstream RefC's own createCFunctions has a
||| packCFType-vs-argument-drop ordering bug that makes reading a
||| GCAnyPtr back unsafe there (see idris2-rc-cg's TODO.md, commit
||| 2aa9b90, which fixed the identical bug on rc2) -- one URL part's
||| worth of leaked bytes per call on RefC only, same accepted leak as
||| before this function distinguished empty from failure.
export
curlUrlGet : HasIO io => AnyPtr -> CURLUPart -> Int -> io (Maybe String)
curlUrlGet u (MkCURLUPart p) flags = do
    raw <- primIO (prim__curlUrlGetRaw u p flags)
    if codegen == "refc"
       then pure (ptrToString raw)
       else if prim__nullAnyPtr raw /= 0
               then pure Nothing
               else Just <$> curlReadAndFree raw

export
curlUrlStrerror : HasIO io => CURLUcode -> io String
curlUrlStrerror (MkCURLUcode c) = primIO (prim__curlUrlStrerror c)

||| `Nothing` on the same allocation-failure contract as `curlEasyInit`
||| (`curl_multi_init(3)`).
export
curlMultiInit : HasIO io => io (Maybe AnyPtr)
curlMultiInit = do
    m <- primIO prim__curlMultiInit
    pure $ if prim__nullAnyPtr m /= 0 then Nothing else Just m

export
curlMultiCleanup : HasIO io => AnyPtr -> io CURLMcode
curlMultiCleanup m = MkCURLMcode <$> primIO (prim__curlMultiCleanup m)

export
curlMultiAddHandle : HasIO io => AnyPtr -> AnyPtr -> io CURLMcode
curlMultiAddHandle m h = MkCURLMcode <$> primIO (prim__curlMultiAddHandle m h)

export
curlMultiRemoveHandle : HasIO io => AnyPtr -> AnyPtr -> io CURLMcode
curlMultiRemoveHandle m h = MkCURLMcode <$> primIO (prim__curlMultiRemoveHandle m h)

export
curlMultiStrerror : HasIO io => CURLMcode -> io String
curlMultiStrerror (MkCURLMcode c) = primIO (prim__curlMultiStrerror c)

||| RefC/rc2-only, no Chez binding -- see `prim__curlMultiPerform`'s own
||| doc comment. Number of easy handles still transferring data, or
||| `Nothing` if `curl_multi_perform` itself reported an error
||| (`idris2curl_multi_perform`'s own collapsed `-1`, indistinguishable
||| from `CURLMcode` here -- acceptable since the running-handle count
||| the caller actually needs either way is only meaningful on success).
export
curlMultiPerform : HasIO io => AnyPtr -> io (Maybe Int)
curlMultiPerform m = do
    n <- primIO (prim__curlMultiPerform m)
    pure $ if n < 0 then Nothing else Just n

||| RefC/rc2-only, same as `curlMultiPerform`. `timeoutMs` -- how long
||| to block waiting for activity on any handle in `m`'s own stack
||| before returning regardless (`curl_multi_wait(3)`); the number of
||| fds that were actually signalled, or `Nothing` on the same
||| collapsed-error contract as `curlMultiPerform`.
export
curlMultiWait : HasIO io => AnyPtr -> (timeoutMs : Int) -> io (Maybe Int)
curlMultiWait m timeoutMs = do
    n <- primIO (prim__curlMultiWait m timeoutMs)
    pure $ if n < 0 then Nothing else Just n

||| RefC/rc2-only, no Chez binding -- see `prim__curlMultiInfoRead`'s
||| own doc comment. `Nothing` once the message queue is empty (the
||| ordinary, expected way this loop ends -- not an error).
||| `(CURLMSG, AnyPtr, CURLcode)` is `(what kind of message, which easy
||| handle it's about, that handle's own result -- only meaningful when
||| the message is `curlmsg_DONE`, see `prim__curlMultimsgResult`'s own
||| doc comment)`.
export
curlMultiInfoRead : HasIO io => AnyPtr -> io (Maybe (CURLMSG, AnyPtr, CURLcode))
curlMultiInfoRead m = do
    msg <- primIO (prim__curlMultiInfoRead m)
    if prim__nullAnyPtr msg /= 0
       then pure Nothing
       else do
         what <- primIO (prim__curlMultimsgMsg msg)
         h <- primIO (prim__curlMultimsgEasyHandle msg)
         result <- primIO (prim__curlMultimsgResult msg)
         pure $ Just (MkCURLMSG what, h, MkCURLcode result)

||| `Nothing` on the same allocation-failure contract as `curlEasyInit`
||| (`curl_share_init(3)`).
export
curlShareInit : HasIO io => io (Maybe AnyPtr)
curlShareInit = do
    sh <- primIO prim__curlShareInit
    pure $ if prim__nullAnyPtr sh /= 0 then Nothing else Just sh

export
curlShareCleanup : HasIO io => AnyPtr -> io CURLSHcode
curlShareCleanup sh = MkCURLSHcode <$> primIO (prim__curlShareCleanup sh)

||| Configures `sh` itself to share (`CURLSHOPT_SHARE`) or stop sharing
||| (`CURLSHOPT_UNSHARE`) one kind of state -- `sh` must still be
||| attached to each easy handle that should actually use it, via
||| `curlEasySetoptSlist h curlopt_SHARE sh` (`curlopt_SHARE`,
||| `Network.Curl.Types`). `share` -- `True` for `CURLSHOPT_SHARE`,
||| `False` for `CURLSHOPT_UNSHARE` (curl/curl.h's own
||| `CURLSHOPT_SHARE = 1`, `CURLSHOPT_UNSHARE = 2`, so `1`/`2` isn't
||| hard-coded here as some unexplained magic number).
export
curlShareSetopt : HasIO io => AnyPtr -> (share : Bool) -> CurlLockData -> io CURLSHcode
curlShareSetopt sh share (MkCurlLockData d) =
    MkCURLSHcode <$> primIO (prim__curlShareSetoptInt sh (if share then 1 else 2) d)

export
curlShareStrerror : HasIO io => CURLSHcode -> io String
curlShareStrerror (MkCURLSHcode c) = primIO (prim__curlShareStrerror c)

||| `Nothing` on the same allocation-failure contract as `curlEasyInit`
||| (`curl_mime_init(3)`). `h` is the easy handle the resulting mime
||| structure will eventually be attached to via
||| `curlEasySetoptSlist h curlopt_MIMEPOST mime` -- required even
||| though a mime handle isn't tied to any one easy handle's own data,
||| just used to allocate memory the same way the easy handle itself
||| does (`curl_mime_init(3)`'s own contract).
export
curlMimeInit : HasIO io => AnyPtr -> io (Maybe AnyPtr)
curlMimeInit h = do
    mime <- primIO (prim__curlMimeInit h)
    pure $ if prim__nullAnyPtr mime /= 0 then Nothing else Just mime

||| Only needed if `mime` is never attached via `CURLOPT_MIMEPOST` (or
||| after removing it again with `curlEasySetoptSlist h curlopt_MIMEPOST
||| curlSlistEmpty`) -- `curl_easy_cleanup`/`curl_easy_reset` already
||| free a still-attached mime structure on their own
||| (`curl_mime_free(3)`).
export
curlMimeFree : HasIO io => AnyPtr -> io ()
curlMimeFree mime = primIO (prim__curlMimeFree mime)

||| `Nothing` on the same allocation-failure contract as `curlEasyInit`
||| (`curl_mime_addpart(3)`).
export
curlMimeAddpart : HasIO io => AnyPtr -> io (Maybe AnyPtr)
curlMimeAddpart mime = do
    part <- primIO (prim__curlMimeAddpart mime)
    pure $ if prim__nullAnyPtr part /= 0 then Nothing else Just part

export
curlMimeName : HasIO io => AnyPtr -> String -> io CURLcode
curlMimeName part name = MkCURLcode <$> primIO (prim__curlMimeName part name)

export
curlMimeFilename : HasIO io => AnyPtr -> String -> io CURLcode
curlMimeFilename part filename = MkCURLcode <$> primIO (prim__curlMimeFilename part filename)

export
curlMimeType : HasIO io => AnyPtr -> String -> io CURLcode
curlMimeType part mimetype = MkCURLcode <$> primIO (prim__curlMimeType part mimetype)

||| Sets `part`'s own data straight from an in-memory `String` --
||| see `prim__curlMimeData`'s own doc comment for why its own real
||| UTF-8 byte length (`Data.Buffer.stringByteLength`) is passed
||| explicitly rather than a "NUL-terminated, compute it yourself"
||| sentinel, and so no separate length parameter is exposed here.
export
curlMimeData : HasIO io => AnyPtr -> String -> io CURLcode
curlMimeData part data_ = MkCURLcode <$> primIO (prim__curlMimeData part data_ (stringByteLength data_))

export
curlMimeFiledata : HasIO io => AnyPtr -> String -> io CURLcode
curlMimeFiledata part filename = MkCURLcode <$> primIO (prim__curlMimeFiledata part filename)

||| `takeOwnership` -- `True` if `headers` should be freed by libcurl
||| itself once `part`'s own mime structure is freed (`curl_free_all`
||| is never called by the caller in that case); `False` if the caller
||| keeps ownership and must `curlSlistFreeAll` it itself afterwards
||| (`curl_mime_headers(3)`'s own `take_ownership` contract).
export
curlMimeHeaders : HasIO io => AnyPtr -> AnyPtr -> (takeOwnership : Bool) -> io CURLcode
curlMimeHeaders part headers takeOwnership =
    MkCURLcode <$> primIO (prim__curlMimeHeaders part headers (if takeOwnership then 1 else 0))

||| `action` -- see `Network.Curl.Types`'s own `curlpause_*` bitmask
||| constants, OR'd together with `Data.Bits`'s own `.|.` for more than
||| one of `curlpause_RECV`/`curlpause_SEND` at once.
export
curlEasyPause : HasIO io => AnyPtr -> (action : Int) -> io CURLcode
curlEasyPause h action = MkCURLcode <$> primIO (prim__curlEasyPause h action)

export
curlEasyUpkeep : HasIO io => AnyPtr -> io CURLcode
curlEasyUpkeep h = MkCURLcode <$> primIO (prim__curlEasyUpkeep h)

||| RefC/rc2-only, no Chez binding -- see `prim__curlEasyHeader`'s own
||| doc comment. `Nothing` on `CURLHE_MISSING`/any other non-OK
||| `CURLHcode` (`idris2curl_easy_header`'s own collapsed `NULL`,
||| indistinguishable from a genuine "no such header" here -- the
||| distinction isn't useful to a caller either way, both mean "this
||| header isn't present"). `origin` -- see `curlh_HEADER`; `request`
||| -- which numbered request this concerns (`0` for the initial one).
export
curlEasyHeader : HasIO io => AnyPtr -> (name : String) -> (origin : Int) -> (request : Int) -> io (Maybe (String, String))
curlEasyHeader h name origin request = do
    hdr <- primIO (prim__curlEasyHeader h name origin request)
    if prim__nullAnyPtr hdr /= 0
       then pure Nothing
       else do
         n <- primIO (prim__curlHeaderName hdr)
         v <- primIO (prim__curlHeaderValue hdr)
         pure $ Just (n, v)

||| RefC/rc2-only, same as `curlEasyHeader`. `prev` -- `curlSlistEmpty`
||| to start iterating from the first header, or a previous call's own
||| result (the raw pointer, not the `(String, String)` pair
||| `curlEasyHeader`/this function's own wrapper hands back -- see
||| `examples/Header.idr` for the iteration pattern) to continue.
||| `Nothing` once iteration reaches the end -- the ordinary, expected
||| way this loop ends, not an error.
export
curlEasyNextheader : HasIO io => AnyPtr -> (origin : Int) -> (request : Int) -> (prev : AnyPtr) -> io (Maybe (AnyPtr, String, String))
curlEasyNextheader h origin request prev = do
    hdr <- primIO (prim__curlEasyNextheader h origin request prev)
    if prim__nullAnyPtr hdr /= 0
       then pure Nothing
       else do
         n <- primIO (prim__curlHeaderName hdr)
         v <- primIO (prim__curlHeaderValue hdr)
         pure $ Just (hdr, n, v)
