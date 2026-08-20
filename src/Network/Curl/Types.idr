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

||| A `CURLUcode` result from the URL API (`curl_url_get`/
||| `curl_url_set`) -- a distinct enum from `CURLcode` in curl/curl.h
||| itself, so kept as its own wrapper here too.
public export
record CURLUcode where
  constructor MkCURLUcode
  code : Int

public export
Eq CURLUcode where
  MkCURLUcode a == MkCURLUcode b = a == b

public export
Show CURLUcode where
  show (MkCURLUcode c) = "CURLUcode " ++ show c

||| Success, per curl/curl.h's `CURLUE_OK = 0` (first enum member).
public export
curlue_OK : CURLUcode
curlue_OK = MkCURLUcode 0

||| A `CURLUPart` -- which URL component `curl_url_get`/`curl_url_set`
||| read or write. Values are the enum's own declaration order in
||| curl/curl.h (`CURLUPART_URL = 0`, ...), same as any plain C enum
||| with no explicit initializers.
public export
record CURLUPart where
  constructor MkCURLUPart
  part : Int

public export
curlupart_URL : CURLUPart
curlupart_URL = MkCURLUPart 0

public export
curlupart_SCHEME : CURLUPart
curlupart_SCHEME = MkCURLUPart 1

public export
curlupart_USER : CURLUPart
curlupart_USER = MkCURLUPart 2

public export
curlupart_PASSWORD : CURLUPart
curlupart_PASSWORD = MkCURLUPart 3

public export
curlupart_HOST : CURLUPart
curlupart_HOST = MkCURLUPart 5

public export
curlupart_PORT : CURLUPart
curlupart_PORT = MkCURLUPart 6

public export
curlupart_PATH : CURLUPart
curlupart_PATH = MkCURLUPart 7

public export
curlupart_QUERY : CURLUPart
curlupart_QUERY = MkCURLUPart 8

public export
curlupart_FRAGMENT : CURLUPart
curlupart_FRAGMENT = MkCURLUPart 9

||| A libcurl `CURLMcode` result from the multi interface -- a
||| distinct enum from both `CURLcode` and `CURLUcode` in curl/multi.h.
||| Note `CURLM_CALL_MULTI_PERFORM = -1` is the enum's own first
||| (negative) member, so `CURLM_OK` is `0` same as `CURLcode`/
||| `CURLUcode`, but this enum alone can carry a negative value.
public export
record CURLMcode where
  constructor MkCURLMcode
  code : Int

public export
Eq CURLMcode where
  MkCURLMcode a == MkCURLMcode b = a == b

public export
Show CURLMcode where
  show (MkCURLMcode c) = "CURLMcode " ++ show c

public export
curlm_OK : CURLMcode
curlm_OK = MkCURLMcode 0

||| A libcurl `CURLMSG` -- the `msg` field of a `CURLMsg` read via
||| `curl_multi_info_read`. Only `CURLMSG_DONE` (the one message this
||| repo currently reads meaning from) is bound; `CURLMSG_NONE` (first
||| enum member, never actually sent) and `CURLMSG_LAST` (a sentinel,
||| never sent either) aren't.
public export
record CURLMSG where
  constructor MkCURLMSG
  msg : Int

public export
Eq CURLMSG where
  MkCURLMSG a == MkCURLMSG b = a == b

public export
curlmsg_DONE : CURLMSG
curlmsg_DONE = MkCURLMSG 1
