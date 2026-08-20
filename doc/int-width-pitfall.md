# `Int`'s own width is backend-dependent -- avoid sentinel/negative values in `%foreign` arguments

Found while binding `curl_mime_data`'s own `datasize` (`size_t`)
argument, initially passed `curl/curl.h`'s own `CURL_ZERO_TERMINATED`
sentinel (`(size_t)-1`) via a plain Idris `-1 : Int`.

## What went wrong

Idris's own plain `Int` maps to a **32-bit C `int`** under the Chez
backend specifically (`Compiler.Scheme.Chez`'s own
`cftySpec CFInt = "int"`), but RefC and rc2 both treat `CFInt` as
**64-bit** (`cTypeOfCFType CFInt = "int64_t"`/`idris2rc2_to_i64`, in
each backend's own `Emit.idr`/`RefC.idr`).

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
string, past the end of the actual allocation), while RefC and rc2
were unaffected (both already treat `Int` as 64-bit, so their own `-1`
bit pattern is already all-ones).

## Why `Int64` doesn't fix it either

Switching the FFI argument's own type to `Int64` makes Chez's own bit
pattern for `-1` correctly all-ones too (`cftySpec CFInt64 =
"integer-64"`) -- but breaks RefC instead: RefC's own `cTypeOfCFType`/
`extractValue`/`packCFType` have no `CFInt64` case reachable through
however the actual installed toolchain's frontend produces it here,
crashing at compile time with "INTERNAL ERROR: Unknown FFI type in C
backend: Int_64". Confirmed directly, not just inferred: rc2 (which
does have a `CFInt64` case in its own `Emit.idr`) built this exact
same declaration successfully.

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
