param(
    [Parameter(Mandatory = $true)]
    [string]$VMName,
    [Parameter(Mandatory = $true)]
    [string]$SourceSystemVHDXPath,
    [Parameter(Mandatory = $true)]
    [string]$DestinationSystemVHDXPath,
    [Parameter(Mandatory = $true)]
    [string]$SourceRuntimeDataVHDXPath,
    [Parameter(Mandatory = $true)]
    [string]$DestinationRuntimeDataVHDXPath,
    [Parameter(Mandatory = $true)]
    [string]$SourceSeedISOPath,
    [Parameter(Mandatory = $true)]
    [string]$DestinationSeedISOPath,
    [string]$SwitchName = "VitalServer Runtime",
    [string]$NatName = "VitalServerRuntimeNAT",
    [string]$SubnetPrefix = "172.24.0.0/24",
    [string]$HostAddress = "172.24.0.1",
    [string]$GuestAddress = "172.24.0.2",
    [UInt64]$MemoryStartupBytes = 8589934592,
    [UInt32]$ProcessorCount = 4,
    [Parameter(Mandatory = $true)]
    [string]$ProvisionStatePath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Hyper-V provisioning requires an elevated Administrator process."
}

$windowsVersion = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
$windowsBuild = [int]$windowsVersion.CurrentBuildNumber
$editionID = [string]$windowsVersion.EditionID
if ($windowsBuild -lt 26100) {
    throw "VitalServer v2 requires Windows 11 24H2 (build 26100) or later. actualBuild=$windowsBuild"
}
if ($editionID -notmatch "^(Professional|ProfessionalEducation|ProfessionalWorkstation|Enterprise|EnterpriseS|Education)$") {
    throw "VitalServer v2 requires Windows 11 Pro, Enterprise, or Education with Hyper-V. actualEdition=$editionID"
}

$feature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
if ($feature.State -ne [Microsoft.Dism.Commands.FeatureState]::Enabled) {
    throw "Hyper-V is unavailable or disabled. Enable Microsoft-Hyper-V-All and reboot before installing VitalServer."
}
foreach ($sourceArtifact in @($SourceSystemVHDXPath, $SourceRuntimeDataVHDXPath, $SourceSeedISOPath)) {
    if (-not (Test-Path -LiteralPath $sourceArtifact -PathType Leaf)) {
        throw "VitalServer Hyper-V source artifact is missing: $sourceArtifact"
    }
}

function Install-VerifiedArtifact {
    param([string]$Source, [string]$Destination, [string]$Label)
    $sourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash.ToLowerInvariant()
    $destinationDirectory = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        $destinationHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($destinationHash -ne $sourceHash) {
            throw "Existing VitalServer $Label identity differs destination=$Destination expectedSHA256=$sourceHash actualSHA256=$destinationHash"
        }
        return $sourceHash
    }
    Copy-Item -LiteralPath $Source -Destination $Destination
    $destinationHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($destinationHash -ne $sourceHash) {
        Remove-Item -LiteralPath $Destination -Force
        throw "Copied VitalServer $Label checksum mismatch expectedSHA256=$sourceHash actualSHA256=$destinationHash"
    }
    return $sourceHash
}

function Install-PreservedRuntimeDataArtifact {
    param([string]$Source, [string]$Destination)
    $sourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash.ToLowerInvariant()
    $destinationDirectory = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        return [ordered]@{
            state = "preserved-existing"
            sourceSHA256 = $sourceHash
            observedSHA256 = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    Copy-Item -LiteralPath $Source -Destination $Destination
    $destinationHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($destinationHash -ne $sourceHash) {
        Remove-Item -LiteralPath $Destination -Force
        throw "Copied VitalServer Runtime data VHDX checksum mismatch expectedSHA256=$sourceHash actualSHA256=$destinationHash"
    }
    return [ordered]@{
        state = "created"
        sourceSHA256 = $sourceHash
        observedSHA256 = $destinationHash
    }
}

$systemVHDXSHA256 = Install-VerifiedArtifact -Source $SourceSystemVHDXPath -Destination $DestinationSystemVHDXPath -Label "system VHDX"
$runtimeDataVHDX = Install-PreservedRuntimeDataArtifact -Source $SourceRuntimeDataVHDXPath -Destination $DestinationRuntimeDataVHDXPath
$seedISOSHA256 = Install-VerifiedArtifact -Source $SourceSeedISOPath -Destination $DestinationSeedISOPath -Label "NoCloud seed ISO"

$switch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
if ($null -eq $switch) {
    $switch = New-VMSwitch -Name $SwitchName -SwitchType Internal
} elseif ($switch.SwitchType -ne [Microsoft.HyperV.PowerShell.VMSwitchType]::Internal) {
    throw "Existing Hyper-V switch has incompatible type name=$SwitchName type=$($switch.SwitchType) expected=Internal"
}

$adapterAlias = "vEthernet ($SwitchName)"
$hostIP = Get-NetIPAddress -InterfaceAlias $adapterAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -eq $HostAddress }
if ($null -eq $hostIP) {
    $conflictingHostIP = Get-NetIPAddress -InterfaceAlias $adapterAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.PrefixOrigin -ne "WellKnown" }
    if ($null -ne $conflictingHostIP) {
        throw "Hyper-V switch already has a different explicit IPv4 address alias=$adapterAlias addresses=$($conflictingHostIP.IPAddress -join ',')"
    }
    New-NetIPAddress -InterfaceAlias $adapterAlias -IPAddress $HostAddress -PrefixLength 24 | Out-Null
}

