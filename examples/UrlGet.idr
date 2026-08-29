module Main

-- Copyright 2026, Hattori,Hiroki. All rights reserved.
-- This module was licensed by BSD3.

-- rc2/RefC-only: exercises curl_url_get, which has no Chez binding at
-- all (see Network.Curl.Raw's own doc comment on prim__curlUrlGet).
-- Building this against Chez fails cleanly at this file's own
-- curlUrlGet call sites -- expected, not a regression.

import Network.Curl.Raw
import Network.Curl.Types

main : IO ()
main = do
    Just u <- curlUrl
        | Nothing => putStrLn "curl_url failed"
    MkCURLUcode 0 <- curlUrlSet u curlupart_URL "https://example.com/path?q=1" 0
        | e1 => putStrLn ("curl_url_set failed: " ++ !(curlUrlStrerror e1))

    Just scheme <- curlUrlGet u curlupart_SCHEME 0
        | Nothing => putStrLn "curl_url_get(SCHEME) failed"
    Just host <- curlUrlGet u curlupart_HOST 0
        | Nothing => putStrLn "curl_url_get(HOST) failed"
    Just path <- curlUrlGet u curlupart_PATH 0
        | Nothing => putStrLn "curl_url_get(PATH) failed"
    Just query <- curlUrlGet u curlupart_QUERY 0
        | Nothing => putStrLn "curl_url_get(QUERY) failed"
    putStrLn ("scheme: " ++ scheme)
    putStrLn ("host: " ++ host)
    putStrLn ("path: " ++ path)
    putStrLn ("query: " ++ query)

    curlUrlCleanup u
