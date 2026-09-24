# 10000 requests, concurrency 1, 5, 10, 25, 3 runs, 30 s cooldown.
# Default work=400. -Work 0 skips the CPU workload.
# -FullLadder extends concurrency through 500 (5xx possible from c=50).
#
#   .\bench.ps1 -TargetHost <linux-ip> -Label 13.1
#   .\bench.ps1 -TargetHost <linux-ip> -Label 13.2

param(
    [string]$TargetHost = "127.0.0.1",
    [int]$Port = 8081,
    [Parameter(Mandatory = $true)]
    [string]$Label,
    [int]$Requests = 10000,
    [string]$TestPath = "/api/test",
    [int]$Work = 400,
    [switch]$FullLadder,
    [int]$WarmupRequests = 1000,
    [int]$WarmupConcurrent = 10,
    [int]$Runs = 3,
    [int]$CooldownSeconds = 30
)

$ErrorActionPreference = "Stop"

if ($FullLadder) {
    $concurrencyLevels = @(1, 5, 10, 25, 50, 100, 150, 200, 250, 300, 350, 400, 450, 500)
}
else {
    $concurrencyLevels = @(1, 5, 10, 25)
}
$ResultsDir = Join-Path $PSScriptRoot "results"

function Find-Bombardier {
    $candidates = @(
        (Join-Path $PSScriptRoot "bombardier.exe"),
        (Join-Path (Get-Location) "bombardier.exe")
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return (Resolve-Path $c).Path }
    }
    $cmd = Get-Command bombardier -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Get-LatencyMs {
    param([string]$Output)
    if ($Output -match 'Latency\s+(\d+\.?\d*)\s*(ms|us|µs|s)\b') {
        $value = [double]$matches[1]
        switch ($matches[2]) {
            "us" { return $value / 1000.0 }
            "µs" { return $value / 1000.0 }
            "s"  { return $value * 1000.0 }
            default { return $value }
        }
    }
    return 0.0
}

function Get-CodeCount {
    param(
        [string]$Output,
        [string]$CodeLabel
    )
    if ($Output -match ("{0}\s*-\s*(\d+)" -f [regex]::Escape($CodeLabel))) {
        return [int]$matches[1]
    }
    return 0
}

function Parse-BombardierOutput {
    param(
        [string]$Output,
        [int]$Requested
    )

    $rps = if ($Output -match 'Reqs/sec\s+(\d+\.?\d*)') { [double]$matches[1] } else { 0.0 }
    $latency = Get-LatencyMs $Output
    $http2xx = Get-CodeCount $Output "2xx"
    $http4xx = Get-CodeCount $Output "4xx"
    $http5xx = Get-CodeCount $Output "5xx"
    $others  = Get-CodeCount $Output "others"

    $errors = $http4xx + $http5xx + $others
    if ($http2xx -eq 0 -and $errors -eq 0) {
        $connHits = [regex]::Matches($Output, '(?i)(connectex|connection refused|connection reset|i/o timeout|no connection could be made|timed out).*?-\s+(\d+)')
        foreach ($m in $connHits) { $errors += [int]$m.Groups[2].Value }
        if ($errors -gt $Requested) { $errors = $Requested }
        $http2xx = [Math]::Max(0, $Requested - $errors)
    }

    $success = $http2xx
    if ($success -gt $Requested) { $success = $Requested }
    $successRate = if ($Requested -gt 0) { [Math]::Round(($success / $Requested) * 100, 2) } else { 0 }
    if ($errors -gt 0 -and $successRate -ge 100) { $successRate = 99.99 }

    return [PSCustomObject]@{
        Rps         = $rps
        LatencyMs   = $latency
        Http2xx     = $http2xx
        Http4xx     = $http4xx
        Http5xx     = $http5xx
        Others      = $others
        Errors      = $errors
        SuccessRate = $successRate
    }
}

