module Main

-- Copyright 2026, Hattori,Hiroki. All rights reserved.
-- This module was licensed by BSD3.

-- rc2-only: exercises curlVersionInfo (Network.Curl.Raw), a
-- Struct/getField binding of curl_version_info_data -- no Chez
-- binding (see VersionInfoPtr's own doc comment). Building this
-- against Chez fails cleanly at this file's own curlVersionInfo call
-- site -- expected, not a regression.

import Data.Bits

import Network.Curl.Raw
import Network.Curl.Types

showMaybe : Maybe String -> String
showMaybe Nothing  = "(none)"
showMaybe (Just s) = s

main : IO ()
main = do
    v <- curlVersionInfo
    putStrLn ("version: " ++ v.version)
    putStrLn ("version_num: " ++ show v.versionNum)
    putStrLn ("host: " ++ v.host)
    putStrLn ("features has SSL: " ++ show ((v.features .&. 4) /= 0))
    putStrLn ("ssl_version: " ++ showMaybe v.sslVersion)
