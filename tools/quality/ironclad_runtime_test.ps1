[CmdletBinding()]
param([string]$Godot = "godot_console")

# Exercise the real runner and Godot in a tiny project with separate cache and user data.
$ErrorActionPreference = "Stop"
$fixture = New-Item -ItemType Directory -Path (Join-Path ([IO.Path]::GetTempPath()) "ironclad-runtime-$([guid]::NewGuid())")
$root = $fixture.FullName
$runner = Join-Path $root "tools/run_tests.ps1"
$logRoot = Join-Path $root "logs"
$compare = Join-Path $PSScriptRoot "ironclad_compare_runs.ps1"
$exe = (Get-Command $Godot -CommandType Application | Select-Object -First 1).Source

function Check([bool]$ok, [string]$message) {
    if (-not $ok) { throw $message }
    Write-Host "PASS $message"
}
function Write-Test([string]$name, [string]$body) {
    "extends SceneTree`nfunc _initialize() -> void:`n$body" | Set-Content -LiteralPath (Join-Path $root "tests/$name.gd") -Encoding ascii
}
function Run([string[]]$flags, [int]$expectedExit, [string]$tag) {
    $destination = Join-Path $logRoot $tag
    $text = & pwsh -NoProfile -File $runner @flags -Godot $exe -LogDirectory $destination 2>&1 | Out-String
    $code = $LASTEXITCODE
    if ($code -ne $expectedExit) { throw "$tag returned $code; expected ${expectedExit}:`n$text" }
    Write-Host "PASS $tag exits $code"
    $resultsFile = Get-ChildItem -LiteralPath $destination -Filter results.json -Recurse | Select-Object -First 1
    return $resultsFile.FullName
}
function Read-Result([string]$path) { Get-Content -LiteralPath $path -Raw | ConvertFrom-Json }

