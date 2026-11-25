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
if ($Import -and $SkipImport) {
    [Console]::Error.WriteLine("Choose either -Import or -SkipImport.")
    exit 2
}
if ($TimeoutSeconds -lt 1 -or $TimeoutSeconds -gt [int]::MaxValue / 1000) {
    [Console]::Error.WriteLine("-TimeoutSeconds must be between 1 and 2147483.")
    exit 2
}
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

function Get-ChangedPaths([string]$ref) {
    $PSNativeCommandUseErrorActionPreference = $false
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Fail-Usage "changed -Since requires Git."
    }
    $commit = git -C $repoRoot rev-parse --verify --end-of-options "${ref}^{commit}"
    if ($LASTEXITCODE -ne 0) { Fail-Usage "Invalid -Since reference '$ref': Git could not resolve a commit." }

    # A move counts in both areas, regardless of Git rename configuration.
    $tracked = git -C $repoRoot diff --no-renames --no-ext-diff --name-only -z $commit --
    if ($LASTEXITCODE -ne 0) { Fail-Usage "Git diff failed for -Since '$ref'." }
    $untracked = git -C $repoRoot ls-files --others --exclude-standard -z
    if ($LASTEXITCODE -ne 0) { Fail-Usage "Git could not list untracked files for -Since '$ref'." }
    (@($tracked) -join "`n") -split "`0"
    (@($untracked) -join "`n") -split "`0"
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
if ($catalog.tests -isnot [pscustomobject] -or $catalog.areas -isnot [array]) {
    Fail-Usage "tests/catalog.json requires a tests object and an areas array."
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
    $fixedFps = Get-Prop $entry "fixed_fps" 0
    if ($null -ne $entry -and $entry.PSObject.Properties.Name -contains "fixed_fps" -and
        ($fixedFps -isnot [long] -and $fixedFps -isnot [int] -or $fixedFps -lt 1 -or $fixedFps -gt 240)) {
        $catalogProblems.Add("INVALID: $name fixed_fps must be an integer from 1 to 240")
        $fixedFps = 0
    }
    $meta[$name] = [pscustomobject]@{
        Name = $name; Sub = $subs; Scope = $scope; Contracts = $contracts; FixedFps = $fixedFps
        Critical = ([string](Get-Prop $entry "crit" "") -eq "critical")
        Smoke = [bool](Get-Prop $entry "smoke" $false); Fast = [bool](Get-Prop $entry "fast" $false)
        Explicit = ($run -eq "explicit"); Req = $req; Kind = $kind; Classified = ($null -ne $entry)
    }
    if ($null -ne $entry) {
        foreach ($s in $subs) { if ($s -notin $validSubsystems) { $catalogProblems.Add("INVALID: $name has unknown subsystem '$s'") } }
        if ($subs.Count -eq 0) { $catalogProblems.Add("INVALID: $name has no subsystem") }
        if ($scope -notin $validScopes) { $catalogProblems.Add("INVALID: $name has unknown scope '$scope'") }
        foreach ($c in $contracts) { if ($c -notin $validContracts) { $catalogProblems.Add("INVALID: $name has unknown contract '$c'") } }
        if ($req -notin @("headless", "render")) { $catalogProblems.Add("INVALID: $name has unknown execution requirement '$req'") }
        foreach ($flag in @("fast", "smoke")) {
            if ($entry.PSObject.Properties.Name -contains $flag -and $entry.$flag -isnot [bool]) {
                $catalogProblems.Add("INVALID: $name has a non-boolean '$flag' flag")
            }
        }
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
$slowCandidates = @()

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
            $paths += @(Get-ChangedPaths $Since)
        }
        if (-not $Changed -and -not $Since) { Fail-Usage "The changed tier needs -Changed <paths> or -Since <git ref>." }
        $paths = @($paths | Where-Object { $_ } | ForEach-Object { $_.Replace("\", "/") } | Sort-Object -Unique)
        $affected = New-Object System.Collections.Generic.HashSet[string]
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
                if ($m.Scope -eq "e2e" -and -not $Thorough) { $slowCandidates += $n } else { Add-Selection $n "critical test of a central or unmapped change" }
            }
        }
        $selectionTitle = "changed ($($paths.Count) path(s))"
        $omittedNote = $areaNotes
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
$selectedNames = @($selected | ForEach-Object { $_.Name })
$slowOmitted = @($slowCandidates | Where-Object { $_ -notin $selectedNames })
$ordinaryNotSelected = @($discovered | Where-Object { -not $meta[$_].Explicit -and $_ -notin $selectedNames -and $_ -notin $slowOmitted })
$explicitExcluded = @($discovered | Where-Object { $meta[$_].Explicit -and $_ -notin $selectedNames })
$skippedExplicit = @($skippedExplicit | Where-Object { $_ -notin $selectedNames } | Sort-Object -Unique)
$lines = @()
$lines += "FuseFire Project Ironclad - $suiteLabel"
$lines += "  selected $($selected.Count) of $($discovered.Count) discovered test scripts: $($runnable.Count) runnable, $($blocked.Count) blocked"
$lines += "  explicit-only exclusions: $($explicitExcluded.Count); long end-to-end omissions: $($slowOmitted.Count); other ordinary tests not selected: $($ordinaryNotSelected.Count)"
if ($slowOmitted.Count -gt 0) {
    $lines += "  omitted long end-to-end critical tests (add -Thorough to include): $($slowOmitted -join ', ')"
}
if ($Tier -eq "changed" -and $selected.Count -eq 0) {
    $lines += "  No tests selected: changed paths matched no tests (for example, documentation or metadata only)."
}

if ($List -or $Why) {
    $lines | ForEach-Object { Write-Host $_ }
    $total = 0.0
    foreach ($s in $selected) {
        $m = $meta[$s.Name]
        $cost = if ($baseline.ContainsKey($s.Name)) { "{0,6:n1}s" -f $baseline[$s.Name] } else { "     ?" }
        if ($s.Name -notin $blocked -and $baseline.ContainsKey($s.Name)) { $total += $baseline[$s.Name] }
        $flagList = @()
        if ($m.Critical) { $flagList += "critical" }
        if ($m.Smoke) { $flagList += "smoke" }
        if ($m.Fast) { $flagList += "fast" }
        if ($m.Explicit) { $flagList += "explicit:" + $m.Kind }
        if ($m.Req -ne "headless") { $flagList += "needs-render" }
        if ($m.FixedFps) { $flagList += "fixed-fps:$($m.FixedFps)" }
        if ($s.Name -in $blocked) { $flagList += "blocked" }
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
    Show-CatalogProblems
    if ($Strict -and $catalogProblems.Count -gt 0) { exit 2 }
    exit 0
}

if ($Tier -eq "changed" -and $selected.Count -eq 0 -and -not $Import -and -not $ProbeFailureHandling) {
    $lines | ForEach-Object { Write-Host $_ }
    Show-CatalogProblems
    if ($Strict -and $catalogProblems.Count -gt 0) { exit 2 }
    exit 0
}

$godotCommand = Get-Command $Godot -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
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
$runName = "$(Get-Date -Format 'yyyyMMdd-HHmmssfff')-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$runDirectory = Join-Path $LogDirectory ("$runName-" + $suiteLabel.Replace("/", "-"))
$testOutputDirectory = Join-Path $runDirectory "test-output"
New-Item -ItemType Directory -Path $testOutputDirectory -Force | Out-Null
$windowsHost = $env:OS -eq "Windows_NT"

# user:// belongs to one Godot entry. Nested Godot processes inherit this profile.
# .godot/ belongs to the checkout and still requires an exclusive runner.
function New-TestProfile([string]$name) {
    if (-not $windowsHost) { return $null }
    $profileRoot = Join-Path $runDirectory "user-data"
    $profile = Join-Path $profileRoot $name
    New-Item -ItemType Directory -Path (Join-Path $profile "roaming"), (Join-Path $profile "local") -Force | Out-Null
    return $profile
}

function Remove-TestProfile([string]$profile) {
    if (-not $profile -or -not (Test-Path -LiteralPath $profile -PathType Container)) { return }
    $root = (Resolve-Path -LiteralPath (Join-Path $runDirectory "user-data")).Path
    $actual = (Resolve-Path -LiteralPath $profile).Path
    $parent = Split-Path -Parent $actual
    if ($parent -ne $root -or (Get-Item -LiteralPath $actual).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Refusing cleanup outside the isolated profile directory: $actual"
    }
    Remove-Item -LiteralPath $actual -Recurse -Force
}

function Stop-TestProcess($process) {
    if ($process.HasExited) { return }
    if ($windowsHost) {
        & taskkill.exe /T /F /PID $process.Id *> $null
    } else {
        $process.Kill($true)
    }
    if (-not $process.WaitForExit(3000)) {
        $process.Kill()
        if (-not $process.WaitForExit(3000)) { throw "Could not stop Godot process $($process.Id)." }
    }
}

function Invoke-Godot([string[]]$arguments, [int]$timeoutSeconds, [string]$logStem, [string]$profile) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $godotCommand.Source
    if ($psi.PSObject.Properties.Name -contains "ArgumentList") {
        foreach ($argument in $arguments) { $psi.ArgumentList.Add($argument) }
    } else {
        $psi.Arguments = (($arguments | ForEach-Object {
            if ($_ -match '[\s"]') { '"' + $_.Replace('"', '\"') + '"' } else { $_ }
        }) -join " ")
    }
    $psi.WorkingDirectory = $repoRoot
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables["FUSEFIRE_TEST_OUTPUT_DIR"] = $testOutputDirectory
    if ($profile) {
        $psi.EnvironmentVariables["APPDATA"] = Join-Path $profile "roaming"
        $psi.EnvironmentVariables["LOCALAPPDATA"] = Join-Path $profile "local"
    }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $stdoutFile = $null
    $stderrFile = $null
    $process = $null
    $started = $false
    $timedOut = $false
    $exitCode = $null
    $problem = $null
    try {
        $stdoutFile = [IO.File]::Open("$logStem.stdout.log", "CreateNew", "Write", "Read")
        $stderrFile = [IO.File]::Open("$logStem.stderr.log", "CreateNew", "Write", "Read")
        $process = [Diagnostics.Process]::Start($psi)
        $started = $true
        $stdout = $process.StandardOutput.BaseStream.CopyToAsync($stdoutFile)
        $stderr = $process.StandardError.BaseStream.CopyToAsync($stderrFile)
        $timeoutMs = $timeoutSeconds * 1000
        # Give PowerShell a pipeline boundary to process Ctrl-C while the child lives.
        while (-not $process.WaitForExit(200)) {
            if ($watch.ElapsedMilliseconds -ge $timeoutMs) {
                $timedOut = $true
                Stop-TestProcess $process
                break
            }
            Start-Sleep -Milliseconds 1
        }
        if (-not $stdout.Wait(5000) -or -not $stderr.Wait(5000)) { throw "Process output did not close after exit." }
        if (-not $timedOut) { $exitCode = $process.ExitCode }
    } catch {
        $problem = $_.Exception.Message
    } finally {
        $watch.Stop()
        try {
            if ($started -and -not $process.HasExited) { Stop-TestProcess $process }
        } finally {
            if ($process) { $process.Dispose() }
            if ($stdoutFile) { $stdoutFile.Dispose() }
            if ($stderrFile) { $stderrFile.Dispose() }
        }
    }
    $output = @()
    foreach ($stream in @("stdout", "stderr")) {
        $streamFile = "$logStem.$stream.log"
        if (Test-Path -LiteralPath $streamFile) { $output += @(Get-Content -LiteralPath $streamFile -Encoding UTF8) }
    }
    if ($problem) { $output += "Ironclad process error: $problem" }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = $output; Started = $started; TimedOut = $timedOut; Problem = $problem; Seconds = $watch.Elapsed.TotalSeconds }
}

# ---------------------------------------------------------------- import freshness
function Test-ImportFresh {
    $stamp = Join-Path $repoRoot ".godot/ironclad-import.stamp"
    if (-not (Test-Path -LiteralPath $stamp) -or
        -not (Test-Path -LiteralPath (Join-Path $repoRoot ".godot/global_script_class_cache.cfg"))) { return $false }
    $stampTime = (Get-Item -LiteralPath $stamp).LastWriteTimeUtc
    $newest = [datetime]::MinValue
    foreach ($dir in @("systems", "units", "presentation", "ui", "levels", "art", "content", "tools", "addons")) {
        $path = Join-Path $repoRoot $dir
        if (-not (Test-Path -LiteralPath $path)) { continue }
        foreach ($file in (Get-ChildItem -LiteralPath $path -Recurse -File -Include *.gd, *.tscn, *.tres, *.gdshader, *.gdextension, *.import, *.uid, *.png, *.svg, *.glb, *.gltf, *.fbx, *.ogg, *.wav, *.ttf, *.otf)) {
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
$doImport = $importMode -eq "always"
if ($doImport) { $runEntries += [pscustomobject]@{ Name = "project_parse"; Script = $null; Kind = "import"; Reason = "project import / class cache" } }
foreach ($s in $runnable) {
    $runEntries += [pscustomobject]@{ Name = $s.Name; Script = "res://tests/$($s.Name).gd"; Kind = "test"; Reason = $s.Reason; FixedFps = $meta[$s.Name].FixedFps }
}
if ($ProbeFailureHandling) {
    $runEntries += [pscustomobject]@{ Name = "intentional_failure_probe"; Script = "res://tools/quality/ironclad_failure_probe.gd"; Kind = "probe"; Reason = "probe"; Timeout = $TimeoutSeconds }
    $runEntries += [pscustomobject]@{ Name = "zero_exit_script_error_probe"; Script = "res://tools/quality/ironclad_script_error_probe.gd"; Kind = "probe"; Reason = "probe"; Timeout = $TimeoutSeconds }
    $runEntries += [pscustomobject]@{ Name = "timeout_probe"; Script = "res://tools/quality/ironclad_timeout_probe.gd"; Kind = "probe"; Reason = "probe"; Timeout = 3 }
}

$results = New-Object System.Collections.Generic.List[object]
$totalWatch = [Diagnostics.Stopwatch]::StartNew()
$processSeconds = 0.0
$finished = $false
$runningEntry = $null
$importFailed = $false
$checkoutLock = $null
$stamp = Join-Path $repoRoot ".godot/ironclad-import.stamp"
$revision = $null
if (Test-Path -LiteralPath (Join-Path $repoRoot ".git")) {
    $PSNativeCommandUseErrorActionPreference = $false
    if (Get-Command git -CommandType Application -ErrorAction SilentlyContinue) {
        $head = git -C $repoRoot rev-parse --verify HEAD 2>$null
        if ($LASTEXITCODE -eq 0) { $revision = [string]$head }
    }
}

function Write-RunReport([string]$verdict) {
    $tests = @($results.ToArray() | Where-Object kind -eq "test")
    $report = [ordered]@{
        schema = 2; run_id = $runName; suite = $suiteLabel; tier = $Tier; revision = $revision
        runner_pid = $PID; project_root = $repoRoot; godot_executable = $godotCommand.Source
        profile_isolation = if ($windowsHost) { "windows-per-entry" } else { "native" }
        verdict = $verdict; complete = $finished; current_entry = $runningEntry
        discovered_scripts = $discovered.Count; catalogued_tests = $entries.Count
        ordinary_selected = @($selected | Where-Object { -not $meta[$_.Name].Explicit }).Count
        selected_runnable = $runnable.Count; explicit_excluded = $explicitExcluded.Count
        skipped_explicit = $skippedExplicit.Count; blocked = $blocked; omitted_long = $slowOmitted
        ordinary_not_selected = $ordinaryNotSelected.Count; unclassified = $unclassified
        catalog_problems = @($catalogProblems.ToArray())
        entry_processes_started = @($results.ToArray() | Where-Object started).Count
        test_processes_started = @($tests | Where-Object started).Count
        tests_completed = @($tests | Where-Object { $_.started -and $_.status -in @("PASS", "FAIL") }).Count
        tests_passed = @($tests | Where-Object status -eq "PASS").Count
        tests_failed = @($tests | Where-Object status -eq "FAIL").Count
        tests_timed_out = @($tests | Where-Object status -eq "TIMEOUT").Count
        tests_not_run = @($tests | Where-Object status -eq "NOT-RUN").Count + $blocked.Count
        import_mode = $importMode
        import = @($results.ToArray() | Where-Object kind -eq "import")
        passed = @($results.ToArray() | Where-Object status -eq "PASS").Count
        failed = @($results.ToArray() | Where-Object { $_.status -in @("FAIL", "TIMEOUT") }).Count
        retries = 0
        total_seconds = [math]::Round($totalWatch.Elapsed.TotalSeconds, 2)
        godot_process_seconds = [math]::Round($processSeconds, 2)
        runner_overhead_seconds = [math]::Round($totalWatch.Elapsed.TotalSeconds - $processSeconds, 2)
        results = $results.ToArray()
    }
    $jsonPath = Join-Path $runDirectory "results.json"
    $report | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath "$jsonPath.tmp" -Encoding UTF8
    if ([IO.File]::Exists($jsonPath)) {
        [IO.File]::Replace("$jsonPath.tmp", $jsonPath, [NullString]::Value)
    } else {
        [IO.File]::Move("$jsonPath.tmp", $jsonPath)
    }
    return $report
}

function Invoke-Entry($entry, [string[]]$arguments, [int]$limit) {
    $stem = Join-Path $runDirectory $entry.Name
    $profile = New-TestProfile $entry.Name
    $run = Invoke-Godot $arguments $limit $stem $profile
    $script:processSeconds += $run.Seconds
    $output = @($run.Output)
    $scriptErrorPattern = 'SCRIPT ERROR:|Parse Error:|Compile Error:'
    $engineLog = "$stem.godot.log"
    $scriptError = ($output -match $scriptErrorPattern) -or
        ((Test-Path -LiteralPath $engineLog) -and (Select-String -LiteralPath $engineLog -Pattern $scriptErrorPattern -Quiet))
    $status = "PASS"
    $failure = $null
    if ($run.TimedOut) {
        $status = "TIMEOUT"
        $failure = "timeout"
        $output += "Ironclad: the process exceeded $limit s. The runner stopped the process."
    } elseif ($run.Problem -or $null -eq $run.ExitCode) {
        $status = "FAIL"
        $failure = "process_error"
    } elseif ($scriptError -or $run.ExitCode -ne 0) {
        $status = "FAIL"
        $failure = if ($scriptError) { "script_error" } else { "nonzero_exit" }
        if ($scriptError -and $run.ExitCode -eq 0) { $output += "Runner rejected a zero exit after a script/parser error." }
    }
    if ($status -eq "PASS") {
        try { Remove-TestProfile $profile } catch {
            $status = "FAIL"
            $failure = "profile_cleanup"
            $output += "Ironclad: $($_.Exception.Message)"
        }
    }
    $output | Set-Content -LiteralPath "$stem.log" -Encoding UTF8
    Write-Host ("[{0}] {1} ({2:n2}s, exit {3})" -f $status, $entry.Name, $run.Seconds, $run.ExitCode)
    if ($status -ne "PASS") { $output | Select-Object -Last 25 | ForEach-Object { Write-Host "       $_" } }
    return [pscustomobject]@{
        name = $entry.Name; kind = $entry.Kind; status = $status; started = $run.Started
        seconds = [math]::Round($run.Seconds, 2); exit = $run.ExitCode; failure = $failure
        why = $entry.Reason; user_data = if ($status -ne "PASS") { $profile } else { $null }
        fixed_fps = $entry.FixedFps
    }
}

$lines | ForEach-Object { Write-Host $_ }
Write-Host "Godot: $($godotCommand.Source)"
Write-Host "Logs:  $runDirectory"
foreach ($note in $omittedNote) { Write-Host "  $note" }
$verdict = "INCOMPLETE"
$null = Write-RunReport $verdict
try {
    $cacheDir = Join-Path $repoRoot ".godot"
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    try {
        $checkoutLock = [IO.File]::Open((Join-Path $cacheDir "ironclad-run.lock"), "OpenOrCreate", "ReadWrite", "None")
    } catch {
        Fail-Usage "Cannot lock the checkout's .godot directory. Use a separate worktree or wait for the other Ironclad run."
    }

    if ($MeasureStartup) {
        $times = @()
        foreach ($i in 1..5) {
            $entry = [pscustomobject]@{ Name = "startup_probe_$i"; Kind = "probe"; Reason = "startup measurement" }
            $runningEntry = $entry.Name
            $null = Write-RunReport "INCOMPLETE"
            $engineLog = Join-Path $runDirectory "$($entry.Name).godot.log"
            $result = Invoke-Entry $entry @("--headless", "--log-file", $engineLog, "--path", $repoRoot, "--script", "res://tools/quality/startup_probe.gd") 120
            $results.Add($result)
            if ($result.status -ne "PASS") { break }
            $times += $result.seconds
        }
        if ($times.Count -eq 5) {
            Write-Host ("Godot start-up (5 runs): min {0:n2}s, median {1:n2}s, max {2:n2}s" -f ($times | Measure-Object -Minimum).Minimum, ($times | Sort-Object)[2], ($times | Measure-Object -Maximum).Maximum)
        }
    } else {
        # Freshness is checked after taking the checkout lock.
        if ($importMode -eq "auto") {
            $testEntries = @($runEntries | Where-Object Kind -ne "import")
            $runEntries = if (Test-ImportFresh) { $testEntries } else {
                @([pscustomobject]@{ Name = "project_parse"; Kind = "import"; Reason = "project import / class cache" }) + $testEntries
            }
        }
        foreach ($entry in $runEntries) {
            if ($importFailed) {
                $results.Add([pscustomobject]@{ name = $entry.Name; kind = $entry.Kind; status = "NOT-RUN"; started = $false; seconds = 0; exit = $null; why = "project import failed" })
                continue
            }
            $runningEntry = $entry.Name
            $null = Write-RunReport "INCOMPLETE"
            $engineLogPath = Join-Path $runDirectory "$($entry.Name).godot.log"
            $arguments = @("--headless", "--log-file", $engineLogPath, "--path", $repoRoot)
            if ($entry.Kind -eq "import") {
                if (Test-Path -LiteralPath $stamp) { Remove-Item -LiteralPath $stamp -Force }
                $arguments += "--import"
            } else {
                if ($entry.FixedFps) { $arguments += @("--fixed-fps", [string]$entry.FixedFps) }
                $arguments += @("--script", $entry.Script)
            }
            $limit = if ($entry.Timeout) { [int]$entry.Timeout } else { $TimeoutSeconds }
            $result = Invoke-Entry $entry $arguments $limit
            $results.Add($result)
            if ($entry.Kind -eq "import") {
                $importFailed = $result.status -ne "PASS"
                if (-not $importFailed) { New-Item -ItemType File -Path $stamp -Force | Out-Null }
            }
        }
    }
    $runningEntry = $null
    $finished = $true
    $verdict = if (@($results.ToArray() | Where-Object { $_.status -in @("FAIL", "TIMEOUT") }).Count) { "RED" }
        elseif ($blocked.Count -or $catalogProblems.Count) { "INCOMPLETE" }
        else { "GREEN" }
} finally {
    $totalWatch.Stop()
    if ($checkoutLock) { $checkoutLock.Dispose() }
    $report = Write-RunReport $verdict
}

$importStatus = if ($report.import.Count) { $report.import[0].status } else { "not run" }
$summary = "$verdict. Tests: $($report.tests_passed) passed, $($report.tests_failed) failed, $($report.tests_timed_out) timed out, $($report.tests_not_run) not run. Import: $importStatus. Explicit-only exclusions: $($report.explicit_excluded). Time: $($report.total_seconds)s."
$summary | Set-Content -LiteralPath (Join-Path $runDirectory "summary.txt")
Write-Host ""
Write-Host "Ironclad ${selectionTitle}: $summary"
$probeResults = @($results.ToArray() | Where-Object kind -eq "probe")
if ($probeResults.Count) {
    Write-Host ("  Probe results: " + (($probeResults | ForEach-Object { "$($_.name)=$($_.status)" }) -join ", "))
}
Write-Host ("Time split: Godot processes {0:n1}s, runner and reporting {1:n1}s" -f $processSeconds, $report.runner_overhead_seconds)
if ($Slowest -gt 0 -and $results.Count -gt 1) {
    Write-Host "Slowest:"
    $results | Where-Object { $_.kind -eq "test" -and $_.started } | Sort-Object seconds -Descending | Select-Object -First $Slowest | ForEach-Object { Write-Host ("  {0,7:n2}s  {1}" -f $_.seconds, $_.name) }
}
if ($blocked.Count -gt 0) {
    Write-Host "Selected but not run (rendering required; run directly without --headless): $($blocked -join ', ')"
}
Show-CatalogProblems
Write-Host "Detailed logs: $runDirectory"
if ($verdict -eq "RED") { exit 1 }
if ($verdict -eq "INCOMPLETE") { exit 2 }
exit 0
