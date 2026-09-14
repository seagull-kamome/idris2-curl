module Network.Curl.Raw

-- Copyright 2026, Hattori,Hiroki. All rights reserved.
-- This module was licensed by BSD3.

-- Direct libcurl FFI declarations -- one `%foreign` per bound
-- function, no Struct/getField, no derived instances. Just enough to
-- exercise curl_easy's "init, setopt, perform, cleanup" lifecycle.

import Data.Buffer
import Data.String.FFI
import Data.TextBuffer
import System.FFI
import System.IO.MemStream as MemStream

import Network.Curl.Types

------------------------------------------------------------------------
-- Global init/cleanup
------------------------------------------------------------------------

%foreign "C:curl_global_init,libcurl,curl/curl.h"
prim__curlGlobalInit : Int -> PrimIO Int

%foreign "C:curl_global_cleanup,libcurl,curl/curl.h"
prim__curlGlobalCleanup : PrimIO ()

------------------------------------------------------------------------
-- Easy handle lifecycle
------------------------------------------------------------------------

%foreign "C:curl_easy_init,libcurl,curl/curl.h"
prim__curlEasyInit : PrimIO AnyPtr

%foreign "C:curl_easy_cleanup,libcurl,curl/curl.h"
prim__curlEasyCleanup : AnyPtr -> PrimIO ()

%foreign "C:curl_easy_setopt,libcurl,curl/curl.h"
prim__curlEasySetoptString : AnyPtr -> Int -> String -> PrimIO Int

%foreign "C:curl_easy_setopt,libcurl,curl/curl.h"
prim__curlEasySetoptLong : AnyPtr -> Int -> Int -> PrimIO Int