try {
    foreach ($dir in @("tools", "tests", "systems")) { New-Item -ItemType Directory -Path (Join-Path $root $dir) | Out-Null }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "../run_tests.ps1") -Destination $runner
    "config_version=5`n[application]`nconfig/name=`"Ironclad Runner Fixture`"" | Set-Content -LiteralPath (Join-Path $root "project.godot")
    $passWriter = @"
	if FileAccess.file_exists("user://marker") or not OS.get_user_data_dir().contains("/user-data/"):
		quit(1)
		return
	var file := FileAccess.open("user://marker", FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string("scoped")
	file.close()
	quit(0)
"@
    if ($env:OS -ne "Windows_NT") { $passWriter = "`tquit(0)" }
    Write-Test "a_writes" $passWriter
    Write-Test "b_isolated" $passWriter
    Write-Test "assertion" "`tpush_error(`"intentional assertion`")`n`tquit(1)"
    Write-Test "explicit_case" "`tquit(0)"
    Write-Test "late_pass" "`tquit(0 if FileAccess.file_exists(`"res://second-attempt`") else 1)"
    Write-Test "unexpected_exit" "`tquit(17)"
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "ironclad_script_error_probe.gd") -Destination (Join-Path $root "tests/zero_exit_error.gd")
    "extends SceneTree`nfunc _initialize() -> void:`n`tpass" |
        Set-Content -LiteralPath (Join-Path $root "tests/timeout_case.gd")
    $metadata = @{}
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root "tests") -Filter "*.gd") {
        $metadata[$file.BaseName] = @{scope="unit"; sub=@("tooling")}
    }
    $metadata["explicit_case"].run = "explicit"
    $metadata["explicit_case"].kind = "batch"
    $catalog = Join-Path $root "tests/catalog.json"
    $document = @{schema=1; tests=$metadata; areas=@(@{path="tools/"; sub=@("tooling")}, @{path="systems/"; sub=@("tooling")})}
    $document | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $catalog
    $startProfile = $env:APPDATA
    $firstPath = Run @("full","-Import","-TimeoutSeconds","10") 1 "original"
    $first = Read-Result $firstPath
    Check ($first.verdict -eq "RED" -and $first.complete -and $first.ordinary_selected -eq 7 -and $first.explicit_excluded -eq 1) "full selection and verdict"
    Check ($first.import[0].status -eq "PASS" -and $first.entry_processes_started -eq 8 -and $first.test_processes_started -eq 7) "import and ordinary process counts"
    Check ($first.tests_passed -eq 2 -and $first.tests_failed -eq 4 -and $first.tests_timed_out -eq 1 -and $first.tests_completed -eq 6) "assertion, unexpected exit, script error and timeout accounting"
    Check (($first.results | Where-Object name -eq "unexpected_exit").exit -eq 17) "unexpected raw exit is preserved"
    $scriptFailure = $first.results | Where-Object name -eq "zero_exit_error"
    Check ($scriptFailure.failure -eq "script_error" -and $scriptFailure.exit -eq 0) "zero-exit script failure is visible"
    $logDirectory = Split-Path -Parent $firstPath
    Check ((Get-Content -LiteralPath (Join-Path $logDirectory "assertion.stderr.log") -Raw).Contains("intentional assertion")) "raw stderr retained"
    Check ($env:APPDATA -eq $startProfile) "runner does not change the caller profile"
    if ($env:OS -eq "Windows_NT") {
        Check ((Test-Path -LiteralPath (Join-Path $logDirectory "user-data/assertion")) -and
            -not (Test-Path -LiteralPath (Join-Path $logDirectory "user-data/a_writes")) -and
            (Test-Path -LiteralPath (Join-Path $logDirectory "user-data/timeout_case"))) "failed profiles retained and successful profiles cleaned"
    }

    $null = New-Item -ItemType File -Path (Join-Path $root "second-attempt")
    $repeatPath = Run @("select","-Test","late_pass","-SkipImport") 0 "repeat"
    $knownPath = Run @("select","-Test","assertion","-SkipImport") 1 "known failure"
    $comparison = & $compare -Initial $firstPath -Rerun $repeatPath,$repeatPath,$knownPath -Baseline $knownPath -Json | ConvertFrom-Json
    Check ($comparison.initial_verdict -eq "RED" -and $comparison.passed_on_rerun -eq 1 -and $comparison.without_clean_rerun -eq 4) "reruns preserve the original RED verdict"
    Check (($comparison.failures | Where-Object name -eq "assertion").rerun_evidence -eq "REPRODUCED" -and
        ($comparison.failures | Where-Object name -eq "assertion").baseline_status -eq "FAIL") "known failure is still present"
    Check (($comparison.failures | Where-Object name -eq "late_pass").attempts.Count -eq 1) "duplicate artifact paths do not inflate attempt counts"
    $explicitPath = Run @("select","-Test","explicit_case","-SkipImport") 0 "explicit"
    $explicit = Read-Result $explicitPath
    Check ($explicit.explicit_excluded -eq 0 -and $explicit.ordinary_selected -eq 0 -and $explicit.test_processes_started -eq 1) "explicit case runs by name"

    $cachedPath = Run @("select","-Test","a_writes") 0 "fresh cache"
    Check ((Read-Result $cachedPath).import.Count -eq 0) "ordinary select can reuse a fresh import"
    $classCache = Join-Path $root ".godot/global_script_class_cache.cfg"
    Remove-Item -LiteralPath $classCache
    $reimportPath = Run @("select","-Test","a_writes") 0 "missing class cache"
    Check ((Read-Result $reimportPath).import[0].status -eq "PASS") "a stamp without a class cache forces import"

    $lockFile = Join-Path $root ".godot/ironclad-run.lock"
    $lock = [IO.File]::Open($lockFile, "Open", "ReadWrite", "None")
    try {
        $blockedPath = Run @("select","-Test","a_writes","-SkipImport") 2 "locked"
        $blocked = Read-Result $blockedPath
        Check (-not $blocked.complete -and $blocked.verdict -eq "INCOMPLETE" -and $blocked.entry_processes_started -eq 0) "locked checkout remains incomplete"
    } finally { $lock.Dispose() }

    Write-Test "interrupt_case" @"
	var marker := FileAccess.open("res://interrupted.pid", FileAccess.WRITE)
	marker.store_string(str(OS.get_process_id()))
	marker.close()
