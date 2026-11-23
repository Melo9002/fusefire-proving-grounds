<#
.SYNOPSIS
  ADDA (AniLab Diagnostic & Debugging Assistant) from the command line: run a Workbench scenario headlessly and write a structured report, inspect a finding, compare two reports.

.DESCRIPTION
  Wraps tools/adda/adda.gd (see docs/claude/adda/07-usage.md). Runs at a fixed 60 fps by default so two runs are comparable.

.EXAMPLE
  .\tools\adda.ps1 list
  .\tools\adda.ps1 run -Scenario landing -Character small_mira_0 -Mesh -Out artifacts/adda/small-landing.json
  .\tools\adda.ps1 inspect -Report artifacts/adda/small-landing.json -Finding F1
  .\tools\adda.ps1 compare -A artifacts/adda/before.json -B artifacts/adda/after.json
#>
param(
	[Parameter(Mandatory = $true, Position = 0)][ValidateSet("run", "inspect", "compare", "list", "isolate", "challenges", "score")][string]$Command,
	[string]$Scenario,
	[string]$Character = "mira_0",
	[switch]$Unarmed,
	[switch]$Mesh,
	[ValidateSet("summary", "full")][string]$Detail = "summary",
	[string]$Window,
	[string]$Out,
	[int]$Fps = 60,
	[string]$FailOn,
	[string]$Report,
	[string]$Finding,
	[string]$Row,
	[string]$A,
	[string]$B,
	[string]$At,
	[string]$Bones,
	[string]$Disable,
	[string]$Set,
	[string]$Challenge,
	[string]$Fault,
	[string]$Stage,
	[string]$Bone,
	[string]$Kind,
	[string]$Godot
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if (-not $Godot) {
	$found = Get-Command godot_console -ErrorAction SilentlyContinue
	if ($found) { $Godot = $found.Source } else { throw "godot_console is not on PATH; pass -Godot <path to godot_console.exe>" }
}
$arguments = @("--headless")
if ($Command -in @("run", "isolate")) { $arguments += @("--fixed-fps", "$Fps") }
$arguments += @("--path", $root, "--script", "res://tools/adda/adda.gd", "--", $Command)
switch ($Command) {
	"run" {
		if (-not $Scenario) { throw "run needs -Scenario <id> (.\tools\adda.ps1 list shows them)" }
		$arguments += "--scenario=$Scenario", "--character=$Character", "--fps=$Fps", "--detail=$Detail"
		if ($Unarmed) { $arguments += "--unarmed" }
		if ($Mesh) { $arguments += "--mesh" }
		if ($Window) { $arguments += "--window=$Window" }
		if ($Out) { $arguments += "--out=$Out" }
		if ($FailOn) { $arguments += "--fail-on=$FailOn" }
		if ($Challenge) { $arguments += "--challenge=$Challenge" }
		if ($Fault) { $arguments += "--fault=$Fault" }
		if ($Disable) { $arguments += "--disable=$Disable" }
		if ($Set) { $arguments += "--set=$Set" }
	}
	"isolate" {
		if (-not $Scenario -or -not $At -or -not $Bones) { throw "isolate needs -Scenario <id> -At <seconds> -Bones <name|@role,...>" }
		$arguments += "--scenario=$Scenario", "--character=$Character", "--at=$At", "--bones=$Bones"
		if ($Unarmed) { $arguments += "--unarmed" }
		if ($Window) { $arguments += "--window=$Window" }
		if ($Challenge) { $arguments += "--challenge=$Challenge" }
		if ($Fault) { $arguments += "--fault=$Fault" }
		if ($Out) { $arguments += "--out=$Out" }
	}
	"score" {
		if (-not $Challenge) { throw "score needs -Challenge <id> and the parts of your answer: -Stage <modifier> -Bone <name|@role> -Kind <offset|pop|drift|yaw|none>" }
		$arguments += "--challenge=$Challenge"
		if ($Stage) { $arguments += "--stage=$Stage" }
		if ($Bone) { $arguments += "--bone=$Bone" }
		if ($Kind) { $arguments += "--kind=$Kind" }
	}
	"inspect" {
		if (-not $Report) { throw "inspect needs -Report <file>" }
		$arguments += "--report=$Report"
		if ($Finding) { $arguments += "--finding=$Finding" }
		if ($Row) { $arguments += "--n=$Row" }
	}
	"compare" {
		if (-not $A -or -not $B) { throw "compare needs -A <report> -B <report>" }
		$arguments += "--a=$A", "--b=$B"
		if ($Out) { $arguments += "--out=$Out" }
		if ($FailOn) { $arguments += "--fail-on=$FailOn" }
	}
}
& $Godot @arguments
exit $LASTEXITCODE
