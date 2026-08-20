module Main

-- Copyright 2026, Hattori,Hiroki. All rights reserved.
-- This module was licensed by BSD3.

-- rc2/RefC-only: exercises curl_easy_header/curl_easy_nextheader,
-- which have no Chez binding at all (see Network.Curl.Raw's own doc
-- comment on prim__curlEasyHeader). Building this against Chez fails
-- cleanly at this file's own curlEasyHeader/curlEasyNextheader call
-- sites -- expected, not a regression.

import Network.Curl.Raw
import Network.Curl.Types

partial
listHeaders : AnyPtr -> AnyPtr -> IO ()
listHeaders h prev = do
    Just (next, name, value) <- curlEasyNextheader h curlh_HEADER 0 prev
        | Nothing => pure ()
    putStrLn (name ++ ": " ++ value)
    listHeaders h next

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

    Just (contentType, ctValue) <- curlEasyHeader h "content-type" curlh_HEADER 0
        | Nothing => putStrLn "content-type header not found"
    putStrLn ("looked up directly: " ++ contentType ++ ": " ++ ctValue)

    putStrLn "all headers via nextheader:"
    listHeaders h curlSlistEmpty

    curlEasyCleanup h
    curlGlobalCleanup
