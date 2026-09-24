# Delphi Linux compiler benchmark

Same code, built with Delphi 13.1 (Linux LLVM 3.3, RTL 37.1) and Delphi 13.2 (Linux LLVM 20, RTL 37.2). The application source does not change. The compiler and RTL do.

- `linux-work-bench` times the fill-and-sum kernel in a console app, with no HTTP in the measurement.
- `webbroker-standalone` runs that kernel inside a standalone WebBroker request. A PowerShell script drives Bombardier.

This is the standalone portion of the comparison. It does not include the Apache module or FastCGI setup.

## Requirements

- RAD Studio 13.1 and/or 13.2
- A Linux64 target with PAServer
- Release configuration for every measured build
- Windows PowerShell and [Bombardier](https://github.com/codesenberg/bombardier/releases) for the HTTP test

You need both RAD Studio versions to reproduce the comparison. One version can still build and run, it just cannot show the difference by itself.

A Windows build is a different compiler. Debug and Release builds are not comparable.

## linux-work-bench

Open `linux-work-bench/LinuxWorkBench.dproj`, select Linux64 and Release, then deploy and run through PAServer. Repeat with the other RAD Studio version.

Both binaries must print the checksum `228495196160` for the default 400 passes. Compare the reported milliseconds per call only after the checksums match.

```
LinuxWorkBench
LinuxWorkBench 400 200
```

First argument is passes (default 400). Second is how many times to repeat the timed loop (default 200).

## webbroker-standalone

Follow `webbroker-standalone/README.md`. The same checksum appears in the `/api/test` JSON response.

The default script runs 10,000 requests at concurrency 1, 5, 10, and 25, three times, with a 30-second cooldown. Compare only rows where both builds completed every request. A full comparison of both builds takes at least 16 minutes with those cooldowns.

`-FullLadder` extends concurrency through 500. On this standalone server that can return 5xx from concurrency 50. Failed requests are not throughput.
