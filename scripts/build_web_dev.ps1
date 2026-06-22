param(
    [string]$BackendUrl = "http://127.0.0.1:8000"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$mobileDir = Join-Path $repoRoot "mobile_app"

Push-Location $mobileDir
try {
    flutter build web `
        --dart-define=APP_ENV=dev `
        --dart-define=BACKEND_BASE_URL=$BackendUrl
}
finally {
    Pop-Location
}
