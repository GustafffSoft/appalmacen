param(
    [string]$ProjectId = "appalmacen-prod-5e987",
    [string]$Region = "us-east1",
    [string]$ServiceName = "appalmacen-api",
    [string]$ServiceAccountName = "appalmacen-api",
    [string]$SecretName = "appalmacen-openai-key",
    [switch]$ConfirmProduction
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$backendDir = Join-Path $repoRoot "backend"
$serviceAccountEmail = "$ServiceAccountName@$ProjectId.iam.gserviceaccount.com"
$commonScript = Join-Path $PSScriptRoot "google_cloud_common.ps1"
. $commonScript
Assert-ProductionDeployment `
    -RepoRoot $repoRoot `
    -Confirmed $ConfirmProduction.IsPresent `
    -ProjectId $ProjectId
$gcloud = Get-GcloudCommand
Assert-GcloudLogin -GcloudCommand $gcloud

Push-Location $backendDir
try {
    & $gcloud run deploy $ServiceName `
        --project $ProjectId `
        --region $Region `
        --source . `
        --service-account $serviceAccountEmail `
        --allow-unauthenticated `
        --port 8080 `
        --cpu 2 `
        --memory 4Gi `
        --concurrency 1 `
        --timeout 900 `
        --min 0 `
        --max 2 `
        --cpu-boost `
        --env-vars-file cloudrun.env.yaml `
        --set-secrets "OPENAI_API_KEY=$SecretName`:latest" `
        --quiet
}
finally {
    Pop-Location
}
