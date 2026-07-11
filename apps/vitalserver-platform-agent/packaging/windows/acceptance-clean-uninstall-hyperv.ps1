param(
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
$platformVersion = $null
$runtimeBundleVersion = $null
$installedAcceptanceRunId = $null
$releaseManifestSHA256 = $null

function Add-Stage {
    param([string]$Name, [string]$Status, [string]$Message)
    $stages.Add([ordered]@{ name = $Name; status = $Status; message = $Message; observedAt = [DateTime]::UtcNow.ToString('o') })
}

function Write-Acceptance {
    param([string]$Status, [string]$FailureStage, [string]$FailureReason, [string]$UninstallOperationId)
    $document = [ordered]@{
        schemaVersion = 1
        kind = 'clean-uninstall'
        runId = $runID
        platform = 'windows-hyperv-amd64'
        status = $Status
        uninstallOperationId = if ($UninstallOperationId) { $UninstallOperationId } else { $null }
        startedAt = $startedAt.ToString('o')
        completedAt = [DateTime]::UtcNow.ToString('o')
        stages = $stages
        failureStage = if ($FailureStage) { $FailureStage } else { $null }
        failureReason = if ($FailureReason) { $FailureReason } else { $null }
        platformVersion = $platformVersion
        runtimeBundleVersion = $runtimeBundleVersion
        installedAcceptanceRunId = $installedAcceptanceRunId
        releaseManifestSHA256 = $releaseManifestSHA256
    }
    $directory = Split-Path -Parent $OutputManifestPath
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporary = "$OutputManifestPath.tmp.$PID"
    [IO.File]::WriteAllText($temporary, ($document | ConvertTo-Json -Depth 10) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $OutputManifestPath -Force
}

function Read-JSONOwner {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label owner is missing path=$Path" }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { throw "$Label owner decode failed path=$Path reason=$($_.Exception.Message)" }
}

function Wait-CleanProof {
    param([string]$Path, [string]$OperationId)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $lastRead = 'not read'
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $proof = Read-JSONOwner -Path $Path -Label 'Windows clean uninstall proof'
            if ($proof.state -eq 'failed') {
                $message = if ($null -ne $proof.failure -and $proof.failure.message) { [string]$proof.failure.message } else { 'failure reason not reported' }
                throw "Windows clean uninstall workflow failed operationId=$OperationId reason=$message"
            }
            if ($proof.schemaVersion -ne 1 -or $proof.operationId -ne $OperationId -or $proof.mode -ne 'clean' -or
                $proof.state -ne 'completed' -or $proof.runtimeDataPreserved -ne $false -or $proof.postconditionsPassed -ne $true) {
                throw "Windows clean uninstall proof contract is invalid path=$Path"
            }
            return $proof
        } catch {
            $lastRead = $_.Exception.Message
            if ($lastRead -like 'Windows clean uninstall workflow failed*') { throw }
        }
        Start-Sleep -Seconds 1
    }
    throw "Windows clean uninstall proof did not appear operationId=$OperationId lastRead=$lastRead"
}

