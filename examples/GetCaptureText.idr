module Main

-- Copyright 2026, Hattori,Hiroki. All rights reserved.
-- This module was licensed by BSD3.

-- rc2-only, not RefC/rc2 like GetCapture.idr: exercises
-- curlMemstreamToTextBuffer. Data.TextBuffer's own rc2base
-- implementation needs rc2's own runtime headers (rc2/datatypes.h,
-- pulled in via text_util.h), so it isn't buildable against real
-- upstream RefC at all -- see Network.Curl.Raw's own doc comment on
-- curlMemstreamToTextBuffer.

import Data.TextBuffer

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

    Just t <- curlMemstreamToTextBuffer m
        | Nothing => putStrLn "curlMemstreamToTextBuffer failed"
    putStrLn ("TextBuffer length (codepoints): " ++ show (Data.TextBuffer.length t))
    putStrLn ("TextBuffer round-trip: " ++ toString t)

    curlMemstreamFree m
    msg <- curlEasyStrerror result
    putStrLn ("curl_easy_perform result: " ++ show result ++ " (" ++ msg ++ ")")

    curlEasyCleanup h
    curlGlobalCleanup