function Invoke-Bombardier {
    param(
        [string]$BombardierPath,
        [string]$Url,
        [int]$Concurrency,
        [int]$Count
    )

    $tempFile = [System.IO.Path]::GetTempFileName()
    try {
        $p = Start-Process -FilePath $BombardierPath `
            -ArgumentList @("-c", "$Concurrency", "-n", "$Count", $Url) `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $tempFile `
            -RedirectStandardError "$tempFile.err"
        $stdout = Get-Content $tempFile -Raw -ErrorAction SilentlyContinue
        $stderr = Get-Content "$tempFile.err" -Raw -ErrorAction SilentlyContinue
        $combined = "$stdout`n$stderr"
        if ($p.ExitCode -ne 0 -and [string]::IsNullOrWhiteSpace($combined)) {
            $combined = "bombardier exit $($p.ExitCode)"
        }
        return $combined
    }
    finally {
        Remove-Item $tempFile, "$tempFile.err" -ErrorAction SilentlyContinue
    }
}

function Get-SafeLabel {
    param([string]$Value)
    $safe = $Value.Trim()
    foreach ($ch in [System.IO.Path]::GetInvalidFileNameChars()) {
        $safe = $safe.Replace([string]$ch, "_")
    }
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = "run" }
    return $safe
}

function Write-Log {
    param([string]$Message, [string]$Color = "Gray")
    $line = "{0}  {1}" -f (Get-Date -Format "HH:mm:ss"), $Message
    Write-Host $line -ForegroundColor $Color
    if ($script:progressLog) {
        Add-Content -Path $script:progressLog -Value $line
    }
}

function New-ResultRow {
    param(
        [string]$SafeLabel,
        [int]$Run,
        [int]$Concurrency,
        [int]$ReqCount,
        [int]$WorkAmount,
        $Parsed,
        [string]$Rtl,
        [string]$CompilerVer,
        [string]$Started,
        [string]$Url,
        [string]$Stamp,
        [string]$Notes = ""
    )
    [PSCustomObject]@{
        label             = $SafeLabel
        run               = $Run
        concurrency       = $Concurrency
        requests          = $ReqCount
        work              = $WorkAmount
        rps               = [Math]::Round($Parsed.Rps, 2)
        latency_ms        = [Math]::Round($Parsed.LatencyMs, 2)
        success_rate      = $Parsed.SuccessRate
        errors            = $Parsed.Errors
        http_2xx          = $Parsed.Http2xx
        http_4xx          = $Parsed.Http4xx
        http_5xx          = $Parsed.Http5xx
        others            = $Parsed.Others
        rtl               = $Rtl
        compiler_version  = $CompilerVer
        started           = $Started
        url               = $Url
        timestamp         = $Stamp
        notes             = $Notes
    }
}

