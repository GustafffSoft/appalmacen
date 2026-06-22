Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Set-Location "$PSScriptRoot\..\backend"

if (Test-Path ".\.venv312\Scripts\python.exe") {
    & ".\.venv312\Scripts\python.exe" -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
    exit
}

if (Test-Path ".\.venv\Scripts\python.exe") {
    & ".\.venv\Scripts\python.exe" -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
    exit
}

uvicorn main:app --reload --host 0.0.0.0 --port 8000
