param(
    [string]$BackendUrl = "https://appalmacen-prod-5e987.web.app"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$mobileDir = Join-Path $repoRoot "mobile_app"

if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) {
    throw "Firebase CLI is not installed or is not in PATH."
}

& (Join-Path $PSScriptRoot "build_web_prod.ps1") -BackendUrl $BackendUrl

Push-Location $mobileDir
try {
    firebase deploy --project prod --only hosting
}
finally {
    Pop-Location
}
