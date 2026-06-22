param(
    [Parameter(Mandatory = $true)]
    [string]$BackendUrl
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$mobileDir = Join-Path $repoRoot "mobile_app"

if (-not $BackendUrl.StartsWith("https://")) {
    throw "Production backend URL must use HTTPS."
}

Push-Location $mobileDir
try {
    flutter build web `
        --dart-define=APP_ENV=prod `
        --dart-define=BACKEND_PROD_URL=$BackendUrl
}
finally {
    Pop-Location
}
