<#
.SYNOPSIS
Measure all combat reliability conditions in bounded, separate Godot processes.
#>
[CmdletBinding()]
param(
    [ValidateRange(128, 2048)][int]$Samples = 2048,
    [string]$Godot = "godot_console"
)
$ErrorActionPreference = "Stop"
trap { Write-Error $_ -ErrorAction Continue; exit 1 }
# Automated native failures must return an exit code rather than leave an
# unattended Windows error dialog open. This does not convert failures to PASS.
Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public static class FuseFireMeasurementErrorMode { [DllImport("kernel32.dll")] public static extern uint SetErrorMode(uint mode); }'
[void][FuseFireMeasurementErrorMode]::SetErrorMode(0x8002)
$repoRoot = Split-Path -Parent $PSScriptRoot
$runRelative = "artifacts/reliability-" + (Get-Date -Format "yyyyMMdd-HHmmss")
$runPath = Join-Path $repoRoot $runRelative
New-Item -ItemType Directory -Path $runPath -Force | Out-Null

function Invoke-Condition([string]$Name, [int]$Count) {
    $outputPath = Join-Path $runPath ($Name + ".json")
    $consolePath = Join-Path $runPath ($Name + ".log")
    $enginePath = Join-Path $runPath ($Name + ".godot.log")
    $arguments = @("--headless", "--path", $repoRoot, "--script", "res://tests/combat_reliability_test.gd", "--log-file", $enginePath, "--", $outputPath)
    if ($Name -ne "inventory") { $arguments += @($Name, [string]$Count) }
    & $Godot @arguments *> $consolePath
    $processResult = $LASTEXITCODE
    if ($processResult -ne 0) { throw "Godot failed for $Name with exit $processResult. See $consolePath" }
    if (Select-String -Path $consolePath -Pattern "SCRIPT ERROR|Parse Error|Compile Error" -Quiet) { throw "Unexpected script error for $Name. See $consolePath" }
    return Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
}

# Discover the case list from the bounded regression itself; do not maintain
# another list of condition names that could drift from the assertions.
$inventory = Invoke-Condition "inventory" 128
$measurements = @()
foreach ($row in $inventory.rows) {
    if ($row.name -notmatch '^[a-z0-9_]+$') { throw "Unsafe condition name" }
    $result = Invoke-Condition $row.name $Samples
    if (@($result.rows).Count -ne 1 -or $result.rows[0].name -ne $row.name -or $result.samples_per_case -ne $Samples -or $result.first_seed -ne $inventory.first_seed -or $result.tuning_signature -ne $inventory.tuning_signature) {
        throw "Inconsistent measurement metadata for $($row.name)"
    }
    $measurements += $result.rows[0]
    Write-Host ("[PASS] {0}: {1}/{2} hits" -f $row.name, $result.rows[0].hits, $Samples)
}
$summary = [ordered]@{ first_seed=$inventory.first_seed; samples_per_case=$Samples; tuning_signature=$inventory.tuning_signature; rows=$measurements }
$summaryPath = Join-Path $runPath "summary.json"
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding utf8
Write-Host "Reliability measurement: $($measurements.Count) conditions, all processes exited zero. $summaryPath"

exit 0
