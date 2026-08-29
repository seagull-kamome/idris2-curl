module Main

-- Copyright 2026, Hattori,Hiroki. All rights reserved.
-- This module was licensed by BSD3.

-- Exercises Phase 1's own new bindings: curl_slist (custom request
-- header), curl_easy_reset, curl_easy_duphandle. curl_easy_getinfo
-- isn't exercised here -- it has no Chez binding at all yet (see
-- doc/const-char-ffi.md-style reasoning in Network.Curl.Raw's own doc
-- comment on prim__curlEasyGetinfoLong); a separate rc2/RefC-only
-- example covers it instead.

import Network.Curl.Raw
import Network.Curl.Types

main : IO ()
main = do
    MkCURLcode 0 <- curlGlobalInit
        | c1 => putStrLn ("curl_global_init failed: " ++ show c1)
    Just h <- curlEasyInit
        | Nothing => putStrLn "curl_easy_init failed"

    let headers = curlSlistEmpty
    headers <- curlSlistAppend headers "X-Idris2-Curl: phase1"

    MkCURLcode 0 <- curlEasySetoptPointer h curlopt_HTTPHEADER headers
        | c2 => putStrLn ("setopt HTTPHEADER failed: " ++ show c2)
    MkCURLcode 0 <- curlEasySetoptString h curlopt_URL "http://example.com"
        | c3 => putStrLn ("setopt URL failed: " ++ show c3)

    result <- curlEasyPerform h
    msg <- curlEasyStrerror result
    putStrLn ("curl_easy_perform result: " ++ show result ++ " (" ++ msg ++ ")")

    curlEasyReset h
    Just h2 <- curlEasyDuphandle h
        | Nothing => putStrLn "curl_easy_duphandle failed"
    curlEasyCleanup h2

    curlSlistFreeAll headers
    curlEasyCleanup h
    curlGlobalCleanup
