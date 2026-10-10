<#
  GMWF network baseline - run on EACH PC (cable and Wi-Fi) before/after the stress test.
  Usage (PowerShell):   .\network_baseline.ps1 -Server 192.168.1.8
  Output: GMWF_Network_Baseline_<PC>_<time>.txt and .json in the current folder and on the Desktop.
  It only reads: ping, adapter info, Wi-Fi signal and a TCP connect test to the GMWF port. Nothing is changed.
#>
param(
  [Parameter(Mandatory = $true)][string]$Server,
  [int]$Port = 53281,
  [int]$PingCount = 100
)

$ErrorActionPreference = 'SilentlyContinue'
$stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$pc = $env:COMPUTERNAME

Write-Host "Pinging $Server x $PingCount ..." -ForegroundColor Cyan
$replies = Test-Connection -ComputerName $Server -Count $PingCount -ErrorAction SilentlyContinue
$times = @($replies | ForEach-Object { if ($_.PSObject.Properties["ResponseTime"]) { $_.ResponseTime } else { $_.Latency } }) | Where-Object { $_ -ne $null }
$sent = $PingCount
$got = $times.Count
$lossPct = [math]::Round(($sent - $got) * 100.0 / $sent, 1)
if ($got -gt 0) {
  $sorted = $times | Sort-Object
  $avg = [math]::Round(($times | Measure-Object -Average).Average, 1)
  $min = $sorted[0]
  $max = $sorted[-1]
  $p95 = $sorted[[int][math]::Floor(($got - 1) * 0.95)]
  $diffs = for ($i = 1; $i -lt $times.Count; $i++) { [math]::Abs($times[$i] - $times[$i - 1]) }
  $jitter = if ($diffs) { [math]::Round(($diffs | Measure-Object -Average).Average, 1) } else { 0 }
} else { $avg = $min = $max = $p95 = $jitter = $null }

Write-Host "TCP connect test to ${Server}:$Port (20 tries) ..." -ForegroundColor Cyan
$connectMs = @()
$connectFail = 0
1..20 | ForEach-Object {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  try {
    $c = New-Object Net.Sockets.TcpClient
    $iar = $c.BeginConnect($Server, $Port, $null, $null)
    if ($iar.AsyncWaitHandle.WaitOne(2000)) { $c.EndConnect($iar); $connectMs += $sw.ElapsedMilliseconds } else { $connectFail++ }
    $c.Close()
  } catch { $connectFail++ }
  Start-Sleep -Milliseconds 200
}
$connAvg = if ($connectMs.Count) { [math]::Round(($connectMs | Measure-Object -Average).Average, 1) } else { $null }

$route = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object RouteMetric | Select-Object -First 1)
$activeAdapter = if ($route) { Get-NetAdapter -InterfaceIndex $route.ifIndex } else { $null }
$wifi = (netsh wlan show interfaces) -join "`n"
$signal = if ($wifi -match 'Signal\s*:\s*(\d+)%') { [int]$Matches[1] } else { $null }
$ssid = if ($wifi -match '\n\s*SSID\s*:\s*(.+)') { $Matches[1].Trim() } else { $null }
$rate = if ($wifi -match 'Receive rate \(Mbps\)\s*:\s*([\d\.]+)') { $Matches[1] } else { $null }
$powerSave = (powercfg /getactivescheme) -join ' '

$result = [ordered]@{
  generatedAt   = (Get-Date).ToString('s')
  pc            = $pc
  server        = "${Server}:$Port"
  adapter       = if ($activeAdapter) { "$($activeAdapter.Name) ($($activeAdapter.InterfaceDescription))" } else { $null }
  linkSpeed     = if ($activeAdapter) { $activeAdapter.LinkSpeed } else { $null }
  wifiSsid      = $ssid
  wifiSignalPct = $signal
  wifiRateMbps  = $rate
  ping          = [ordered]@{ sent = $sent; received = $got; lossPercent = $lossPct; minMs = $min; avgMs = $avg; p95Ms = $p95; maxMs = $max; jitterMs = $jitter }
  tcpConnect    = [ordered]@{ tries = 20; failed = $connectFail; avgMs = $connAvg }
  powerPlan     = $powerSave
}

$verdict = @()
$icmpBlocked = ($got -eq 0 -and $connectFail -lt 20)
if ($icmpBlocked) {
  $verdict += "INFO: ping is blocked by the server's firewall (normal). Using the TCP connect time instead: avg ${connAvg}ms"
  if ($connAvg -ne $null -and $connAvg -gt 50) { $verdict += "WARN: TCP connect avg ${connAvg}ms (target <= 50ms)" }
} elseif ($lossPct -gt 1) { $verdict += "FAIL: packet loss $lossPct% (target <= 1%)" }
if ($p95 -ne $null -and $p95 -gt 50) { $verdict += "WARN: p95 latency ${p95}ms (target <= 50ms on LAN)" }
if ($jitter -ne $null -and $jitter -gt 20) { $verdict += "WARN: jitter ${jitter}ms (target <= 20ms)" }
if ($connectFail -gt 0) { $verdict += "FAIL: $connectFail/20 TCP connects to the GMWF port failed" }
if ($signal -ne $null -and $signal -lt 60) { $verdict += "WARN: Wi-Fi signal $signal% (target >= 60%)" }
if (-not $verdict) { $verdict = @('PASS: link looks healthy') }
$result['verdict'] = $verdict

$json = $result | ConvertTo-Json -Depth 5
function Flat($v) {
  if ($v -is [System.Collections.IDictionary]) { return (($v.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '; ') }
  if ($v -is [array]) { return ($v -join ' | ') }
  return "$v"
}
$txt = @("GMWF NETWORK BASELINE - $pc - $stamp", ('-' * 60)) + ($result.GetEnumerator() | ForEach-Object { "{0,-14}: {1}" -f $_.Key, (Flat $_.Value) })

$name = "GMWF_Network_Baseline_${pc}_$stamp"
foreach ($dir in @((Get-Location).Path, [Environment]::GetFolderPath('Desktop'))) {
  $json | Out-File -Encoding utf8 (Join-Path $dir "$name.json")
  $txt  | Out-File -Encoding utf8 (Join-Path $dir "$name.txt")
}
$txt | ForEach-Object { Write-Host $_ }
Write-Host "`nSaved: $name.txt / .json (current folder and Desktop)" -ForegroundColor Green
