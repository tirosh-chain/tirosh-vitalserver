param(
    [Parameter(Mandatory = $true)]
    [string]$InstallDirectory,
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,
    [Parameter(Mandatory = $true)]
    [string]$HyperVConfigPath,
    [Parameter(Mandatory = $true)]
    [string]$ProvisionStatePath,
    [Parameter(Mandatory = $true)]
    [string]$PlatformVersion,
    [Parameter(Mandatory = $true)]
    [string]$RuntimeBundleVersion,
    [Parameter(Mandatory = $true)]
    [string]$ReleaseManifestPath,
    [Parameter(Mandatory = $true)]
    [string]$ReleasePath,
    [Parameter(Mandatory = $true)]
    [string]$SystemVHDXPath,
    [Parameter(Mandatory = $true)]
    [string]$SeedISOPath,
    [string]$PreviousReleasePath,
    [string]$PreviousSystemVHDXPath,
    [string]$PreviousSeedISOPath,
    [Parameter(Mandatory = $true)]
    [string]$APITokenPath,
    [Parameter(Mandatory = $true)]
    [string]$RuntimeProviderDocumentPath,
    [Parameter(Mandatory = $true)]
    [string]$HyperVImageManifestPath,
    [Parameter(Mandatory = $true)]
    [string]$AcceptanceManifestPath,
    [Parameter(Mandatory = $true)]
    [string]$InstallDocumentPath,
    [string]$BaseURL = "http://127.0.0.1:18321"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "VitalServer Windows Service installation requires an elevated Administrator process."
}

$agentServiceName = "VitalServerPlatformAgent"
$providerServiceName = "VitalServerHyperVRuntime"
$agentBinary = Join-Path $InstallDirectory "vitalserver-platform-agent.exe"
$providerBinary = Join-Path $InstallDirectory "vitalserver-hyperv-runtime-provider.exe"
$acceptanceScript = Join-Path $PSScriptRoot "acceptance-hyperv.ps1"

foreach ($requiredFile in @($agentBinary, $providerBinary, $ConfigPath, $HyperVConfigPath, $ProvisionStatePath, $APITokenPath, $HyperVImageManifestPath, $ReleaseManifestPath, $acceptanceScript)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "VitalServer Windows Service input is missing: $requiredFile"
    }
}
if ($PlatformVersion -notmatch '^[A-Za-z0-9._+-]+$' -or $RuntimeBundleVersion -notmatch '^[A-Za-z0-9._+-]+$') {
    throw "Windows install release identity is invalid platformVersion=$PlatformVersion runtimeBundleVersion=$RuntimeBundleVersion"
}

try {
    $platformConfig = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $hyperVConfig = Get-Content -LiteralPath $HyperVConfigPath -Raw | ConvertFrom-Json
    $provisionState = Get-Content -LiteralPath $ProvisionStatePath -Raw | ConvertFrom-Json
} catch {
    throw "VitalServer Windows Service owner document decode failed: $($_.Exception.Message)"
}
if (-not $platformConfig.installDocument) {
    throw "Platform Agent config has no explicit installDocument owner path=$ConfigPath"
}
if ([IO.Path]::GetFullPath([string]$platformConfig.installDocument) -ne [IO.Path]::GetFullPath($InstallDocumentPath)) {
    throw "Platform Agent config and Windows installer use different install owner paths config=$($platformConfig.installDocument) installer=$InstallDocumentPath"
}
if ([IO.Path]::GetFullPath([string]$platformConfig.runtimeProviderDocument) -ne [IO.Path]::GetFullPath($RuntimeProviderDocumentPath)) {
    throw "Platform Agent config and Windows acceptance use different Runtime Provider owner paths config=$($platformConfig.runtimeProviderDocument) acceptance=$RuntimeProviderDocumentPath"
}
$apiToken = (Get-Content -LiteralPath $APITokenPath -Raw).Trim()
if (-not $apiToken -or $platformConfig.apiToken -ne $apiToken) {
    throw "Platform Agent config and API token owner file differ config=$ConfigPath tokenOwner=$APITokenPath"
}
if ($provisionState.schemaVersion -ne 1 -or $provisionState.state -ne "provisioned") {
    throw "Hyper-V provision state is not a supported provisioned document path=$ProvisionStatePath"
}
if ($provisionState.vmName -ne $hyperVConfig.vmName) {
    throw "Hyper-V config and provision state VM names differ config=$($hyperVConfig.vmName) provisioned=$($provisionState.vmName)"
}
if ($provisionState.guestAddress -ne $hyperVConfig.runtimeEndpointAddress) {
    throw "Hyper-V config and provision state guest addresses differ config=$($hyperVConfig.runtimeEndpointAddress) provisioned=$($provisionState.guestAddress)"
}
if ([IO.Path]::GetFullPath($ReleasePath) -ne [IO.Path]::GetFullPath((Split-Path -Parent $ReleaseManifestPath))) {
    throw "Windows release path and release manifest parent differ release=$ReleasePath manifest=$ReleaseManifestPath"
}
if ([IO.Path]::GetFullPath($SystemVHDXPath) -ne [IO.Path]::GetFullPath([string]$provisionState.systemVHDXPath) -or
    [IO.Path]::GetFullPath($SeedISOPath) -ne [IO.Path]::GetFullPath([string]$provisionState.seedISOPath)) {
    throw "Windows install disk owners differ from Hyper-V provision owner."
}