-- Same `curl_easy_setopt` C symbol, this overload's own third argument
-- typed for any object-pointer option whose value is a raw pointer,
-- not a `String`/`Int` -- a `curl_slist *` (CURLOPT_HTTPHEADER,
-- CURLOPT_SHARE, ...), a `curl_mime *` (CURLOPT_MIMEPOST), or any
-- other `void *`-valued option (e.g. CURLOPT_WRITEDATA, see
-- curlEasyPerformToBuffer's own doc comment).
%foreign "C:curl_easy_setopt,libcurl,curl/curl.h"
prim__curlEasySetoptPointer : AnyPtr -> Int -> AnyPtr -> PrimIO Int

%foreign "C:curl_easy_perform,libcurl,curl/curl.h"
prim__curlEasyPerform : AnyPtr -> PrimIO Int

%foreign "C:curl_easy_duphandle,libcurl,curl/curl.h"
prim__curlEasyDuphandle : AnyPtr -> PrimIO AnyPtr

%foreign "C:curl_easy_reset,libcurl,curl/curl.h"
prim__curlEasyReset : AnyPtr -> PrimIO ()

------------------------------------------------------------------------
-- curl_slist
------------------------------------------------------------------------

%foreign "C:curl_slist_append,libcurl,curl/curl.h"
prim__curlSlistAppend : AnyPtr -> String -> PrimIO AnyPtr

%foreign "C:curl_slist_free_all,libcurl,curl/curl.h"
prim__curlSlistFreeAll : AnyPtr -> PrimIO ()

------------------------------------------------------------------------
-- Error strings
------------------------------------------------------------------------

-- curl_easy_strerror returns `const char *`; rc2's own %foreign
-- lowering hardcodes CFString as non-const `char *`, which collides
-- with -Werror -Wdiscarded-qualifiers on a direct binding. Chez has no
-- such issue -- dynamically typed, no C-level qualifier to discard --
-- so only rc2 routes through idris2curl_compat.h's `static inline`
-- shim (zero call overhead: the cast, not a real wrapper call, is the
-- point); Chez keeps calling curl_easy_strerror directly, since the
-- shim only exists as a real symbol under static linking, never in
-- libcurl.so's own dynamic-load table.
--
-- Two %foreign targets pick the right one per backend: rc2's own FFI
-- target tags are `["RC2", "RefC", "C"]` (`Compiler.RC2.Emit`'s own
-- `ffiTags`, checked in that order) so `"RC2:..."` wins there; Chez's
-- own target list (`["scheme,chez", "scheme", ..., "C"]`) matches
-- neither and falls through to the plain `"C:..."` entry.
%foreign "C:curl_easy_strerror,libcurl,curl/curl.h"
         "RC2:idris2curl_easy_strerror,libcurl,idris2curl_compat.h"
prim__curlEasyStrerror : Int -> PrimIO String

------------------------------------------------------------------------
-- curl_easy_getinfo
------------------------------------------------------------------------

-- curl_easy_getinfo() is variadic (the real C signature takes a
-- write-through output pointer whose type depends on the CURLINFO);
-- %foreign can't express that at all, so there's no plain "C:..."
-- target here -- Chez has no shim to fall back to (see
-- idris2curl_compat.h's own doc comment on why this shim can only
-- exist under static linking), and fails cleanly with "was not
-- accepted by any backend" at the one call site that actually needs
-- one, rather than breaking every Chez build of this library.
%foreign "RC2:idris2curl_getinfo_long,libcurl,idris2curl_compat.h"
prim__curlEasyGetinfoLong : AnyPtr -> Int -> PrimIO Int

%foreign "RC2:idris2curl_getinfo_string,libcurl,idris2curl_compat.h"
prim__curlEasyGetinfoString : AnyPtr -> Int -> PrimIO String

%foreign "RC2:idris2curl_getinfo_double,libcurl,idris2curl_compat.h"
prim__curlEasyGetinfoDouble : AnyPtr -> Int -> PrimIO Double

-- `Int64`, not `Int` -- `curl_off_t` is always a real 64-bit signed
-- integer in libcurl, regardless of the host platform's own `long`
-- width; see idris2curl_getinfo_offt's own doc comment
-- (idris2curl_compat.h) for the matching `int64_t` C-side return type.
-- rc2-only, same "static inline, static linking only" reasoning as
-- every other getinfo tag here -- no Chez binding.
%foreign "RC2:idris2curl_getinfo_offt,libcurl,idris2curl_compat.h"
prim__curlEasyGetinfoOfft : AnyPtr -> Int -> PrimIO Int64

-- `struct curl_slist` itself (curl/curl.h: `{ char *data; struct
-- curl_slist *next; }`) -- bound via `Struct`/`getField` (same `%cg
-- rc2 externStruct=<name>` mechanism `VersionInfoPtr` below uses),
-- rather than a shim per field. Unlike `curl_version_info_data`, both
-- of the real struct's fields are bound here, in the real struct's
-- own declaration order, so there's no partial-field-list offset
-- mismatch to worry about -- see doc/version-info-struct.md's own
-- "`curl_slist`" section.
--
-- Must be declared before prim__curlEasyGetinfoSlist below, and that
-- declaration's own use of SlistPtr must stay *reachable* in whatever
-- program actually gets compiled -- rc2's `RStructGet` codegen only
-- knows a struct name once Emit.idr has walked an actual `%foreign`
-- declaration typed with it, and that walk only reaches definitions
-- the compiled program's own call graph still includes after dead-
-- code elimination. Confirmed the hard way: a scratch program that
-- built and read back a `curl_slist` purely through
-- curlSlistAppend/curlSlistToList, never calling
-- curlEasyGetinfoSlist at all, failed with "INTERNAL ERROR: [rc2]
-- RStructGet: unknown struct curl_slist" even though SlistPtr is
-- declared right here at module scope -- only adding a real call to
-- curlEasyGetinfoSlist somewhere in that same program fixed it. Every
-- real caller of curlSlistToList in this repo already goes through
-- curlEasyGetinfoSlist first (GetInfo.idr's own COOKIELIST read), so
-- this doesn't bite today -- but a hypothetical future program that
-- only ever builds slists (curlSlistAppend) and never reads one back
-- via curl_easy_getinfo would hit this. Nothing else in this module
-- mentions SlistPtr in a %foreign signature.
%cg rc2 externStruct=curl_slist

SlistPtr : Type
SlistPtr = Struct "curl_slist" [ ("data", AnyPtr), ("next", AnyPtr) ]

-- Opaque `struct curl_slist *` handle -- read via curlSlistToList
-- below, released via curlSlistFreeAll once done (see
-- idris2curl_getinfo_slist's own doc comment, idris2curl_compat.h, for
-- why this tag's value is caller-owned unlike every other getinfo tag
-- here). Typed `SlistPtr`, not `AnyPtr`, purely so this declaration is
-- the one that registers `curl_slist` with rc2 (see `SlistPtr`'s own
-- doc comment above) -- `curlEasyGetinfoSlist` below casts straight
-- back to `AnyPtr`, the type every other slist-handling function in
-- this module still uses.
%foreign "RC2:idris2curl_getinfo_slist,libcurl,idris2curl_compat.h"
prim__curlEasyGetinfoSlist : AnyPtr -> Int -> PrimIO SlistPtr

-- `curl_socket_t` is a plain C `int` on every non-Windows platform
-- (curl/curl.h's own typedef), an exact fit for Idris2's `Int`.
%foreign "RC2:idris2curl_getinfo_socket,libcurl,idris2curl_compat.h"
prim__curlEasyGetinfoSocket : AnyPtr -> Int -> PrimIO Int

------------------------------------------------------------------------
-- Escape/unescape
------------------------------------------------------------------------

-- curl_easy_escape/curl_easy_unescape/curl_free: all return/take a
-- plain (non-const) `char *`/`void *`, so no const-cast shim is
-- needed here unlike curl_easy_strerror above. The escaped/unescaped
-- result is libcurl's own fresh allocation, meant to be released with
-- curl_free() once read -- the raw `AnyPtr` is handed back untouched
-- so curlReadAndFree below can wrap it in a GCAnyPtr keyed to
-- curl_free and read it back leak-free, on both remaining backends.
-- curl_easy_unescape's own fourth argument (`int *outlength`) is
-- passed NULL -- always safe per curl_easy_unescape(3) when the
-- caller only needs the NUL-terminated string result, not a decoded
-- length that could itself embed a NUL byte.
%foreign "C:curl_easy_escape,libcurl,curl/curl.h"
prim__curlEasyEscapeRaw : AnyPtr -> String -> Int -> PrimIO AnyPtr

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

------------------------------------------------------------------------
-- Version / curl_version_info
------------------------------------------------------------------------

%foreign "C:curl_version,libcurl,curl/curl.h"
prim__curlVersion : PrimIO String

-- curl_version_info() returns curl_version_info_data* -- a real C
-- struct (curl/curl.h), not a scalar %foreign can hand back directly.
-- Bound via System.FFI's own Struct/getField now that rc2's own
-- `%cg rc2 externStruct=<name>` directive (idris2-rc-cg's
-- rc2/doc/directives.md) exists to suppress rc2's own conflicting
-- `typedef struct` for a name curl/curl.h already typedefs itself --
-- see doc/version-info-struct.md for the full history (an
-- externStruct-less attempt at exactly this was tried and rejected
-- first). rc2-only regardless: getField/setField's own C-struct-
-- backed implementation has no Chez equivalent here (Chez's own
-- Struct/getField goes through a from-scratch `define-ftype`
-- computed from this same field list rather than the real header's
-- own layout -- safe only for a struct this repo defines itself, not
-- one reflecting into curl/curl.h, so not attempted).
--
-- Deliberately only the same 5 fields the pre-Struct/getField shim
-- design bound (version/version_num/host/features/ssl_version) --
-- NOT the full ~25-field struct. A first attempt at binding every
-- non-array field OOM-crashed idris2 itself at compile time (observed
-- directly, not a guess -- `out of memory`/SIGABRT under Chez, with a
-- 6GB `ulimit -v` in place): upstream `System.FFI`'s `getField`
-- elaboration doesn't scale to a struct this wide. See
-- doc/version-info-struct.md for the full story and where the actual
-- field-count wall is (not yet bisected). `age`/`libz_version`/every
-- field added after `CURLVERSION_FIRST`, and the `protocols`/
-- `feature_names` string arrays remain unbound.
%cg rc2 externStruct=curl_version_info_data

VersionInfoPtr : Type
VersionInfoPtr = Struct "curl_version_info_data"
    [ ("version", String)
    , ("version_num", Int)
    , ("host", String)
    , ("features", Int)
    , ("ssl_version", AnyPtr)
    ]

%foreign "C:curl_version_info,libcurl,curl/curl.h"
prim__curlVersionInfo : Int -> PrimIO VersionInfoPtr

------------------------------------------------------------------------
-- URL API
------------------------------------------------------------------------

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
-- all. rc2-only, no Chez binding -- see doc/variadic-getinfo.md-style
-- reasoning, `prim__curlEasyGetinfoString`'s own doc comment above.
%foreign "RC2:idris2curl_url_get_raw,libcurl,idris2curl_compat.h"
prim__curlUrlGetRaw : AnyPtr -> Int -> Int -> PrimIO AnyPtr

-- curl_url_strerror() returns `const char *`, same const-cast
-- reasoning as curl_easy_strerror above.
%foreign "C:curl_url_strerror,libcurl,curl/curl.h"
         "RC2:idris2curl_url_strerror,libcurl,idris2curl_compat.h"
prim__curlUrlStrerror : Int -> PrimIO String

------------------------------------------------------------------------
-- Multi interface
------------------------------------------------------------------------

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
         "RC2:idris2curl_multi_strerror,libcurl,idris2curl_compat.h"
prim__curlMultiStrerror : Int -> PrimIO String

-- curl_multi_perform()/curl_multi_wait()/curl_multi_info_read() each
-- take a write-through output-pointer argument %foreign can't express
-- cleanly (an int count, or -- for info_read -- a CURLMsg* result
-- alongside a count) -- see idris2curl_multi_perform/multi_wait/
-- multi_info_read's own doc comments (idris2curl_compat.h) for how
-- each is collapsed to a plain return. rc2-only, no Chez binding,
-- same reasoning as curl_easy_getinfo (doc/variadic-getinfo.md).
%foreign "RC2:idris2curl_multi_perform,libcurl,idris2curl_compat.h"
prim__curlMultiPerform : AnyPtr -> PrimIO Int

%foreign "RC2:idris2curl_multi_wait,libcurl,idris2curl_compat.h"
prim__curlMultiWait : AnyPtr -> Int -> PrimIO Int

%foreign "RC2:idris2curl_multi_info_read,libcurl,idris2curl_compat.h"
prim__curlMultiInfoRead : AnyPtr -> PrimIO AnyPtr

%foreign "RC2:idris2curl_multimsg_msg,libcurl,idris2curl_compat.h"
prim__curlMultimsgMsg : AnyPtr -> PrimIO Int

%foreign "RC2:idris2curl_multimsg_easy_handle,libcurl,idris2curl_compat.h"
prim__curlMultimsgEasyHandle : AnyPtr -> PrimIO AnyPtr

%foreign "RC2:idris2curl_multimsg_result,libcurl,idris2curl_compat.h"
prim__curlMultimsgResult : AnyPtr -> PrimIO Int

------------------------------------------------------------------------
-- Share interface
------------------------------------------------------------------------

%foreign "C:curl_share_init,libcurl,curl/curl.h"
prim__curlShareInit : PrimIO AnyPtr

%foreign "C:curl_share_cleanup,libcurl,curl/curl.h"
prim__curlShareCleanup : AnyPtr -> PrimIO Int

-- curl_share_setopt() is variadic like curl_easy_setopt() above, but
-- (unlike curl_easy_getinfo/curl_multi_perform's own output-pointer
-- trouble) every argument here is a plain input value libcurl reads,
-- never a pointer libcurl writes through -- the same shape
-- curl_easy_setopt's own three overloads already bind directly and
-- run correctly on both backends. Only CURLSHOPT_SHARE/
-- CURLSHOPT_UNSHARE (an int curl_lock_data value) are bound;
-- CURLSHOPT_LOCKFUNC/CURLSHOPT_UNLOCKFUNC/CURLSHOPT_USERDATA need a
-- callback, not bound (see TODO.md).
%foreign "C:curl_share_setopt,libcurl,curl/curl.h"
prim__curlShareSetoptInt : AnyPtr -> Int -> Int -> PrimIO Int

-- curl_share_strerror() returns `const char *`, same const-cast
-- reasoning as curl_easy_strerror above.
%foreign "C:curl_share_strerror,libcurl,curl/curl.h"
         "RC2:idris2curl_share_strerror,libcurl,idris2curl_compat.h"
prim__curlShareStrerror : Int -> PrimIO String

------------------------------------------------------------------------
-- Mime interface
------------------------------------------------------------------------

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
-- = "int"`; rc2 treats `Int` as 64-bit, so this only bites Chez), and
-- a 32-bit `-1` doesn't sign-extend into a 64-bit `(size_t)-1`
-- consistently across calling conventions, landing on some huge-but-
-- wrong value instead -- confirmed directly: this crashed with
-- "invalid memory reference" under Chez specifically (libcurl reading
-- `datasize` bytes past a 5-byte string). `curlMimeData`
-- (Network.Curl.Raw below) sidesteps the problem by
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

------------------------------------------------------------------------
-- Pause/upkeep
------------------------------------------------------------------------

%foreign "C:curl_easy_pause,libcurl,curl/curl.h"
prim__curlEasyPause : AnyPtr -> Int -> PrimIO Int

%foreign "C:curl_easy_upkeep,libcurl,curl/curl.h"
prim__curlEasyUpkeep : AnyPtr -> PrimIO Int

------------------------------------------------------------------------
-- Structured headers
------------------------------------------------------------------------

-- `struct curl_header` itself (curl/header.h: `{ char *name; char
-- *value; size_t amount; size_t index; unsigned int origin; void
-- *anchor; }`) -- bound via `Struct`/`getField` (same `%cg rc2
-- externStruct=<name>` mechanism `SlistPtr`/`VersionInfoPtr` use)
-- rather than a shim per field. All six of the real struct's fields
-- are listed here, in the real struct's own declaration order, even
-- though only `name`/`value` are ever read via `getField` below --
-- `amount`/`index`/`origin`/`anchor` exist purely so a from-scratch
-- Chez `define-ftype` computed from this list (see `SlistPtr`'s own
-- doc comment, and doc/version-info-struct.md's own caveat on
-- `VersionInfoPtr`, for why a *partial* field list is unsafe there)
-- lands on the real struct's actual byte layout rather than a wrong
-- one -- `curl_easy_nextheader` (below) has a real Chez `%foreign`
-- target, unlike `curl_easy_header`, so this one isn't reliably rc2-
-- only by construction the way `SlistPtr` currently is. `anchor` --
-- `void *`, curl/header.h's own comment on the field itself: "handle
-- privately used by libcurl" -- is listed for the same layout-only
-- reason, never read.
%cg rc2 externStruct=curl_header

HeaderPtr : Type
HeaderPtr = Struct "curl_header"
    [ ("name", String)
    , ("value", String)
    , ("amount", Bits64)
    , ("index", Bits64)
    , ("origin", Bits32)
    , ("anchor", AnyPtr)
    ]

-- curl_easy_header()'s own last argument is a write-through output
-- pointer -- see idris2curl_easy_header's own doc comment
-- (idris2curl_compat.h) for why it's collapsed via a csrc/ shim,
-- rc2-only, same reasoning as curl_easy_getinfo
-- (doc/variadic-getinfo.md). Typed `HeaderPtr`, not `AnyPtr`, so this
-- declaration registers `curl_header` with rc2 -- see `HeaderPtr`'s
-- own doc comment above, and `SlistPtr`'s own doc comment for why a
-- `%foreign` declaration has to actually stay *reachable*, not just
-- exist somewhere in the module, to do that.
%foreign "RC2:idris2curl_easy_header,libcurl,idris2curl_compat.h"
prim__curlEasyHeader : AnyPtr -> String -> Int -> Int -> PrimIO HeaderPtr

-- curl_easy_nextheader() itself takes only plain input
-- arguments/returns a pointer directly (no output-pointer trouble),
-- so -- unlike curl_easy_header just above -- this binds directly on
-- both backends. Also typed `HeaderPtr`, both as `prev` (curl_easy_
-- nextheader's own real signature takes `struct curl_header *prev`)
-- and as the return type -- independently sufficient to register
-- curl_header with rc2 whenever this declaration alone is reachable
-- (same reasoning as prim__curlEasyHeader above), not reliant on that
-- other declaration also being reachable in the same program.
%foreign "C:curl_easy_nextheader,libcurl,curl/curl.h"
prim__curlEasyNextheader : AnyPtr -> Int -> Int -> HeaderPtr -> PrimIO HeaderPtr

------------------------------------------------------------------------
-- Global init/cleanup
------------------------------------------------------------------------

||| `CURL_GLOBAL_ALL`, per curl/curl.h.
curlGlobalAll : Int
curlGlobalAll = 3

export
curlGlobalInit : HasIO io => io CURLcode
curlGlobalInit = MkCURLcode <$> primIO (prim__curlGlobalInit curlGlobalAll)

export
curlGlobalCleanup : HasIO io => io ()
curlGlobalCleanup = primIO prim__curlGlobalCleanup

------------------------------------------------------------------------
-- Easy handle lifecycle
------------------------------------------------------------------------

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

||| Any object-pointer-valued option -- a `curl_slist *`, a
||| `curl_mime *`, a `curl_share *`, a `FILE *`, ... -- see
||| `prim__curlEasySetoptPointer`'s own doc comment.
export
curlEasySetoptPointer : HasIO io => AnyPtr -> CURLoption -> AnyPtr -> io CURLcode
curlEasySetoptPointer h (MkCURLoption o) v = MkCURLcode <$> primIO (prim__curlEasySetoptPointer h o v)

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

------------------------------------------------------------------------
-- curl_easy_getinfo
------------------------------------------------------------------------

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
curlEasyGetinfoSlist h (MkCURLINFO i) = believe_me <$> primIO (prim__curlEasyGetinfoSlist h i)

export
curlEasyGetinfoSocket : HasIO io => AnyPtr -> CURLINFO -> io Int
curlEasyGetinfoSocket h (MkCURLINFO i) = primIO (prim__curlEasyGetinfoSocket h i)

------------------------------------------------------------------------
-- curl_slist
------------------------------------------------------------------------

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
||| `Data.String.FFI.ptrToString`'s bare copy -- no `curl_free`/GC
||| registration happens per node here, since ownership of every
||| node's own `data` belongs to the list as a whole. Does not consume
||| or free `list` itself -- release it with `curlSlistFreeAll` once
||| done reading. `believe_me`s `list` into `SlistPtr` to read its two
||| fields via `getField` -- safe per `SlistPtr`'s own doc comment
||| (same runtime representation, a raw pointer, as the `AnyPtr` this
||| function's own signature keeps using throughout).
export
curlSlistToList : HasIO io => AnyPtr -> io (List String)
curlSlistToList list =
    if prim__nullAnyPtr list /= 0
       then pure []
       else do
           let node = the SlistPtr (believe_me list)
               d = getField node "data"
               n = getField node "next"
           rest <- curlSlistToList n
           pure $ case ptrToString d of
                       Nothing => rest
                       Just s => s :: rest

------------------------------------------------------------------------
-- Escape/unescape
------------------------------------------------------------------------

||| Wraps a non-NULL libcurl-allocated `char *` in a `GCAnyPtr` keyed
||| to `curl_free`, then reads it back leak-free through
||| `prim__curlGetStringGC`. Safe on both remaining backends: a
||| %foreign call's own return value is packed into a boxed Idris
||| value *before* that same call's GCPtr-typed arguments are dropped,
||| true for Chez (tracing GC, no synchronous mid-call finalizer to
||| begin with) and rc2 (idris2-rc-cg commit 2aa9b90).
export
curlReadAndFree : HasIO io => AnyPtr -> io String
curlReadAndFree raw = do
    gcptr <- onCollectAny raw (\p => primIO (prim__curlFree p))
    primIO (prim__curlGetStringGC gcptr)

||| `Nothing` on the same "libcurl itself reports an error" contract as
||| `curl_easy_escape(3)` (`Nothing` for both allocation failure and a
||| `length` too large to represent as the underlying `int`).
||| Leak-free via `curlReadAndFree` on both backends.
export
curlEasyEscape : HasIO io => AnyPtr -> String -> io (Maybe String)
curlEasyEscape h s = do
    raw <- primIO (prim__curlEasyEscapeRaw h s 0)
    if prim__nullAnyPtr raw /= 0
       then pure Nothing
       else Just <$> curlReadAndFree raw

||| Same leak-free-via-`curlReadAndFree` shape as `curlEasyEscape`.
export
curlEasyUnescape : HasIO io => AnyPtr -> String -> io (Maybe String)
curlEasyUnescape h s = do
    raw <- primIO (prim__curlEasyUnescapeRaw h s 0 prim__getNullAnyPtr)
    if prim__nullAnyPtr raw /= 0
       then pure Nothing
       else Just <$> curlReadAndFree raw

------------------------------------------------------------------------
-- Version / curl_version_info
------------------------------------------------------------------------

export
curlVersion : HasIO io => io String
curlVersion = primIO prim__curlVersion

||| `curl_version_info_data`, field-for-field -- see
||| `VersionInfoPtr`'s own doc comment for which fields are bound and
||| why.
public export
record VersionInfo where
  constructor MkVersionInfo
  version    : String
  versionNum : Int
  host       : String
  features   : Int
  sslVersion : Maybe String

-- CURLVERSION_NOW == CURLVERSION_TWELFTH, curl/curl.h's own 0-based
-- CURLversion ordinal as of libcurl 8.8.0. Passed explicitly rather
-- than resolving a same-named C macro, since %foreign has no access
-- to preprocessor macros at all (only real declarations). Every field
-- VersionInfoPtr actually binds has existed since CURLVERSION_FIRST
-- (libcurl 7.10), so unlike a hypothetically wider binding, this
-- doesn't need to guard against an older running libcurl having a
-- smaller struct than curl/curl.h itself declares.
curlversionNow : Int
curlversionNow = 11

||| rc2-only (`VersionInfoPtr`'s own doc comment).
export
curlVersionInfo : HasIO io => io VersionInfo
curlVersionInfo = do
    v <- primIO (prim__curlVersionInfo curlversionNow)
    let version    = getField v "version"
        versionNum = getField v "version_num"
        host       = getField v "host"
        features   = getField v "features"
        sslVersion = ptrToString (getField v "ssl_version")
    pure $ MkVersionInfo version versionNum host features sslVersion

------------------------------------------------------------------------
-- URL API
------------------------------------------------------------------------

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

||| rc2-only, no Chez binding -- see `Network.Curl.Raw`'s own doc
||| comment on `prim__curlUrlGetRaw` and `doc/variadic-getinfo.md`-style
||| reasoning (the underlying shim is `static inline`, unreachable
||| under Chez's own dynamic FFI). `flags` -- see `curlUrlSet`'s own
||| doc comment. `Nothing` on a `curl_url_get` failure, `Just` (with a
||| possibly-empty `String`) otherwise -- distinguishable because
||| `idris2curl_url_get_raw` hands back NULL only on failure. Read back
||| leak-free via `curlReadAndFree`'s GCAnyPtr.
export
curlUrlGet : HasIO io => AnyPtr -> CURLUPart -> Int -> io (Maybe String)
curlUrlGet u (MkCURLUPart p) flags = do
    raw <- primIO (prim__curlUrlGetRaw u p flags)
    if prim__nullAnyPtr raw /= 0
       then pure Nothing
       else Just <$> curlReadAndFree raw

export
curlUrlStrerror : HasIO io => CURLUcode -> io String
curlUrlStrerror (MkCURLUcode c) = primIO (prim__curlUrlStrerror c)

------------------------------------------------------------------------
-- Multi interface
------------------------------------------------------------------------

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

||| rc2-only, no Chez binding -- see `prim__curlMultiPerform`'s own
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

||| rc2-only, same as `curlMultiPerform`. `timeoutMs` -- how long
||| to block waiting for activity on any handle in `m`'s own stack
||| before returning regardless (`curl_multi_wait(3)`); the number of
||| fds that were actually signalled, or `Nothing` on the same
||| collapsed-error contract as `curlMultiPerform`.
export
curlMultiWait : HasIO io => AnyPtr -> (timeoutMs : Int) -> io (Maybe Int)
curlMultiWait m timeoutMs = do
    n <- primIO (prim__curlMultiWait m timeoutMs)
    pure $ if n < 0 then Nothing else Just n

||| rc2-only, no Chez binding -- see `prim__curlMultiInfoRead`'s
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

------------------------------------------------------------------------
-- Share interface
------------------------------------------------------------------------

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
||| `curlEasySetoptPointer h curlopt_SHARE sh` (`curlopt_SHARE`,
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

------------------------------------------------------------------------
-- Mime interface
------------------------------------------------------------------------

||| `Nothing` on the same allocation-failure contract as `curlEasyInit`
||| (`curl_mime_init(3)`). `h` is the easy handle the resulting mime
||| structure will eventually be attached to via
||| `curlEasySetoptPointer h curlopt_MIMEPOST mime` -- required even
||| though a mime handle isn't tied to any one easy handle's own data,
||| just used to allocate memory the same way the easy handle itself
||| does (`curl_mime_init(3)`'s own contract).
export
curlMimeInit : HasIO io => AnyPtr -> io (Maybe AnyPtr)
curlMimeInit h = do
    mime <- primIO (prim__curlMimeInit h)
    pure $ if prim__nullAnyPtr mime /= 0 then Nothing else Just mime

||| Only needed if `mime` is never attached via `CURLOPT_MIMEPOST` (or
||| after removing it again with `curlEasySetoptPointer h curlopt_MIMEPOST
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

------------------------------------------------------------------------
-- Pause/upkeep
------------------------------------------------------------------------

||| `action` -- see `Network.Curl.Types`'s own `curlpause_*` bitmask
||| constants, OR'd together with `Data.Bits`'s own `.|.` for more than
||| one of `curlpause_RECV`/`curlpause_SEND` at once.
export
curlEasyPause : HasIO io => AnyPtr -> (action : Int) -> io CURLcode
curlEasyPause h action = MkCURLcode <$> primIO (prim__curlEasyPause h action)

export
curlEasyUpkeep : HasIO io => AnyPtr -> io CURLcode
curlEasyUpkeep h = MkCURLcode <$> primIO (prim__curlEasyUpkeep h)

------------------------------------------------------------------------
-- Structured headers
------------------------------------------------------------------------

||| rc2-only, no Chez binding -- see `prim__curlEasyHeader`'s own
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
    if prim__nullAnyPtr (believe_me hdr) /= 0
       then pure Nothing
       else pure $ Just (getField hdr "name", getField hdr "value")

||| rc2-only, same as `curlEasyHeader`. `prev` -- `curlSlistEmpty`
||| to start iterating from the first header, or a previous call's own
||| result (the raw pointer, not the `(String, String)` pair
||| `curlEasyHeader`/this function's own wrapper hands back -- see
||| `examples/Header.idr` for the iteration pattern) to continue.
||| `Nothing` once iteration reaches the end -- the ordinary, expected
||| way this loop ends, not an error.
export
curlEasyNextheader : HasIO io => AnyPtr -> (origin : Int) -> (request : Int) -> (prev : AnyPtr) -> io (Maybe (AnyPtr, String, String))
curlEasyNextheader h origin request prev = do
    hdr <- primIO (prim__curlEasyNextheader h origin request (believe_me prev))
    if prim__nullAnyPtr (believe_me hdr) /= 0
       then pure Nothing
       else pure $ Just (believe_me hdr, getField hdr "name", getField hdr "value")

------------------------------------------------------------------------
-- Response-body capture
------------------------------------------------------------------------

||| Performs the transfer with `CURLOPT_WRITEDATA` pointed at an
||| in-memory capture stream (`System.IO.MemStream`, `rc2base`), so the
||| response body ends up here instead of the process's own stdout --
||| `CURLOPT_WRITEFUNCTION` itself still isn't bound (see `TODO.md`).
||| See `doc/memstream-capture.md` for the full design -- this
||| function's own callers never see a `MemStream` at all. `Nothing` if
||| the capture stream itself couldn't be set up (allocation/
||| `open_memstream(3)`/setopt failure -- `curl_easy_perform` is never
||| even attempted then) or the final `Buffer` read failed; otherwise
||| always `Just`, even on a `curl_easy_perform` failure of its own --
||| the captured body, whatever there is of it, alongside the
||| `CURLcode`, a caller that only cares about success checks that code
||| itself.
export
curlEasyPerformToBuffer : HasIO io => AnyPtr -> io (Maybe (CURLcode, Buffer))
curlEasyPerformToBuffer h = do
    Just ms <- liftIO MemStream.newMemStream
        | Nothing => pure Nothing
    fp <- liftIO (MemStream.filePtr ms)
    MkCURLcode 0 <- curlEasySetoptPointer h curlopt_WRITEDATA fp
        | _ => do liftIO (MemStream.free ms)
                  pure Nothing
    result <- curlEasyPerform h
    liftIO (MemStream.close ms)
    mbuf <- liftIO (MemStream.toBuffer ms)
    liftIO (MemStream.free ms)
    pure (map (\b => (result, b)) mbuf)

||| Same as `curlEasyPerformToBuffer`, reading the captured body as a
||| `String` instead (`MemStream.toString`, one copy, NUL-terminated --
||| see that function's own doc comment for the embedded-NUL caveat).
export
curlEasyPerformToString : HasIO io => AnyPtr -> io (Maybe (CURLcode, String))
curlEasyPerformToString h = do
    Just ms <- liftIO MemStream.newMemStream
        | Nothing => pure Nothing
    fp <- liftIO (MemStream.filePtr ms)
    MkCURLcode 0 <- curlEasySetoptPointer h curlopt_WRITEDATA fp
        | _ => do liftIO (MemStream.free ms)
                  pure Nothing
    result <- curlEasyPerform h
    liftIO (MemStream.close ms)
    mstr <- liftIO (MemStream.toString ms)
    liftIO (MemStream.free ms)
    pure (map (\s => (result, s)) mstr)

||| Same as `curlEasyPerformToBuffer`, reading the captured body as a
||| `TextBuffer` instead (`MemStream.toTextBuffer`, one copy). rc2-only,
||| unlike the other two -- `Data.TextBuffer`'s own implementation
||| needs rc2's own runtime headers, see `doc/memstream-capture.md`.
export
curlEasyPerformToTextBuffer : HasIO io => AnyPtr -> io (Maybe (CURLcode, TextBuffer))
curlEasyPerformToTextBuffer h = do
    Just ms <- liftIO MemStream.newMemStream
        | Nothing => pure Nothing
    fp <- liftIO (MemStream.filePtr ms)
    MkCURLcode 0 <- curlEasySetoptPointer h curlopt_WRITEDATA fp
        | _ => do liftIO (MemStream.free ms)
                  pure Nothing
    result <- curlEasyPerform h
    liftIO (MemStream.close ms)
    mtxt <- liftIO (MemStream.toTextBuffer ms)
    liftIO (MemStream.free ms)
    pure (map (\t => (result, t)) mtxt)
