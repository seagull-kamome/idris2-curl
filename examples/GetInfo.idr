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
    activeSocket <- curlEasyGetinfoSocket h curlinfo_ACTIVESOCKET
    putStrLn ("response code: " ++ show code)
    putStrLn ("effective url: " ++ url)
    putStrLn ("content type: " ++ ctype)
    putStrLn ("total time: " ++ show totalTime)
    putStrLn ("active socket is valid fd: " ++ show (activeSocket >= 0))

    -- No cookies set on this handle, so an empty list is expected --
    -- exercises the CURLINFO_SLIST read path itself, not cookie
    -- content. Caller-owned per curl_easy_getinfo(3): must be released
    -- with curlSlistFreeAll, unlike every other getinfo tag above.
    cookieSlist <- curlEasyGetinfoSlist h curlinfo_COOKIELIST
    cookies <- curlSlistToList cookieSlist
    putStrLn ("cookie list: " ++ show cookies)
    curlSlistFreeAll cookieSlist

    curlEasyCleanup h
    curlGlobalCleanup
