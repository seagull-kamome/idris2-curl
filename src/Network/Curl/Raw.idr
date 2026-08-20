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

%foreign "C:curl_easy_perform,libcurl,curl/curl.h"
prim__curlEasyPerform : AnyPtr -> PrimIO Int

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
