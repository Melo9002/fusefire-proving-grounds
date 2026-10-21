<#
.SYNOPSIS
Runs FuseFire's Project Ironclad test tiers through Godot 4.x.

.EXAMPLE
.\tools\run_tests.ps1 smoke

.EXAMPLE
.\tools\run_tests.ps1 subsystem -Subsystem combat

.EXAMPLE
.\tools\run_tests.ps1 full

.EXAMPLE
.\tools\run_tests.ps1 full -List

.NOTES
Rendered capture and long stress/batch scripts remain explicit-only and are listed by the full tier.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("smoke", "subsystem", "full")]
    [string]$Tier = "smoke",

    [ValidateSet("combat", "movement", "ai", "replay", "generation", "missions", "assets", "ui")]
    [string]$Subsystem,

    [string]$Godot = "godot_console",
    [string]$LogDirectory,
    [switch]$List,
    [switch]$ProbeFailureHandling
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$testsRoot = Join-Path $repoRoot "tests"

$smokeTests = @(
    "battle_dependency_isolation_test.gd",
    "tactical_action_service_test.gd",
    "map_validation_smoke.gd",
    "objective_foundation_smoke.gd",
    "ai_commander_policy_smoke.gd",
    "replay_schema_test.gd",
    "debug_draw_3d_integration_test.gd",
    "asset_calibration_test.gd",
    "battle_smoke.gd"
)

$subsystemPatterns = @{
    combat     = "action|aim_|ap_|combat|condition|overwatch|shield|shot_|supply|tempo|archetype"
    movement   = "movement|path_|traversal|elevation|locomotion|map_data|vault"
    ai         = "^ai_|commander|objective_ai|protect_rescue_ai|rescue_carrier|rescue_refinery|squad_context|survive_ai"
    replay     = "replay|determinism|seed_failure"
    generation = "battlefield|coherent_|container_maps|flat_map|generated_|industrial_|modular_|semantic_district|structural_|map_generation|map_quality|map_validation|transport_placement"
    missions   = "mission|objective|rescue|enemy_evacuation|survive_ai|transport_placement"
    assets     = "asset|environment_asset|locomotion|pose|unit_visual"
    ui         = "camera|debug_|feedback|hud|map_editor|match_setup|pause|portrait|visualizer|world_bar"
}

# Explicitly invoked workflows: rendered captures require a GPU/output path; extended
# batches are valuable but too expensive for the ordinary full tier.
$visualTests = @(
    "asset_lab_capture.gd",
    "coherent_layout_capture.gd",
    "debug_draw_3d_capture.gd",
    "industrial_warehouse_capture.gd",
    "semantic_asset_contact_sheet.gd",
    "semantic_asset_review_capture.gd",
    "semantic_machine_connection_capture.gd",
    "spatial_transform_capture.gd",
    "coherent_road_orientation_capture.gd",
	"coherent_asset_first_frontage_capture.gd",
    "structural_building_capture.gd"
)
$extendedTests = @(
    "ai_match_simulation_smoke.gd",
    "battlefield_stress_smoke.gd",
    "container_maps_smoke.gd",
    "map_quality_metrics_smoke.gd",
    "prototype_1_milestone.gd"
)

$allTests = @(Get-ChildItem -LiteralPath $testsRoot -Filter "*.gd" -File | Sort-Object Name)
$selectedNames = @()
$skippedNames = @()

switch ($Tier) {
    "smoke" {
        $selectedNames = $smokeTests
    }
    "subsystem" {
        if ([string]::IsNullOrWhiteSpace($Subsystem)) {
			[Console]::Error.WriteLine("-Subsystem is required for the subsystem tier. Valid names: $($subsystemPatterns.Keys -join ', ').")
            exit 2
        }
        $pattern = $subsystemPatterns[$Subsystem]
        $explicitOnly = @($visualTests + $extendedTests)
        $selectedNames = @($allTests | Where-Object { $_.BaseName -match $pattern -and $_.Name -notin $explicitOnly } | ForEach-Object Name)
        $skippedNames = @($allTests | Where-Object { $_.BaseName -match $pattern -and $_.Name -in $explicitOnly } | ForEach-Object Name)
    }
    "full" {
        $excluded = @($visualTests + $extendedTests)
        $selectedNames = @($allTests | Where-Object { $_.Name -notin $excluded } | ForEach-Object Name)
        $skippedNames = @($allTests | Where-Object { $_.Name -in $excluded } | ForEach-Object Name)
    }
}

$entries = @(
    [pscustomobject]@{ Name = "project_parse"; Script = $null; Kind = "parse" }
)
foreach ($name in $selectedNames) {
    $entries += [pscustomobject]@{ Name = [IO.Path]::GetFileNameWithoutExtension($name); Script = "res://tests/$name"; Kind = "test" }
}
if ($ProbeFailureHandling) {
    $entries += [pscustomobject]@{ Name = "intentional_failure_probe"; Script = "res://tools/quality/ironclad_failure_probe.gd"; Kind = "probe" }
}
$suiteLabel = $Tier
if (-not [string]::IsNullOrWhiteSpace($Subsystem)) {
    $suiteLabel += "/$Subsystem"
}

if ($List) {
    Write-Host "FuseFire Project Ironclad - $suiteLabel"
    $entries | ForEach-Object { Write-Host "  $($_.Name)" }
    if ($skippedNames.Count -gt 0) {
        Write-Host "Explicit-only checks excluded from this tier:"
        $skippedNames | ForEach-Object { Write-Host "  $_" }
    }
    exit 0
}

