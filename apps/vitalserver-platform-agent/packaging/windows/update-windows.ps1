param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('summary', 'verify', 'apply')]
    [string]$Action,
    [Parameter(Mandatory = $true)]
    [string]$Bundle,
    [string]$OperationId,
    [string]$OperationDocument
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'windows-delivery.psm1') -Force

function Write-Workflow {
    param([string]$State, [string]$StartedAt, [object]$Release, [object]$Failure)
    if (-not $OperationId -or -not $OperationDocument) {
        return
    }
    $document = [ordered]@{
        schemaVersion = 1
        operationId = $OperationId
        kind = if ($Action -eq 'verify') { 'update-verify' } else { 'update-apply' }
        state = $State
        startedAt = $StartedAt
        updatedAt = [DateTime]::UtcNow.ToString('o')
        release = $Release
        artifact = $null
        failure = $Failure
    }
    $directory = Split-Path -Parent $OperationDocument
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporary = "$OperationDocument.tmp.$PID"
    $json = $document | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $OperationDocument -Force
}

if ($Action -ne 'summary' -and (-not $OperationId -or -not $OperationDocument)) {
    throw "$Action requires OperationId and OperationDocument"
}
$startedAt = [DateTime]::UtcNow.ToString('o')
if ($Action -ne 'summary') {
    Write-Workflow -State 'running' -StartedAt $startedAt -Release $null -Failure $null
}
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("vitalserver-windows-update-" + [Guid]::NewGuid().ToString('N'))
try {
    $bundleRoot = Expand-VitalServerWindowsBundle -ArchivePath $Bundle -OutputDirectory $temporaryRoot
    Assert-VitalServerWindowsBundle -BundleRoot $bundleRoot
    $release = Read-VitalServerWindowsRelease -BundleRoot $bundleRoot
    $workflowRelease = [ordered]@{
        platformVersion = [string]$release.platformVersion
        runtimeBundleVersion = [string]$release.runtimeBundleVersion
    }
    if ($Action -eq 'summary') {
        [ordered]@{
            summary = "VitalServer Windows $($release.platformVersion) / Runtime Bundle $($release.runtimeBundleVersion) / windows/amd64/hyperv"
            release = $workflowRelease
        } | ConvertTo-Json -Compress
        exit 0
    }
    if ($Action -eq 'apply') {
        $applyTool = Join-Path $bundleRoot 'packaging\apply-update-windows.ps1'
        if (-not (Test-Path -LiteralPath $applyTool -PathType Leaf)) {
            throw "Windows update apply tool is missing from verified bundle path=$applyTool"
        }
        & $applyTool -BundleRoot $bundleRoot -OperationId $OperationId -OperationDocument $OperationDocument
    }
    Write-Workflow -State 'completed' -StartedAt $startedAt -Release $workflowRelease -Failure $null
    [ordered]@{ state = 'completed'; release = $workflowRelease } | ConvertTo-Json -Compress
    exit 0
} catch {
    $reason = $_.Exception.Message
    if ($Action -ne 'summary') {
        Write-Workflow -State 'failed' -StartedAt $startedAt -Release $null -Failure ([ordered]@{
            kind = if ($Action -eq 'verify') { 'updateVerifyFailed' } else { 'updateApplyFailed' }
            message = $reason
        })
    }
    [ordered]@{ state = 'failed'; failure = [ordered]@{ kind = 'updateBundleInvalid'; message = $reason } } | ConvertTo-Json -Compress
    exit 1
} finally {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
}