$nat = Get-NetNat -Name $NatName -ErrorAction SilentlyContinue
if ($null -eq $nat) {
    $nat = New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $SubnetPrefix
} elseif ($nat.InternalIPInterfaceAddressPrefix -ne $SubnetPrefix) {
    throw "Existing Hyper-V NAT has incompatible prefix name=$NatName actual=$($nat.InternalIPInterfaceAddressPrefix) expected=$SubnetPrefix"
}

$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if ($null -eq $vm) {
    $vm = New-VM -Name $VMName -Generation 2 -MemoryStartupBytes $MemoryStartupBytes -VHDPath $DestinationSystemVHDXPath -SwitchName $SwitchName
    Add-VMHardDiskDrive -VM $vm -Path $DestinationRuntimeDataVHDXPath
    Add-VMDvdDrive -VM $vm -Path $DestinationSeedISOPath
    Set-VMProcessor -VM $vm -Count $ProcessorCount
    Set-VMMemory -VM $vm -DynamicMemoryEnabled $false -StartupBytes $MemoryStartupBytes
    Set-VMFirmware -VM $vm -EnableSecureBoot On -SecureBootTemplate MicrosoftUEFICertificateAuthority
    Set-VM -VM $vm -AutomaticStartAction StartIfRunning -AutomaticStopAction ShutDown -Notes "VitalServer Runtime v2 managed VM"
} else {
    $drives = Get-VMHardDiskDrive -VM $vm
    $expectedDrivePaths = @($DestinationSystemVHDXPath, $DestinationRuntimeDataVHDXPath) | Sort-Object
    $actualDrivePaths = @($drives.Path) | Sort-Object
    if ($drives.Count -ne 2 -or (Compare-Object -ReferenceObject $expectedDrivePaths -DifferenceObject $actualDrivePaths)) {
        throw "Existing VM does not match the managed VitalServer disks vm=$VMName expected=$($expectedDrivePaths -join ',') actual=$($actualDrivePaths -join ',')"
    }
    $dvdDrives = Get-VMDvdDrive -VM $vm
    if ($dvdDrives.Count -ne 1 -or $dvdDrives[0].Path -ne $DestinationSeedISOPath) {
        throw "Existing VM does not match the managed VitalServer seed ISO vm=$VMName expected=$DestinationSeedISOPath actual=$($dvdDrives.Path -join ',')"
    }
    $adapters = Get-VMNetworkAdapter -VM $vm
    if ($adapters.Count -ne 1 -or $adapters[0].SwitchName -ne $SwitchName) {
        throw "Existing VM does not match the managed VitalServer switch vm=$VMName expected=$SwitchName actual=$($adapters.SwitchName -join ',')"
    }
}

$stateDirectory = Split-Path -Parent $ProvisionStatePath
New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
$state = [ordered]@{
    schemaVersion = 1
    state = "provisioned"
    vmName = $VMName
    vmID = $vm.Id.ToString()
    systemVHDXPath = $DestinationSystemVHDXPath
    systemVHDXSHA256 = $systemVHDXSHA256
    runtimeDataVHDXPath = $DestinationRuntimeDataVHDXPath
    runtimeDataVHDXProvisioningState = $runtimeDataVHDX.state
    runtimeDataVHDXSourceSHA256 = $runtimeDataVHDX.sourceSHA256
    runtimeDataVHDXObservedSHA256 = $runtimeDataVHDX.observedSHA256
    seedISOPath = $DestinationSeedISOPath
    seedISOSHA256 = $seedISOSHA256
    switchName = $SwitchName
    natName = $NatName
    subnetPrefix = $SubnetPrefix
    hostAddress = $HostAddress
    guestAddress = $GuestAddress
    provisionedAt = [DateTime]::UtcNow.ToString("o")
    readError = $null
}
$temporaryState = "$ProvisionStatePath.tmp.$PID"
$state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $temporaryState -Encoding UTF8
Move-Item -LiteralPath $temporaryState -Destination $ProvisionStatePath -Force

Write-Output "VitalServer Hyper-V provisioning passed vm=$VMName guestAddress=$GuestAddress systemVHDXSHA256=$systemVHDXSHA256 runtimeDataVHDXState=$($runtimeDataVHDX.state) runtimeDataVHDXObservedSHA256=$($runtimeDataVHDX.observedSHA256) seedISOSHA256=$seedISOSHA256"
