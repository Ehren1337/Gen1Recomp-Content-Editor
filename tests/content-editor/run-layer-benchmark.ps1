param(
  [string]$BaselineRevision = 'a1ab535',
  [ValidateRange(1,10)][int]$Trials = 3
)
$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Push-Location $workspace
try {
  $env:EDITOR_TEST_ROOT = $workspace
  $directory = Join-Path $PSScriptRoot 'layer-benchmark-smoke'
  $source = & git show "${BaselineRevision}:tools/content-editor/Gen3LayeredRuntime.lua"
  if ($LASTEXITCODE -ne 0) { throw 'Cannot read benchmark baseline revision' }
  [IO.File]::WriteAllText((Join-Path $directory 'baseline.lua'), ($source -join "`n"), [Text.UTF8Encoding]::new($false))
  $results = @()
  for ($trial=1; $trial -le $Trials; $trial++) {
    foreach ($variant in @('baseline','updated')) {
      foreach ($scenario in @('static','animated')) {
        $env:EDITOR_BENCH_VARIANT=$variant
        $env:EDITOR_BENCH_SCENARIO=$scenario
        $result=Join-Path $directory "$variant-$scenario.txt"
        Set-Content -LiteralPath $result -Value 'RUNNING'
        $process=Start-Process -FilePath (Join-Path $workspace 'love/love.exe') -ArgumentList 'tests/content-editor/layer-benchmark-smoke' -WindowStyle Hidden -PassThru
        if (-not $process.WaitForExit(45000)) { $process.Kill(); throw 'Layer benchmark timed out' }
        $text=(Get-Content -LiteralPath $result -Raw).Trim()
        if (-not $text.StartsWith("$variant $scenario |")) { throw $text }
        $line="trial=$trial | $text"
        $results += $line
        Write-Output $line
      }
    }
  }
  Set-Content -LiteralPath (Join-Path $directory 'trials.txt') -Value $results
} finally { Pop-Location }
