module Main

-- Copyright 2026, Hattori,Hiroki. All rights reserved.
-- This module was licensed by BSD3.

-- RefC/rc2-only: captures a response body into Idris without ever
-- binding CURLOPT_WRITEFUNCTION, via curlEasyPerformToBuffer/
-- curlEasyPerformToString -- see doc/memstream-capture.md and
-- Network.Curl.Raw's own doc comment on curlEasyPerformToBuffer.
-- Building this against Chez fails cleanly at this file's own call
-- sites -- expected, not a regression. Only the Buffer/String
-- conversions -- examples/GetCaptureText.idr exercises
-- curlEasyPerformToTextBuffer separately, since Data.TextBuffer's own
-- rc2base implementation needs rc2's own runtime headers
-- (rc2/datatypes.h) and so is rc2-only, unlike everything else here.

import Data.Buffer

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

    Just (result, buf) <- curlEasyPerformToBuffer h
        | Nothing => putStrLn "curlEasyPerformToBuffer failed"
    bufSize <- rawSize buf
    putStrLn ("Buffer rawSize: " ++ show bufSize)

    Just (_, s) <- curlEasyPerformToString h
        | Nothing => putStrLn "curlEasyPerformToString failed"
    putStrLn ("String length (bytes): " ++ show (length s))
    putStrLn ("String content: " ++ s)

    msg <- curlEasyStrerror result
    putStrLn ("curl_easy_perform result: " ++ show result ++ " (" ++ msg ++ ")")

    curlEasyCleanup h
    curlGlobalCleanup
