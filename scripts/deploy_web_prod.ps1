param(
    [string]$BackendUrl = "https://appalmacen-prod-5e987.web.app",
    [switch]$ConfirmProduction
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$mobileDir = Join-Path $repoRoot "mobile_app"
$commonScript = Join-Path $PSScriptRoot "google_cloud_common.ps1"
. $commonScript
Assert-ProductionDeployment `
    -RepoRoot $repoRoot `
    -Confirmed $ConfirmProduction.IsPresent

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
