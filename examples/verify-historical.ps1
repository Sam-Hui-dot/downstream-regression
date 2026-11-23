param(
    [string]$Moon = 'moon',
    [string]$Git = 'git',
    [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$projectDir = Split-Path -Parent $PSScriptRoot
$moonExecutable = (Get-Command $Moon -CommandType Application | Select-Object -First 1).Source
$gitExecutable = (Get-Command $Git -CommandType Application | Select-Object -First 1).Source

Push-Location -LiteralPath $projectDir
try {
    $cliArgs = @('run', '--target', 'wasm', 'cmd/main', '--')
    if ($OutDir) {
        $cliArgs += @('--out', $OutDir)
    }
    $cliArgs += @('batch', $moonExecutable, $gitExecutable, 'examples/historical-plan.json')
    $output = & $moonExecutable @cliArgs
    $code = $LASTEXITCODE
    if ($code -ne 1) {
        $diagnostics = $output | Select-Object -Last 1 | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
        foreach ($trial in $diagnostics.cases) {
            Write-Host "Case: $($trial.id)"
            $reportPath = Join-Path $trial.evidence 'report.json'
            if (Test-Path -LiteralPath $reportPath -PathType Leaf) {
                Get-Content -Raw -LiteralPath $reportPath | Write-Host
            }
            foreach ($name in 'baseline-test.txt', 'candidate-test.txt') {
                $log = Join-Path $trial.evidence $name
                if (Test-Path -LiteralPath $log -PathType Leaf) {
                    Write-Host "Log: $name"
                    $lines = Get-Content -LiteralPath $log
                    $lines | Select-String -Pattern 'Error|error|failed|panic|Total tests' | Select-Object -Last 24 | ForEach-Object { Write-Host "  $($_.Line)" }
                    $lines | Select-Object -Last 8 | ForEach-Object { Write-Host "  $_" }
                }
            }
        }
        throw "Expected one regression in the batch. Exit code $code. Output: $output"
    }

    $batch = $output | Select-Object -Last 1 | ConvertFrom-Json
    $changed = $batch.cases | Where-Object id -eq 'moonback-async-cancellation'
    $control = $batch.cases | Where-Object id -eq 'moonyacc-async-control'
    if ($batch.cases.Count -ne 2 -or $changed.exit_code -ne 1 -or $control.exit_code -ne 0) {
        throw "Unexpected batch status. Evidence: $($batch.evidence)"
    }
    if ($changed.status -ne 'new_test_failure' -or $changed.new_failure_count -ne 6 -or $control.status -ne 'pass') {
        throw "Unexpected batch summary metadata. Evidence: $($batch.evidence)"
    }

    $batchMd = Join-Path $batch.evidence 'batch.md'
    $moonbackMd = Join-Path $changed.evidence 'report.md'
    $moonyaccMd = Join-Path $control.evidence 'report.md'
    foreach ($mdPath in $batchMd, $moonbackMd, $moonyaccMd) {
        if (-not (Test-Path -LiteralPath $mdPath -PathType Leaf)) {
            throw "Expected Markdown report was not written: $mdPath"
        }
    }

    $moonbackReport = Get-Content -Raw -LiteralPath (Join-Path $changed.evidence 'report.json') | ConvertFrom-Json -AsHashtable
    $moonyaccReport = Get-Content -Raw -LiteralPath (Join-Path $control.evidence 'report.json') | ConvertFrom-Json -AsHashtable
    if ($moonbackReport.status -ne 'new_test_failure' -or
        $moonbackReport.baseline.dependency -ne 'moonbitlang/async@0.21.0' -or
        $moonbackReport.candidate.dependency -ne 'moonbitlang/async@0.22.0' -or
        $moonbackReport.baseline.counts.passed -ne 89 -or
        $moonbackReport.candidate.counts.passed -ne 83 -or
        $moonbackReport.new_failures.Count -ne 6) {
        throw "MoonBack comparison did not reproduce the expected failures. Evidence: $($changed.evidence)"
    }
    if ($moonyaccReport.status -ne 'pass' -or
        $moonyaccReport.baseline.dependency -ne 'moonbitlang/async@0.20.3' -or
        $moonyaccReport.candidate.dependency -ne 'moonbitlang/async@0.22.4' -or
        $moonyaccReport.baseline.counts.passed -ne 74 -or
        $moonyaccReport.candidate.counts.passed -ne 74 -or
        $moonyaccReport.new_failures.Count -ne 0) {
        throw "moonyacc comparison did not reproduce the expected passing control. Evidence: $($control.evidence)"
    }

    Write-Output "MoonBack: 89/89 -> 83/89, six new failures. moonyacc: 74/74 -> 74/74."
    Write-Output "Evidence: $($batch.evidence)"
} finally {
    Pop-Location
}
