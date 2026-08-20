# Starts NANDAL using an installed Python, or the runtime bundled with Codex.
$ErrorActionPreference = 'Stop'
$serverFile = Join-Path $PSScriptRoot 'server.py'
$bundledPython = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'

if (Get-Command py -ErrorAction SilentlyContinue) {
    & py $serverFile
} elseif ((Get-Command python -ErrorAction SilentlyContinue) -and -not ((Get-Command python).Source -like '*WindowsApps*')) {
    & python $serverFile
} elseif (Test-Path -LiteralPath $bundledPython) {
    & $bundledPython $serverFile
} else {
    Write-Host 'Python is not installed. Install it from https://www.python.org/downloads/ then run this file again.' -ForegroundColor Yellow
}
