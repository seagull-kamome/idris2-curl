# `webapi`: design notes

`webapi` (`webapi.ipkg`, `src-webapi/`) holds clients for web
services, named by category and API: `Network.WebAPI.AI.OpenAI`,
`Network.WebAPI.Auth.OAuth2`. For using it, see
`webapi-getting-started.md`. This page explains the choices behind it.

## Only `Network.Curl.Fetch`

Every HTTP call goes through `Network.Curl.Fetch` (`fetch`, `post`,
`FetchRequest`/`FetchResponse`), never `Network.Curl.Raw`. The aim is
to swap the HTTP layer later for an interface, or for another library,
by changing only these calls. The public types don't mention curl
either: a transfer failure reaches the caller as
`TransportError String`, not as curl's `FetchError`.

`fetch` is `partial` (its header walk has no structural bound), so
`chat`, `refresh`, `accessToken` and `login` are `partial` too.

## One OpenAI-compatible client

Claude, Gemini and llama.cpp all serve OpenAI's
`POST /chat/completions` and all accept `Authorization: Bearer`. So one
client covers them, and each service is only an `Endpoint`: a base URL
plus an `IO` action producing the auth headers. The action runs before
every request, which is where an OAuth token refreshes itself.

Each service's native API (Anthropic's Messages API, Gemini's
`generateContent`) has more features. Those can become their own
modules under `Network.WebAPI.AI` when needed.

## JSON

Parsing uses contrib's `Language.JSON`. Encoding is our own `render`,
because contrib prints every number as a `Double`, so `1024` comes out
as `1024.0`. APIs with strict integer fields (`max_tokens`) reject
that.

## OAuth 2.0: authorization code, PKCE, loopback

The first plan was the device flow (a code shown in the terminal and
typed into a browser anywhere). **Google allows it only for a short
list of scopes** (profile, e-mail, a few Drive and YouTube scopes), and
Gemini's `cloud-platform` / `generative-language.retriever` are not
among them. So `login` uses the authorization code flow for native apps
(RFC 8252) with PKCE (RFC 7636).

- **Redirect to `http://127.0.0.1:<port>`.** Google accepts any port
  for a desktop client. `login` picks a random port in 49152-65535 and
  tries up to five in a row.
- **Two ways back.** It waits with `poll(2)` on both the listening
  socket and stdin. The browser's redirect arrives on the socket. When
  the browser can't reach this machine (SSH, a container, no socket
  allowed at all), the user pastes the error page's address into stdin
  instead. When no socket can listen, only the paste path is left. The
  redirect URI is the same in all cases, so the authorization request
  doesn't change.
- **`state`** is checked against the redirect, and the PKCE verifier
  goes with the code exchange. Both come from `/dev/urandom`, not
  contrib's `System.Random`, which has no C backend
  (`idris2-rc-cg/TODO.md`).
- **SHA-256 is written in Idris** (`Network.WebAPI.Auth.PKCE`). base and
  contrib have none, and binding libcrypto would add a dependency for
  hashing 43 bytes. It is checked against coreutils' `sha256sum` in
  `TestWebAPIPure`.
- **Tokens** are saved as JSON with mode 0600. The file is created
  empty, restricted, then written, so the refresh token is never
  readable by others. A refresh response usually has no refresh token,
  so the old one is kept.

## `poll(2)` without a shim

`struct pollfd[2]` is a `System.FFI.Struct` allocated with libc
`malloc`, as `ffi-without-shims.md` section 2 describes. Two things
were found along the way:

- **A `Buffer` doesn't work on rc2.** It is passed as `char *`, which
  gcc rejects against `poll.h`'s `struct pollfd *`. Dropping the
  header instead leaves `poll` undeclared.
- **Read the `Struct` before freeing it, in a way the compiler can't
  reorder.** `getField` is pure. Reading it in a `case` and then calling
  `free` compiled, on Chez, to a read *after* the free: `revents` came
  back wrong, and `login` sat waiting on stdin while the browser's
  request went unanswered. The cell is now allocated once per `login`
  and freed after the wait loop ends.

## Tests

`tests/verify.sh` runs three programs on both backends, with no
outbound network:

- `TestWebAPIPure`: hashing, JSON, URL and token encoding.
- `TestWebAPIChat`: `chat` against `tests/data/mock_api.py`, a
  stand-in API server.
- `TestWebAPILogin`: `login` against the same mock. It is driven by
  `tests/src/TestWebAPILogin.sh`, which plays the browser: it opens the
  authorization URL so the mock records the PKCE challenge, then
  returns the code through the loopback listener, by pasting, and as a
  refusal. The mock checks the verifier against the challenge.

The real services are exercised by hand with `examples/WebAPIChat.idr`
and `examples/WebAPILogin.idr`.
