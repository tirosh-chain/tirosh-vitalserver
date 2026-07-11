param(
    [Parameter(Mandatory = $true)][string]$APITokenPath,
    [Parameter(Mandatory = $true)][string]$InstallDocumentPath,
    [Parameter(Mandatory = $true)][string]$UpdateBundlePath,
    [Parameter(Mandatory = $true)][string]$ExpectedUpdatePlatformVersion,
    [Parameter(Mandatory = $true)][string]$ExpectedUpdateRuntimeBundleVersion,
    [Parameter(Mandatory = $true)][string]$OutputManifestPath,
    [string]$BaseURL = 'http://127.0.0.1:18321',
    [int]$TimeoutSeconds = 1200
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$runID = [Guid]::NewGuid().ToString()
$startedAt = [DateTime]::UtcNow
$stages = [Collections.Generic.List[object]]::new()
$currentStage = 'preflight'
$originalSettingsJSON = $null
$settingsMarkerApplied = $false
$headers = $null
$originalPlatformVersion = $null
$originalRuntimeBundleVersion = $null
$updatePlatformVersion = $ExpectedUpdatePlatformVersion
$updateRuntimeBundleVersion = $ExpectedUpdateRuntimeBundleVersion
$beforeInstalledAcceptanceRunId = $null
$afterRollbackInstalledAcceptanceRunId = $null
$originalReleaseManifestSHA256 = $null
$updateBundleSHA256 = $null

function Add-Stage {
    param([string]$Name, [string]$Status, [string]$Message)
    $stages.Add([ordered]@{ name = $Name; status = $Status; message = $Message; observedAt = [DateTime]::UtcNow.ToString('o') })
}

function Write-Proof {
    param([string]$Status, [string]$FailureStage, [string]$FailureReason, [string]$SettingsRestoreError)
    $proof = [ordered]@{
        schemaVersion = 1
        runId = $runID
        platform = 'windows-hyperv-amd64'
        kind = 'update-rollback-data-preservation'
        status = $Status
        startedAt = $startedAt.ToString('o')
        completedAt = [DateTime]::UtcNow.ToString('o')
        stages = $stages
        failureStage = if ($FailureStage) { $FailureStage } else { $null }
        failureReason = if ($FailureReason) { $FailureReason } else { $null }
        settingsRestoreError = if ($SettingsRestoreError) { $SettingsRestoreError } else { $null }
        originalPlatformVersion = $originalPlatformVersion
        originalRuntimeBundleVersion = $originalRuntimeBundleVersion
        updatePlatformVersion = $updatePlatformVersion
        updateRuntimeBundleVersion = $updateRuntimeBundleVersion
        beforeInstalledAcceptanceRunId = $beforeInstalledAcceptanceRunId
        afterRollbackInstalledAcceptanceRunId = $afterRollbackInstalledAcceptanceRunId
        originalReleaseManifestSHA256 = $originalReleaseManifestSHA256
        updateBundleSHA256 = $updateBundleSHA256
    }
    $directory = Split-Path -Parent $OutputManifestPath
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporary = "$OutputManifestPath.tmp.$PID"
    $json = $proof | ConvertTo-Json -Depth 10
    [IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $OutputManifestPath -Force
}

function Read-InstallOwner {
    $owner = Get-Content -LiteralPath $InstallDocumentPath -Raw | ConvertFrom-Json
    if ($owner.schemaVersion -ne 1 -or $owner.state -ne 'installed' -or -not $owner.platformVersion -or -not $owner.runtimeBundleVersion -or -not $owner.installedAcceptanceRunId -or -not $owner.releasePath) {
        throw "Windows install owner contract is invalid path=$InstallDocumentPath"
    }
    return $owner
}

function Wait-PlatformWorkflow {
    param([string]$OperationId, [string]$Kind)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $lastRead = 'not read'
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $resource = Invoke-RestMethod -Method Get -Uri "$BaseURL/platform/workflows/current" -Headers $headers -TimeoutSec 30
            if ($resource.state -ne 'loaded' -or $null -eq $resource.operation) {
                $lastRead = "resourceState=$($resource.state) readError=$($resource.readError)"
            } elseif ($resource.operation.operationId -ne $OperationId) {
                throw "Platform workflow identity changed expected=$OperationId actual=$($resource.operation.operationId)"
            } elseif ($resource.operation.kind -ne $Kind) {
                throw "Platform workflow kind changed expected=$Kind actual=$($resource.operation.kind)"
            } elseif ($resource.operation.state -eq 'completed') {
                return $resource.operation
            } elseif ($resource.operation.state -eq 'failed') {
                throw "Platform workflow failed operationId=$OperationId failure=$($resource.operation.failure.message)"
            } else {
                $lastRead = "state=$($resource.operation.state)"
            }
        } catch {
            $lastRead = $_.Exception.Message
            if ($lastRead -match 'identity changed|kind changed|workflow failed') {
                throw
            }
        }
        Start-Sleep -Seconds 1
    }
    throw "Platform workflow did not complete operationId=$OperationId lastRead=$lastRead"
}

