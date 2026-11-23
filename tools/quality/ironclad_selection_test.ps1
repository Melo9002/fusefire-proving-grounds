# Runner-only invariant checks. The fixture contains no executable Godot tests.
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false
$shell = (Get-Process -Id $PID).Path
$fixture = New-Item -ItemType Directory -Path (Join-Path ([IO.Path]::GetTempPath()) ("ironclad-selection-" + [guid]::NewGuid()))
$root = $fixture.FullName

function Invoke-FixtureGit {
    git -C $root @args
    if ($LASTEXITCODE -ne 0) { throw "Fixture Git failed: $args" }
}

function Assert-Selection([string]$case, [int]$expectedExit, [string[]]$required, [string[]]$forbidden = @()) {
    $output = & $shell -NoProfile -File (Join-Path $root "tools/run_tests.ps1") @args 2>&1
    $actualExit = $LASTEXITCODE
    $message = $output -join "`n"
    if ($actualExit -ne $expectedExit) { throw "$case expected exit $expectedExit, got $actualExit`n$message" }
    foreach ($pattern in $required) {
        if ($message -notmatch $pattern) { throw "$case missing '$pattern'`n$message" }
    }
    foreach ($pattern in $forbidden) {
        if ($message -match $pattern) { throw "$case unexpectedly matched '$pattern'`n$message" }
    }
    Write-Host "PASS $case (exit $actualExit)"
}

try {
    foreach ($dir in @("tools", "tests", "docs", "systems/objectives", "systems/replay")) {
        New-Item -ItemType Directory -Path (Join-Path $root $dir) -Force | Out-Null
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "../run_tests.ps1") -Destination (Join-Path $root "tools/run_tests.ps1")
    @'
{
  "areas": [
    {"path":"systems/objectives/","sub":["missions"],"central":true},
    {"path":"systems/replay/","sub":["replay"]},
    {"path":"tools/","sub":["tooling"]}
  ],
  "tests": {
    "mission_matrix":{"scope":"e2e","sub":["missions"],"crit":"critical"},
    "replay_matrix":{"scope":"e2e","sub":["replay"],"crit":"critical"},
    "ordinary":{"scope":"unit","sub":["ai"]},
    "render_capture":{"scope":"component","sub":["missions"],"run":"explicit","req":"render","kind":"capture"}
  }
}
'@ | Set-Content -LiteralPath (Join-Path $root "tests/catalog.json")
    foreach ($name in @("mission_matrix", "replay_matrix", "ordinary", "render_capture")) {
        New-Item -ItemType File -Path (Join-Path $root "tests/$name.gd") | Out-Null
    }
    "*.ignored" | Set-Content -LiteralPath (Join-Path $root ".gitignore")
    "base" | Set-Content -LiteralPath (Join-Path $root "docs/guide.md")
    "base" | Set-Content -LiteralPath (Join-Path $root "systems/objectives/old name.gd")
    "base" | Set-Content -LiteralPath (Join-Path $root "systems/objectives/delete.gd")
    Invoke-FixtureGit init -q
    Invoke-FixtureGit add --all
    Invoke-FixtureGit -c user.name=Ironclad -c user.email=ironclad@example.invalid -c commit.gpgsign=false commit -qm baseline

    Assert-Selection "invalid ref" 2 @("Invalid -Since reference") @("No tests selected") changed -Since missing-ref -List
    "changed" | Set-Content -LiteralPath (Join-Path $root "docs/guide.md")
    "ignored" | Set-Content -LiteralPath (Join-Path $root "systems/replay/local.ignored")
    Assert-Selection "docs only without Godot" 0 @("selected 0 of 4", "No tests selected") @("Required Godot") changed -Since HEAD -Godot ironclad-missing-godot

    $previousIndex = $env:GIT_INDEX_FILE
    $env:GIT_INDEX_FILE = Join-Path $root "corrupt.ignored"
    try {
        "invalid index" | Set-Content -LiteralPath $env:GIT_INDEX_FILE
        Assert-Selection "valid ref with failing Git diff" 2 @("Git diff failed") @("No tests selected") changed -Since HEAD -List
    } finally {
        $env:GIT_INDEX_FILE = $previousIndex
    }

    Assert-Selection "affected expensive test selected once" 0 @(
        "selected 1 of 4.*1 runnable, 0 blocked",
        "explicit-only exclusions: 1; long end-to-end omissions: 1; other ordinary tests not selected: 1",
        "omitted long end-to-end critical tests .*: replay_matrix"
    ) @("omitted long .*mission_matrix") changed -Changed systems/objectives/old.gd -Why
    Assert-Selection "Thorough restores global E2E" 0 @("selected 2 of 4", "long end-to-end omissions: 0") @("omitted long end-to-end critical tests") changed -Changed systems/objectives/old.gd -Thorough -List

    Invoke-FixtureGit mv -- "systems/objectives/old name.gd" "systems/replay/new name.gd"
    Remove-Item -LiteralPath (Join-Path $root "systems/objectives/delete.gd")
    "staged" | Set-Content -LiteralPath (Join-Path $root "systems/replay/staged.gd")
    Invoke-FixtureGit add -- systems/replay/staged.gd
    "untracked" | Set-Content -LiteralPath (Join-Path $root "systems/replay/untracked.gd")
    Assert-Selection "rename, delete, staged add and untracked" 0 @(
        "selected 2 of 4.*2 runnable", "systems/objectives/old name.gd -> missions",
        "systems/replay/new name.gd -> replay", "systems/objectives/delete.gd -> missions",
        "systems/replay/staged.gd -> replay", "systems/replay/untracked.gd -> replay"
    ) @("local\.ignored") changed -Since HEAD -Why

    Assert-Selection "rendered selection is blocked, not excluded" 0 @("selected 1 of 4.*0 runnable, 1 blocked", "explicit-only exclusions: 0", "other ordinary tests not selected: 3") @("Explicit-only checks excluded") select -Test render_capture -Why
    Assert-Selection "wildcard excludes explicit capture" 0 @("selected 0 of 4.*0 runnable, 0 blocked", "explicit-only exclusions: 1") @("Selected but cannot run headless") select -Test "render_*" -List
} finally {
    # The directory was created for this invocation with a unique name.
    if ((Get-Item -LiteralPath $root).FullName -eq $fixture.FullName -and $fixture.Name -match '^ironclad-selection-[a-f0-9-]{36}$') {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}
