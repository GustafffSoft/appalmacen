param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("dev", "prod")]
    [string]$Environment,
    [switch]$IncludeStorage
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$mobileDir = Join-Path $repoRoot "mobile_app"

Push-Location $mobileDir
try {
    firebase deploy --only "firestore:rules" --project $Environment --non-interactive
    if ($IncludeStorage) {
        firebase deploy --only "storage" --project $Environment --non-interactive
    }
}
finally {
    Pop-Location
}