function Stop-ServiceIfRunning {
    param([string]$Name)
    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($null -ne $service -and $service.Status -ne [ServiceProcess.ServiceControllerStatus]::Stopped) {
        Stop-Service -Name $Name -ErrorAction Stop
        $service.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromMinutes(4))
    }
}

function Ensure-Service {
    param(
        [string]$Name,
        [string]$DisplayName,
        [string]$BinaryPath
    )
    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $service) {
        New-Service -Name $Name -BinaryPathName $BinaryPath -DisplayName $DisplayName -StartupType Automatic | Out-Null
        return
    }
    $cimService = Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'"
    if ($null -eq $cimService) {
        throw "Windows Service exists but its Win32_Service owner resource is unavailable: $Name"
    }
    $change = Invoke-CimMethod -InputObject $cimService -MethodName Change -Arguments @{
        PathName = $BinaryPath
        StartMode = "Automatic"
        DisplayName = $DisplayName
    }
    if ($change.ReturnValue -ne 0) {
        throw "Windows Service configuration failed service=$Name returnValue=$($change.ReturnValue)"
    }
}

Stop-ServiceIfRunning -Name $agentServiceName
Stop-ServiceIfRunning -Name $providerServiceName

$providerBinaryPath = ('"{0}" --config "{1}"' -f $providerBinary, $HyperVConfigPath)
$agentBinaryPath = ('"{0}" --config "{1}"' -f $agentBinary, $ConfigPath)
Ensure-Service -Name $providerServiceName -DisplayName "VitalServer Hyper-V Runtime Provider" -BinaryPath $providerBinaryPath
Ensure-Service -Name $agentServiceName -DisplayName "VitalServer Platform Agent" -BinaryPath $agentBinaryPath

& sc.exe failure $providerServiceName reset= 86400 actions= restart/10000/restart/30000/restart/60000 | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Windows Service recovery configuration failed: service=$providerServiceName exitCode=$LASTEXITCODE"
}
& sc.exe failure $agentServiceName reset= 86400 actions= restart/5000/restart/10000/restart/30000 | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Windows Service recovery configuration failed: service=$agentServiceName exitCode=$LASTEXITCODE"
}

Start-Service -Name $providerServiceName
(Get-Service -Name $providerServiceName).WaitForStatus([ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromMinutes(1))
Start-Service -Name $agentServiceName
(Get-Service -Name $agentServiceName).WaitForStatus([ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromMinutes(1))

& $acceptanceScript `
    -PlatformVersion $PlatformVersion `
    -RuntimeBundleVersion $RuntimeBundleVersion `
    -ReleaseManifestPath $ReleaseManifestPath `
    -APITokenPath $APITokenPath `
    -RuntimeProviderDocumentPath $RuntimeProviderDocumentPath `
    -HyperVImageManifestPath $HyperVImageManifestPath `
    -OutputManifestPath $AcceptanceManifestPath `
    -BaseURL $BaseURL

try {
    $acceptance = Get-Content -LiteralPath $AcceptanceManifestPath -Raw | ConvertFrom-Json
} catch {
    throw "Windows acceptance proof decode failed path=$AcceptanceManifestPath reason=$($_.Exception.Message)"
}
if ($acceptance.status -ne "passed" -or -not $acceptance.runId -or -not $acceptance.hostBootSessionId -or $acceptance.platformVersion -ne $PlatformVersion -or $acceptance.runtimeBundleVersion -ne $RuntimeBundleVersion) {
    throw "Windows acceptance proof does not match this install path=$AcceptanceManifestPath"
}

$installDirectory = Split-Path -Parent $InstallDocumentPath
New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
$installOwner = [ordered]@{
    schemaVersion = 1
    state = "installed"
    platformVersion = $PlatformVersion
    runtimeBundleVersion = $RuntimeBundleVersion
    installedAcceptanceRunId = $acceptance.runId
    installedAt = [DateTime]::UtcNow.ToString("o")
    installedBootSessionId = $acceptance.hostBootSessionId
    releasePath = [IO.Path]::GetFullPath($ReleasePath)
    previousReleasePath = if ($PreviousReleasePath) { [IO.Path]::GetFullPath($PreviousReleasePath) } else { $null }
    systemVHDXPath = [IO.Path]::GetFullPath($SystemVHDXPath)
    previousSystemVHDXPath = if ($PreviousSystemVHDXPath) { [IO.Path]::GetFullPath($PreviousSystemVHDXPath) } else { $null }
    seedISOPath = [IO.Path]::GetFullPath($SeedISOPath)
    previousSeedISOPath = if ($PreviousSeedISOPath) { [IO.Path]::GetFullPath($PreviousSeedISOPath) } else { $null }
}
$temporaryInstallOwner = "$InstallDocumentPath.tmp.$PID"
$installOwnerJSON = $installOwner | ConvertTo-Json -Depth 4
[IO.File]::WriteAllText($temporaryInstallOwner, $installOwnerJSON + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporaryInstallOwner -Destination $InstallDocumentPath -Force

Write-Output "VitalServer Windows Services installed provider=$providerServiceName agent=$agentServiceName platformVersion=$PlatformVersion acceptanceRunId=$($acceptance.runId)"
