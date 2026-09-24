# Linux compiler work bench

Console timer for the fill-and-sum kernel. No Bombardier, nginx, or Apache. This is the quickest way to see the codegen difference.

The accompanying `webbroker-standalone` project runs the same kernel inside an HTTP request.

## Build

1. Open `LinuxWorkBench.dproj` in 13.1 or 13.2.
2. Platform **Linux64**, configuration **Release**.
3. Deploy and run through PAServer.

If 13.2 offers to upgrade the project, that is fine for that session. Keep a copy of the folder for 13.1 if the older IDE then refuses the file.

A Windows build is a different compiler. Debug and Release builds are not comparable. Use Release for both versions.

## What you should see

Both binaries print compiler version, RTL, and a checksum. RTL 37.1 is 13.1. RTL 37.2 is 13.2. The checksum must match before you compare timings. For the default 400 passes it is `228495196160`.

Compare the **per call** milliseconds. Your wall-clock result depends on the machine.

```
LinuxWorkBench
LinuxWorkBench 400 200
```

First argument is passes (default 400). Second is how many times to repeat the timed loop (default 200).
