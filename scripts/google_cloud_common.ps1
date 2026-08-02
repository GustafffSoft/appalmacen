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

function Assert-ProductionDeployment {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][bool]$Confirmed,
        [string]$ProjectId = "appalmacen-prod-5e987"
    )

    if (-not $Confirmed) {
        throw (
            "Production is protected. Run the command again with " +
            "-ConfirmProduction only after the release is approved."
        )
    }

    if ($ProjectId -ne "appalmacen-prod-5e987") {
        throw "Unexpected production project: $ProjectId"
    }

    $branch = (& git -C $RepoRoot branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $branch) {
        throw "The current Git branch could not be determined."
    }
    if ($branch -ne "main") {
        throw (
            "Production deployments are only allowed from main. " +
            "Current branch: $branch"
        )
    }

    Write-Warning "Confirmed production operation for $ProjectId from main."
}
