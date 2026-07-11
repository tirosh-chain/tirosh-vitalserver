param(
    [Parameter(Mandatory = $true)][string]$BundlePath,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExpectedSHA256,
    [string]$ProgramDataRoot = (Join-Path $env:ProgramData 'VitalServer')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'VitalServer update trust provisioning requires an elevated Administrator process.'
}
if (-not (Test-Path -LiteralPath $BundlePath -PathType Leaf)) {
    throw "Windows update bundle is missing path=$BundlePath"
}
$actual = (Get-FileHash -LiteralPath $BundlePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $ExpectedSHA256) {
    throw "Windows update bundle differs from administrator-provided digest expected=$ExpectedSHA256 actual=$actual"
}

function Write-JSONNoBOM {
    param([string]$Path, [object]$Document, [int]$Depth = 10)
    $temporary = "$Path.tmp.$PID"
    $json = $Document | ConvertTo-Json -Depth $Depth
    [IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
    & icacls.exe $Path /inheritance:r /grant:r '*S-1-5-18:(F)' '*S-1-5-32-544:(F)' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Windows update trust owner ACL hardening failed path=$Path exitCode=$LASTEXITCODE"
    }
}

$configPath = Join-Path $ProgramDataRoot 'config\platform-agent.json'
$catalogPath = Join-Path $ProgramDataRoot 'config\trusted-bundle-digests.json'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "Windows Platform Agent config owner is missing path=$configPath"
}
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
if ($config.schemaVersion -ne 1 -or $null -eq $config.delivery -or $config.delivery.schedulerKind -ne 'windows-scheduled-task') {
    throw "Windows Platform Agent delivery owner is invalid path=$configPath"
}
$catalog = [ordered]@{ schemaVersion = 1; sha256 = @($ExpectedSHA256) }
Write-JSONNoBOM -Path $catalogPath -Document $catalog
$config.delivery.applyPolicy = 'sha256-allowlist'
if ($config.delivery.PSObject.Properties.Name -contains 'trustedBundleDigests') {
    $config.delivery.trustedBundleDigests = $catalogPath
} else {
    $config.delivery | Add-Member -NotePropertyName trustedBundleDigests -NotePropertyValue $catalogPath
}
Write-JSONNoBOM -Path $configPath -Document $config
Restart-Service -Name 'VitalServerPlatformAgent' -ErrorAction Stop
(Get-Service -Name 'VitalServerPlatformAgent').WaitForStatus([ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromMinutes(1))
Write-Output "VitalServer Windows update trust provisioned sha256=$ExpectedSHA256 catalog=$catalogPath"