function Apply-SettingsDocument {
    param([string]$SettingsJSON)
    $body = '{"settings":' + $SettingsJSON + '}'
    $operation = Invoke-RestMethod -Method Put -Uri "$BaseURL/runtime/settings" -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 120
    if ($operation.state -notin @('accepted', 'running', 'completed')) {
        throw "Runtime settings apply failed state=$($operation.state) failure=$($operation.failure.message)"
    }
}

function Require-SettingsMarker {
    param([string]$Marker, [string]$Transition)
    $read = Invoke-RestMethod -Method Get -Uri "$BaseURL/runtime/settings" -Headers $headers -TimeoutSec 60
    if ($read.state -ne 'loaded' -or $null -eq $read.settings -or $read.settings.publicHost -ne $Marker) {
        throw "Runtime settings marker was not preserved after $Transition state=$($read.state) actual=$($read.settings.publicHost)"
    }
}

$settingsRestoreError = $null
$failureReason = $null
try {
    if (-not (Test-Path -LiteralPath $APITokenPath -PathType Leaf) -or -not (Test-Path -LiteralPath $UpdateBundlePath -PathType Leaf)) {
        throw 'Windows update acceptance inputs are missing.'
    }
    $apiToken = (Get-Content -LiteralPath $APITokenPath -Raw).Trim()
    if (-not $apiToken) { throw "Platform API token owner is empty path=$APITokenPath" }
    $headers = @{ Authorization = "Bearer $apiToken" }
    $before = Read-InstallOwner
    $originalPlatformVersion = [string]$before.platformVersion
    $originalRuntimeBundleVersion = [string]$before.runtimeBundleVersion
    $beforeInstalledAcceptanceRunId = [string]$before.installedAcceptanceRunId
    $originalReleaseManifestPath = Join-Path ([string]$before.releasePath) 'release.json'
    $originalReleaseManifestSHA256 = (Get-FileHash -LiteralPath $originalReleaseManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $updateBundleSHA256 = (Get-FileHash -LiteralPath $UpdateBundlePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $capabilities = Invoke-RestMethod -Method Get -Uri "$BaseURL/platform/capabilities" -Headers $headers -TimeoutSec 30
    if ($capabilities.canApplyBundle -ne $true -or $capabilities.canRollbackRelease -ne $true) {
        throw 'Platform Agent does not explicitly support trusted update apply and release rollback.'
    }
    Add-Stage -Name 'preflight' -Status 'passed' -Message 'Trusted update, owner-selected rollback, and Runtime settings owners are available.'

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

    $currentStage = 'update-accepted'
    $bundleBody = [ordered]@{ bundle = [ordered]@{ kind = 'localPath'; value = [IO.Path]::GetFullPath($UpdateBundlePath) } } | ConvertTo-Json -Compress
    $update = Invoke-RestMethod -Method Post -Uri "$BaseURL/platform/update-bundles/apply" -Headers $headers -ContentType 'application/json' -Body $bundleBody -TimeoutSec 60
    if ($update.kind -ne 'update-apply' -or $update.state -ne 'accepted') { throw "Update workflow was not accepted response=$update" }
    Add-Stage -Name $currentStage -Status 'passed' -Message "Update accepted operationId=$($update.operationId)."

    $currentStage = 'update-completed'
    $completedUpdate = Wait-PlatformWorkflow -OperationId $update.operationId -Kind 'update-apply'
    $afterUpdate = Read-InstallOwner
    if ($afterUpdate.platformVersion -ne $ExpectedUpdatePlatformVersion -or $afterUpdate.runtimeBundleVersion -ne $ExpectedUpdateRuntimeBundleVersion) {
        throw "Install owner did not advance to expected update expected=$ExpectedUpdatePlatformVersion/$ExpectedUpdateRuntimeBundleVersion actual=$($afterUpdate.platformVersion)/$($afterUpdate.runtimeBundleVersion)"
    }
    Add-Stage -Name $currentStage -Status 'passed' -Message "Update completed operationId=$($completedUpdate.operationId)."

    $currentStage = 'update-data-preserved'
    Require-SettingsMarker -Marker $marker -Transition 'update'
    Add-Stage -Name $currentStage -Status 'passed' -Message 'Runtime-owned mutable settings marker survived system VHDX replacement.'

    $currentStage = 'rollback-accepted'
    $rollback = Invoke-RestMethod -Method Post -Uri "$BaseURL/platform/releases/rollback" -Headers $headers -TimeoutSec 60
    if ($rollback.kind -ne 'rollback' -or $rollback.state -ne 'accepted') { throw "Rollback workflow was not accepted response=$rollback" }
    Add-Stage -Name $currentStage -Status 'passed' -Message "Rollback accepted operationId=$($rollback.operationId)."

    $currentStage = 'rollback-completed'
    $completedRollback = Wait-PlatformWorkflow -OperationId $rollback.operationId -Kind 'rollback'
    $afterRollback = Read-InstallOwner
    if ($afterRollback.platformVersion -ne $before.platformVersion -or $afterRollback.runtimeBundleVersion -ne $before.runtimeBundleVersion) {
        throw "Install owner did not return to original release expected=$($before.platformVersion)/$($before.runtimeBundleVersion) actual=$($afterRollback.platformVersion)/$($afterRollback.runtimeBundleVersion)"
    }
    $afterRollbackInstalledAcceptanceRunId = [string]$afterRollback.installedAcceptanceRunId
    $afterRollbackReleaseSHA256 = (Get-FileHash -LiteralPath (Join-Path ([string]$afterRollback.releasePath) 'release.json') -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($afterRollbackReleaseSHA256 -ne $originalReleaseManifestSHA256) {
        throw "Rollback immutable release identity changed expected=$originalReleaseManifestSHA256 actual=$afterRollbackReleaseSHA256"
    }
    Add-Stage -Name $currentStage -Status 'passed' -Message "Rollback completed operationId=$($completedRollback.operationId)."

    $currentStage = 'rollback-data-preserved'
    Require-SettingsMarker -Marker $marker -Transition 'rollback'
    Add-Stage -Name $currentStage -Status 'passed' -Message 'Runtime-owned mutable settings marker survived release rollback.'
} catch {
    $failureReason = $_.Exception.Message
    Add-Stage -Name $currentStage -Status 'failed' -Message $failureReason
} finally {
    if ($settingsMarkerApplied -and $originalSettingsJSON) {
        try {
            Apply-SettingsDocument -SettingsJSON $originalSettingsJSON
        } catch {
            $settingsRestoreError = $_.Exception.Message
        }
    }
}

if ($failureReason -or $settingsRestoreError) {
    $reason = if ($failureReason) { $failureReason } else { "Original Runtime settings restoration failed: $settingsRestoreError" }
    Write-Proof -Status 'failed' -FailureStage $currentStage -FailureReason $reason -SettingsRestoreError $settingsRestoreError
    throw "VitalServer Windows update/rollback acceptance failed runId=$runID stage=$currentStage reason=$reason manifest=$OutputManifestPath"
}
Add-Stage -Name 'runtime-settings-restored' -Status 'passed' -Message 'Original Runtime settings were restored after data-preservation proof.'
Write-Proof -Status 'passed' -FailureStage '' -FailureReason '' -SettingsRestoreError ''
Write-Output "VitalServer Windows update/rollback acceptance passed runId=$runID manifest=$OutputManifestPath"
