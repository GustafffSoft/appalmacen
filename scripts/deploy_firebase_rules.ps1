param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("dev", "prod")]
    [string]$Environment,
    [switch]$IncludeStorage,
    [switch]$ConfirmProduction
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$mobileDir = Join-Path $repoRoot "mobile_app"

if ($Environment -eq "prod") {
    $commonScript = Join-Path $PSScriptRoot "google_cloud_common.ps1"
    . $commonScript
    Assert-ProductionDeployment `
        -RepoRoot $repoRoot `
        -Confirmed $ConfirmProduction.IsPresent
}

if ($IncludeStorage) {
    $commonScript = Join-Path $PSScriptRoot "google_cloud_common.ps1"
    . $commonScript
    $gcloud = Get-GcloudCommand
    Assert-GcloudLogin -GcloudCommand $gcloud

    $firebaseConfig = Get-Content (Join-Path $mobileDir ".firebaserc") -Raw |
        ConvertFrom-Json
    $projectId = $firebaseConfig.projects.$Environment
    $projectNumber = & $gcloud projects describe $projectId `
        --format="value(projectNumber)"
    if ($LASTEXITCODE -ne 0 -or -not $projectNumber) {
        throw "Could not resolve the project number for $projectId."
    }

    $storageServiceAgent =
        "service-$projectNumber@gcp-sa-firebasestorage.iam.gserviceaccount.com"
    & $gcloud projects add-iam-policy-binding $projectId `
        --member "serviceAccount:$storageServiceAgent" `
        --role "roles/firebaserules.firestoreServiceAgent" `
        --condition=None `
        --format=none `
        --quiet
    if ($LASTEXITCODE -ne 0) {
        throw "Storage could not be authorized to read Firestore roles."
    }

    $storageCors = Join-Path $mobileDir "storage.cors.json"
    $storageBucket = "gs://$projectId.firebasestorage.app"
    & $gcloud storage buckets update $storageBucket `
        --cors-file=$storageCors `
        --quiet
    if ($LASTEXITCODE -ne 0) {
        throw "Storage CORS configuration failed for $Environment."
    }
}

Push-Location $mobileDir
try {
    firebase deploy --only "firestore:rules" --project $Environment --non-interactive
    if ($LASTEXITCODE -ne 0) {
        throw "Firestore rules deployment failed for $Environment."
    }
    if ($IncludeStorage) {
        firebase deploy --only "storage" --project $Environment --non-interactive
        if ($LASTEXITCODE -ne 0) {
            throw "Storage rules deployment failed for $Environment."
        }
    }
}
finally {
    Pop-Location
}
