param(
    [string]$ProjectId = "appalmacen-prod-5e987",
    [string]$SecretName = "appalmacen-openai-key",
    [switch]$ConfirmProduction
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $repoRoot "backend\.env"
$commonScript = Join-Path $PSScriptRoot "google_cloud_common.ps1"
. $commonScript
Assert-ProductionDeployment `
    -RepoRoot $repoRoot `
    -Confirmed $ConfirmProduction.IsPresent `
    -ProjectId $ProjectId
$gcloud = Get-GcloudCommand
Assert-GcloudLogin -GcloudCommand $gcloud

$keyLine = Get-Content -LiteralPath $envPath |
    Where-Object { $_ -like "OPENAI_API_KEY=*" } |
    Select-Object -First 1
if (-not $keyLine) {
    throw "OPENAI_API_KEY is missing from backend/.env."
}

$key = $keyLine.Substring("OPENAI_API_KEY=".Length).Trim()
if (-not $key) {
    throw "OPENAI_API_KEY is empty in backend/.env."
}

$tempFile = Join-Path $env:TEMP (
    "appalmacen-openai-" + [Guid]::NewGuid().ToString("N") + ".tmp"
)
try {
    [IO.File]::WriteAllText(
        $tempFile,
        $key,
        [Text.UTF8Encoding]::new($false)
    )
    & $gcloud secrets versions add $SecretName `
        --project $ProjectId `
        --data-file $tempFile
    if ($LASTEXITCODE -ne 0) {
        throw "The OpenAI secret version could not be uploaded."
    }
}
finally {
    $key = $null
    if (Test-Path -LiteralPath $tempFile) {
        Remove-Item -LiteralPath $tempFile -Force
    }
}

Write-Host "OpenAI secret version uploaded without exposing its value."
