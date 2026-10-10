$desktop = [Environment]::GetFolderPath('Desktop')
if (-not (Test-Path $desktop)) {
    $desktop = [System.IO.Path]::Combine($env:USERPROFILE, "OneDrive", "Desktop")
}
if (-not (Test-Path $desktop)) {
    $desktop = [System.IO.Path]::Combine($env:USERPROFILE, "Desktop")
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = Split-Path -Parent $scriptDir
$targetExe = Join-Path $projectDir "gmwf_pressure_test.exe"

if (-not (Test-Path $targetExe)) {
    $targetExe = Join-Path $projectDir "build\windows\x64\runner\Release\gmwf_pressure_test.exe"
}

$shortcutPath = Join-Path $desktop "GMWF Network Pressure Test.lnk"
$ws = New-Object -ComObject WScript.Shell
$s = $ws.CreateShortcut($shortcutPath)
$s.TargetPath = $targetExe
$s.WorkingDirectory = $projectDir
$s.Description = "GMWF LAN Network Pressure & Real Device Chaos Audit"
$s.Save()

Write-Host "✅ Created shortcut at: $shortcutPath"
Write-Host "   Target: $targetExe"