function Show-Comparison {
    param([string]$Dir)

    $path131 = Join-Path $Dir "13.1.csv"
    $path132 = Join-Path $Dir "13.2.csv"
    if (-not ((Test-Path $path131) -and (Test-Path $path132))) {
        Write-Host ""
        Write-Host "Comparison table appears after both results\13.1.csv and results\13.2.csv exist (those files are the averaged ladders)." -ForegroundColor DarkGray
        return
    }

    $old = @(Import-Csv $path131)
    $new = @(Import-Csv $path132)
    $oldMeta = $old | Select-Object -First 1
    $newMeta = $new | Select-Object -First 1

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "13.1 (LLVM 3.3) vs 13.2 (LLVM 20)  [averaged ladders]" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host ("13.1: rtl={0}  started={1}  work={2}" -f $oldMeta.rtl, $oldMeta.started, $oldMeta.work)
    Write-Host ("13.2: rtl={0}  started={1}  work={2}" -f $newMeta.rtl, $newMeta.started, $newMeta.work)
    if ($oldMeta.work -ne $newMeta.work) {
        Write-Host "WARNING: work= differs between CSVs. Compare only matching workloads." -ForegroundColor Yellow
    }
    if ($oldMeta.rtl -and $newMeta.rtl -and ($oldMeta.rtl -eq $newMeta.rtl) -and ($oldMeta.started -eq $newMeta.started)) {
        Write-Host "WARNING: both labels hit the same rtl/started fingerprint. Redeploy the other IDE's binary before comparing." -ForegroundColor Yellow
    }
    if ([int]$oldMeta.work -eq 0 -or [int]$newMeta.work -eq 0) {
        Write-Host "WARNING: work=0 skips CPU work, so both compilers look similar. Use the default work=400 to compare them." -ForegroundColor Yellow
    }
    $hdr = "{0,-6} {1,10} {2,10} {3,10} {4,10} {5,10}"
    Write-Host ($hdr -f "c", "13.1 rps", "13.2 rps", "delta", "13.1 ms", "13.2 ms")
    Write-Host ($hdr -f "------", "----------", "----------", "----------", "----------", "----------")

    $levels = @($old + $new | ForEach-Object { [int]$_.concurrency } | Sort-Object -Unique)
    foreach ($c in $levels) {
        $o = $old | Where-Object { [int]$_.concurrency -eq $c } | Select-Object -First 1
        $n = $new | Where-Object { [int]$_.concurrency -eq $c } | Select-Object -First 1
        if (-not $o -or -not $n) { continue }

        $oldOk = ([double]$o.success_rate -ge 100) -and ([int]$o.errors -eq 0)
        $newOk = ([double]$n.success_rate -ge 100) -and ([int]$n.errors -eq 0)
        $oldRps = [double]$o.rps
        $newRps = [double]$n.rps
        if (-not $oldOk -or -not $newOk) {
            Write-Host ("{0,-6} {1,10:N0} {2,10:N0} {3,10} {4,10:N2} {5,10:N2}  (skip: not 100% success)" -f
                $c, $oldRps, $newRps, "n/a",
                [double]$o.latency_ms, [double]$n.latency_ms) -ForegroundColor DarkGray
            continue
        }

        $delta = if ($oldRps -gt 0) { (($newRps - $oldRps) / $oldRps) * 100 } else { 0 }
        $deltaText = ("{0:+0.0;-0.0}%" -f $delta).PadLeft(10)
        $color = if ($delta -ge 0) { "Green" } else { "Yellow" }

        Write-Host ("{0,-6} {1,10:N0} {2,10:N0} {3,10} {4,10:N2} {5,10:N2}" -f
            $c, $oldRps, $newRps, $deltaText,
            [double]$o.latency_ms, [double]$n.latency_ms) -ForegroundColor $color
    }
}

$bombardier = Find-Bombardier
if (-not $bombardier) {
    Write-Host "ERROR: bombardier.exe not found." -ForegroundColor Red
    Write-Host "Download: https://github.com/codesenberg/bombardier/releases" -ForegroundColor Yellow
    Write-Host "Place bombardier-windows-amd64.exe as bombardier.exe in this folder." -ForegroundColor Yellow
    exit 1
}

$safeLabel = Get-SafeLabel $Label
$sep = if ($TestPath.Contains("?")) { "&" } else { "?" }
$url = "http://${TargetHost}:${Port}${TestPath}${sep}work=${Work}"

$cellsPerRun = $concurrencyLevels.Count
$cooldownCells = $cellsPerRun * $Runs
if ($WarmupRequests -gt 0) { $cooldownCells += 1 }
if ($Runs -gt 1) { $cooldownCells += ($Runs - 1) }
$estMin = [Math]::Ceiling(($cooldownCells * $CooldownSeconds) / 60.0)

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Standalone Linux benchmark (work=$Work)" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Label:     $safeLabel"
Write-Host "URL:       $url"
Write-Host "Requests:  $Requests"
Write-Host "Work:      $Work  (default 400; 0 skips CPU work)"
Write-Host "Runs:      $Runs"
Write-Host "Cooldown:  ${CooldownSeconds}s after each cell and between runs"
Write-Host "Concurrency: $($concurrencyLevels -join ', ')$(if ($FullLadder) { '  (-FullLadder)' } else { '' })"
Write-Host "Tool:      $bombardier"
Write-Host "Sleep time: about ${estMin} min of cooldowns (plus bombardier itself)"
Write-Host ""