$uninstallOperationID = $null
$failureReason = $null
try {
    $output = [IO.Path]::GetFullPath($OutputManifestPath)
    $managedRoot = [IO.Path]::GetFullPath($ProgramDataRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ($output.StartsWith($managedRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Clean uninstall acceptance output must be outside managed ProgramData.'
    }
    $install = Read-JSONOwner -Path (Join-Path $ProgramDataRoot 'install.json') -Label 'Windows install'
    $provision = Read-JSONOwner -Path (Join-Path $ProgramDataRoot 'hyperv-provision.json') -Label 'Hyper-V provision'
    if ($install.schemaVersion -ne 1 -or $install.state -ne 'installed' -or -not $install.installedAcceptanceRunId -or
        $provision.schemaVersion -ne 1 -or $provision.state -ne 'provisioned') {
        throw 'Windows install/provision owner contracts are invalid.'
    }
    $platformVersion = [string]$install.platformVersion
    $runtimeBundleVersion = [string]$install.runtimeBundleVersion
    $installedAcceptanceRunId = [string]$install.installedAcceptanceRunId
    $installedReleaseManifestPath = Join-Path ([string]$install.releasePath) 'release.json'
    $installedRelease = Read-JSONOwner -Path $installedReleaseManifestPath -Label 'Installed sealed release'
    if ($installedRelease.state -ne 'releaseCandidate' -or $installedRelease.platformVersion -ne $platformVersion -or
        $installedRelease.runtimeBundleVersion -ne $runtimeBundleVersion) {
        throw 'Windows clean uninstall acceptance requires an installed sealed releaseCandidate.'
    }
    $releaseManifestSHA256 = (Get-FileHash -LiteralPath $installedReleaseManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $tokenPath = Join-Path $ProgramDataRoot 'secrets\platform-api-token'
    $token = (Get-Content -LiteralPath $tokenPath -Raw).Trim()
    if (-not $token) { throw "Platform API token owner is empty path=$tokenPath" }
    $headers = @{ Authorization = "Bearer $token" }
    $capabilities = Invoke-RestMethod -Method Get -Uri "$BaseURL/platform/capabilities" -Headers $headers -TimeoutSec 30
    if ($capabilities.canUninstallRuntime -ne $true) { throw 'Platform Agent does not explicitly support uninstall.' }
    Add-Stage -Name 'preflight' -Status 'passed' -Message 'Installed acceptance, Hyper-V resource identities, clean output boundary, and uninstall capability are explicit.'

    $currentStage = 'clean-uninstall-accepted'
    $operation = Invoke-RestMethod -Method Post -Uri "$BaseURL/platform/uninstall" -Headers $headers -ContentType 'application/json' -Body '{"mode":"clean"}' -TimeoutSec 60
    if ($operation.kind -ne 'uninstall' -or $operation.state -ne 'accepted' -or -not $operation.operationId) {
        throw "Clean uninstall was not accepted response=$operation"
    }
    $uninstallOperationID = [string]$operation.operationId
    Add-Stage -Name $currentStage -Status 'passed' -Message "Clean uninstall accepted operationId=$uninstallOperationID."

    $currentStage = 'clean-uninstall-completed'
    $proofPath = Join-Path (Join-Path $env:ProgramData 'VitalServer-UninstallProof') ("windows-uninstall-$uninstallOperationID.json")
    Wait-CleanProof -Path $proofPath -OperationId $uninstallOperationID | Out-Null
    $remainingPaths = @($ProgramFilesRoot, $ProgramDataRoot, [string]$provision.systemVHDXPath, [string]$provision.runtimeDataVHDXPath, [string]$provision.seedISOPath) |
        Where-Object { Test-Path -LiteralPath $_ }
    $remainingServices = @('VitalServerHyperVRuntime', 'VitalServerPlatformAgent') |
        Where-Object { $null -ne (Get-Service -Name $_ -ErrorAction SilentlyContinue) }
    if ($remainingPaths.Count -gt 0 -or $remainingServices.Count -gt 0 -or
        $null -ne (Get-VM -Name ([string]$provision.vmName) -ErrorAction SilentlyContinue) -or
        $null -ne (Get-NetNat -Name ([string]$provision.natName) -ErrorAction SilentlyContinue) -or
        $null -ne (Get-VMSwitch -Name ([string]$provision.switchName) -ErrorAction SilentlyContinue)) {
        throw "Clean uninstall acceptance found managed residue paths=$($remainingPaths -join ',') services=$($remainingServices -join ',')"
    }
    Add-Stage -Name $currentStage -Status 'passed' -Message "External uninstall proof and independent residual-resource checks passed operationId=$uninstallOperationID."
} catch {
    $failureReason = $_.Exception.Message
    Add-Stage -Name $currentStage -Status 'failed' -Message $failureReason
}

if ($failureReason) {
    Write-Acceptance -Status 'failed' -FailureStage $currentStage -FailureReason $failureReason -UninstallOperationId $uninstallOperationID
    throw "VitalServer Windows clean uninstall acceptance failed runId=$runID stage=$currentStage reason=$failureReason manifest=$OutputManifestPath"
}
Write-Acceptance -Status 'passed' -FailureStage '' -FailureReason '' -UninstallOperationId $uninstallOperationID
Write-Output "VitalServer Windows clean uninstall acceptance passed runId=$runID operationId=$uninstallOperationID manifest=$OutputManifestPath"
