# Binding `curl_multi_*`: output pointers throughout, RefC/rc2-only

Every function actually driving a multi-handle transfer loop --
`curl_multi_perform`, `curl_multi_wait`, `curl_multi_info_read` --
takes at least one write-through output-pointer argument, the same
kind of shape `curl_easy_getinfo` (`doc/variadic-getinfo.md`) and
`curl_url_get` (`doc/const-char-ffi.md`-adjacent reasoning) already
needed a `csrc/` shim for. `curl_multi_init`/`curl_multi_cleanup`/
`curl_multi_add_handle`/`curl_multi_remove_handle`/
`curl_multi_strerror` don't have this problem (plain arguments/return,
or -- for `curl_multi_strerror` -- the same `const char *` cast
`curl_easy_strerror` needed) and are bound directly/via the usual
three-target pattern.

## The three shims

`csrc/idris2curl_compat.h`:

- `idris2curl_multi_perform`: collapses `curl_multi_perform`'s own
  `int *running_handles` and its `CURLMcode` result together into one
  `int` -- the running-handle count on `CURLM_OK`, `-1` on anything
  else. The two aren't actually ambiguous: a running-handle count is
  always `>= 0`.
- `idris2curl_multi_wait`: same idea for `curl_multi_wait`'s own
  `int *ret` (fds signalled). Its own `extra_fds`/`extra_nfds` (watch
  additional non-easy-handle sockets too) aren't exposed -- nothing
  this repo does yet needs them.
- `idris2curl_multi_info_read`: `curl_multi_info_read` itself already
  returns a pointer (`CURLMsg *`, `NULL` once the queue's empty), so
  the shim only needs to swallow its own `int *msgs_in_queue` (not
  useful yet -- every call site here just loops until `NULL`, never
  needing the remaining count up front) and hand the `CURLMsg *` back
  as an opaque `void *`.

## Reading a `CURLMsg` without `Struct`/`getField`

Same reasoning as `doc/version-info-struct.md`: rather than bind
`CURLMsg` as a `Struct` (Chez-only, upstream RefC doesn't implement
`getField`/`setField` at all), three more shims --
`idris2curl_multimsg_msg`/`_easy_handle`/`_result` -- each read one
field off the opaque pointer `idris2curl_multi_info_read` handed back.
`Network.Curl.Raw`'s own `curlMultiInfoRead` calls all three and
assembles `Maybe (CURLMSG, AnyPtr, CURLcode)` from them, so nothing
above that layer ever sees the raw pointer.

`data.result` is a union member only meaningful when
`msg == curlmsg_DONE` (`curl/multi.h`'s own `CURLMsg` doc comment) --
reading it for any other message value reads the union's other member
(`data.whatever`, a `void *`) reinterpreted as an `int`. Not undefined
behavior (same union, no uninitialized read), just meaningless; callers
are expected to check `msg` first, same as libcurl's own C API expects.

## No Chez binding at all -- same reasoning as `curl_easy_getinfo`

Confirmed the same way as every other RefC/rc2-only binding in this
repo: a `%foreign` with only `"RefC:..."`/`"RC2:..."` targets still
type-checks fine under Chez, only failing -- cleanly, "was not
accepted by any backend" -- at the specific call site of a program
that's actually compiled against Chez. `examples/Multi.idr` (the one
place `curlMultiPerform`/`curlMultiWait`/`curlMultiInfoRead` are
called) is RefC/rc2-only by construction, not part of Chez's own
examples build.
