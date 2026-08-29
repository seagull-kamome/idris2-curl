module Main

-- Copyright 2026, Hattori,Hiroki. All rights reserved.
-- This module was licensed by BSD3.

-- RefC/rc2-only: captures a response body into Idris without ever
-- binding CURLOPT_WRITEFUNCTION, via CURLOPT_WRITEDATA pointed at an
-- open_memstream(3) FILE* -- see doc/memstream-capture.md and
-- Network.Curl.Raw's own doc comment on curlMemstreamOpen. Building
-- this against Chez fails cleanly at this file's own curlMemstream*
-- call sites -- expected, not a regression. Only the Buffer/String
-- conversions -- examples/GetCaptureText.idr exercises
-- curlMemstreamToTextBuffer separately, since Data.TextBuffer's own
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
    Just m <- curlMemstreamOpen
        | Nothing => putStrLn "curlMemstreamOpen failed"

    filep <- curlMemstreamFilep m
    MkCURLcode 0 <- curlEasySetoptPointer h curlopt_WRITEDATA filep
        | c2 => putStrLn ("setopt WRITEDATA failed: " ++ show c2)
    MkCURLcode 0 <- curlEasySetoptString h curlopt_URL "http://example.com"
        | c3 => putStrLn ("setopt URL failed: " ++ show c3)

    result <- curlEasyPerform h
    curlMemstreamClose m

    size <- curlMemstreamSize m
    putStrLn ("captured size: " ++ show size)

    Just buf <- curlMemstreamToBuffer m
        | Nothing => putStrLn "curlMemstreamToBuffer failed"
    bufSize <- rawSize buf
    putStrLn ("Buffer rawSize: " ++ show bufSize)

    Just s <- curlMemstreamToString m
        | Nothing => putStrLn "curlMemstreamToString failed"
    putStrLn ("String length (bytes): " ++ show (length s))
    putStrLn ("String content: " ++ s)

    curlMemstreamFree m
    msg <- curlEasyStrerror result
    putStrLn ("curl_easy_perform result: " ++ show result ++ " (" ++ msg ++ ")")

    curlEasyCleanup h
    curlGlobalCleanup
