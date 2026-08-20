module Network.Curl.Types

-- Copyright 2026, Hattori,Hiroki. All rights reserved.
-- This module was licensed by BSD3.

||| A libcurl `CURLcode` result. Wrapped rather than a bare `Int` so
||| callers can't accidentally compare it against a `CURLoption` value.
public export
record CURLcode where
  constructor MkCURLcode
  code : Int

public export
Eq CURLcode where
  MkCURLcode a == MkCURLcode b = a == b

public export
Show CURLcode where
  show (MkCURLcode c) = "CURLcode " ++ show c

||| Success, per curl/curl.h's `CURLE_OK = 0`.
public export
curle_OK : CURLcode
curle_OK = MkCURLcode 0

||| A libcurl `CURLoption` -- the value passed as `curl_easy_setopt`'s
||| own second argument. Every option value below is `CURLOPTTYPE_*`
||| (per curl/curl.h) plus the option's own small ordinal, exactly as
||| curl.h's own `CURLOPT()` macro constructs it.
public export
record CURLoption where
  constructor MkCURLoption
  opt : Int

public export
curlopt_VERBOSE : CURLoption
curlopt_VERBOSE = MkCURLoption 41 -- CURLOPTTYPE_LONG + 41

public export
curlopt_URL : CURLoption
curlopt_URL = MkCURLoption 10002 -- CURLOPTTYPE_OBJECTPOINT + 2
