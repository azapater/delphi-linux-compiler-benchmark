# Standalone Linux compiler benchmark

Same standalone WebBroker source, built with RAD Studio **13.1** (Linux LLVM 3.3, RTL 37.1) and **13.2** (Linux LLVM 20, RTL 37.2). The application source does not change. The compiler and RTL do.

`/api/test` runs the fill-and-sum kernel so the compiler difference shows up in latency and throughput. With `work=0` the handler returns JSON only, and both binaries look similar.

Each JSON response includes `compiler_version`, `rtl`, `started`, `work`, and `checksum` so you can confirm which binary answered and that both builds did the same work.

This is the standalone HTTP portion of the comparison. It does not reproduce the Apache module or FastCGI measurements. `linux-work-bench` times the same kernel without HTTP.

## Prerequisites

- RAD Studio **13.1** and/or **13.2**
- A Linux target with **PAServer**
- Windows PowerShell on the load-generating machine
- [Bombardier](https://github.com/codesenberg/bombardier/releases). Put `bombardier-windows-amd64.exe` in this folder as `bombardier.exe`.

Use your Linux IP.

## Build and run

1. Open `Standalone.dproj` in RAD Studio.
2. Platform **Linux64**, configuration **Release**.
3. Deploy and run via PAServer. The app listens on port **8081** as soon as it starts.
4. Confirm the console and `/api/test` show **RTL 37.1** for 13.1 and **RTL 37.2** for 13.2.
5. Confirm both responses contain the checksum **`228495196160`** when `work=400`.

If 13.2 offers to upgrade the project, you can allow it for that session. Keep a clean copy of this folder for 13.1 if the older IDE then refuses the file.

Press ENTER in the console to stop the server before switching binaries. Leave the process running while you measure.

`/api/test` with no query uses `work=400`. Pass `?work=0` only if you want JSON with no CPU work.

The Windows test machine must reach TCP port 8081 on the Linux target. If the smoke test cannot connect, check the target IP, PAServer deployment, and the Linux firewall before changing the benchmark.

## Measure

The script runs 10,000 requests at concurrency 1, 5, 10, and 25, with three runs and a 30-second cooldown. Concurrency 1 is the cleanest compiler comparison. One compiler spends about eight minutes in cooldowns, plus Bombardier. Allow at least 16 minutes to test both builds.

With the **13.1** binary running:

```powershell
.\bench.ps1 -TargetHost <linux-ip> -Label 13.1
```

Stop it, run the **13.2** binary, then:

```powershell
.\bench.ps1 -TargetHost <linux-ip> -Label 13.2
```

After both averages exist, the script prints the side-by-side table. Results and progress logs go to the `results` folder.

Only compare rows where both builds completed every request. Requests per second are misleading when the server returns errors.

## Optional parameters

- `-Work 0` runs the thin JSON test without the CPU workload.
- `-Work <passes>` changes the amount of CPU work per request.
- `-Requests <count>` changes the number of requests in each test point.
- `-Port <port>` uses a port other than 8081.
- `-FullLadder` extends concurrency through 500. The standalone server may return 5xx from concurrency 50. Do not treat those failed requests as throughput.

```powershell
.\bench.ps1 -TargetHost <linux-ip> -Label 13.2 -Work 400 -Requests 10000
```

The two builds also use different RTL versions. This compares complete Delphi 13.1 and 13.2 Linux builds, not LLVM in isolation.
