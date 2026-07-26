param(
    [Parameter(Mandatory = $true)]
    [string]$BundleDirectory,
    [string]$ProgramFilesRoot = (Join-Path $env:ProgramFiles "VitalServer"),
    [string]$ProgramDataRoot = (Join-Path $env:ProgramData "VitalServer"),
    [string]$VMName = "VitalServer Runtime",
    [string]$SwitchName = "VitalServer Runtime",
    [string]$NatName = "VitalServerRuntimeNAT",
    [string]$SubnetPrefix = "172.24.0.0/24",
    [string]$HostAddress = "172.24.0.1",
    [string]$GuestAddress = "172.24.0.2",
    [UInt64]$MemoryStartupBytes = 8589934592,
    [UInt32]$ProcessorCount = 4
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "VitalServer Windows offline installation requires an elevated Administrator process."
}

function Write-JSONNoBOM {
    param([object]$Document, [string]$Path, [int]$Depth = 8)
    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporary = "$Path.tmp.$PID"
    $json = $Document | ConvertTo-Json -Depth $Depth
    [IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Protect-OwnerFile {
    param([string]$Path)
    & icacls.exe $Path /inheritance:r /grant:r '*S-1-5-18:(F)' '*S-1-5-32-544:(F)' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Windows owner file ACL hardening failed path=$Path exitCode=$LASTEXITCODE"
    }
}

function Protect-OwnerDirectory {
    param([string]$Path)
    & icacls.exe $Path /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)(F)' '*S-1-5-32-544:(OI)(CI)(F)' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Windows owner directory ACL hardening failed path=$Path exitCode=$LASTEXITCODE"
    }
}

