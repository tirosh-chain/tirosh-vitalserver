param(
    [Parameter(Mandatory = $true)][string]$BundleDirectory,
    [Parameter(Mandatory = $true)][string]$OutputManifestPath,
    [string]$ProgramFilesRoot = (Join-Path $env:ProgramFiles 'VitalServer'),
    [string]$ProgramDataRoot = (Join-Path $env:ProgramData 'VitalServer'),
    [string]$BaseURL = 'http://127.0.0.1:18321',
    [int]$TimeoutSeconds = 1200
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$runID = [Guid]::NewGuid().ToString()
$startedAt = [DateTime]::UtcNow
$stages = [Collections.Generic.List[object]]::new()
$currentStage = 'preflight'
$headers = $null
$originalSettingsJSON = $null
$settingsMarkerApplied = $false
$platformVersion = $null
$runtimeBundleVersion = $null
$sealedAcceptanceRunId = $null
$releaseManifestSHA256 = $null
$beforeInstalledAcceptanceRunId = $null
$afterInstalledAcceptanceRunId = $null
$runtimeDataVHDXPath = $null

function Add-Stage {
    param([string]$Name, [string]$Status, [string]$Message)
    $stages.Add([ordered]@{ name = $Name; status = $Status; message = $Message; observedAt = [DateTime]::UtcNow.ToString('o') })
}

function Write-Proof {
    param([string]$Status, [string]$FailureStage, [string]$FailureReason, [string]$SettingsRestoreError)
    $proof = [ordered]@{
        schemaVersion = 1
        kind = 'uninstall-reinstall-data-preservation'
        runId = $runID
        platform = 'windows-hyperv-amd64'
        status = $Status
        startedAt = $startedAt.ToString('o')
        completedAt = [DateTime]::UtcNow.ToString('o')
        stages = $stages
        failureStage = if ($FailureStage) { $FailureStage } else { $null }
        failureReason = if ($FailureReason) { $FailureReason } else { $null }
        settingsRestoreError = if ($SettingsRestoreError) { $SettingsRestoreError } else { $null }
        platformVersion = $platformVersion
        runtimeBundleVersion = $runtimeBundleVersion
        sealedAcceptanceRunId = $sealedAcceptanceRunId
        releaseManifestSHA256 = $releaseManifestSHA256
        beforeInstalledAcceptanceRunId = $beforeInstalledAcceptanceRunId
        afterInstalledAcceptanceRunId = $afterInstalledAcceptanceRunId
        runtimeDataVHDXPath = $runtimeDataVHDXPath
    }
    $directory = Split-Path -Parent $OutputManifestPath
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporary = "$OutputManifestPath.tmp.$PID"
    [IO.File]::WriteAllText($temporary, ($proof | ConvertTo-Json -Depth 10) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $OutputManifestPath -Force
}

function Read-JSONOwner {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label owner is missing path=$Path" }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { throw "$Label owner decode failed path=$Path reason=$($_.Exception.Message)" }
}

function Read-InstallOwner {
    param([string]$Path)
    $owner = Read-JSONOwner -Path $Path -Label 'Windows install'
    if ($owner.schemaVersion -ne 1 -or $owner.state -ne 'installed' -or -not $owner.platformVersion -or
        -not $owner.runtimeBundleVersion -or -not $owner.installedAcceptanceRunId) {
        throw "Windows install owner contract is invalid path=$Path"
    }
    return $owner
}

function Get-OwnerDigests {
    param([string[]]$Paths)
    $digests = [ordered]@{}
    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Mutable Host owner is missing path=$path" }
        $digests[[IO.Path]::GetFullPath($path)] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return $digests
}

function Assert-OwnerDigests {
    param([object]$Expected)
    foreach ($property in $Expected.GetEnumerator()) {
        $path = [string]$property.Key
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Mutable Host owner disappeared path=$path" }
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne [string]$property.Value) { throw "Mutable Host owner changed path=$path expected=$($property.Value) actual=$actual" }
    }
}

function Apply-SettingsDocument {
    param([string]$SettingsJSON)
    $body = '{"settings":' + $SettingsJSON + '}'
    $operation = Invoke-RestMethod -Method Put -Uri "$BaseURL/runtime/settings" -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 120
    if ($operation.state -notin @('accepted', 'running', 'completed')) { throw "Runtime settings apply failed state=$($operation.state)" }
}

function Require-SettingsMarker {
    param([string]$Marker, [string]$Transition)
    $read = Invoke-RestMethod -Method Get -Uri "$BaseURL/runtime/settings" -Headers $headers -TimeoutSec 60
    if ($read.state -ne 'loaded' -or $null -eq $read.settings -or $read.settings.publicHost -ne $Marker) {
        throw "Runtime settings marker was not preserved after $Transition state=$($read.state) actual=$($read.settings.publicHost)"
    }
}

function Wait-LocalUninstall {
    param([string]$Path, [string]$OperationId)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $lastRead = 'not read'
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $operation = Read-JSONOwner -Path $Path -Label 'Windows uninstall workflow'
            if ($operation.operationId -ne $OperationId) { throw "Uninstall workflow identity changed expected=$OperationId actual=$($operation.operationId)" }
            if ($operation.kind -ne 'uninstall') { throw "Uninstall workflow kind changed actual=$($operation.kind)" }
            if ($operation.state -eq 'completed') { return $operation }
            if ($operation.state -eq 'failed') { throw "Uninstall workflow failed failure=$($operation.failure.message)" }
            $lastRead = "state=$($operation.state)"
        } catch {
            $lastRead = $_.Exception.Message
            if ($lastRead -match 'identity changed|kind changed|workflow failed') { throw }
        }
        Start-Sleep -Seconds 1
    }
    throw "Uninstall workflow did not complete operationId=$OperationId lastRead=$lastRead"
}

