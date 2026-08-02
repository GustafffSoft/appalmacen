param(
    [string]$ProjectId = "appalmacen-prod-5e987",
    [string]$Region = "us-east1",
    [string]$ServiceAccountName = "appalmacen-api",
    [string]$SecretName = "appalmacen-openai-key",
    [switch]$ConfirmProduction
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$commonScript = Join-Path $PSScriptRoot "google_cloud_common.ps1"
. $commonScript
Assert-ProductionDeployment `
    -RepoRoot $repoRoot `
    -Confirmed $ConfirmProduction.IsPresent `
    -ProjectId $ProjectId
$gcloud = Get-GcloudCommand
Assert-GcloudLogin -GcloudCommand $gcloud

& $gcloud config set project $ProjectId
& $gcloud config set run/region $Region
& $gcloud services enable `
    run.googleapis.com `
    cloudbuild.googleapis.com `
    artifactregistry.googleapis.com `
    secretmanager.googleapis.com `
    iam.googleapis.com

$serviceAccountEmail = "$ServiceAccountName@$ProjectId.iam.gserviceaccount.com"
& $gcloud iam service-accounts describe $serviceAccountEmail --project $ProjectId 2>$null
if ($LASTEXITCODE -ne 0) {
    & $gcloud iam service-accounts create $ServiceAccountName `
        --project $ProjectId `
        --display-name "appalmacen Cloud Run API"
}

foreach ($role in @("roles/datastore.user", "roles/firebaseauth.viewer")) {
    & $gcloud projects add-iam-policy-binding $ProjectId `
        --member "serviceAccount:$serviceAccountEmail" `
        --role $role `
        --condition=None `
        --quiet
}

& $gcloud secrets describe $SecretName --project $ProjectId 2>$null
if ($LASTEXITCODE -ne 0) {
    & $gcloud secrets create $SecretName `
        --project $ProjectId `
        --replication-policy automatic
}

$addSecret = Read-Host "Agregar una nueva version de OPENAI_API_KEY ahora? (s/n)"
if ($addSecret.Trim().ToLowerInvariant() -eq "s") {
    $secureValue = Read-Host "OPENAI_API_KEY" -AsSecureString
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureValue)
    $tempFile = [IO.Path]::GetTempFileName()
    try {
        $plainValue = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        [IO.File]::WriteAllText(
            $tempFile,
            $plainValue,
            [Text.UTF8Encoding]::new($false)
        )
        & $gcloud secrets versions add $SecretName `
            --project $ProjectId `
            --data-file $tempFile
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        $plainValue = $null
    }
}

& $gcloud secrets add-iam-policy-binding $SecretName `
    --project $ProjectId `
    --member "serviceAccount:$serviceAccountEmail" `
    --role roles/secretmanager.secretAccessor `
    --quiet

Write-Host "Google Cloud production setup completed for $ProjectId."