function Assert-SafeBundle {
    param([string]$Root)
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $checksumPath = Join-Path $rootPath "checksums.sha256"
    if (-not (Test-Path -LiteralPath $checksumPath -PathType Leaf)) {
        throw "Windows bundle checksum owner is missing path=$checksumPath"
    }
    $expected = @{}
    $lineNumber = 0
    foreach ($line in [IO.File]::ReadAllLines($checksumPath, [Text.Encoding]::UTF8)) {
        $lineNumber += 1
        if ($line -notmatch '^([0-9a-f]{64})  ([A-Za-z0-9][A-Za-z0-9._/+-]*)$') {
            throw "Windows bundle checksum line is invalid line=$lineNumber"
        }
        $digest = $Matches[1]
        $relative = $Matches[2]
        if ($expected.ContainsKey($relative)) {
            throw "Windows bundle checksum path is duplicated path=$relative"
        }
        $nativeRelative = $relative.Replace([char]'/', [IO.Path]::DirectorySeparatorChar)
        $candidate = [IO.Path]::GetFullPath((Join-Path $rootPath $nativeRelative))
        if (-not $candidate.StartsWith($rootPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Windows bundle checksum path escapes bundle root path=$relative"
        }
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "Windows bundle checksum member is missing path=$relative"
        }
        $item = Get-Item -LiteralPath $candidate -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Windows bundle contains unsupported reparse point path=$relative"
        }
        $actual = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $digest) {
            throw "Windows bundle checksum mismatch path=$relative expected=$digest actual=$actual"
        }
        $expected[$relative] = $true
    }
    if ($expected.Count -eq 0) {
        throw "Windows bundle checksum owner is empty path=$checksumPath"
    }
    $reparsePoints = @(
        Get-ChildItem -LiteralPath $rootPath -Recurse -Force |
        Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 }
    )
    if ($reparsePoints.Count -gt 0) {
        throw "Windows bundle contains unsupported reparse points paths=$($reparsePoints.FullName -join ',')"
    }
    $actualFiles = @(
        Get-ChildItem -LiteralPath $rootPath -File -Recurse -Force |
        Where-Object { $_.FullName -ne $checksumPath } |
        ForEach-Object { $_.FullName.Substring($rootPath.Length + 1).Replace('\', '/') }
    )
    $unexpected = @($actualFiles | Where-Object { -not $expected.ContainsKey($_) })
    if ($unexpected.Count -gt 0 -or $actualFiles.Count -ne $expected.Count) {
        throw "Windows bundle checksum inventory differs unexpected=$($unexpected -join ',') expectedCount=$($expected.Count) actualCount=$($actualFiles.Count)"
    }
}

$bundleRoot = [IO.Path]::GetFullPath($BundleDirectory)
Assert-SafeBundle -Root $bundleRoot
$releasePath = Join-Path $bundleRoot "release.json"
$imageManifestPath = Join-Path $bundleRoot "hyperv-image\hyperv-image.json"
try {
    $release = Get-Content -LiteralPath $releasePath -Raw | ConvertFrom-Json
    $image = Get-Content -LiteralPath $imageManifestPath -Raw | ConvertFrom-Json
} catch {
    throw "Windows bundle owner document decode failed: $($_.Exception.Message)"
}
if ($release.schemaVersion -ne 1 -or $release.target.os -ne "windows" -or $release.target.architecture -ne "amd64" -or $release.target.provider -ne "hyperv") {
    throw "Windows release owner is not a windows/amd64 Hyper-V release path=$releasePath"
}
if ($release.state -notin @('acceptanceCandidate', 'releaseCandidate')) {
    throw "Windows release owner state is not installable state=$($release.state) path=$releasePath"
}
if (($release.state -eq 'acceptanceCandidate' -and $null -ne $release.installedAcceptanceRunId) -or
    ($release.state -eq 'releaseCandidate' -and -not $release.installedAcceptanceRunId)) {
    throw "Windows release owner acceptance identity does not match state=$($release.state) path=$releasePath"
}
$platformVersion = [string]$release.platformVersion
$runtimeBundleVersion = [string]$release.runtimeBundleVersion
if ($platformVersion -notmatch '^[A-Za-z0-9._+-]+$' -or $runtimeBundleVersion -notmatch '^[A-Za-z0-9._+-]+$') {
    throw "Windows release identity is invalid platformVersion=$platformVersion runtimeBundleVersion=$runtimeBundleVersion"
}
if ($image.schemaVersion -ne 1 -or $image.state -ne "compiled" -or $image.architecture -ne "amd64" -or $image.guestAddress -ne $GuestAddress) {
    throw "Hyper-V image owner differs from installer target guestAddress=$GuestAddress path=$imageManifestPath"
}

$installDocument = Join-Path $ProgramDataRoot "install.json"
if (Test-Path -LiteralPath $installDocument) {
    throw "VitalServer is already installed according to its owner path=$installDocument; use the Platform update workflow."
}

$releasesRoot = Join-Path $ProgramFilesRoot "releases"
$releaseRoot = Join-Path $releasesRoot $platformVersion
$stagingRoot = Join-Path $releasesRoot ".$platformVersion.installing.$PID"
New-Item -ItemType Directory -Path $releasesRoot -Force | Out-Null
if (Test-Path -LiteralPath $releaseRoot) {
    $installedReleasePath = Join-Path $releaseRoot "release.json"
    if (-not (Test-Path -LiteralPath $installedReleasePath -PathType Leaf) -or
        (Get-FileHash -LiteralPath $installedReleasePath -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $releasePath -Algorithm SHA256).Hash) {
        throw "Immutable Windows release version already exists with different identity path=$releaseRoot"
    }
} else {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $stagingRoot | Out-Null
    foreach ($name in @("bin", "pwa", "packaging", "hyperv-image", "proof", "config")) {
        Copy-Item -LiteralPath (Join-Path $bundleRoot $name) -Destination (Join-Path $stagingRoot $name) -Recurse
    }
    Copy-Item -LiteralPath $releasePath -Destination (Join-Path $stagingRoot "release.json")
    Move-Item -LiteralPath $stagingRoot -Destination $releaseRoot
}

$configRoot = Join-Path $ProgramDataRoot "config"
$runRoot = Join-Path $ProgramDataRoot "run"
$proofRoot = Join-Path $ProgramDataRoot "proof"
$secretRoot = Join-Path $ProgramDataRoot "secrets"
$vmRoot = Join-Path $ProgramDataRoot "vm"
$inboxRoot = Join-Path $ProgramDataRoot "inbox"
foreach ($directory in @($configRoot, $runRoot, $proofRoot, $secretRoot, $vmRoot, $inboxRoot)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}
Protect-OwnerDirectory -Path $inboxRoot

$platformConfigPath = Join-Path $configRoot "platform-agent.json"
$providerConfigPath = Join-Path $configRoot "hyperv-runtime-provider.json"
$tokenPath = Join-Path $secretRoot "platform-api-token"
$existingConfigCount = @(@($platformConfigPath, $providerConfigPath, $tokenPath) | Where-Object { Test-Path -LiteralPath $_ }).Count
if ($existingConfigCount -ne 0 -and $existingConfigCount -ne 3) {
    throw "Existing Windows Platform owner set is incomplete configRoot=$configRoot"
}
if ($existingConfigCount -eq 0) {
    $tokenBytes = New-Object byte[] 32
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $random.GetBytes($tokenBytes)
    } finally {
        $random.Dispose()
    }
    $apiToken = -join ($tokenBytes | ForEach-Object { $_.ToString("x2") })
    [IO.File]::WriteAllText($tokenPath, $apiToken + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Protect-OwnerFile -Path $tokenPath
    $powerShell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $platformConfig = [ordered]@{
        schemaVersion = 1
        listenAddress = "127.0.0.1:18321"
        apiToken = $apiToken
        runtimeExecutable = (Join-Path $releaseRoot "bin\vitalserver-hyperv-runtime-provider.exe")
        runtimeEndpointDocument = (Join-Path $runRoot "runtime-endpoint.json")
        runtimeProviderDocument = (Join-Path $runRoot "runtime-provider.json")
        operationLeaseDocument = (Join-Path $runRoot "operation-lease.json")
        installDocument = $installDocument
        runtimeControllerPort = 18330
        pwaDirectory = (Join-Path $releaseRoot "pwa")
        delivery = [ordered]@{
            workflowDocument = (Join-Path $runRoot "platform-workflow.json")
            updateTool = (Join-Path $releaseRoot "packaging\update-windows.ps1")
            rollbackTool = (Join-Path $releaseRoot "packaging\rollback-windows.ps1")
            uninstallTool = (Join-Path $releaseRoot "packaging\uninstall-windows.ps1")
            supportExportTool = (Join-Path $releaseRoot "packaging\support-export-windows.ps1")
            schedulerExecutable = $powerShell
            schedulerKind = "windows-scheduled-task"
            schedulerScript = (Join-Path $releaseRoot "packaging\schedule-workflow-windows.ps1")
            applyPolicy = "verify-only"
            trustedBundleInbox = $inboxRoot
        }
        platformServices = [ordered]@{
            "runtime-provider" = "VitalServerHyperVRuntime"
            "public-proxy" = $null
            "log-sync" = $null
            "sleep-prevention" = $null
            "watchdog" = $null
        }
    }
    $providerConfig = [ordered]@{
        schemaVersion = 1
        powerShellExecutable = $powerShell
        vmName = $VMName
        runtimeReadyURL = "http://${GuestAddress}:18330/ready"
        runtimeEndpointAddress = $GuestAddress
        runtimeEndpointDocument = (Join-Path $runRoot "runtime-endpoint.json")
        runtimeProviderDocument = (Join-Path $runRoot "runtime-provider.json")
        startupTimeoutSeconds = 300
        shutdownTimeoutSeconds = 180
    }
    Write-JSONNoBOM -Document $platformConfig -Path $platformConfigPath
    Write-JSONNoBOM -Document $providerConfig -Path $providerConfigPath
    Protect-OwnerFile -Path $platformConfigPath
    Protect-OwnerFile -Path $providerConfigPath
} else {
    $apiToken = (Get-Content -LiteralPath $tokenPath -Raw).Trim()
    $platformConfig = Get-Content -LiteralPath $platformConfigPath -Raw | ConvertFrom-Json
    if (-not $apiToken -or $platformConfig.apiToken -ne $apiToken -or $platformConfig.installDocument -ne $installDocument) {
        throw "Existing Windows Platform config does not match explicit token/install owners."
    }
    if ($null -eq $platformConfig.delivery -or $platformConfig.delivery.schedulerKind -ne 'windows-scheduled-task') {
        throw "Existing Windows Platform config has no supported explicit delivery owner."
    }
    $platformConfig.runtimeExecutable = (Join-Path $releaseRoot "bin\vitalserver-hyperv-runtime-provider.exe")
    $platformConfig.pwaDirectory = (Join-Path $releaseRoot "pwa")
    $platformConfig.delivery.updateTool = (Join-Path $releaseRoot "packaging\update-windows.ps1")
    $platformConfig.delivery.rollbackTool = (Join-Path $releaseRoot "packaging\rollback-windows.ps1")
    $platformConfig.delivery.uninstallTool = (Join-Path $releaseRoot "packaging\uninstall-windows.ps1")
    $supportExportTool = Join-Path $releaseRoot "packaging\support-export-windows.ps1"
    if ($platformConfig.delivery.PSObject.Properties.Name -contains 'supportExportTool') {
        $platformConfig.delivery.supportExportTool = $supportExportTool
    } else {
        $platformConfig.delivery | Add-Member -NotePropertyName supportExportTool -NotePropertyValue $supportExportTool
    }
    $platformConfig.delivery.schedulerScript = (Join-Path $releaseRoot "packaging\schedule-workflow-windows.ps1")
    if ($platformConfig.delivery.PSObject.Properties.Name -contains 'trustedBundleInbox') {
        if ($platformConfig.delivery.trustedBundleInbox -ne $inboxRoot) {
            throw "Existing Windows Platform config has a different trusted bundle inbox owner path=$($platformConfig.delivery.trustedBundleInbox)"
        }
    } else {
        $platformConfig.delivery | Add-Member -NotePropertyName trustedBundleInbox -NotePropertyValue $inboxRoot
    }
    Write-JSONNoBOM -Document $platformConfig -Path $platformConfigPath
    Protect-OwnerFile -Path $platformConfigPath
}

$sourceImageRoot = Join-Path $releaseRoot "hyperv-image"
function Resolve-ImageArtifact {
    param([object]$Artifact, [string]$Label)
    $relative = [string]$Artifact.path
    if ($relative -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        throw "Hyper-V image artifact path is invalid label=$Label path=$relative"
    }
    $path = Join-Path $sourceImageRoot $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Hyper-V image artifact is missing label=$Label path=$path"
    }
    return $path
}
$systemVHDXSource = Resolve-ImageArtifact -Artifact $image.systemVHDX -Label "systemVHDX"
$runtimeDataVHDXSource = Resolve-ImageArtifact -Artifact $image.runtimeDataVHDX -Label "runtimeDataVHDX"
$seedISOSource = Resolve-ImageArtifact -Artifact $image.seedISO -Label "seedISO"
$systemVHDXDestination = Join-Path $vmRoot "vitalserver-system.vhdx"
$runtimeDataVHDXDestination = Join-Path $vmRoot "vitalserver-runtime-data.vhdx"
$seedISODestination = Join-Path $vmRoot "vitalserver-seed.iso"
$provisionStatePath = Join-Path $ProgramDataRoot "hyperv-provision.json"
$provisionScript = Join-Path $releaseRoot "packaging\provision-hyperv.ps1"
& $provisionScript `
    -VMName $VMName `
    -SourceSystemVHDXPath $systemVHDXSource `
    -DestinationSystemVHDXPath $systemVHDXDestination `
    -SourceRuntimeDataVHDXPath $runtimeDataVHDXSource `
    -DestinationRuntimeDataVHDXPath $runtimeDataVHDXDestination `
    -SourceSeedISOPath $seedISOSource `
    -DestinationSeedISOPath $seedISODestination `
    -SwitchName $SwitchName `
    -NatName $NatName `
    -SubnetPrefix $SubnetPrefix `
    -HostAddress $HostAddress `
    -GuestAddress $GuestAddress `
    -MemoryStartupBytes $MemoryStartupBytes `
    -ProcessorCount $ProcessorCount `
    -ProvisionStatePath $provisionStatePath

$serviceInstaller = Join-Path $releaseRoot "packaging\install-service.ps1"
& $serviceInstaller `
    -InstallDirectory (Join-Path $releaseRoot "bin") `
    -ConfigPath $platformConfigPath `
    -HyperVConfigPath $providerConfigPath `
    -ProvisionStatePath $provisionStatePath `
    -PlatformVersion $platformVersion `
    -RuntimeBundleVersion $runtimeBundleVersion `
    -ReleaseManifestPath (Join-Path $releaseRoot "release.json") `
    -ReleasePath $releaseRoot `
    -SystemVHDXPath $systemVHDXDestination `
    -SeedISOPath $seedISODestination `
    -APITokenPath $tokenPath `
    -RuntimeProviderDocumentPath (Join-Path $runRoot "runtime-provider.json") `
    -HyperVImageManifestPath (Join-Path $releaseRoot "hyperv-image\hyperv-image.json") `
    -AcceptanceManifestPath (Join-Path $proofRoot "windows-hyperv-acceptance.json") `
    -InstallDocumentPath $installDocument

Write-Output "VitalServer Windows offline installation passed platformVersion=$platformVersion runtimeBundleVersion=$runtimeBundleVersion installOwner=$installDocument"
