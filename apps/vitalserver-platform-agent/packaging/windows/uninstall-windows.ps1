param(
    [Parameter(Mandatory = $true)][ValidateSet('standard', 'clean')][string]$Mode,
    [Parameter(Mandatory = $true)][string]$OperationId,
    [Parameter(Mandatory = $true)][string]$OperationDocument,
    [string]$ProgramFilesRoot = (Join-Path $env:ProgramFiles 'VitalServer'),
    [string]$ProgramDataRoot = (Join-Path $env:ProgramData 'VitalServer')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Workflow {
    param([string]$State, [string]$StartedAt, [object]$Failure)
    $document = [ordered]@{
        schemaVersion = 1
        operationId = $OperationId
        kind = 'uninstall'
        state = $State
        startedAt = $StartedAt
        updatedAt = [DateTime]::UtcNow.ToString('o')
        release = $null
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

function Stop-ServiceAndWait {
    param([string]$Name)
    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($null -ne $service -and $service.Status -ne [ServiceProcess.ServiceControllerStatus]::Stopped) {
        Stop-Service -Name $Name -ErrorAction Stop
        $service.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromMinutes(5))
    }
}

function Remove-ServiceOwner {
    param([string]$Name)
    if ($null -ne (Get-Service -Name $Name -ErrorAction SilentlyContinue)) {
        & sc.exe delete $Name | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Windows Service removal failed service=$Name exitCode=$LASTEXITCODE"
        }
    }
}

function Write-UninstallProof {
    param([string]$Path, [object]$Document)
    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporary = "$Path.tmp.$PID"
    [IO.File]::WriteAllText($temporary, ($Document | ConvertTo-Json -Depth 5) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

$startedAt = [DateTime]::UtcNow.ToString('o')
Write-Workflow -State 'running' -StartedAt $startedAt -Failure $null
try {
    $installPath = Join-Path $ProgramDataRoot 'install.json'
    $providerConfigPath = Join-Path $ProgramDataRoot 'config\hyperv-runtime-provider.json'
    $provisionPath = Join-Path $ProgramDataRoot 'hyperv-provision.json'
    foreach ($required in @($installPath, $providerConfigPath, $provisionPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Windows uninstall owner is missing path=$required"
        }
    }
    $install = Get-Content -LiteralPath $installPath -Raw | ConvertFrom-Json
    $providerConfig = Get-Content -LiteralPath $providerConfigPath -Raw | ConvertFrom-Json
    $provision = Get-Content -LiteralPath $provisionPath -Raw | ConvertFrom-Json
    if ($install.schemaVersion -ne 1 -or $install.state -ne 'installed' -or $provision.schemaVersion -ne 1 -or $provision.state -ne 'provisioned') {
        throw 'Windows uninstall owner contracts are invalid.'
    }
    $vm = Get-VM -Name ([string]$providerConfig.vmName) -ErrorAction Stop
    if ($vm.Id.ToString() -ne [string]$provision.vmID) {
        throw "Windows uninstall refuses VM with different owner identity expected=$($provision.vmID) actual=$($vm.Id)"
    }
    $expectedDisks = @([IO.Path]::GetFullPath([string]$provision.systemVHDXPath), [IO.Path]::GetFullPath([string]$provision.runtimeDataVHDXPath)) | Sort-Object
    $actualDisks = @(Get-VMHardDiskDrive -VM $vm | ForEach-Object { [IO.Path]::GetFullPath($_.Path) }) | Sort-Object
    $actualSeed = @(Get-VMDvdDrive -VM $vm | ForEach-Object { [IO.Path]::GetFullPath($_.Path) })
    if ($actualDisks.Count -ne 2 -or (Compare-Object -ReferenceObject $expectedDisks -DifferenceObject $actualDisks) -or
        $actualSeed.Count -ne 1 -or $actualSeed[0] -ne [IO.Path]::GetFullPath([string]$provision.seedISOPath)) {
        throw 'Windows uninstall refuses Hyper-V VM whose disk owners differ from provision state.'
    }
    $nat = Get-NetNat -Name ([string]$provision.natName) -ErrorAction SilentlyContinue
    if ($null -ne $nat -and $nat.InternalIPInterfaceAddressPrefix -ne $provision.subnetPrefix) {
        throw 'Windows uninstall refuses NAT with different owner prefix.'
    }
    $switch = Get-VMSwitch -Name ([string]$provision.switchName) -ErrorAction SilentlyContinue
    if ($null -ne $switch -and $switch.SwitchType -ne [Microsoft.HyperV.PowerShell.VMSwitchType]::Internal) {
        throw 'Windows uninstall refuses virtual switch with different owner type.'
    }

    Stop-ServiceAndWait -Name 'VitalServerHyperVRuntime'
    Stop-ServiceAndWait -Name 'VitalServerPlatformAgent'
    $vm = Get-VM -Name ([string]$providerConfig.vmName) -ErrorAction Stop
    if ([string]$vm.State -ne 'Off') {
        throw "Windows uninstall Runtime VM is not off state=$($vm.State)"
    }
    Remove-VM -VM $vm -Force
    Remove-ServiceOwner -Name 'VitalServerHyperVRuntime'
    Remove-ServiceOwner -Name 'VitalServerPlatformAgent'

    if ($null -ne $nat) {
        Remove-NetNat -Name $nat.Name -Confirm:$false
    }
    if ($null -ne $switch) {
        $remainingAdapters = @(Get-VMNetworkAdapter -All | Where-Object { $_.SwitchName -eq $switch.Name })
        if ($remainingAdapters.Count -gt 0) {
            throw "Windows uninstall cannot remove managed switch still used by another VM switch=$($switch.Name)"
        }
        Remove-VMSwitch -Name $switch.Name -Force
    }

    Remove-Item -LiteralPath ([string]$provision.systemVHDXPath) -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath ([string]$provision.seedISOPath) -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $ProgramFilesRoot -Recurse -Force -ErrorAction SilentlyContinue

    if ($Mode -eq 'standard') {
        Remove-Item -LiteralPath $installPath, $provisionPath -Force -ErrorAction SilentlyContinue
        Get-ChildItem -LiteralPath (Join-Path $ProgramDataRoot 'run') -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -ne [IO.Path]::GetFullPath($OperationDocument) } |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Workflow -State 'completed' -StartedAt $startedAt -Failure $null
    } else {
        Write-Workflow -State 'completed' -StartedAt $startedAt -Failure $null
        Remove-Item -LiteralPath $ProgramDataRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    $remainingReplaceable = @(
        $ProgramFilesRoot,
        [string]$provision.systemVHDXPath,
        [string]$provision.seedISOPath
    ) | Where-Object { Test-Path -LiteralPath $_ }
    $remainingServices = @('VitalServerHyperVRuntime', 'VitalServerPlatformAgent') |
        Where-Object { $null -ne (Get-Service -Name $_ -ErrorAction SilentlyContinue) }
    if ($remainingReplaceable.Count -gt 0 -or $remainingServices.Count -gt 0 -or
        $null -ne (Get-VM -Name ([string]$providerConfig.vmName) -ErrorAction SilentlyContinue) -or
        $null -ne (Get-NetNat -Name ([string]$provision.natName) -ErrorAction SilentlyContinue) -or
        $null -ne (Get-VMSwitch -Name ([string]$provision.switchName) -ErrorAction SilentlyContinue)) {
        throw "Windows uninstall postcondition failed mode=$Mode remainingPaths=$($remainingReplaceable -join ',') remainingServices=$($remainingServices -join ',')"
    }
    if ($Mode -eq 'standard') {
        if (-not (Test-Path -LiteralPath ([string]$provision.runtimeDataVHDXPath) -PathType Leaf) -or
            -not (Test-Path -LiteralPath $providerConfigPath -PathType Leaf) -or
            -not (Test-Path -LiteralPath (Join-Path $ProgramDataRoot 'secrets\platform-api-token') -PathType Leaf)) {
            throw 'Windows standard uninstall did not preserve its explicit Runtime data/config/token owners.'
        }
    } elseif ((Test-Path -LiteralPath $ProgramDataRoot) -or (Test-Path -LiteralPath ([string]$provision.runtimeDataVHDXPath))) {
        throw 'Windows clean uninstall left managed ProgramData or Runtime data VHDX state.'
    }

    $proofRoot = if ($Mode -eq 'clean') { Join-Path $env:ProgramData 'VitalServer-UninstallProof' } else { Join-Path $ProgramDataRoot 'proof' }
    $proofPath = Join-Path $proofRoot ("windows-uninstall-$OperationId.json")
    $proof = [ordered]@{
        schemaVersion = 1
        operationId = $OperationId
        mode = $Mode
        state = 'completed'
        removedAt = [DateTime]::UtcNow.ToString('o')
        runtimeDataPreserved = ($Mode -eq 'standard')
        runtimeDataVHDXPath = if ($Mode -eq 'standard') { [string]$provision.runtimeDataVHDXPath } else { $null }
        postconditionsPassed = $true
    }
    Write-UninstallProof -Path $proofPath -Document $proof
    Write-Output "VitalServer Windows uninstall completed mode=$Mode proof=$proofPath"
    exit 0
} catch {
    $reason = $_.Exception.Message
    try {
        Write-Workflow -State 'failed' -StartedAt $startedAt -Failure ([ordered]@{ kind = 'uninstallFailed'; message = $reason })
    } catch {
        Write-Warning "Windows uninstall failure owner write failed reason=$($_.Exception.Message)"
    }
    Write-Error $reason
    exit 1
}