function Wait-Platform {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $lastRead = 'not read'
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            Invoke-RestMethod -Method Get -Uri "$BaseURL/platform" -Headers $headers -TimeoutSec 30 | Out-Null
            Invoke-RestMethod -Method Get -Uri "$BaseURL/runtime/capabilities" -Headers $headers -TimeoutSec 30 | Out-Null
            return
        } catch { $lastRead = $_.Exception.Message }
        Start-Sleep -Seconds 1
    }
    throw "Reinstalled Platform and Runtime APIs did not become available lastRead=$lastRead"
}

$settingsRestoreError = $null
$failureReason = $null
try {
    $bundleRoot = [IO.Path]::GetFullPath($BundleDirectory)
    $bundleRelease = Read-JSONOwner -Path (Join-Path $bundleRoot 'release.json') -Label 'Sealed bundle release'
    if ($bundleRelease.schemaVersion -ne 1 -or $bundleRelease.state -ne 'releaseCandidate' -or -not $bundleRelease.installedAcceptanceRunId) {
        throw 'Uninstall/reinstall acceptance requires a sealed Windows releaseCandidate bundle.'
    }
    $platformVersion = [string]$bundleRelease.platformVersion
    $runtimeBundleVersion = [string]$bundleRelease.runtimeBundleVersion
    $sealedAcceptanceRunId = [string]$bundleRelease.installedAcceptanceRunId
    $releaseManifestSHA256 = (Get-FileHash -LiteralPath (Join-Path $bundleRoot 'release.json') -Algorithm SHA256).Hash.ToLowerInvariant()
    $installPath = Join-Path $ProgramDataRoot 'install.json'
    $provisionPath = Join-Path $ProgramDataRoot 'hyperv-provision.json'
    $operationPath = Join-Path $ProgramDataRoot 'run\platform-workflow.json'
    $tokenPath = Join-Path $ProgramDataRoot 'secrets\platform-api-token'
    $ownerPaths = @($tokenPath, (Join-Path $ProgramDataRoot 'config\platform-agent.json'), (Join-Path $ProgramDataRoot 'config\hyperv-runtime-provider.json'))
    $beforeInstall = Read-InstallOwner -Path $installPath
    $beforeInstalledAcceptanceRunId = [string]$beforeInstall.installedAcceptanceRunId
    if ($beforeInstall.platformVersion -ne $bundleRelease.platformVersion -or
        $beforeInstall.runtimeBundleVersion -ne $bundleRelease.runtimeBundleVersion) {
        throw 'Installed release identity differs from the sealed reinstall bundle.'
    }
    $bundleReleasePath = Join-Path $bundleRoot 'release.json'
    $installedReleasePath = Join-Path ([string]$beforeInstall.releasePath) 'release.json'
    if ((Get-FileHash -LiteralPath $installedReleasePath -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath $bundleReleasePath -Algorithm SHA256).Hash) {
        throw 'Installed immutable release bytes differ from the sealed reinstall bundle.'
    }
    $beforeProvision = Read-JSONOwner -Path $provisionPath -Label 'Hyper-V provision'
    if ($beforeProvision.schemaVersion -ne 1 -or $beforeProvision.state -ne 'provisioned') { throw 'Hyper-V provision owner contract is invalid.' }
    $dataPath = [IO.Path]::GetFullPath([string]$beforeProvision.runtimeDataVHDXPath)
    $runtimeDataVHDXPath = $dataPath
    $dataItem = Get-Item -LiteralPath $dataPath -ErrorAction Stop
    $dataCreationTime = $dataItem.CreationTimeUtc.ToString('o')
    $ownerDigests = Get-OwnerDigests -Paths $ownerPaths
    $apiToken = (Get-Content -LiteralPath $tokenPath -Raw).Trim()
    if (-not $apiToken) { throw "Platform API token owner is empty path=$tokenPath" }
    $headers = @{ Authorization = "Bearer $apiToken" }
    $capabilities = Invoke-RestMethod -Method Get -Uri "$BaseURL/platform/capabilities" -Headers $headers -TimeoutSec 30
    if ($capabilities.canUninstallRuntime -ne $true) { throw 'Platform Agent does not explicitly support uninstall.' }
    Add-Stage -Name 'preflight' -Status 'passed' -Message 'Sealed release, install/provision owners, standard uninstall capability, mutable Host owners, and Runtime data VHDX are explicit.'

    $currentStage = 'runtime-data-marker-applied'
    $settingsRead = Invoke-RestMethod -Method Get -Uri "$BaseURL/runtime/settings" -Headers $headers -TimeoutSec 60
    if ($settingsRead.state -ne 'loaded' -or $null -eq $settingsRead.settings) { throw 'Runtime settings owner is not loaded.' }
    $originalSettingsJSON = $settingsRead.settings | ConvertTo-Json -Depth 20 -Compress
    $markerSettings = $originalSettingsJSON | ConvertFrom-Json
    $marker = "acceptance-$runID.invalid"
    $markerSettings.publicHost = $marker
    Apply-SettingsDocument -SettingsJSON ($markerSettings | ConvertTo-Json -Depth 20 -Compress)
    $settingsMarkerApplied = $true
    Require-SettingsMarker -Marker $marker -Transition 'marker apply'
    Add-Stage -Name $currentStage -Status 'passed' -Message "Runtime-owned mutable settings marker applied marker=$marker."

    $currentStage = 'uninstall-accepted'
    $uninstall = Invoke-RestMethod -Method Post -Uri "$BaseURL/platform/uninstall" -Headers $headers -ContentType 'application/json' -Body '{"mode":"standard"}' -TimeoutSec 60
    if ($uninstall.kind -ne 'uninstall' -or $uninstall.state -ne 'accepted') { throw "Standard uninstall was not accepted response=$uninstall" }
    Add-Stage -Name $currentStage -Status 'passed' -Message "Standard uninstall accepted operationId=$($uninstall.operationId)."

    $currentStage = 'uninstall-completed'
    Wait-LocalUninstall -Path $operationPath -OperationId $uninstall.operationId | Out-Null
    if ((Get-Service -Name 'VitalServerPlatformAgent' -ErrorAction SilentlyContinue) -or
        (Get-Service -Name 'VitalServerHyperVRuntime' -ErrorAction SilentlyContinue) -or
        (Get-VM -Name ([string]$beforeProvision.vmName) -ErrorAction SilentlyContinue) -or
        (Test-Path -LiteralPath $ProgramFilesRoot) -or (Test-Path -LiteralPath $installPath) -or (Test-Path -LiteralPath $provisionPath)) {
        throw 'Standard uninstall left replaceable Windows Platform owners.'
    }
    Add-Stage -Name $currentStage -Status 'passed' -Message "Standard uninstall completed operationId=$($uninstall.operationId)."

    $currentStage = 'uninstall-data-preserved'
    Assert-OwnerDigests -Expected $ownerDigests
    $afterUninstallData = Get-Item -LiteralPath $dataPath -ErrorAction Stop
    if ($afterUninstallData.CreationTimeUtc.ToString('o') -ne $dataCreationTime) { throw 'Runtime data VHDX identity changed during standard uninstall.' }
    Add-Stage -Name $currentStage -Status 'passed' -Message 'Mutable Host owners and the existing Runtime data VHDX identity survived standard uninstall.'

    $currentStage = 'offline-reinstall'
    & (Join-Path $bundleRoot 'packaging\install-windows.ps1') -BundleDirectory $bundleRoot -ProgramFilesRoot $ProgramFilesRoot -ProgramDataRoot $ProgramDataRoot
    Wait-Platform
    $afterInstall = Read-InstallOwner -Path $installPath
    if ($afterInstall.platformVersion -ne $beforeInstall.platformVersion -or
        $afterInstall.runtimeBundleVersion -ne $beforeInstall.runtimeBundleVersion) {
        throw 'Reinstall owner identity differs from the original sealed release.'
    }
    if ($afterInstall.installedAcceptanceRunId -eq $beforeInstall.installedAcceptanceRunId) {
        throw 'Reinstall did not publish a new host-local installed acceptance identity.'
    }
    $afterInstalledAcceptanceRunId = [string]$afterInstall.installedAcceptanceRunId
    if ((Get-FileHash -LiteralPath (Join-Path ([string]$afterInstall.releasePath) 'release.json') -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath $bundleReleasePath -Algorithm SHA256).Hash) {
        throw 'Reinstalled immutable release bytes differ from the sealed bundle.'
    }
    Add-Stage -Name $currentStage -Status 'passed' -Message "Sealed offline reinstall completed acceptanceRunId=$($afterInstall.installedAcceptanceRunId)."

    $currentStage = 'reinstall-data-preserved'
    Assert-OwnerDigests -Expected $ownerDigests
    $afterProvision = Read-JSONOwner -Path $provisionPath -Label 'Reinstalled Hyper-V provision'
    if ([IO.Path]::GetFullPath([string]$afterProvision.runtimeDataVHDXPath) -ne $dataPath -or
        $afterProvision.runtimeDataVHDXProvisioningState -ne 'preserved-existing' -or
        (Get-Item -LiteralPath $dataPath -ErrorAction Stop).CreationTimeUtc.ToString('o') -ne $dataCreationTime) {
        throw 'Reinstall did not explicitly reuse the preserved Runtime data VHDX.'
    }
    Require-SettingsMarker -Marker $marker -Transition 'standard uninstall and reinstall'
    Add-Stage -Name $currentStage -Status 'passed' -Message 'Runtime marker, mutable Host owners, and preserved-existing data VHDX identity survived reinstall.'
} catch {
    $failureReason = $_.Exception.Message
    Add-Stage -Name $currentStage -Status 'failed' -Message $failureReason
} finally {
    if ($settingsMarkerApplied -and $originalSettingsJSON) {
        try { Apply-SettingsDocument -SettingsJSON $originalSettingsJSON } catch { $settingsRestoreError = $_.Exception.Message }
    }
}

if ($failureReason -or $settingsRestoreError) {
    $reason = if ($failureReason) { $failureReason } else { "Original Runtime settings restoration failed: $settingsRestoreError" }
    Write-Proof -Status 'failed' -FailureStage $currentStage -FailureReason $reason -SettingsRestoreError $settingsRestoreError
    throw "VitalServer Windows uninstall/reinstall acceptance failed runId=$runID stage=$currentStage reason=$reason manifest=$OutputManifestPath"
}
Add-Stage -Name 'runtime-settings-restored' -Status 'passed' -Message 'Original Runtime settings were restored after data-preservation proof.'
Write-Proof -Status 'passed' -FailureStage '' -FailureReason '' -SettingsRestoreError ''
Write-Output "VitalServer Windows uninstall/reinstall acceptance passed runId=$runID manifest=$OutputManifestPath"
