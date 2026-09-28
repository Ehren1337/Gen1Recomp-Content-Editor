$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Push-Location $workspace
try {
  $env:EDITOR_TEST_ROOT = $workspace
  $result = Join-Path $PSScriptRoot 'layer-performance-smoke/result.txt'
  Set-Content -LiteralPath $result -Value 'RUNNING'
  $process = Start-Process -FilePath (Join-Path $workspace 'love/love.exe') -ArgumentList 'tests/content-editor/layer-performance-smoke' -WindowStyle Hidden -PassThru
  if (-not $process.WaitForExit(30000)) { $process.Kill(); throw 'Layer performance tests timed out' }
  $output = Get-Content -LiteralPath $result -Raw
  Write-Output $output
  if (-not $output.StartsWith('PASS:')) { throw 'Layer performance tests failed' }
} finally { Pop-Location }
