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

public export
curlopt_HTTPHEADER : CURLoption
curlopt_HTTPHEADER = MkCURLoption 10023 -- CURLOPTTYPE_OBJECTPOINT + 23

||| A libcurl `CURLINFO` -- the value passed as `curl_easy_getinfo`'s
||| own second argument. Every value below is `CURLINFO_*`'s own
||| `CURLINFO_STRING`/`CURLINFO_LONG`/`CURLINFO_DOUBLE` type tag (per
||| curl/curl.h) plus the info's own small ordinal, same construction
||| as `CURLoption` above. Only the three type tags this module's own
||| `curlEasyGetinfo*` functions (`Network.Curl.Raw`) support are
||| represented here -- `CURLINFO_SLIST`/`CURLINFO_OFF_T`/
||| `CURLINFO_SOCKET`-tagged infos aren't bound yet.
public export
record CURLINFO where
  constructor MkCURLINFO
  info : Int

public export
curlinfo_EFFECTIVE_URL : CURLINFO
curlinfo_EFFECTIVE_URL = MkCURLINFO 1048577 -- CURLINFO_STRING + 1

public export
curlinfo_RESPONSE_CODE : CURLINFO
curlinfo_RESPONSE_CODE = MkCURLINFO 2097154 -- CURLINFO_LONG + 2

public export
curlinfo_TOTAL_TIME : CURLINFO
curlinfo_TOTAL_TIME = MkCURLINFO 3145731 -- CURLINFO_DOUBLE + 3

public export
curlinfo_NAMELOOKUP_TIME : CURLINFO
curlinfo_NAMELOOKUP_TIME = MkCURLINFO 3145732 -- CURLINFO_DOUBLE + 4

public export
curlinfo_CONNECT_TIME : CURLINFO
curlinfo_CONNECT_TIME = MkCURLINFO 3145733 -- CURLINFO_DOUBLE + 5

public export
curlinfo_HEADER_SIZE : CURLINFO
curlinfo_HEADER_SIZE = MkCURLINFO 2097163 -- CURLINFO_LONG + 11

public export
curlinfo_REQUEST_SIZE : CURLINFO
curlinfo_REQUEST_SIZE = MkCURLINFO 2097164 -- CURLINFO_LONG + 12

public export
curlinfo_CONTENT_TYPE : CURLINFO
curlinfo_CONTENT_TYPE = MkCURLINFO 1048594 -- CURLINFO_STRING + 18

public export
curlinfo_REDIRECT_COUNT : CURLINFO
curlinfo_REDIRECT_COUNT = MkCURLINFO 2097172 -- CURLINFO_LONG + 20