"@
    $document.tests["interrupt_case"] = @{scope="unit"; sub=@("tooling")}
    $document | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $catalog
    $interruptPath = Join-Path $logRoot "interruption"
    $pipeline = [powershell]::Create()
    try {
        $null = $pipeline.AddCommand($runner).AddParameter("Tier", "select").AddParameter("Test", @("interrupt_case")).
            AddParameter("Godot", $exe).AddParameter("LogDirectory", $interruptPath).
            AddParameter("SkipImport").AddParameter("TimeoutSeconds", 20)
        $pending = $pipeline.BeginInvoke()
        $marker = Join-Path $root "interrupted.pid"
        $deadline = (Get-Date).AddSeconds(10)
        while (-not (Test-Path -LiteralPath $marker) -and (Get-Date) -lt $deadline -and -not $pending.IsCompleted) {
            Start-Sleep -Milliseconds 50
        }
        Check (Test-Path -LiteralPath $marker) "interruption control reached the live child"
        $childId = [int](Get-Content -LiteralPath $marker -Raw)
        $pipeline.Stop()
        $checkpoint = Get-ChildItem -LiteralPath $interruptPath -Filter results.json -Recurse | Select-Object -First 1
        $partial = Read-Result $checkpoint.FullName
        Check (-not $partial.complete -and $partial.verdict -eq "INCOMPLETE" -and $partial.current_entry -eq "interrupt_case") "interruption preserves partial results"
        Check (-not (Get-Process -Id $childId -ErrorAction SilentlyContinue)) "interruption stops the test child"
    } finally { $pipeline.Dispose() }

    "class_name BrokenImport`nextends Node`nfunc parse_error_here(" |
        Set-Content -LiteralPath (Join-Path $root "systems/broken_import.gd")
    # The editor scan registers unloaded scripts without compiling all their bodies.
    # An autoload requires the editor import to actually load the invalid script.
    "`n[autoload]`nBrokenBoot=`"*res://systems/broken_import.gd`"" |
        Add-Content -LiteralPath (Join-Path $root "project.godot")
    $importFailPath = Run @("select","-Test","a_writes","-Import") 1 "import failure"
    $importFail = Read-Result $importFailPath
    Check ($importFail.verdict -eq "RED" -and $importFail.import[0].status -eq "FAIL" -and
        $importFail.test_processes_started -eq 0 -and $importFail.tests_not_run -eq 1 -and
        -not (Test-Path -LiteralPath (Join-Path $root ".godot/ironclad-import.stamp"))) "failed import stops dependent scripts and invalidates the stamp"

    $missing = & pwsh -NoProfile -File $runner select -Test a_writes -Godot "ironclad-missing-exe" 2>&1 | Out-String
    Check ($LASTEXITCODE -eq 2 -and $missing.Contains("Required Godot executable")) "missing executable is a setup error"
    $document.tests.Remove("assertion")
    $document.tests["a_writes"].fixed_fps = "bad"
    $document | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $catalog
    $bad = & pwsh -NoProfile -File $runner check 2>&1 | Out-String
    Check ($LASTEXITCODE -eq 2 -and $bad.Contains("UNCLASSIFIED") -and $bad.Contains("fixed_fps")) "missing and invalid catalog metadata are reported"
    $done = $true
} finally {
    if ($done -and (Get-Item -LiteralPath $root).FullName -eq $fixture.FullName -and $fixture.Name -match '^ironclad-runtime-[a-f0-9-]{36}$') {
        Remove-Item -LiteralPath $root -Recurse -Force
    } else {
        Write-Host "Fixture and diagnostic output retained at $root"
    }
}
