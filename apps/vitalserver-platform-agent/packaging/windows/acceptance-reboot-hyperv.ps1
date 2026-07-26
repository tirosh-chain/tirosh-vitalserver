param(
    [Parameter(Mandatory = $true)]
    [string]$APITokenPath,
    [Parameter(Mandatory = $true)]
    [string]$RuntimeProviderDocumentPath,
    [Parameter(Mandatory = $true)]
    [string]$HyperVImageManifestPath,
    [Parameter(Mandatory = $true)]
    [string]$InstallDocumentPath,
    [Parameter(Mandatory = $true)]
    [string]$ReleaseManifestPath,
    [Parameter(Mandatory = $true)]
    [string]$RuntimeAcceptanceManifestPath,
    [Parameter(Mandatory = $true)]
    [string]$OutputManifestPath,
    [string]$BaseURL = "http://127.0.0.1:18321",
    [int]$TimeoutSeconds = 360
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$runID = [Guid]::NewGuid().ToString()
$startedAt = [DateTime]::UtcNow
$stages = [System.Collections.Generic.List[object]]::new()
$currentStage = "preflight"
$installedBootSessionId = $null
$currentBootSessionId = $null
$runtimeAcceptanceRunId = $null
$platformVersion = $null
$runtimeBundleVersion = $null
$installedAcceptanceRunId = $null
$releaseManifestSHA256 = $null

function Add-Stage {
    param([string]$Name, [string]$Status, [string]$Message)
    $stages.Add([ordered]@{
        name = $Name
        status = $Status
        message = $Message
        observedAt = [DateTime]::UtcNow.ToString("o")
    })
}

function Write-Proof {
    param([string]$Status, [string]$FailureStage, [string]$FailureReason)
    $proof = [ordered]@{
        schemaVersion = 1
        runId = $runID
        platform = "windows-hyperv-amd64"
        kind = "reboot"
        status = $Status
        startedAt = $startedAt.ToString("o")
        completedAt = [DateTime]::UtcNow.ToString("o")
        stages = $stages
        failureStage = if ($FailureStage) { $FailureStage } else { $null }
        failureReason = if ($FailureReason) { $FailureReason } else { $null }
        installedBootSessionId = $installedBootSessionId
        currentBootSessionId = $currentBootSessionId
        runtimeAcceptanceRunId = $runtimeAcceptanceRunId
        platformVersion = $platformVersion
        runtimeBundleVersion = $runtimeBundleVersion
        installedAcceptanceRunId = $installedAcceptanceRunId
        releaseManifestSHA256 = $releaseManifestSHA256
    }
    $directory = Split-Path -Parent $OutputManifestPath
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporary = "$OutputManifestPath.tmp.$PID"
    $json = $proof | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $OutputManifestPath -Force
}

try {
    if (-not (Test-Path -LiteralPath $InstallDocumentPath -PathType Leaf)) {
        throw "Windows install owner is missing path=$InstallDocumentPath"
    }
    $install = Get-Content -LiteralPath $InstallDocumentPath -Raw | ConvertFrom-Json
    if ($install.schemaVersion -ne 1 -or $install.state -ne "installed" -or -not $install.platformVersion -or -not $install.runtimeBundleVersion -or -not $install.installedBootSessionId -or -not $install.installedAcceptanceRunId) {
        throw "Windows install owner contract is invalid path=$InstallDocumentPath"
    }
    $release = Get-Content -LiteralPath $ReleaseManifestPath -Raw | ConvertFrom-Json
    if ($release.schemaVersion -ne 1 -or $release.state -ne 'releaseCandidate' -or
        $release.platformVersion -ne $install.platformVersion -or $release.runtimeBundleVersion -ne $install.runtimeBundleVersion) {
        throw "Windows reboot acceptance requires the installed sealed release manifest path=$ReleaseManifestPath"
    }
    $platformVersion = [string]$install.platformVersion
    $runtimeBundleVersion = [string]$install.runtimeBundleVersion
    $installedAcceptanceRunId = [string]$install.installedAcceptanceRunId
    $releaseManifestSHA256 = (Get-FileHash -LiteralPath $ReleaseManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $installedBootSessionId = [DateTime]::Parse([string]$install.installedBootSessionId).ToUniversalTime().ToString("o")
    $currentBootSessionId = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString("o")
    Add-Stage -Name $currentStage -Status "passed" -Message "Install and host boot-session owners are available."

    $currentStage = "boot-session-changed"
    if ($currentBootSessionId -eq $installedBootSessionId) {
        throw "Windows host has not rebooted since install owner publication bootSessionId=$currentBootSessionId"
    }
    Add-Stage -Name $currentStage -Status "passed" -Message "Windows host boot session changed installed=$installedBootSessionId current=$currentBootSessionId."

    $currentStage = "installed-runtime-acceptance"
    $acceptanceScript = Join-Path $PSScriptRoot "acceptance-hyperv.ps1"
    & $acceptanceScript `
        -PlatformVersion $install.platformVersion `
        -RuntimeBundleVersion $install.runtimeBundleVersion `
        -ReleaseManifestPath $ReleaseManifestPath `
        -APITokenPath $APITokenPath `
        -RuntimeProviderDocumentPath $RuntimeProviderDocumentPath `
        -HyperVImageManifestPath $HyperVImageManifestPath `
        -OutputManifestPath $RuntimeAcceptanceManifestPath `
        -BaseURL $BaseURL `
        -TimeoutSeconds $TimeoutSeconds
    $acceptance = Get-Content -LiteralPath $RuntimeAcceptanceManifestPath -Raw | ConvertFrom-Json
    if ($acceptance.status -ne "passed" -or $acceptance.hostBootSessionId -ne $currentBootSessionId -or -not $acceptance.runId) {
        throw "Post-reboot Hyper-V Runtime acceptance does not prove the current host boot session."
    }
    $runtimeAcceptanceRunId = $acceptance.runId
    Add-Stage -Name $currentStage -Status "passed" -Message "Hyper-V Runtime acceptance passed after host reboot runId=$runtimeAcceptanceRunId."

    Write-Proof -Status "passed" -FailureStage "" -FailureReason ""
    Write-Output "VitalServer Windows reboot acceptance passed runId=$runID manifest=$OutputManifestPath"
} catch {
    $reason = $_.Exception.Message
    Add-Stage -Name $currentStage -Status "failed" -Message $reason
    Write-Proof -Status "failed" -FailureStage $currentStage -FailureReason $reason
    throw "VitalServer Windows reboot acceptance failed runId=$runID stage=$currentStage reason=$reason manifest=$OutputManifestPath"
}
