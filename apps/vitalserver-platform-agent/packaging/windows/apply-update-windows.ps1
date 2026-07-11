param(
    [Parameter(Mandatory = $true)][string]$BundleRoot,
    [Parameter(Mandatory = $true)][string]$OperationId,
    [Parameter(Mandatory = $true)][string]$OperationDocument,
    [string]$ProgramFilesRoot = (Join-Path $env:ProgramFiles 'VitalServer'),
    [string]$ProgramDataRoot = (Join-Path $env:ProgramData 'VitalServer')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'VitalServer Windows update requires an elevated workflow task.'
}

function Write-BytesAtomic {
    param([string]$Path, [byte[]]$Bytes)
    $temporary = "$Path.tmp.$PID"
    [IO.File]::WriteAllBytes($temporary, $Bytes)
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Write-JSONNoBOM {
    param([string]$Path, [object]$Document, [int]$Depth = 8)
    $json = $Document | ConvertTo-Json -Depth $Depth
    Write-BytesAtomic -Path $Path -Bytes ([Text.UTF8Encoding]::new($false).GetBytes($json + [Environment]::NewLine))
}

function Protect-OwnerFile {
    param([string]$Path)
    & icacls.exe $Path /inheritance:r /grant:r '*S-1-5-18:(F)' '*S-1-5-32-544:(F)' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Windows owner file ACL hardening failed path=$Path exitCode=$LASTEXITCODE"
    }
}

function Install-VerifiedArtifact {
    param([string]$Source, [string]$Destination, [string]$ExpectedSHA256, [string]$Label)
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Windows update artifact is missing label=$Label path=$Source"
    }
    $actualSource = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualSource -ne $ExpectedSHA256) {
        throw "Windows update source checksum differs label=$Label expected=$ExpectedSHA256 actual=$actualSource"
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        $actualDestination = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualDestination -ne $ExpectedSHA256) {
            throw "Immutable Windows update artifact already differs label=$Label path=$Destination"
        }
        return
    }
    Copy-Item -LiteralPath $Source -Destination $Destination
    $actualDestination = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualDestination -ne $ExpectedSHA256) {
        Remove-Item -LiteralPath $Destination -Force
        throw "Windows update artifact copy checksum differs label=$Label expected=$ExpectedSHA256 actual=$actualDestination"
    }
}

function Stop-ServiceAndWait {
    param([string]$Name)
    $service = Get-Service -Name $Name -ErrorAction Stop
    if ($service.Status -ne [ServiceProcess.ServiceControllerStatus]::Stopped) {
        Stop-Service -Name $Name -ErrorAction Stop
        $service.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromMinutes(5))
    }
}

function Configure-ServiceBinary {
    param([string]$Name, [string]$BinaryPath)
    $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'"
    if ($null -eq $service) {
        throw "Windows Service owner is unavailable service=$Name"
    }
    $change = Invoke-CimMethod -InputObject $service -MethodName Change -Arguments @{
        PathName = $BinaryPath
        StartMode = 'Automatic'
    }
    if ($change.ReturnValue -ne 0) {
        throw "Windows Service binary configuration failed service=$Name returnValue=$($change.ReturnValue)"
    }
}