Write-Host "Smoke test..." -ForegroundColor Gray
$rtl = ""
$compilerVer = ""
$started = ""
try {
    $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 8
    $body = [string]$resp.Content
    $ok = ($resp.StatusCode -eq 200) -and (($body.TrimStart().StartsWith("{")) -or ([string]$resp.Headers["Content-Type"] -match "json"))
    if (-not $ok) {
        Write-Host "ERROR: $url did not return HTTP 200 JSON." -ForegroundColor Red
        Write-Host $body.Substring(0, [Math]::Min(200, $body.Length))
        exit 2
    }
    Write-Host "  HTTP $($resp.StatusCode)" -ForegroundColor Green
    try {
        $json = $body | ConvertFrom-Json
        $rtl = [string]$json.rtl
        $compilerVer = [string]$json.compiler_version
        $started = [string]$json.started
        if ($rtl) {
            Write-Host "  status=$($json.status)  rtl=$rtl  compiler=$compilerVer  started=$started  work=$($json.work)  checksum=$($json.checksum)" -ForegroundColor Cyan
        }
        else {
            Write-Host "  WARNING: JSON has no rtl field. Redeploy the binary from this folder so the script can tell 13.1 from 13.2." -ForegroundColor Yellow
        }
    }
    catch { }
}
catch {
    Write-Host "ERROR: cannot reach $url" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Start Standalone on Linux (port $Port) and pass -TargetHost <linux-ip>." -ForegroundColor Yellow
    exit 2
}

