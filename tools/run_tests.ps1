<#
.SYNOPSIS
Runs FuseFire's Project Ironclad test tiers through Godot 4.x.

.DESCRIPTION
Every test under tests/*.gd is described in tests/catalog.json (subsystems, scope, criticality, FAST/SMOKE membership, explicit-only status).
The catalog is the single source for selection; discovery itself is still "every top-level tests/*.gd", so an unclassified test is
reported loudly and still runs in the full tier.

.EXAMPLE
.\tools\run_tests.ps1 fast
.\tools\run_tests.ps1 fast -Subsystem animation
.\tools\run_tests.ps1 smoke
.\tools\run_tests.ps1 subsystem -Subsystem combat
.\tools\run_tests.ps1 subsystem -Subsystem movement,replay -Critical
.\tools\run_tests.ps1 select -Test traversal_*,path_refiner_test
.\tools\run_tests.ps1 changed -Since HEAD
.\tools\run_tests.ps1 changed -Changed presentation/characters/rig/modifiers/cover_crouch_modifier.gd
.\tools\run_tests.ps1 full -List
.\tools\run_tests.ps1 full
.\tools\run_tests.ps1 check

.NOTES
-List shows what would run and why without executing. Rendered captures and long batch scripts are explicit-only: name them with
"select -Test <name>" (batches) or run captures directly without --headless.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("smoke", "fast", "subsystem", "select", "changed", "full", "check")]
    [string]$Tier = "smoke",

    [ValidateSet("core", "actions", "combat", "equipment", "movement", "animation", "ai", "missions", "rescue", "generation", "replay", "persistence", "ui", "assets", "tooling")]
    [string[]]$Subsystem,

    [string[]]$Test,
    [string[]]$Contract,
    [string[]]$Changed,
    [string]$Since,
    [switch]$Critical,
    [switch]$Thorough,

    [string]$Godot = "godot_console",
    [string]$LogDirectory,
    [int]$TimeoutSeconds = 900,
    [int]$Slowest = 5,
    [switch]$List,
    [switch]$Why,
    [switch]$Strict,
    [switch]$Import,
    [switch]$SkipImport,
    [switch]$ForceHeadless,
    [switch]$MeasureStartup,
    [switch]$ProbeFailureHandling
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$testsRoot = Join-Path $repoRoot "tests"
$catalogPath = Join-Path $testsRoot "catalog.json"
$baselinePath = Join-Path $repoRoot "docs/quality/test-timings-baseline.json"

$validSubsystems = @("core", "actions", "combat", "equipment", "movement", "animation", "ai", "missions", "rescue", "generation", "replay", "persistence", "ui", "assets", "tooling")
$validScopes = @("unit", "component", "integration", "battle", "e2e")
$validContracts = @("authority", "legality", "movement", "replay", "mission", "presentation-sync", "lifecycle", "persistence")
$validKinds = @("capture", "batch", "benchmark")

function Fail-Usage([string]$message) {
    [Console]::Error.WriteLine($message)
    exit 2
}

# ---------------------------------------------------------------- catalog
if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
    Fail-Usage "Test catalog is missing: $catalogPath"
}
try {
    $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
} catch {
    Fail-Usage "tests/catalog.json is not valid JSON: $($_.Exception.Message)"
}
$entries = @{}
foreach ($property in $catalog.tests.PSObject.Properties) { $entries[$property.Name] = $property.Value }
$allTests = @(Get-ChildItem -LiteralPath $testsRoot -Filter "*.gd" -File | Sort-Object Name)
$discovered = @($allTests | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_.Name) })

$catalogProblems = New-Object System.Collections.Generic.List[string]
$unclassified = @($discovered | Where-Object { -not $entries.ContainsKey($_) })
$stale = @($entries.Keys | Where-Object { $_ -notin $discovered } | Sort-Object)
foreach ($name in $unclassified) { $catalogProblems.Add("UNCLASSIFIED: tests/$name.gd has no entry in tests/catalog.json (it still runs in the full tier)") }
foreach ($name in $stale) { $catalogProblems.Add("STALE ENTRY: catalog lists '$name' but tests/$name.gd does not exist") }

function Get-Prop($entry, [string]$name, $default) {
    if ($null -ne $entry -and $entry.PSObject.Properties.Name -contains $name) { return $entry.$name }
    return $default
}

# Effective metadata for every discovered test (an unclassified *_capture script is treated as explicit-only, everything else as an ordinary headless test).
$meta = @{}
foreach ($name in $discovered) {
    $entry = if ($entries.ContainsKey($name)) { $entries[$name] } else { $null }
    $isCapture = $name -like "*_capture"
    $subs = @(Get-Prop $entry "sub" @())
    $scope = [string](Get-Prop $entry "scope" "")
    $run = [string](Get-Prop $entry "run" $(if ($null -eq $entry -and $isCapture) { "explicit" } else { "standard" }))
    $req = [string](Get-Prop $entry "req" $(if ($null -eq $entry -and $isCapture) { "render" } else { "headless" }))
    $kind = [string](Get-Prop $entry "kind" $(if ($run -eq "explicit" -and $req -eq "render") { "capture" } else { "" }))
    $contracts = @(Get-Prop $entry "contracts" @())
    $meta[$name] = [pscustomobject]@{
        Name = $name; Sub = $subs; Scope = $scope; Contracts = $contracts
        Critical = ([string](Get-Prop $entry "crit" "") -eq "critical")
        Smoke = [bool](Get-Prop $entry "smoke" $false); Fast = [bool](Get-Prop $entry "fast" $false)
        Explicit = ($run -eq "explicit"); Req = $req; Kind = $kind; Classified = ($null -ne $entry)
    }
    if ($null -ne $entry) {
        foreach ($s in $subs) { if ($s -notin $validSubsystems) { $catalogProblems.Add("INVALID: $name has unknown subsystem '$s'") } }
        if ($subs.Count -eq 0) { $catalogProblems.Add("INVALID: $name has no subsystem") }
        if ($scope -notin $validScopes) { $catalogProblems.Add("INVALID: $name has unknown scope '$scope'") }
        foreach ($c in $contracts) { if ($c -notin $validContracts) { $catalogProblems.Add("INVALID: $name has unknown contract '$c'") } }
        if ($run -notin @("standard", "explicit")) { $catalogProblems.Add("INVALID: $name has unknown run mode '$run'") }
        if ($run -eq "explicit" -and $kind -notin $validKinds) { $catalogProblems.Add("INVALID: explicit test $name needs a kind (capture, batch or benchmark)") }
        if ($run -eq "explicit" -and ($meta[$name].Smoke -or $meta[$name].Fast)) { $catalogProblems.Add("INVALID: explicit-only test $name cannot be in FAST or SMOKE") }
        if ($req -ne "headless" -and ($meta[$name].Smoke -or $meta[$name].Fast)) { $catalogProblems.Add("INVALID: $name needs rendering and cannot be in FAST or SMOKE") }
    }
}
foreach ($area in $catalog.areas) {
    foreach ($s in $area.sub) { if ($s -notin $validSubsystems) { $catalogProblems.Add("INVALID: area '$($area.path)' has unknown subsystem '$s'") } }
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $area.path))) { $catalogProblems.Add("STALE: area '$($area.path)' names a path that does not exist") }
}
# Changed-file selection is only as good as the area table: a source file no area covers is "unmapped" and falls back to every critical test, which does NOT include the
# non-critical suite that guards it (Task 14 found this for presentation/motion and research/). Every script and scene under the source roots must match an area.
foreach ($sourceRoot in @("systems", "units", "presentation", "research", "ui", "levels", "tools", "content", "art")) {
    $rootPath = Join-Path $repoRoot $sourceRoot
    if (-not (Test-Path -LiteralPath $rootPath)) { continue }
    foreach ($file in (Get-ChildItem -LiteralPath $rootPath -Recurse -File | Where-Object { $_.Extension -in @(".gd", ".tscn") })) {
        $relative = $file.FullName.Substring($repoRoot.Length + 1).Replace("\", "/")
        $covered = $false
        foreach ($area in $catalog.areas) { if ($relative.StartsWith($area.path)) { $covered = $true; break } }
        if (-not $covered) { $catalogProblems.Add("UNMAPPED: $relative is covered by no area in tests/catalog.json (changed-file selection would not know which tests guard it)") }
    }
}

function Show-CatalogProblems {
    if ($catalogProblems.Count -gt 0) {
        Write-Host ""
        Write-Host "TEST CATALOG PROBLEMS ($($catalogProblems.Count)):"
        $catalogProblems | ForEach-Object { Write-Host "  $_" }
    }
}

if ($Tier -eq "check") {
    $explicitCount = @($meta.Values | Where-Object { $_.Explicit }).Count
    Write-Host "Test catalog: $($discovered.Count) discovered scripts, $($entries.Count) catalog entries, $explicitCount explicit-only, $(@($meta.Values | Where-Object { $_.Fast }).Count) FAST, $(@($meta.Values | Where-Object { $_.Smoke }).Count) SMOKE"
    Show-CatalogProblems
    if ($catalogProblems.Count -gt 0) { exit 2 }
    Write-Host "Catalog is complete and consistent."
    exit 0
}

# ---------------------------------------------------------------- baseline timings (measured with the previous runner; informational)
$baseline = @{}
if (Test-Path -LiteralPath $baselinePath -PathType Leaf) {
    try {
        $b = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json
        foreach ($p in $b.tests.PSObject.Properties) { $baseline[$p.Name] = [double]$p.Value }
    } catch { }
}

# ---------------------------------------------------------------- selection
$selected = New-Object System.Collections.Generic.List[object]   # @{ Name; Reason }
$skippedExplicit = @()
$selectionTitle = $Tier
$smokeNames = @($discovered | Where-Object { $meta[$_].Smoke })

# Tests that reference a fixture/support file (a path under tests/ below the top level), directly or transitively through other fixture/support files. Matching is by the
# res:// path string (the way tests preload fixtures) or by the fixture's class_name when it declares one; the area-table fallback covers anything neither finds.
$script:testSourceIndex = $null
function Get-FixtureReferrers([string]$relativePath) {
    if ($null -eq $script:testSourceIndex) {
        $script:testSourceIndex = @{}
        foreach ($file in (Get-ChildItem -LiteralPath $testsRoot -Recurse -File -Include *.gd, *.tscn, *.tres)) {
            $relative = $file.FullName.Substring($repoRoot.Length + 1).Replace("\", "/")
            $script:testSourceIndex[$relative] = Get-Content -LiteralPath $file.FullName -Raw
        }
    }
    $found = New-Object System.Collections.Generic.HashSet[string]
    $seen = New-Object System.Collections.Generic.HashSet[string]
    $queue = New-Object System.Collections.Generic.Queue[string]
    [void]$seen.Add($relativePath)
    $queue.Enqueue($relativePath)
    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        $needle = "res://$current"
        # A fixture that declares a class_name is also reached by that name.
        $classPattern = $null
        if ($script:testSourceIndex.ContainsKey($current)) {
            $declared = [regex]::Match($script:testSourceIndex[$current], '(?m)^class_name\s+(\w+)')
            if ($declared.Success) { $classPattern = '\b' + $declared.Groups[1].Value + '\b' }
        }
        foreach ($candidate in $script:testSourceIndex.Keys) {
            if ($candidate -eq $current) { continue }
            $text = $script:testSourceIndex[$candidate]
            if (-not $text.Contains($needle) -and ($null -eq $classPattern -or -not [regex]::IsMatch($text, $classPattern))) { continue }
            if ($candidate -match '^tests/[^/]+\.gd$') {
                [void]$found.Add([IO.Path]::GetFileNameWithoutExtension($candidate))
            } elseif ($seen.Add($candidate)) {
                $queue.Enqueue($candidate)
            }
        }
    }
    return @($found | Sort-Object)
}

function Add-Selection([string]$name, [string]$reason) {
    $existing = $selected | Where-Object { $_.Name -eq $name } | Select-Object -First 1
    if ($null -ne $existing) { if ($existing.Reason -notlike "*$reason*") { $existing.Reason += "; $reason" }; return }
    $selected.Add([pscustomobject]@{ Name = $name; Reason = $reason })
}
function Test-Filters($m) {
    if ($Subsystem -and -not (@($m.Sub | Where-Object { $_ -in $Subsystem }).Count)) { return $false }
    if ($Contract -and -not (@($m.Contracts | Where-Object { $_ -in $Contract }).Count)) { return $false }
    if ($Critical -and -not $m.Critical) { return $false }
    return $true
}
$subLabel = if ($Subsystem) { $Subsystem -join "," } else { "" }
$omittedNote = @()

switch ($Tier) {
    "smoke" {
        foreach ($n in $smokeNames) { if (Test-Filters $meta[$n]) { Add-Selection $n "SMOKE set" } }
        if ($smokeNames.Count -eq 0) { Fail-Usage "No test is marked smoke in the catalog." }
    }
    "fast" {
        $fastReason = "FAST (cheap, headless)" + $(if ($subLabel) { ", subsystem $subLabel" } else { "" })
        foreach ($n in $discovered) { $m = $meta[$n]; if ($m.Fast -and -not $m.Explicit -and (Test-Filters $m)) { Add-Selection $n $fastReason } }
    }
    "subsystem" {
        if (-not $Subsystem -and -not $Contract) { Fail-Usage "-Subsystem (or -Contract) is required for the subsystem tier. Valid subsystems: $($validSubsystems -join ', ')." }
        foreach ($n in $discovered) {
            $m = $meta[$n]
            if (-not (Test-Filters $m)) { continue }
            if ($m.Explicit) { $skippedExplicit += $n; continue }
            $reasonText = if ($Subsystem) { "subsystem $subLabel" } else { "contract $($Contract -join ',')" }
            Add-Selection $n ($reasonText + $(if ($Critical) { " (critical only)" } else { "" }))
        }
    }
    "select" {
        if (-not $Test) { Fail-Usage "-Test is required for the select tier (names or wildcards, e.g. -Test traversal_*,path_refiner_test)." }
        foreach ($pattern in $Test) {
            $pattern = $pattern -replace "\.gd$", ""
            $found = @($discovered | Where-Object { $_ -like $pattern })
            if ($found.Count -eq 0) { Fail-Usage "-Test '$pattern' matches no test script in tests/." }
            $isWildcard = $pattern -match '[\*\?]'
            foreach ($n in $found) {
                # A wildcard never pulls in an explicit-only script by accident; only an exact name does.
                if ($isWildcard -and $meta[$n].Explicit) { $skippedExplicit += $n; continue }
                Add-Selection $n "named by -Test $pattern"
            }
        }
    }
    "changed" {
        $paths = @()
        if ($Changed) { $paths += $Changed }
        if ($Since) {
            Push-Location $repoRoot
            try {
                $paths += @(git diff --name-only $Since)
                $paths += @(git ls-files --others --exclude-standard)
            } finally { Pop-Location }
        }
        if (-not $Changed -and -not $Since) { Fail-Usage "The changed tier needs -Changed <paths> or -Since <git ref>." }
        $paths = @($paths | Where-Object { $_ } | ForEach-Object { $_.Replace("\", "/") } | Sort-Object -Unique)
        $affected = New-Object System.Collections.Generic.HashSet[string]
        $slowOmitted = @()
        $broaden = $false
        $areaNotes = @()
        foreach ($path in $paths) {
            if ($path -match '^tests/[^/]+\.gd$') {
                $n = [IO.Path]::GetFileNameWithoutExtension($path)
                if ($meta.ContainsKey($n) -and -not $meta[$n].Explicit) { Add-Selection $n "the test itself changed" }
                continue
            }
            if ($path -like "tests/*" -and ($path -like "*.gd" -or $path -like "*.tscn" -or $path -like "*.tres" -or $path -like "*.json" -or $path -like "*.gdshader")) {
                # A fixture or support file (anything under tests/ that is not a top-level test script): select every test that references it, directly or through other fixture/support files.
                # tests/catalog.json is test metadata, not a fixture.
                if ($path -eq "tests/catalog.json") { continue }
                $referrers = @(Get-FixtureReferrers $path)
                $fixtureTests = @($referrers | Where-Object { $meta.ContainsKey($_) -and -not $meta[$_].Explicit })
                if ($fixtureTests.Count -gt 0) {
                    foreach ($n in $fixtureTests) { Add-Selection $n "references changed fixture/support file $path" }
                    $areaNotes += "$path -> $($fixtureTests.Count) referencing test(s) (fixture/support reference scan)"
                    continue
                }
                # Nothing references it: fall back to the area table, and say so.
                $fallback = $null
                foreach ($area in $catalog.areas) { if ($path.StartsWith($area.path) -and ($null -eq $fallback -or $area.path.Length -gt $fallback.path.Length)) { $fallback = $area } }
                if ($null -ne $fallback) {
                    foreach ($s in $fallback.sub) { [void]$affected.Add($s) }
                    $areaNotes += "$path -> unreferenced fixture/support file: fell back to subsystem $($fallback.sub -join '+')"
                } else {
                    $broaden = $true
                    $areaNotes += "$path -> unreferenced fixture/support file with no area: broadened to every critical test"
                }
                continue
            }
            if ($path -like "docs/*" -or $path -like "*.md" -or $path -like "*.import" -or $path -like "*.uid" -or $path -like "tests/*") { continue }
            $best = $null
            foreach ($area in $catalog.areas) { if ($path.StartsWith($area.path) -and ($null -eq $best -or $area.path.Length -gt $best.path.Length)) { $best = $area } }
            if ($null -eq $best) {
                $broaden = $true
                $areaNotes += "$path -> unmapped: broadened to every critical test"
                continue
            }
            foreach ($s in $best.sub) { [void]$affected.Add($s) }
            if ($best.central) { $broaden = $true; $areaNotes += "$path -> $($best.sub -join '+') (central area: critical tests of every subsystem added)" }
            else { $areaNotes += "$path -> $($best.sub -join '+')" }
        }
        foreach ($n in $discovered) {
            $m = $meta[$n]
            if ($m.Explicit) { continue }
            $inAffected = @($m.Sub | Where-Object { $affected.Contains($_) }).Count -gt 0
            if ($inAffected) {
                if ($Thorough) { Add-Selection $n "affected subsystem ($(($m.Sub | Where-Object { $affected.Contains($_) }) -join ','))" }
                elseif ($m.Fast -or $m.Smoke -or $m.Critical) { Add-Selection $n ("affected subsystem ($(($m.Sub | Where-Object { $affected.Contains($_) }) -join ',') ): " + $(if ($m.Critical) { "critical" } elseif ($m.Smoke) { "smoke" } else { "fast" })) }
            }
            if ($broaden -and $m.Critical) {
                if ($m.Scope -eq "e2e" -and -not $Thorough) { $slowOmitted += $n } else { Add-Selection $n "critical test of a central or unmapped change" }
            }
        }
        $selectionTitle = "changed ($($paths.Count) path(s))"
        $omittedNote = $areaNotes
        if ($slowOmitted.Count -gt 0) { $omittedNote += "omitted long end-to-end critical tests (add -Thorough to include): " + ($slowOmitted -join ", ") }
        if ($selected.Count -eq 0) { Write-Host "No test selected: the changed paths map to no test (docs/metadata only?)." }
    }
    "full" {
        foreach ($n in $discovered) {
            $m = $meta[$n]
            if ($m.Explicit) { $skippedExplicit += $n; continue }
            if (Test-Filters $m) { Add-Selection $n "full tier: every ordinary test" }
        }
    }
}
if ($Tier -in @("fast", "smoke") -and $Subsystem -and $selected.Count -eq 0) {
    Write-Host "No $Tier test is classified under: $subLabel. Use 'subsystem -Subsystem $subLabel' for its full set."
}

# Render-only tests cannot run headless: say so instead of letting them fail with an engine error.
$blocked = @()
$runnable = New-Object System.Collections.Generic.List[object]
foreach ($s in $selected) {
    $m = $meta[$s.Name]
    if ($m.Req -ne "headless" -and -not $ForceHeadless) { $blocked += $s.Name } else { $runnable.Add($s) }
}

$suiteLabel = $Tier
if ($Subsystem) { $suiteLabel += "/" + ($Subsystem -join "+") }
$lines = @()
$lines += "FuseFire Project Ironclad - $suiteLabel"
$lines += "  selected $($selected.Count) of $($discovered.Count) discovered test scripts; explicit-only in this tier: $($skippedExplicit.Count); not selected: $($discovered.Count - $selected.Count - $skippedExplicit.Count)"

if ($List -or $Why) {
    $lines | ForEach-Object { Write-Host $_ }
    $total = 0.0
    foreach ($s in $selected) {
        $m = $meta[$s.Name]
        $cost = if ($baseline.ContainsKey($s.Name)) { "{0,6:n1}s" -f $baseline[$s.Name] } else { "     ?" }
        if ($baseline.ContainsKey($s.Name)) { $total += $baseline[$s.Name] }
        $flagList = @()
        if ($m.Critical) { $flagList += "critical" }
        if ($m.Smoke) { $flagList += "smoke" }
        if ($m.Fast) { $flagList += "fast" }
        if ($m.Explicit) { $flagList += "explicit:" + $m.Kind }
        if ($m.Req -ne "headless") { $flagList += "needs-render" }
        if (-not $m.Classified) { $flagList += "UNCLASSIFIED" }
        $flags = $flagList -join ","
        $line = "  {0,-46} {1,-11} {2} [{3}]" -f $s.Name, $m.Scope, $cost, $flags
        if ($Why) { $line += "  <- $($s.Reason)" }
        Write-Host $line
    }
    if ($total -gt 0) { Write-Host ("  last measured total (previous runner, 1 s granularity, no import): about {0:n0} s" -f $total) }
    if ($blocked.Count -gt 0) { Write-Host "Selected but cannot run headless (rendering required): $($blocked -join ', ')" }
    if ($skippedExplicit.Count -gt 0) { Write-Host "Explicit-only checks excluded from this tier: $($skippedExplicit -join ', ')" }
    if ($omittedNote.Count -gt 0) { Write-Host "Path mapping:"; $omittedNote | ForEach-Object { Write-Host "  $_" } }
    if ($Tier -ne "full") {
        $unsel = @($discovered | Where-Object { $n = $_; (-not $meta[$n].Explicit) -and -not (@($selected | Where-Object { $_.Name -eq $n }).Count) })
        Write-Host "NOT verified by this selection: $($unsel.Count) ordinary test(s). Use the full tier for comprehensive regression."
    }
    Show-CatalogProblems
    exit 0
}

$godotCommand = Get-Command $Godot -ErrorAction SilentlyContinue
if ($null -eq $godotCommand) {
    Fail-Usage "Required Godot executable '$Godot' was not found. Install Godot 4.x or pass its executable path through -Godot."
}

# ---------------------------------------------------------------- run directory
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
$testOutputDirectory = Join-Path $runDirectory "test-output"
New-Item -ItemType Directory -Path $testOutputDirectory -Force | Out-Null

# ---------------------------------------------------------------- one Godot process
# System.Diagnostics.Process with async output readers: Start-Process -Wait costs a 1 s polling granularity per process
# (a no-op script took 1.02 s that way and 0.19 s here), and cannot enforce a timeout. A timed-out process tree is killed and reported as TIMEOUT.
function Invoke-Godot([string[]]$arguments, [int]$timeoutSeconds) {
    $quoted = $arguments | ForEach-Object { if ($_ -match '[\s"]') { '"' + $_.Replace('"', '\"') + '"' } else { $_ } }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $godotCommand.Source
    $psi.Arguments = ($quoted -join " ")
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $timedOut = $false
    $process = [Diagnostics.Process]::Start($psi)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($timeoutSeconds * 1000)) {
        $timedOut = $true
        & taskkill.exe /T /F /PID $process.Id *> $null
        $process.WaitForExit()
    } else {
        $process.WaitForExit()   # flush the redirected streams
    }
    $watch.Stop()
    $text = @()
    if ($stdout.Wait(5000)) { $text += @($stdout.Result -split "\r?\n") }
    if ($stderr.Wait(5000)) { $text += @($stderr.Result -split "\r?\n") }
    return [pscustomobject]@{ ExitCode = $(if ($timedOut) { $null } else { $process.ExitCode }); Output = $text; TimedOut = $timedOut; Seconds = $watch.Elapsed.TotalSeconds }
}

if ($MeasureStartup) {
    $probe = "res://tools/quality/startup_probe.gd"
    $times = @()
    foreach ($i in 1..5) { $times += (Invoke-Godot @("--headless", "--path", $repoRoot, "--script", $probe) 120).Seconds }
    Write-Host ("Godot process start-up with an empty script (5 runs): min {0:n3}s, median {1:n3}s, max {2:n3}s" -f ($times | Measure-Object -Minimum).Minimum, ($times | Sort-Object)[2], ($times | Measure-Object -Maximum).Maximum)
    exit 0
}

# ---------------------------------------------------------------- import freshness
function Test-ImportFresh {
    $stamp = Join-Path $repoRoot ".godot/ironclad-import.stamp"
    if (-not (Test-Path -LiteralPath $stamp)) { return $false }
    $stampTime = (Get-Item -LiteralPath $stamp).LastWriteTimeUtc
    $newest = [datetime]::MinValue
    foreach ($dir in @("systems", "units", "presentation", "ui", "levels", "art", "content", "tools", "addons")) {
        $path = Join-Path $repoRoot $dir
        if (-not (Test-Path -LiteralPath $path)) { continue }
        foreach ($file in (Get-ChildItem -LiteralPath $path -Recurse -File -Include *.gd, *.tscn, *.tres, *.gdshader, *.gdextension)) {
            if ($file.LastWriteTimeUtc -gt $newest) { $newest = $file.LastWriteTimeUtc }
        }
    }
    foreach ($file in (Get-ChildItem -LiteralPath $testsRoot -Recurse -File -Include *.gd, *.tscn, *.tres)) {
        if ($file.LastWriteTimeUtc -gt $newest) { $newest = $file.LastWriteTimeUtc }
    }
    $project = Get-Item -LiteralPath (Join-Path $repoRoot "project.godot")
    if ($project.LastWriteTimeUtc -gt $newest) { $newest = $project.LastWriteTimeUtc }
    return $newest -le $stampTime
}

$runEntries = @()
$importMode = if ($Import) { "always" } elseif ($SkipImport) { "never" } elseif ($Tier -in @("fast", "select", "changed")) { "auto" } else { "always" }
$doImport = switch ($importMode) { "always" { $true } "never" { $false } default { -not (Test-ImportFresh) } }
if ($doImport) { $runEntries += [pscustomobject]@{ Name = "project_parse"; Script = $null; Kind = "parse"; Reason = "project import / class cache" } }
foreach ($s in $runnable) {
    $runEntries += [pscustomobject]@{ Name = $s.Name; Script = "res://tests/$($s.Name).gd"; Kind = "test"; Reason = $s.Reason }
}
if ($ProbeFailureHandling) {
    $runEntries += [pscustomobject]@{ Name = "intentional_failure_probe"; Script = "res://tools/quality/ironclad_failure_probe.gd"; Kind = "probe"; Reason = "probe"; Timeout = $TimeoutSeconds }
    $runEntries += [pscustomobject]@{ Name = "zero_exit_script_error_probe"; Script = "res://tools/quality/ironclad_script_error_probe.gd"; Kind = "probe"; Reason = "probe"; Timeout = $TimeoutSeconds }
    $runEntries += [pscustomobject]@{ Name = "timeout_probe"; Script = "res://tools/quality/ironclad_timeout_probe.gd"; Kind = "probe"; Reason = "probe"; Timeout = 3 }
}

$passed = 0
$failed = 0
$timedOutCount = 0
$results = New-Object System.Collections.Generic.List[object]
$totalWatch = [Diagnostics.Stopwatch]::StartNew()
$previousTestOutput = $env:FUSEFIRE_TEST_OUTPUT_DIR
$env:FUSEFIRE_TEST_OUTPUT_DIR = $testOutputDirectory
$processSeconds = 0.0
Push-Location $repoRoot
try {
    Write-Host "FuseFire Project Ironclad - $suiteLabel"
    Write-Host "Godot: $($godotCommand.Source)"
    Write-Host "Logs:  $runDirectory"
    Write-Host $lines[1].Trim()
    foreach ($note in $omittedNote) { Write-Host "  $note" }
    if ($catalogProblems.Count -gt 0) {
        Write-Host "WARNING: $($catalogProblems.Count) test catalog problem(s); see the end of this run (run '.\tools\run_tests.ps1 check')."
    }
    foreach ($entry in $runEntries) {
        $logPath = Join-Path $runDirectory "$($entry.Name).log"
        if ($entry.Kind -ne "parse") {
            $localPath = Join-Path $repoRoot ($entry.Script.Replace("res://", "").Replace("/", [IO.Path]::DirectorySeparatorChar))
            if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
                "Required test script is missing: $($entry.Script)" | Set-Content -LiteralPath $logPath
                Write-Host "[FAIL] $($entry.Name) - missing script"
                $failed++
                $results.Add([pscustomobject]@{ name = $entry.Name; status = "FAIL"; seconds = 0.0; exit = $null; why = "missing script" })
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
        $limit = if ($entry.PSObject.Properties.Name -contains "Timeout" -and $entry.Timeout) { [int]$entry.Timeout } else { $TimeoutSeconds }
        $run = $null
        try {
            $run = Invoke-Godot $arguments $limit
            $output = @($run.Output)
            $exitCode = $run.ExitCode
        } catch {
            $output = @($_ | Out-String)
            $exitCode = 1
            $run = [pscustomobject]@{ TimedOut = $false; Seconds = 0.0 }
        }
        $processSeconds += $run.Seconds
        if ($run.TimedOut) {
            $output += "Ironclad: the process exceeded the $limit s limit and its process tree was killed."
        } elseif ($null -eq $exitCode) {
            $output += "Godot process completed without reporting an exit code. Treating the result as a runner failure."
            $exitCode = 1
        }
        # Godot can emit an unhandled script error and still exit zero.
        # Preserve expected application-level negative-test diagnostics, but
        # never accept unexpected parser/runtime script failures as PASS.
        $scriptErrorPattern = 'SCRIPT ERROR:|Parse Error:|Compile Error:'
        $engineScriptError = (Test-Path -LiteralPath $engineLogPath) -and
            (Select-String -LiteralPath $engineLogPath -Pattern $scriptErrorPattern -Quiet)
        if (-not $run.TimedOut -and $exitCode -eq 0 -and (($output -match $scriptErrorPattern) -or $engineScriptError)) {
            $output += "Runner rejected a zero exit after a script/parser error."
            $exitCode = 1
        }
        $output | Set-Content -LiteralPath $logPath
        $seconds = $run.Seconds
        if ($run.TimedOut) {
            Write-Host ("[TIMEOUT] {0} ({1:n2}s, limit {2} s)" -f $entry.Name, $seconds, $limit)
            $output | Select-Object -Last 10 | ForEach-Object { Write-Host "       $_" }
            $timedOutCount++
            $failed++
            $results.Add([pscustomobject]@{ name = $entry.Name; status = "TIMEOUT"; seconds = [math]::Round($seconds, 2); exit = $null; why = $entry.Reason })
        } elseif ($exitCode -eq 0) {
            Write-Host ("[PASS] {0} ({1:n2}s)" -f $entry.Name, $seconds)
            $passed++
            $results.Add([pscustomobject]@{ name = $entry.Name; status = "PASS"; seconds = [math]::Round($seconds, 2); exit = 0; why = $entry.Reason })
            if ($entry.Kind -eq "parse") { New-Item -ItemType File -Path (Join-Path $repoRoot ".godot/ironclad-import.stamp") -Force | Out-Null }
        } else {
            Write-Host ("[FAIL] {0} ({1:n2}s, exit {2})" -f $entry.Name, $seconds, $exitCode)
            $output | Select-Object -Last 25 | ForEach-Object { Write-Host "       $_" }
            $failed++
            $results.Add([pscustomobject]@{ name = $entry.Name; status = "FAIL"; seconds = [math]::Round($seconds, 2); exit = $exitCode; why = $entry.Reason })
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

$skipped = $skippedExplicit.Count
$summary = "PASS=$passed FAIL=$failed SKIP=$skipped TIME=$('{0:n2}' -f $totalWatch.Elapsed.TotalSeconds)s"
$extra = @()
if ($timedOutCount -gt 0) { $extra += "TIMEOUT=$timedOutCount (counted in FAIL)" }
if ($blocked.Count -gt 0) { $extra += "NOT-RUN=$($blocked.Count) (need rendering)" }
if ($unclassified.Count -gt 0) { $extra += "UNCLASSIFIED=$($unclassified.Count)" }
$summary | Set-Content -LiteralPath (Join-Path $runDirectory "summary.txt")
$overhead = $totalWatch.Elapsed.TotalSeconds - $processSeconds
@{ suite = $suiteLabel; passed = $passed; failed = $failed; skipped_explicit = $skipped; blocked = $blocked; unclassified = $unclassified; total_seconds = [math]::Round($totalWatch.Elapsed.TotalSeconds, 2); godot_process_seconds = [math]::Round($processSeconds, 2); runner_overhead_seconds = [math]::Round($overhead, 2); results = $results } |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runDirectory "results.json") -Encoding UTF8
Write-Host ""
Write-Host "Ironclad summary: $summary"
if ($extra.Count -gt 0) { Write-Host "  $($extra -join '; ')" }
Write-Host ("Time split: Godot processes {0:n1}s, runner and reporting {1:n1}s" -f $processSeconds, $overhead)
if ($Slowest -gt 0 -and $results.Count -gt 1) {
    Write-Host "Slowest:"
    $results | Where-Object { $_.name -ne "project_parse" } | Sort-Object seconds -Descending | Select-Object -First $Slowest | ForEach-Object { Write-Host ("  {0,7:n2}s  {1}" -f $_.seconds, $_.name) }
}
if ($blocked.Count -gt 0) { Write-Host "Selected but not run (rendering required; run directly without --headless): $($blocked -join ', ')" }
if ($skipped -gt 0) {
    Write-Host "Explicit-only checks: $($skippedExplicit -join ', ')"
}
if ($Tier -ne "full") {
    $unsel = @($discovered | Where-Object { $n = $_; (-not $meta[$n].Explicit) -and -not (@($selected | Where-Object { $_.Name -eq $n }).Count) }).Count
    Write-Host "Not verified by this run: $unsel ordinary test(s) were not selected. A subset does not replace the full tier."
    foreach ($note in $omittedNote) { if ($note -like "omitted long*") { Write-Host "  $note" } }
}
Show-CatalogProblems
Write-Host "Detailed logs: $runDirectory"
$exit = 0
if ($failed -gt 0) { $exit = 1 }
elseif ($blocked.Count -gt 0 -and $Tier -eq "select") { $exit = 2 }
elseif ($Strict -and $catalogProblems.Count -gt 0) { $exit = 2 }
exit $exit
