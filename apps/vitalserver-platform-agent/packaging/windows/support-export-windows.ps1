param(
    [Parameter(Mandatory = $true)][ValidatePattern('^workflow-[0-9a-f]{32}$')][string]$OperationId,
    [Parameter(Mandatory = $true)][string]$OperationDocument,
    [string]$ProgramDataRoot = (Join-Path $env:ProgramData 'VitalServer')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Protect-OwnerPath {
    param([string]$Path, [switch]$Directory)
    $grants = if ($Directory) {
        @('*S-1-5-18:(OI)(CI)(F)', '*S-1-5-32-544:(OI)(CI)(F)')
    } else {
        @('*S-1-5-18:(F)', '*S-1-5-32-544:(F)')
    }
    & icacls.exe $Path /inheritance:r /grant:r $grants | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Windows support owner ACL hardening failed path=$Path exitCode=$LASTEXITCODE"
    }
}

function Write-JSONNoBOM {
    param([object]$Document, [string]$Path)
    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporary = "$Path.tmp.$PID"
    $json = $Document | ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Write-Workflow {
    param([string]$State, [string]$StartedAt, [object]$Artifact, [object]$Failure)
    Write-JSONNoBOM -Path $OperationDocument -Document ([ordered]@{
        schemaVersion = 1
        operationId = $OperationId
        kind = 'support-export'
        state = $State
        startedAt = $StartedAt
        updatedAt = [DateTime]::UtcNow.ToString('o')
        release = $null
        artifact = $Artifact
        failure = $Failure
    })
}

$startedAt = [DateTime]::UtcNow.ToString('o')
Write-Workflow -State 'running' -StartedAt $startedAt -Artifact $null -Failure $null
$supportRoot = Join-Path $ProgramDataRoot 'support'
$destination = Join-Path $supportRoot "vitalserver-support-$OperationId.zip"
$staging = Join-Path ([IO.Path]::GetTempPath()) "vitalserver-support-$OperationId"
try {
    New-Item -ItemType Directory -Path $supportRoot -Force | Out-Null
    Protect-OwnerPath -Path $supportRoot -Directory
    if (Test-Path -LiteralPath $destination) {
        throw "Support artifact already exists path=$destination"
    }
    New-Item -ItemType Directory -Path (Join-Path $staging 'owners') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $staging 'diagnostics') -Force | Out-Null
    Protect-OwnerPath -Path $staging -Directory
    $files = [Collections.Generic.List[object]]::new()
    foreach ($relative in @('install.json', 'hyperv-provision.json', 'run\runtime-endpoint.json', 'run\runtime-provider.json')) {
        $source = Join-Path $ProgramDataRoot $relative
        if (Test-Path -LiteralPath $source) {
            $sourceItem = Get-Item -LiteralPath $source -Force
            if ($sourceItem.PSIsContainer -or ($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                $files.Add([ordered]@{
                    source = $source
                    archivePath = $null
                    state = 'invalid'
                    reason = 'not a regular file'
                })
                continue
            }
            $archivePath = Join-Path 'owners' ($relative -replace '\\', '/')
            $target = Join-Path $staging $archivePath
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            try {
                Copy-Item -LiteralPath $source -Destination $target -ErrorAction Stop
                $files.Add([ordered]@{
                    source = $source
                    archivePath = $archivePath
                    state = 'collected'
                    sizeBytes = $sourceItem.Length
                })
            } catch {
                Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
                $files.Add([ordered]@{
                    source = $source
                    archivePath = $null
                    state = 'read-failed'
                    reason = $_.Exception.Message
                })
            }
        } else {
            $files.Add([ordered]@{ source = $source; archivePath = $null; state = 'missing' })
        }
    }
    $services = foreach ($name in @('VitalServerPlatformAgent', 'VitalServerHyperVRuntime')) {
        $service = Get-CimInstance Win32_Service -Filter "Name='$name'" -ErrorAction SilentlyContinue
        if ($null -eq $service) {
            [ordered]@{ name = $name; state = 'missing' }
        } else {
            [ordered]@{
                name = $name
                state = [string]$service.State
                startMode = [string]$service.StartMode
                processId = [UInt32]$service.ProcessId
                exitCode = [UInt32]$service.ExitCode
            }
        }
    }
    $servicesPath = Join-Path $staging 'diagnostics\services.json'
    Write-JSONNoBOM -Path $servicesPath -Document @($services)
    $files.Add([ordered]@{
        source = 'Win32_Service:VitalServerPlatformAgent,VitalServerHyperVRuntime'
        archivePath = 'diagnostics/services.json'
        state = 'collected'
        sizeBytes = (Get-Item -LiteralPath $servicesPath).Length
    })
    $hyperVDiagnosticState = 'collected'
    $hyperVDiagnosticReason = $null
    $hyperVDiagnosticPath = Join-Path $staging 'diagnostics\hyperv-vm.json'
    try {
        $provisionPath = Join-Path $ProgramDataRoot 'hyperv-provision.json'
        $provision = Get-Content -LiteralPath $provisionPath -Raw | ConvertFrom-Json
        if ($provision.schemaVersion -ne 1 -or $provision.state -ne 'provisioned' -or -not $provision.vmName) {
            throw "Hyper-V provision owner is invalid path=$provisionPath"
        }
        $vm = Get-VM -Name ([string]$provision.vmName) -ErrorAction Stop
        Write-JSONNoBOM -Path $hyperVDiagnosticPath -Document ([ordered]@{
            name = $vm.Name
            id = $vm.Id.ToString()
            state = $vm.State.ToString()
            status = $vm.Status
            uptimeSeconds = [Int64]$vm.Uptime.TotalSeconds
        })
    } catch {
        $hyperVDiagnosticState = 'command-failed'
        $hyperVDiagnosticReason = $_.Exception.Message
        Write-JSONNoBOM -Path $hyperVDiagnosticPath -Document ([ordered]@{
            state = 'failed'
            reason = $hyperVDiagnosticReason
        })
    }
    $hyperVDiagnosticEntry = [ordered]@{
        source = 'Hyper-V VM state from explicit provision owner vmName'
        archivePath = if (Test-Path -LiteralPath $hyperVDiagnosticPath) { 'diagnostics/hyperv-vm.json' } else { $null }
        state = $hyperVDiagnosticState
    }
    if ($hyperVDiagnosticReason) { $hyperVDiagnosticEntry['reason'] = $hyperVDiagnosticReason }
    if (Test-Path -LiteralPath $hyperVDiagnosticPath) {
        $hyperVDiagnosticEntry['sizeBytes'] = (Get-Item -LiteralPath $hyperVDiagnosticPath).Length
    }
    $files.Add($hyperVDiagnosticEntry)
    Write-JSONNoBOM -Path (Join-Path $staging 'manifest.json') -Document ([ordered]@{
        schemaVersion = 1
        operationId = $OperationId
        generatedAt = [DateTime]::UtcNow.ToString('o')
        platform = 'windows'
        files = $files
        excluded = @(
            (Join-Path $ProgramDataRoot 'config\platform-agent.json'),
            (Join-Path $ProgramDataRoot 'secrets'),
            'runtime product settings and datastore contents'
        )
    })
    Compress-Archive -LiteralPath $staging -DestinationPath $destination -CompressionLevel Optimal
    Protect-OwnerPath -Path $destination
    $file = Get-Item -LiteralPath $destination
    $artifact = [ordered]@{
        path = $file.FullName
        sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        sizeBytes = [Int64]$file.Length
    }
    Write-Workflow -State 'completed' -StartedAt $startedAt -Artifact $artifact -Failure $null
    exit 0
} catch {
    $reason = $_.Exception.Message
    Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
    Write-Workflow -State 'failed' -StartedAt $startedAt -Artifact $null -Failure ([ordered]@{
        kind = 'supportExportFailed'
        message = $reason
    })
    Write-Error $reason
    exit 1
} finally {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
}