$godotCommand = Get-Command $Godot -ErrorAction SilentlyContinue
if ($null -eq $godotCommand) {
	[Console]::Error.WriteLine("Required Godot executable '$Godot' was not found. Install Godot 4.x or pass its executable path through -Godot.")
    exit 2
}

if ([string]::IsNullOrWhiteSpace($LogDirectory)) {
    $LogDirectory = Join-Path $repoRoot "artifacts/test-results"
} elseif (-not [IO.Path]::IsPathRooted($LogDirectory)) {
	# Tests receive this directory through FUSEFIRE_TEST_OUTPUT_DIR. Keep it
	# absolute so Godot never interprets a CI-relative path under user://.
	$LogDirectory = Join-Path $repoRoot $LogDirectory
}
$runName = Get-Date -Format "yyyyMMdd-HHmmss"
$runDirectory = Join-Path $LogDirectory ("$runName-" + $suiteLabel.Replace("/", "-"))
New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null

$passed = 0
$failed = 0
$totalWatch = [Diagnostics.Stopwatch]::StartNew()
$testOutputDirectory = Join-Path $runDirectory "test-output"
New-Item -ItemType Directory -Path $testOutputDirectory -Force | Out-Null
$previousTestOutput = $env:FUSEFIRE_TEST_OUTPUT_DIR
$env:FUSEFIRE_TEST_OUTPUT_DIR = $testOutputDirectory
Push-Location $repoRoot
try {
    Write-Host "FuseFire Project Ironclad - $suiteLabel"
    Write-Host "Godot: $($godotCommand.Source)"
    Write-Host "Logs:  $runDirectory"
    foreach ($entry in $entries) {
        $logPath = Join-Path $runDirectory "$($entry.Name).log"
        if ($entry.Kind -ne "parse") {
            $localPath = Join-Path $repoRoot ($entry.Script.Replace("res://", "").Replace("/", [IO.Path]::DirectorySeparatorChar))
            if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
                "Required test script is missing: $($entry.Script)" | Set-Content -LiteralPath $logPath
                Write-Host "[FAIL] $($entry.Name) - missing script"
                $failed++
                continue
            }
        }
		$engineLogPath = Join-Path $runDirectory "$($entry.Name).godot.log"
        $arguments = if ($entry.Kind -eq "parse") {
			# --import waits for a clean checkout's class cache and imported assets.
			# A frame-limited editor launch can quit while the import scan is active.
            @("--headless", "--log-file", $engineLogPath, "--path", $repoRoot, "--import")
        } else {
            @("--headless", "--log-file", $engineLogPath, "--path", $repoRoot, "--script", $entry.Script)
        }
        $watch = [Diagnostics.Stopwatch]::StartNew()
		$stdoutPath = "$logPath.stdout.tmp"
		$stderrPath = "$logPath.stderr.tmp"
        try {
			# Start-Process waits for both console- and GUI-subsystem Godot builds.
			# Direct invocation with '&' returns immediately for Godot's windowed
			# Windows executable, leaving $LASTEXITCODE unset and tests concurrent.
			$launchArguments = @($arguments | ForEach-Object {
				if ($_ -match '[\s"]') { '"' + $_.Replace('"', '\"') + '"' } else { $_ }
			})
			$process = Start-Process -FilePath $godotCommand.Source -ArgumentList $launchArguments `
				-Wait -PassThru -NoNewWindow `
				-RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
			$output = @()
			if (Test-Path -LiteralPath $stdoutPath) {
				$output += @(Get-Content -LiteralPath $stdoutPath)
			}
			if (Test-Path -LiteralPath $stderrPath) {
				$output += @(Get-Content -LiteralPath $stderrPath)
			}
			$exitCode = $process.ExitCode
        } catch {
            $output = @($_ | Out-String)
            $exitCode = 1
		} finally {
			Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
        }
		if ($null -eq $exitCode) {
			$output += "Godot process completed without reporting an exit code. Treating the result as a runner failure."
			$exitCode = 1
		}
        $watch.Stop()
        $output | Set-Content -LiteralPath $logPath
        if ($exitCode -eq 0) {
            Write-Host ("[PASS] {0} ({1:n2}s)" -f $entry.Name, $watch.Elapsed.TotalSeconds)
            $passed++
        } else {
            Write-Host ("[FAIL] {0} ({1:n2}s, exit {2})" -f $entry.Name, $watch.Elapsed.TotalSeconds, $exitCode)
            $output | Select-Object -Last 25 | ForEach-Object { Write-Host "       $_" }
            $failed++
        }
    }
} finally {
    Pop-Location
	if ($null -eq $previousTestOutput) {
		Remove-Item Env:FUSEFIRE_TEST_OUTPUT_DIR -ErrorAction SilentlyContinue
	} else {
		$env:FUSEFIRE_TEST_OUTPUT_DIR = $previousTestOutput
	}
    $totalWatch.Stop()
}

$skipped = $skippedNames.Count
$summary = "PASS=$passed FAIL=$failed SKIP=$skipped TIME=$('{0:n2}' -f $totalWatch.Elapsed.TotalSeconds)s"
$summary | Set-Content -LiteralPath (Join-Path $runDirectory "summary.txt")
Write-Host ""
Write-Host "Ironclad summary: $summary"
if ($skipped -gt 0) {
    Write-Host "Explicit-only checks: $($skippedNames -join ', ')"
}
Write-Host "Detailed logs: $runDirectory"
exit $(if ($failed -gt 0) { 1 } else { 0 })
