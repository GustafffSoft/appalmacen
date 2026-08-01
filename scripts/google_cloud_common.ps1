function Get-GcloudCommand {
    $command = Get-Command gcloud -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd"),
        "C:\Program Files\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd",
        "C:\Program Files (x86)\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    throw "Google Cloud CLI (gcloud) is not installed or is not in PATH."
}

function Assert-GcloudLogin {
    param([Parameter(Mandatory = $true)][string]$GcloudCommand)

    $account = & $GcloudCommand auth list `
        --filter="status:ACTIVE" `
        --format="value(account)"
    if (-not $account) {
        throw "Google Cloud login is required. Run: gcloud auth login"
    }
    Write-Host "Google Cloud account: $account"
}
