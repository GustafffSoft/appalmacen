$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$backendDir = Join-Path $repoRoot "backend"
$mobileDir = Join-Path $repoRoot "mobile_app"

Start-Process powershell `
    -ArgumentList "-NoExit", "-Command", "cd '$backendDir'; .\.venv312\Scripts\python.exe -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload"

Start-Process powershell `
    -ArgumentList "-NoExit", "-Command", "cd '$mobileDir'; `$env:HOST='0.0.0.0'; `$env:PORT='5180'; node .\scripts\serve_web_build.js"
