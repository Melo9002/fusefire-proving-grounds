[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Initial,
    [string[]]$Rerun = @(),
    [string]$Baseline,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
function Read-Run([string]$path) {
    $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if ($data.PSObject.Properties.Name -notcontains "results" -or -not $data.suite) {
        throw "Not an Ironclad results file: $path"
    }
    return $data
}

function Is-Failure($entry) { $entry.status -in @("FAIL", "TIMEOUT") }
function Get-Verdict($run) {
    if ($run.verdict) { return $run.verdict }
    if ($run.failed -gt 0) { return "RED" }
    if ($run.blocked -or $run.unclassified) { return "INCOMPLETE" }
    return "GREEN"
}

$initialPath = (Resolve-Path -LiteralPath $Initial).Path
$first = Read-Run $initialPath
$baselineRun = if ($Baseline) { Read-Run $Baseline }
$seenAttempts = @{}
$followups = @(foreach ($path in $Rerun) {
    $absolute = (Resolve-Path -LiteralPath $path).Path
    $attempt = Read-Run $absolute
    if ($absolute -eq $initialPath -or ($attempt.run_id -and $attempt.run_id -eq $first.run_id)) {
        throw "The initial run cannot also be supplied as a rerun."
    }
    $id = if ($attempt.run_id) { $attempt.run_id } else { $absolute }
    if (-not $seenAttempts.ContainsKey($id)) {
        $seenAttempts[$id] = $true
        $attempt
    }
})
$details = @(
    foreach ($failure in $first.results | Where-Object { Is-Failure $_ }) {
        $attempts = @(foreach ($run in $followups) {
            foreach ($entry in $run.results | Where-Object name -eq $failure.name) {
                [pscustomobject]@{ run_id = $run.run_id; suite = $run.suite; revision = $run.revision; status = $entry.status }
            }
        })
        $pass = @($attempts | Where-Object status -eq "PASS").Count
        $repeat = @($attempts | Where-Object { Is-Failure $_ }).Count
        $evidence = if ($repeat -and $pass) { "MIXED" }
            elseif ($repeat) { "REPRODUCED" }
            elseif ($pass) { "PASSED_ON_RERUN" }
            else { "NOT_RETESTED" }
        $baselineEntry = if ($baselineRun) {
            $baselineRun.results | Where-Object name -eq $failure.name | Select-Object -First 1
        }
        [pscustomobject]@{
            name = $failure.name; original = $failure.status; rerun_evidence = $evidence
            baseline_status = if ($baselineEntry) { $baselineEntry.status }
            attempts = $attempts
        }
    }
)
$report = [ordered]@{
    initial_verdict = Get-Verdict $first
    initial_complete = if ($first.PSObject.Properties.Name -contains "complete") { $first.complete } else { $null }
    initial_suite = $first.suite
    initial_revision = $first.revision
    baseline_revision = if ($baselineRun) { $baselineRun.revision }
    original_failures = $details.Count
    passed_on_rerun = @($details | Where-Object rerun_evidence -eq "PASSED_ON_RERUN").Count
    without_clean_rerun = @($details | Where-Object rerun_evidence -ne "PASSED_ON_RERUN").Count
    failures = $details
}
if ($Json) { $report | ConvertTo-Json -Depth 7; return }

"Original $($report.initial_suite): $($report.initial_verdict). $($report.original_failures) failed entries; $($report.passed_on_rerun) passed on rerun; $($report.without_clean_rerun) mixed, still failing or untested."
foreach ($row in $details) {
    $baselineText = if ($row.baseline_status) { " (baseline $($row.baseline_status))" } else { "" }
    "  $($row.name): $($row.original) -> $($row.rerun_evidence)$baselineText"
}
"Rerun and baseline outcomes are observations. Classify their causes separately."
