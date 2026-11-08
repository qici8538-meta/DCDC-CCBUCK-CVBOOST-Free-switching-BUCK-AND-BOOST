$ErrorActionPreference = 'Stop'
$dapPidFile = Join-Path $PSScriptRoot '.mcuviewer-dap\server.pid'
if (-not (Test-Path -LiteralPath $dapPidFile)) { Write-Output 'No managed server PID.'; exit 0 }
$dapOwnedId = [int](Get-Content -LiteralPath $dapPidFile)
$dapOwnedProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$dapOwnedId"
if ($null -eq $dapOwnedProcess) { Write-Output 'Server already stopped.'; exit 0 }
$dapExpectedConfig = Join-Path $PSScriptRoot 'tools\mcuviewer_dap.cfg'
if ($dapOwnedProcess.Name -ne 'openocd.exe' -or -not $dapOwnedProcess.CommandLine.Contains($dapExpectedConfig)) {
    throw 'PID belongs to another process; nothing stopped.'
}
Stop-Process -Id $dapOwnedId
Write-Output 'DAP GDB server stopped; probe is available to Keil.'