$installPath = Join-Path $ProgramDataRoot 'install.json'
$configPath = Join-Path $ProgramDataRoot 'config\platform-agent.json'
$providerConfigPath = Join-Path $ProgramDataRoot 'config\hyperv-runtime-provider.json'
$provisionPath = Join-Path $ProgramDataRoot 'hyperv-provision.json'
$tokenPath = Join-Path $ProgramDataRoot 'secrets\platform-api-token'
foreach ($required in @($installPath, $configPath, $providerConfigPath, $provisionPath, $tokenPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Windows update owner is missing path=$required"
    }
}
try {
    $install = Get-Content -LiteralPath $installPath -Raw | ConvertFrom-Json
    $platformConfig = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $providerConfig = Get-Content -LiteralPath $providerConfigPath -Raw | ConvertFrom-Json
    $provision = Get-Content -LiteralPath $provisionPath -Raw | ConvertFrom-Json
    $release = Get-Content -LiteralPath (Join-Path $BundleRoot 'release.json') -Raw | ConvertFrom-Json
    $image = Get-Content -LiteralPath (Join-Path $BundleRoot 'hyperv-image\hyperv-image.json') -Raw | ConvertFrom-Json
} catch {
    throw "Windows update owner decode failed: $($_.Exception.Message)"
}
if ($install.schemaVersion -ne 1 -or $install.state -ne 'installed' -or -not $install.releasePath -or -not $install.systemVHDXPath -or -not $install.seedISOPath) {
    throw "Windows install owner lacks immutable release rollback fields path=$installPath"
}
$targetVersion = [string]$release.platformVersion
if ($targetVersion -notmatch '^[A-Za-z0-9._+-]+$' -or $targetVersion -eq [string]$install.platformVersion) {
    throw "Windows update target version is invalid or already installed target=$targetVersion current=$($install.platformVersion)"
}
if ($release.target.os -ne 'windows' -or $release.target.architecture -ne 'amd64' -or $release.target.provider -ne 'hyperv') {
    throw 'Windows update target release is not windows/amd64/hyperv.'
}
if ($image.schemaVersion -ne 1 -or $image.state -ne 'compiled' -or $image.architecture -ne 'amd64' -or $image.guestAddress -ne $providerConfig.runtimeEndpointAddress) {
    throw "Windows update Hyper-V image owner differs from Provider target guestAddress=$($providerConfig.runtimeEndpointAddress)"
}
foreach ($artifact in @($image.systemVHDX, $image.seedISO)) {
    if ([string]$artifact.path -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or [string]$artifact.sha256 -notmatch '^[0-9a-f]{64}$') {
        throw 'Windows update Hyper-V image artifact contract is invalid.'
    }
}

$oldReleasePath = [IO.Path]::GetFullPath([string]$install.releasePath)
$newReleasePath = Join-Path (Join-Path $ProgramFilesRoot 'releases') $targetVersion
$stagePath = "$newReleasePath.installing.$PID"
if (Test-Path -LiteralPath $newReleasePath) {
    if ((Get-FileHash -LiteralPath (Join-Path $newReleasePath 'release.json') -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath (Join-Path $BundleRoot 'release.json') -Algorithm SHA256).Hash) {
        throw "Immutable Windows update release already exists with different identity path=$newReleasePath"
    }
} else {
    Remove-Item -LiteralPath $stagePath -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $stagePath -Force | Out-Null
    foreach ($name in @('bin', 'pwa', 'packaging', 'hyperv-image', 'proof', 'config')) {
        Copy-Item -LiteralPath (Join-Path $BundleRoot $name) -Destination (Join-Path $stagePath $name) -Recurse
    }
    Copy-Item -LiteralPath (Join-Path $BundleRoot 'release.json') -Destination (Join-Path $stagePath 'release.json')
    Move-Item -LiteralPath $stagePath -Destination $newReleasePath
}

$imageRoot = Join-Path $newReleasePath 'hyperv-image'
$systemSource = Join-Path $imageRoot ([string]$image.systemVHDX.path)
$seedSource = Join-Path $imageRoot ([string]$image.seedISO.path)
$vmReleaseRoot = Join-Path (Join-Path $ProgramDataRoot 'vm\releases') $targetVersion
$newSystemPath = Join-Path $vmReleaseRoot 'vitalserver-system.vhdx'
$newSeedPath = Join-Path $vmReleaseRoot 'vitalserver-seed.iso'
Install-VerifiedArtifact -Source $systemSource -Destination $newSystemPath -ExpectedSHA256 ([string]$image.systemVHDX.sha256) -Label 'system VHDX'
Install-VerifiedArtifact -Source $seedSource -Destination $newSeedPath -ExpectedSHA256 ([string]$image.seedISO.sha256) -Label 'seed ISO'

