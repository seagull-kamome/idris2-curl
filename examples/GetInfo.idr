module Main

-- Copyright 2026, Hattori,Hiroki. All rights reserved.
-- This module was licensed by BSD3.

-- rc2/RefC-only: exercises curl_easy_getinfo, which has no Chez
-- binding at all (see Network.Curl.Raw's own doc comment on
-- prim__curlEasyGetinfoLong for why). Building this against Chez
-- fails cleanly at this file's own getinfo call sites -- expected,
-- not a regression -- see AGENT.md's own "Build & test" section.

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

    code <- curlEasyGetinfoLong h curlinfo_RESPONSE_CODE
    url <- curlEasyGetinfoString h curlinfo_EFFECTIVE_URL
    ctype <- curlEasyGetinfoString h curlinfo_CONTENT_TYPE
    totalTime <- curlEasyGetinfoDouble h curlinfo_TOTAL_TIME
    putStrLn ("response code: " ++ show code)
    putStrLn ("effective url: " ++ url)
    putStrLn ("content type: " ++ ctype)
    putStrLn ("total time: " ++ show totalTime)

    curlEasyCleanup h
    curlGlobalCleanup
