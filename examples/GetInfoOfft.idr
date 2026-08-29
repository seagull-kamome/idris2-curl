module Main

-- Copyright 2026, Hattori,Hiroki. All rights reserved.
-- This module was licensed by BSD3.

-- rc2-only, not RefC/rc2 like GetInfo.idr: exercises
-- curl_easy_getinfo's own CURLINFO_OFF_T tag (CURLINFO_SIZE_DOWNLOAD_T),
-- which needs an Int64-returning %foreign target -- confirmed directly
-- that real upstream RefC's own C backend crashes on that ("INTERNAL
-- ERROR: Unknown FFI type in C backend: Int_64"), see
-- Network.Curl.Raw's own doc comment on prim__curlEasyGetinfoOfft.
-- Chez has no binding here either, same doc/variadic-getinfo.md
-- reasoning as every other curlEasyGetinfo* function.

import Network.Curl.Raw
import Network.Curl.Types

main : IO ()
main = do
    MkCURLcode 0 <- curlGlobalInit
        | c1 => putStrLn ("curl_global_init failed: " ++ show c1)
    Just h <- curlEasyInit
        | Nothing => putStrLn "curl_easy_init failed"

    MkCURLcode 0 <- curlEasySetoptString h curlopt_URL "http://example.com"
        | c2 => putStrLn ("setopt URL failed: " ++ show c2)

    MkCURLcode 0 <- curlEasyPerform h
        | c3 => putStrLn ("curl_easy_perform failed: " ++ show c3)

    downloadSize <- curlEasyGetinfoOfft h curlinfo_SIZE_DOWNLOAD_T
    putStrLn ("download size (off_t): " ++ show downloadSize)

    curlEasyCleanup h
    curlGlobalCleanup
