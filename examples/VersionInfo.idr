module Main

-- Copyright 2026, Hattori,Hiroki. All rights reserved.
-- This module was licensed by BSD3.

-- rc2/RefC-only: exercises curl_version_info, which has no Chez
-- binding at all (see Network.Curl.Raw's own doc comment on
-- prim__curlVersionInfoVersion). Building this against Chez fails
-- cleanly at this file's own curlVersionInfo* call sites -- expected,
-- not a regression.

import Data.Bits

import Network.Curl.Raw
import Network.Curl.Types

main : IO ()
main = do
    v <- curlVersionInfoVersion
    n <- curlVersionInfoVersionNum
    host <- curlVersionInfoHost
    features <- curlVersionInfoFeatures
    ssl <- curlVersionInfoSslVersion
    putStrLn ("version: " ++ v)
    putStrLn ("version_num: " ++ show n)
    putStrLn ("host: " ++ host)
    putStrLn ("features has SSL: " ++ show ((features .&. 4) /= 0))
    putStrLn ("ssl_version: " ++ ssl)