if (-not (Test-Path $ResultsDir)) {
    New-Item -ItemType Directory -Path $ResultsDir | Out-Null
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$script:progressLog = Join-Path $ResultsDir "${safeLabel}_${stamp}_progress.log"
$avgCsvPath = Join-Path $ResultsDir "${safeLabel}_${stamp}_avg.csv"
$labelCsvPath = Join-Path $ResultsDir "$safeLabel.csv"
$runCsvPaths = @()
$allRows = @()

Write-Log ("Session stamp $stamp  cells/run=$cellsPerRun  runs=$Runs  cooldown=${CooldownSeconds}s") "Cyan"

if ($WarmupRequests -gt 0) {
    Write-Log "Warmup: -n $WarmupRequests -c $WarmupConcurrent" "Gray"
    [void](Invoke-Bombardier -BombardierPath $bombardier -Url $url -Concurrency $WarmupConcurrent -Count $WarmupRequests)
    Write-Log "Cooldown ${CooldownSeconds}s after warmup" "DarkGray"
    Start-Sleep -Seconds $CooldownSeconds
}

for ($run = 1; $run -le $Runs; $run++) {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Log ("RUN $run / $Runs") "Cyan"
    Write-Host "==================================================" -ForegroundColor Cyan

    $runRows = @()
    $cell = 0
    foreach ($concurrency in $concurrencyLevels) {
        $cell++
        Write-Log ("[$safeLabel] run $run  cell $cell/$cellsPerRun  c=$concurrency  $url") "Cyan"
        $output = Invoke-Bombardier -BombardierPath $bombardier -Url $url -Concurrency $concurrency -Count $Requests
        $parsed = Parse-BombardierOutput -Output $output -Requested $Requests
        $color = if ($parsed.Errors -gt 0) { "Red" } else { "Green" }
        Write-Log ("  Reqs/sec: {0:F2}  Latency: {1:F2} ms  Success: {2}/{3} ({4} pct)  errors={5}" -f `
            $parsed.Rps, $parsed.LatencyMs, $parsed.Http2xx, $Requests, $parsed.SuccessRate, $parsed.Errors) $color

        $row = New-ResultRow -SafeLabel $safeLabel -Run $run -Concurrency $concurrency `
            -ReqCount $Requests -WorkAmount $Work -Parsed $parsed `
            -Rtl $rtl -CompilerVer $compilerVer -Started $started -Url $url -Stamp $stamp
        $runRows += $row
        $allRows += $row

        Write-Log "Cooldown ${CooldownSeconds}s" "DarkGray"
        Start-Sleep -Seconds $CooldownSeconds
    }

    $runCsv = Join-Path $ResultsDir "${safeLabel}_${stamp}_run${run}.csv"
    $runRows | Export-Csv -Path $runCsv -NoTypeInformation -Encoding UTF8
    $runCsvPaths += $runCsv
    Write-Log "Wrote $runCsv" "Cyan"

    if ($run -lt $Runs) {
        Write-Log "Cooldown ${CooldownSeconds}s between full runs" "Yellow"
        Start-Sleep -Seconds $CooldownSeconds
    }
}

$avgRows = foreach ($concurrency in $concurrencyLevels) {
    $group = @($allRows | Where-Object { [int]$_.concurrency -eq $concurrency })
    $clean = @($group | Where-Object { [int]$_.errors -eq 0 -and [double]$_.success_rate -ge 100 })
    $bad = @($group | Where-Object { [int]$_.errors -gt 0 -or [double]$_.success_rate -lt 100 })
    $used = if ($clean.Count -gt 0) { $clean } else { $group }

    $rpsAvg = [Math]::Round((($used | ForEach-Object { [double]$_.rps }) | Measure-Object -Average).Average, 2)
    $latAvg = [Math]::Round((($used | ForEach-Object { [double]$_.latency_ms }) | Measure-Object -Average).Average, 2)
    $srAvg  = [Math]::Round((($group | ForEach-Object { [double]$_.success_rate }) | Measure-Object -Average).Average, 2)
    $errSum = (($group | ForEach-Object { [int]$_.errors }) | Measure-Object -Sum).Sum
    $h2 = [int][Math]::Round((($used | ForEach-Object { [double]$_.http_2xx }) | Measure-Object -Average).Average)
    $h4 = [int][Math]::Round((($group | ForEach-Object { [double]$_.http_4xx }) | Measure-Object -Average).Average)
    $h5 = [int][Math]::Round((($group | ForEach-Object { [double]$_.http_5xx }) | Measure-Object -Average).Average)
    $ho = [int][Math]::Round((($group | ForEach-Object { [double]$_.others }) | Measure-Object -Average).Average)

    $nClean = $clean.Count
    $nGroup = $group.Count
    if ($nClean -eq $nGroup) {
        $note = "avg of $nClean/$nGroup runs"
    }
    elseif ($nClean -gt 0) {
        $excl = ($bad | ForEach-Object { "run$($_.run) errors=$($_.errors) success=$($_.success_rate) pct" }) -join "; "
        $note = "avg of $nClean/$nGroup runs; excluded: $excl"
    }
    else {
        $note = "NO clean runs; averaged $nGroup error cells"
    }

    [PSCustomObject]@{
        label             = $safeLabel
        run               = "avg"
        concurrency       = $concurrency
        requests          = $Requests
        work              = $Work
        rps               = $rpsAvg
        latency_ms        = $latAvg
        success_rate      = $srAvg
        errors            = $errSum
        http_2xx          = $h2
        http_4xx          = $h4
        http_5xx          = $h5
        others            = $ho
        rtl               = $rtl
        compiler_version  = $compilerVer
        started           = $started
        url               = $url
        timestamp         = $stamp
        notes             = $note
    }
}

$avgRows | Export-Csv -Path $avgCsvPath -NoTypeInformation -Encoding UTF8
$avgRows | Export-Csv -Path $labelCsvPath -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ("           AVERAGED SUMMARY ($Runs runs)") -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ("{0,-12} {1,12} {2,15} {3,12} {4,10} {5}" -f "Concurrency", "Reqs/sec", "Latency (ms)", "Success pct", "Errors", "Notes")
Write-Host ("{0,-12} {1,12} {2,15} {3,12} {4,10} {5}" -f "-----------", "--------", "------------", "---------", "------", "-----")
foreach ($row in $avgRows) {
    $color = if ([int]$row.errors -gt 0) { "Red" } else { "Green" }
    Write-Host ("{0,-12} {1,12} {2,15} {3,12} {4,10} {5}" -f
        $row.concurrency,
        $row.rps.ToString("F2"),
        $row.latency_ms.ToString("F2"),
        ([string]$row.success_rate + " pct"),
        $row.errors,
        $row.notes) -ForegroundColor $color
}

Write-Host ""
Write-Host "Results written:" -ForegroundColor Cyan
foreach ($p in $runCsvPaths) { Write-Host "  $p" }
Write-Host "  $avgCsvPath"
Write-Host "  $labelCsvPath"
Write-Host "  $script:progressLog"
Write-Log ("Benchmark completed ($Runs runs, ${CooldownSeconds}s cooldown).") "Cyan"

Show-Comparison -Dir $ResultsDir
Write-Host ""