$oldConfigBytes = [IO.File]::ReadAllBytes($configPath)
$oldProvisionBytes = [IO.File]::ReadAllBytes($provisionPath)
$oldInstallBytes = [IO.File]::ReadAllBytes($installPath)
$oldSystemPath = [IO.Path]::GetFullPath([string]$install.systemVHDXPath)
$oldSeedPath = [IO.Path]::GetFullPath([string]$install.seedISOPath)
$vmName = [string]$providerConfig.vmName
$providerService = 'VitalServerHyperVRuntime'
$agentService = 'VitalServerPlatformAgent'
$changedSystemDisk = $false
$changedSeedISO = $false

try {
    Stop-ServiceAndWait -Name $providerService
    Stop-ServiceAndWait -Name $agentService
    $vm = Get-VM -Name $vmName -ErrorAction Stop
    if ([string]$vm.State -ne 'Off') {
        throw "Hyper-V VM is not off after Runtime Provider stop vm=$vmName state=$($vm.State)"
    }
    $systemDrive = Get-VMHardDiskDrive -VM $vm | Where-Object { [IO.Path]::GetFullPath($_.Path) -eq $oldSystemPath }
    $dvd = Get-VMDvdDrive -VM $vm | Where-Object { [IO.Path]::GetFullPath($_.Path) -eq $oldSeedPath }
    if (@($systemDrive).Count -ne 1 -or @($dvd).Count -ne 1) {
        throw "Hyper-V VM does not match install owner systemDisk=$oldSystemPath seedISO=$oldSeedPath"
    }
    Set-VMHardDiskDrive -VMHardDiskDrive $systemDrive -Path $newSystemPath
    $changedSystemDisk = $true
    Set-VMDvdDrive -VMDvdDrive $dvd -Path $newSeedPath
    $changedSeedISO = $true

    $platformConfig.runtimeExecutable = Join-Path $newReleasePath 'bin\vitalserver-hyperv-runtime-provider.exe'
    $platformConfig.pwaDirectory = Join-Path $newReleasePath 'pwa'
    if ($null -ne $platformConfig.delivery) {
        $platformConfig.delivery.updateTool = Join-Path $newReleasePath 'packaging\update-windows.ps1'
        $platformConfig.delivery.rollbackTool = Join-Path $newReleasePath 'packaging\rollback-windows.ps1'
        $platformConfig.delivery.uninstallTool = Join-Path $newReleasePath 'packaging\uninstall-windows.ps1'
        $supportExportTool = Join-Path $newReleasePath 'packaging\support-export-windows.ps1'
        if ($platformConfig.delivery.PSObject.Properties.Name -contains 'supportExportTool') {
            $platformConfig.delivery.supportExportTool = $supportExportTool
        } else {
            $platformConfig.delivery | Add-Member -NotePropertyName supportExportTool -NotePropertyValue $supportExportTool
        }
        $platformConfig.delivery.schedulerScript = Join-Path $newReleasePath 'packaging\schedule-workflow-windows.ps1'
    }
    Write-JSONNoBOM -Path $configPath -Document $platformConfig
    Protect-OwnerFile -Path $configPath

    $provision.systemVHDXPath = $newSystemPath
    $provision.systemVHDXSHA256 = [string]$image.systemVHDX.sha256
    $provision.seedISOPath = $newSeedPath
    $provision.seedISOSHA256 = [string]$image.seedISO.sha256
    $provision.provisionedAt = [DateTime]::UtcNow.ToString('o')
    Write-JSONNoBOM -Path $provisionPath -Document $provision

    $serviceInstaller = Join-Path $newReleasePath 'packaging\install-service.ps1'
    & $serviceInstaller `
        -InstallDirectory (Join-Path $newReleasePath 'bin') `
        -ConfigPath $configPath `
        -HyperVConfigPath $providerConfigPath `
        -ProvisionStatePath $provisionPath `
        -PlatformVersion $targetVersion `
        -RuntimeBundleVersion ([string]$release.runtimeBundleVersion) `
        -ReleaseManifestPath (Join-Path $newReleasePath 'release.json') `
        -ReleasePath $newReleasePath `
        -SystemVHDXPath $newSystemPath `
        -SeedISOPath $newSeedPath `
        -PreviousReleasePath $oldReleasePath `
        -PreviousSystemVHDXPath $oldSystemPath `
        -PreviousSeedISOPath $oldSeedPath `
        -APITokenPath $tokenPath `
        -RuntimeProviderDocumentPath (Join-Path $ProgramDataRoot 'run\runtime-provider.json') `
        -HyperVImageManifestPath (Join-Path $newReleasePath 'hyperv-image\hyperv-image.json') `
        -AcceptanceManifestPath (Join-Path $ProgramDataRoot 'proof\windows-hyperv-update-acceptance.json') `
        -InstallDocumentPath $installPath `
        -SupportExportMode 'capability-only'
    return
} catch {
    $applyReason = $_.Exception.Message
    $restoreErrors = [Collections.Generic.List[string]]::new()
    try { Stop-ServiceAndWait -Name $providerService } catch { $restoreErrors.Add($_.Exception.Message) }
    try { Stop-ServiceAndWait -Name $agentService } catch { $restoreErrors.Add($_.Exception.Message) }
    if ($changedSystemDisk -or $changedSeedISO) {
        try {
            $vm = Get-VM -Name $vmName -ErrorAction Stop
            if ($changedSystemDisk) {
                $systemDrive = Get-VMHardDiskDrive -VM $vm | Where-Object { [IO.Path]::GetFullPath($_.Path) -eq [IO.Path]::GetFullPath($newSystemPath) }
                Set-VMHardDiskDrive -VMHardDiskDrive $systemDrive -Path $oldSystemPath
            }
            if ($changedSeedISO) {
                $dvd = Get-VMDvdDrive -VM $vm | Where-Object { [IO.Path]::GetFullPath($_.Path) -eq [IO.Path]::GetFullPath($newSeedPath) }
                Set-VMDvdDrive -VMDvdDrive $dvd -Path $oldSeedPath
            }
        } catch { $restoreErrors.Add("VM attachment restore failed: $($_.Exception.Message)") }
    }
    try {
        Write-BytesAtomic -Path $configPath -Bytes $oldConfigBytes
        Protect-OwnerFile -Path $configPath
    } catch { $restoreErrors.Add($_.Exception.Message) }
    try { Write-BytesAtomic -Path $provisionPath -Bytes $oldProvisionBytes } catch { $restoreErrors.Add($_.Exception.Message) }
    try { Write-BytesAtomic -Path $installPath -Bytes $oldInstallBytes } catch { $restoreErrors.Add($_.Exception.Message) }
    try {
        Configure-ServiceBinary -Name $providerService -BinaryPath ('"{0}" --config "{1}"' -f (Join-Path $oldReleasePath 'bin\vitalserver-hyperv-runtime-provider.exe'), $providerConfigPath)
        Configure-ServiceBinary -Name $agentService -BinaryPath ('"{0}" --config "{1}"' -f (Join-Path $oldReleasePath 'bin\vitalserver-platform-agent.exe'), $configPath)
        Start-Service -Name $providerService
        (Get-Service -Name $providerService).WaitForStatus([ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromMinutes(1))
        Start-Service -Name $agentService
        (Get-Service -Name $agentService).WaitForStatus([ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromMinutes(1))
        $recoveryAcceptance = Join-Path $oldReleasePath 'packaging\acceptance-hyperv.ps1'
        & $recoveryAcceptance `
            -PlatformVersion ([string]$install.platformVersion) `
            -RuntimeBundleVersion ([string]$install.runtimeBundleVersion) `
            -ReleaseManifestPath (Join-Path $oldReleasePath 'release.json') `
            -APITokenPath $tokenPath `
            -RuntimeProviderDocumentPath (Join-Path $ProgramDataRoot 'run\runtime-provider.json') `
            -HyperVImageManifestPath (Join-Path $oldReleasePath 'hyperv-image\hyperv-image.json') `
            -OutputManifestPath (Join-Path $ProgramDataRoot 'proof\windows-hyperv-update-recovery-acceptance.json') `
            -SupportExportMode 'capability-only'
    } catch { $restoreErrors.Add("Service restore failed: $($_.Exception.Message)") }
    if ($restoreErrors.Count -gt 0) {
        throw "Windows update failed reason=$applyReason rollbackState=failed rollbackErrors=$($restoreErrors -join '; ')"
    }
    throw "Windows update failed reason=$applyReason rollbackState=restored"
}
