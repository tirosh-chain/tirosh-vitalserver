param(
    [Parameter(Mandatory = $true)][string]$OperationId,
    [Parameter(Mandatory = $true)][string]$OperationDocument,
    [string]$ProgramFilesRoot = (Join-Path $env:ProgramFiles 'VitalServer'),
    [string]$ProgramDataRoot = (Join-Path $env:ProgramData 'VitalServer')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Workflow {
    param([string]$State, [string]$StartedAt, [object]$Release, [object]$Failure)
    $document = [ordered]@{
        schemaVersion = 1
        operationId = $OperationId
        kind = 'rollback'
        state = $State
        startedAt = $StartedAt
        updatedAt = [DateTime]::UtcNow.ToString('o')
        release = $Release
        artifact = $null
        failure = $Failure
    }
    $temporary = "$OperationDocument.tmp.$PID"
    $json = $document | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $OperationDocument -Force
}

$startedAt = [DateTime]::UtcNow.ToString('o')
Write-Workflow -State 'running' -StartedAt $startedAt -Release $null -Failure $null
try {
    $installPath = Join-Path $ProgramDataRoot 'install.json'
    $install = Get-Content -LiteralPath $installPath -Raw | ConvertFrom-Json
    if ($install.schemaVersion -ne 1 -or $install.state -ne 'installed' -or -not $install.previousReleasePath) {
        throw "Windows install owner has no previous immutable release path=$installPath"
    }
    $previousRelease = [IO.Path]::GetFullPath([string]$install.previousReleasePath)
    $releaseRoot = [IO.Path]::GetFullPath((Join-Path $ProgramFilesRoot 'releases'))
    if (-not $previousRelease.StartsWith($releaseRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath (Join-Path $previousRelease 'release.json') -PathType Leaf)) {
        throw "Windows rollback target is outside the immutable release owner root path=$previousRelease"
    }
    $applyTool = Join-Path $previousRelease 'packaging\apply-update-windows.ps1'
    if (-not (Test-Path -LiteralPath $applyTool -PathType Leaf)) {
        throw "Windows rollback target has no apply transaction tool path=$applyTool"
    }
    & $applyTool `
        -BundleRoot $previousRelease `
        -OperationId $OperationId `
        -OperationDocument $OperationDocument `
        -ProgramFilesRoot $ProgramFilesRoot `
        -ProgramDataRoot $ProgramDataRoot
    $rolledBackInstall = Get-Content -LiteralPath $installPath -Raw | ConvertFrom-Json
    $release = [ordered]@{
        platformVersion = [string]$rolledBackInstall.platformVersion
        runtimeBundleVersion = [string]$rolledBackInstall.runtimeBundleVersion
    }
    Write-Workflow -State 'completed' -StartedAt $startedAt -Release $release -Failure $null
    exit 0
} catch {
    $reason = $_.Exception.Message
    Write-Workflow -State 'failed' -StartedAt $startedAt -Release $null -Failure ([ordered]@{
        kind = 'rollbackFailed'
        message = $reason
    })
    Write-Error $reason
    exit 1
}
