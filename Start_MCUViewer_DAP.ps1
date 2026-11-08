$ErrorActionPreference = 'Stop'
$dapOpenOcd = 'D:\software\stm32cubeide\STM32CubeIDE_2.0.0\STM32CubeIDE\plugins\com.st.stm32cube.ide.mcu.externaltools.openocd.win32_2.4.300.202509300731\tools\bin\openocd.exe'
$dapScripts = 'D:\software\stm32cubeide\STM32CubeIDE_2.0.0\STM32CubeIDE\plugins\com.st.stm32cube.ide.mcu.debug.openocd_2.3.200.202510310951\resources\openocd\st_scripts'
$dapConfig = Join-Path $PSScriptRoot 'tools\mcuviewer_dap.cfg'
$dapLogDirectory = Join-Path $PSScriptRoot '.mcuviewer-dap'
foreach ($dapRequired in @($dapOpenOcd, $dapScripts, $dapConfig)) {
    if (-not (Test-Path -LiteralPath $dapRequired)) { throw "Missing: $dapRequired" }
}
$dapExisting = @(Get-NetTCPConnection -State Listen -LocalPort 3333 -ErrorAction SilentlyContinue)
if ($dapExisting.Count -gt 0) {
    Write-Output 'Port 3333 is already listening. This does NOT verify the target link.'
    Write-Output 'After MCU/SLAVE power loss, use Restart_MCUViewer_DAP.cmd, then disconnect/reconnect MCUViewer.'
    exit 0
}
New-Item -ItemType Directory -Path $dapLogDirectory -Force | Out-Null
$dapArguments = '-s "{0}" -f "{1}"' -f $dapScripts, $dapConfig
$dapProcess = Start-Process -FilePath $dapOpenOcd -ArgumentList $dapArguments -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $dapLogDirectory 'server.stdout.log') -RedirectStandardError (Join-Path $dapLogDirectory 'server.stderr.log')
$dapProcess.Id | Set-Content -LiteralPath (Join-Path $dapLogDirectory 'server.pid')
for ($dapAttempt = 0; $dapAttempt -lt 20; $dapAttempt++) {
    Start-Sleep -Milliseconds 250
    $dapProcess.Refresh()
    if ($dapProcess.HasExited) {
        Get-Content -LiteralPath (Join-Path $dapLogDirectory 'server.stderr.log')
        throw 'DAP GDB server exited. Check wiring, pairing, power and probe ownership.'
    }
    if (Get-NetTCPConnection -State Listen -LocalPort 3333 -ErrorAction SilentlyContinue) {
        Write-Output 'DAP GDB server ready: 127.0.0.1:3333. Start acquisition in MCUViewer.'
        exit 0
    }
}
throw 'Server startup timed out; see .mcuviewer-dap logs.'
