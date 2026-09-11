# `Int`'s own width is backend-dependent -- avoid sentinel/negative values in `%foreign` arguments

Found while binding `curl_mime_data`'s own `datasize` (`size_t`)
argument, initially passed `curl/curl.h`'s own `CURL_ZERO_TERMINATED`
sentinel (`(size_t)-1`) via a plain Idris `-1 : Int`.

## What went wrong

Idris's own plain `Int` maps to a **32-bit C `int`** under the Chez
backend specifically (`Compiler.Scheme.Chez`'s own
`cftySpec CFInt = "int"`), but rc2 treats `CFInt` as **64-bit**
(`cTypeOfCFType CFInt = "int64_t"`/`idris2rc2_to_i64`, in its own
`Emit.idr`).

For a small non-negative value (`0`, `1`, `41`, ...) this never
matters -- the same bit pattern reads correctly whether the receiving
C function treats it as 32-bit or 64-bit, sign or zero extension makes
no difference. It matters the moment the *bit pattern itself* is
meant to carry meaning independent of the number's own mathematical
value -- exactly what `(size_t)-1` (all-ones, "unbounded"/"compute it
yourself" as a sentinel, not literally "negative one") is. A 32-bit
`-1`'s own bit pattern (`0xFFFFFFFF`) is not the same 64-bit value as
`(size_t)-1` (`0xFFFFFFFFFFFFFFFF`) -- confirmed directly: passing
`-1 : Int` here crashed with "invalid memory reference" under Chez
specifically (libcurl reading `datasize` bytes starting from a 5-byte
string, past the end of the actual allocation), while rc2 was
unaffected (already treats `Int` as 64-bit, so its own `-1` bit
pattern is already all-ones).

## Why `Int64` wasn't reached for instead

Switching the FFI argument's own type to `Int64` would make Chez's own
bit pattern for `-1` correctly all-ones too (`cftySpec CFInt64 =
"integer-64"`), and rc2 already has a working `CFInt64` case in its
own `Emit.idr` -- so `Int64` would in fact have fixed this cleanly on
both of this project's current backends. It was originally rejected
because this project also targeted upstream RefC at the time, and real
upstream RefC's own `cTypeOfCFType`/`extractValue`/`packCFType` had no
`CFInt64` case reachable through however the actual installed
toolchain's frontend produced it, crashing at compile time with
"INTERNAL ERROR: Unknown FFI type in C backend: Int_64". Recorded here
for the historical reasoning even though RefC is no longer a target --
the "avoid sentinel bit patterns" fix below is still the better
practice regardless (works identically on any future backend, no
width assumption to get right at all), so the code was never reverted
to `Int64` after RefC support was dropped.

## The actual fix: never rely on a sentinel bit pattern

`Network.Curl.Raw`'s own `curlMimeData` sidesteps the whole problem by
never passing `CURL_ZERO_TERMINATED` at all -- it passes the string's
own real UTF-8 byte length (`Data.Buffer.stringByteLength`) instead. A
small positive value's own bit pattern reads identically regardless
of whether the receiving side treats the argument as 32-bit or
64-bit, so which width `Int` happens to map to on a given backend
stops mattering.

## The general lesson for any future `%foreign` binding here

Avoid passing a negative value, or any value meant to be read as a
raw bit pattern rather than a mathematical quantity (a sentinel, a
bitmask meant to fill every bit, `~0`-style "all features"/"no
limit" constants), as a plain `Int` `%foreign` argument. If a C API
genuinely needs one, prefer computing an actual value that means the
same thing (as `curlMimeData` does here) over trying to pick an FFI
argument type that happens to have the "right" width on every
backend -- there isn't one that reliably does, per the `Int`/`Int64`
story above.
