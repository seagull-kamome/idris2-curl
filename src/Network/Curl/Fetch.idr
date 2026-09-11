module Network.Curl.Fetch

-- Copyright 2026, Hattori,Hiroki. All rights reserved.
-- This module was licensed by BSD3.

-- A JS `fetch()`-shaped convenience layer over Network.Curl.Raw --
-- hides curl_global_init/curl_easy_init/setopt/slist bookkeeping
-- behind ordinary Idris records and one function call per request.
-- No relation to CURLOPT_WRITEFUNCTION-style streaming or libcurl's
-- own multi interface (both a separate, unrelated axis -- see
-- Network.Curl.Raw's own curlMultiInit/etc. for concurrent transfers,
-- unaffected by anything below) -- every function here still performs
-- one whole synchronous transfer per call, same as Network.Curl.Raw's
-- own curlEasyPerformToBuffer/ToString.
--
-- rc2-only, this module as a whole: the HTTP status code -- the one
-- thing a `fetch()`-shaped API can't really do without -- only comes
-- from `curl_easy_getinfo` (`curlinfo_RESPONSE_CODE`), which has no
-- Chez `%foreign` target at all (`Network.Curl.Raw`'s own doc comment
-- on `prim__curlEasyGetinfoLong`, `doc/variadic-getinfo.md`) --
-- confirmed directly, not assumed: an earlier version of this module
-- split response headers out into an "rc2-only" variant while keeping
-- `fetch`/`fetchBytes` themselves nominally portable, then failed to
-- even *build* the example against Chez with "was not accepted by any
-- backend" pointing at the status-code lookup inside `fetch` itself.
-- Chez callers should use `Network.Curl.Raw` directly (`curlEasyPerform`/
-- `curlEasyPerformToBuffer`/`ToString` give body + `CURLcode` -- a
-- transfer either reached the server and got *some* HTTP response, or
-- it didn't -- with no way to distinguish "got a 200" from "got a
-- 404" beyond that).

import Data.Buffer

import Network.Curl.Raw
import Network.Curl.Types

||| HTTP method. `OTHER` covers anything not listed (WebDAV verbs,
||| ...) via `curlopt_CUSTOMREQUEST`.
public export
data Method = GET | POST | PUT | PATCH | DELETE | HEAD | OTHER String

||| One HTTP request. Build with `get`/`post`/`request` below rather
||| than the constructor directly, then override individual fields
||| with ordinary record update syntax, e.g.
||| `{ headers := [("Accept", "application/json")] } (get url)`.
public export
record FetchRequest where
  constructor MkFetchRequest
  url     : String
  method  : Method
  headers : List (String, String)
  body    : Maybe String

||| `GET url`, no extra headers, no body.
export
get : String -> FetchRequest
get url = MkFetchRequest url GET [] Nothing

||| `POST url` with `body` as the request body
||| (`curlopt_COPYPOSTFIELDS`, raw bytes -- not form-encoded). Set a
||| `Content-Type` header yourself if the server needs one, e.g.
||| `{ headers := [("Content-Type", "application/json")] } (post url body)`.
export
post : (url : String) -> (body : String) -> FetchRequest
post url body = MkFetchRequest url POST [] (Just body)

||| A bare request with an arbitrary method and no body -- add one
||| with ordinary record update, e.g.
||| `{ body := Just "..." } (request PUT url)`.
export
request : Method -> String -> FetchRequest
request method url = MkFetchRequest url method [] Nothing

||| `status`/`headers`/`body`, in that order matching `curl -i`'s own
||| output shape. `headers` -- every response header, oldest-declared-
||| first (`collectHeaders`'s own doc comment for how).
public export
record FetchResponse where
  constructor MkFetchResponse
  status  : Int
  headers : List (String, String)
  body    : String

||| Same as `FetchResponse`, `body` as a `Buffer` instead -- for
||| binary responses, or to avoid `String`'s own embedded-NUL
||| truncation risk (`curlEasyPerformToString`'s own doc comment).
public export
record FetchResponseBytes where
  constructor MkFetchResponseBytes
  status  : Int
  headers : List (String, String)
  body    : Buffer

||| `CurlError` -- `curl_easy_perform` itself failed (network/TLS/DNS/
||| ..., never reached the server at all). An HTTP `4xx`/`5xx` is
||| *not* an error here -- same as JS `fetch()`'s own `response.ok`
||| convention -- check `FetchResponse.status` for that instead;
||| `fetchText`'s own folding of non-`2xx` into `HttpError` is the
||| one exception, for callers that only want the happy path.
||| `SetupError` -- something before `curl_easy_perform` failed
||| (`curl_global_init`/`curl_easy_init`/the response capture stream
||| itself).
public export
data FetchError = CurlError CURLcode String | SetupError String | HttpError Int

export
Show FetchError where
  show (CurlError c msg) = "CurlError " ++ show c ++ " (" ++ msg ++ ")"
  show (SetupError msg)  = "SetupError " ++ msg
  show (HttpError s)     = "HttpError " ++ show s

methodName : Method -> String
methodName GET       = "GET"
methodName POST      = "POST"
methodName PUT       = "PUT"
methodName PATCH     = "PATCH"
methodName DELETE    = "DELETE"
methodName HEAD      = "HEAD"
methodName (OTHER m) = m

buildHeaderList : HasIO io => List (String, String) -> io AnyPtr
buildHeaderList []              = pure curlSlistEmpty
buildHeaderList ((k, v) :: kvs) = do
    list <- buildHeaderList kvs
    curlSlistAppend list (k ++ ": " ++ v)

||| `GET`/`HEAD`/`POST` each have a dedicated boolean `CURLOPT_*` that
||| also resets any method a *previous* `curl_easy_setopt` on the same
||| handle configured (`curl_easy_setopt(3)`'s own note); every other
||| `Method` goes through `curlopt_CUSTOMREQUEST` instead, libcurl's
||| own catch-all for a verb it has no dedicated option for. Setopt
||| return codes are ignored throughout `applyMethod`/`applyRequest`
||| below -- realistically only ever fail for a disabled-at-build-time
||| feature or a null/malformed option value, never a plain string/
||| long argument like these (same trust `examples/*.idr` already
||| places in the less common setopt calls it doesn't bother
||| checking) -- a genuine failure to actually reach the server still
||| surfaces via `curl_easy_perform`'s own `CURLcode`.
applyMethod : HasIO io => AnyPtr -> Method -> Maybe String -> io ()
applyMethod h GET  _     = ignore $ curlEasySetoptLong h curlopt_HTTPGET 1
applyMethod h HEAD _     = ignore $ curlEasySetoptLong h curlopt_NOBODY 1
applyMethod h POST mbody = do
    ignore $ curlEasySetoptLong h curlopt_POST 1
    maybe (pure ()) (ignore . curlEasySetoptString h curlopt_COPYPOSTFIELDS) mbody
applyMethod h m mbody = do
    ignore $ curlEasySetoptString h curlopt_CUSTOMREQUEST (methodName m)
    maybe (pure ()) (ignore . curlEasySetoptString h curlopt_COPYPOSTFIELDS) mbody

||| Applies `req`'s own url/method/headers/body to a fresh easy handle
||| `h`, and follows redirects (`curlopt_FOLLOWLOCATION`) -- shared
||| setup both `fetch`/`fetchBytes` build on. Returns the
||| `curl_slist *` built for `curlopt_HTTPHEADER` (`curlSlistEmpty` if
||| `req.headers` was `[]`) so the caller can free it with
||| `curlSlistFreeAll` once done -- attaching one via setopt doesn't
||| transfer ownership (`curlSlistFreeAll`'s own doc comment).
applyRequest : HasIO io => AnyPtr -> FetchRequest -> io AnyPtr
applyRequest h req = do
    ignore $ curlEasySetoptString h curlopt_URL req.url
    ignore $ curlEasySetoptLong h curlopt_FOLLOWLOCATION 1
    hlist <- buildHeaderList req.headers
    ignore $ curlEasySetoptPointer h curlopt_HTTPHEADER hlist
    applyMethod h req.method req.body
    pure hlist

||| `curl_global_init`+`curl_easy_init`, handing the handle to `body`,
||| always tearing both down afterward regardless of how `body`
||| finished. Shared by `fetch`/`fetchBytes` -- same "no persistent
||| state between calls" convention every `examples/*.idr` in this
||| repo already uses (fine for occasional calls, wasteful in a tight
||| loop -- each call pays `curl_global_init`'s own one-time-per-process
||| setup cost again; reach for `Network.Curl.Raw` directly and manage
||| one handle yourself across many requests if that matters).
withEasyHandle : HasIO io => (AnyPtr -> io (Either FetchError a)) -> io (Either FetchError a)
withEasyHandle body = do
    MkCURLcode 0 <- curlGlobalInit
        | c => pure (Left (SetupError ("curl_global_init failed: " ++ show c)))
    Just h <- curlEasyInit
        | Nothing => do curlGlobalCleanup
                        pure (Left (SetupError "curl_easy_init failed"))
    result <- body h
    curlEasyCleanup h
    curlGlobalCleanup
    pure result

||| Every response header, oldest-declared-first, via
||| `curl_easy_nextheader` (`examples/Header.idr`'s own iteration
||| pattern). Not provably total to Idris's own totality checker (no
||| structural decrease it can see -- `curl_easy_nextheader` itself is
||| the only thing that knows when the list ends), same as
||| `examples/Header.idr`'s own `listHeaders`; genuinely terminating in
||| practice, since libcurl's own header list for one response is
||| always finite.
partial
collectHeaders : HasIO io => AnyPtr -> AnyPtr -> io (List (String, String))
collectHeaders h prev = do
    Just (next, name, value) <- curlEasyNextheader h curlh_HEADER 0 prev
        | Nothing => pure []
    rest <- collectHeaders h next
    pure ((name, value) :: rest)

||| `fetch(req)` -- performs `req`, capturing the whole response body
||| as `String` (`curlEasyPerformToString`, one copy, NUL-terminated --
||| see that function's own doc comment for the embedded-NUL caveat).
export
fetch : HasIO io => FetchRequest -> io (Either FetchError FetchResponse)
fetch req = withEasyHandle $ \h => do
    hlist <- applyRequest h req
    Just (result, body) <- curlEasyPerformToString h
        | Nothing => do curlSlistFreeAll hlist
                        pure (Left (SetupError "response capture failed"))
    curlSlistFreeAll hlist
    if result == curle_OK
       then do status <- curlEasyGetinfoLong h curlinfo_RESPONSE_CODE
               hdrs <- collectHeaders h curlSlistEmpty
               pure (Right (MkFetchResponse status hdrs body))
       else do msg <- curlEasyStrerror result
               pure (Left (CurlError result msg))

||| Same as `fetch`, reading the captured body as a `Buffer` instead
||| (`curlEasyPerformToBuffer`, one copy, exact byte count).
export
fetchBytes : HasIO io => FetchRequest -> io (Either FetchError FetchResponseBytes)
fetchBytes req = withEasyHandle $ \h => do
    hlist <- applyRequest h req
    Just (result, body) <- curlEasyPerformToBuffer h
        | Nothing => do curlSlistFreeAll hlist
                        pure (Left (SetupError "response capture failed"))
    curlSlistFreeAll hlist
    if result == curle_OK
       then do status <- curlEasyGetinfoLong h curlinfo_RESPONSE_CODE
               hdrs <- collectHeaders h curlSlistEmpty
               pure (Right (MkFetchResponseBytes status hdrs body))
       else do msg <- curlEasyStrerror result
               pure (Left (CurlError result msg))

||| The simplest possible call -- `GET url`, discard everything but
||| the body, folding a non-`2xx` status into `Left (HttpError status)`
||| (unlike `fetch` itself, which always hands back `Right` for any
||| completed HTTP exchange -- see `FetchError`'s own doc comment).
||| For anything needing the status code, headers, or a non-`GET`
||| method, use `fetch`/`get`/`request` directly instead.
export
fetchText : HasIO io => String -> io (Either FetchError String)
fetchText url = do
    Right resp <- fetch (get url)
        | Left err => pure (Left err)
    if resp.status >= 200 && resp.status < 300
       then pure (Right resp.body)
       else pure (Left (HttpError resp.status))
