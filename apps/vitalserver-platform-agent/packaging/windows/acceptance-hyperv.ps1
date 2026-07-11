param(
    [Parameter(Mandatory = $true)]
    [string]$PlatformVersion,
    [Parameter(Mandatory = $true)]
    [string]$RuntimeBundleVersion,
    [Parameter(Mandatory = $true)]
    [string]$ReleaseManifestPath,
    [Parameter(Mandatory = $true)]
    [string]$APITokenPath,
    [Parameter(Mandatory = $true)]
    [string]$RuntimeProviderDocumentPath,
    [Parameter(Mandatory = $true)]
    [string]$HyperVImageManifestPath,
    [Parameter(Mandatory = $true)]
    [string]$OutputManifestPath,
    [string]$BaseURL = "http://127.0.0.1:18321",
    [int]$TimeoutSeconds = 360
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$runID = [Guid]::NewGuid().ToString()
$startedAt = [DateTime]::UtcNow
$stages = [System.Collections.Generic.List[object]]::new()
$imageManifest = $null
$imageManifestSHA256 = $null
$imageCompileRunId = $null
$hostBootSessionId = $null
$releaseInputs = $null
$releaseManifestSHA256 = $null
$supportExportOperationId = $null
$supportArtifactSHA256 = $null
$supportArtifactSizeBytes = $null

function Add-Stage {
    param([string]$Name, [string]$Status, [string]$Message)
    $stages.Add([ordered]@{
        name = $Name
        status = $Status
        message = $Message
        observedAt = [DateTime]::UtcNow.ToString("o")
    })
}

function Write-AcceptanceManifest {
    param([string]$Status, [string]$FailureStage, [string]$FailureReason)
    $manifest = [ordered]@{
        schemaVersion = 1
        runId = $runID
        platform = "windows-hyperv-amd64"
        platformVersion = $PlatformVersion
        runtimeBundleVersion = $RuntimeBundleVersion
        status = $Status
        startedAt = $startedAt.ToString("o")
        completedAt = [DateTime]::UtcNow.ToString("o")
        stages = $stages
        failureStage = if ($FailureStage) { $FailureStage } else { $null }
        failureReason = if ($FailureReason) { $FailureReason } else { $null }
        runtimeProviderDocumentPath = $RuntimeProviderDocumentPath
        hyperVImageManifestPath = $HyperVImageManifestPath
        hyperVImageManifestSHA256 = $imageManifestSHA256
        imageCompileRunId = $imageCompileRunId
        hostBootSessionId = $hostBootSessionId
        releaseInputs = $releaseInputs
        releaseManifestSHA256 = $releaseManifestSHA256
        supportExportOperationId = $supportExportOperationId
        supportArtifactSHA256 = $supportArtifactSHA256
        supportArtifactSizeBytes = $supportArtifactSizeBytes
    }
    $directory = Split-Path -Parent $OutputManifestPath
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporary = "$OutputManifestPath.tmp.$PID"
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $OutputManifestPath -Force
}

function Wait-RuntimeProviderState {
    param([string]$ExpectedState, [DateTime]$Deadline)
    $lastRead = $null
    while ([DateTime]::UtcNow -lt $Deadline) {
        try {
            if (-not (Test-Path -LiteralPath $RuntimeProviderDocumentPath -PathType Leaf)) {
                throw "Runtime Provider document is missing."
            }
            $document = Get-Content -LiteralPath $RuntimeProviderDocumentPath -Raw | ConvertFrom-Json
            if ($document.schemaVersion -ne 1) {
                throw "Runtime Provider schemaVersion is unsupported: $($document.schemaVersion)"
            }
            if ($document.state -eq "failed") {
                throw "Runtime Provider reported failed terminalReason=$($document.terminalReason) message=$($document.message)"
            }
            if ($document.state -eq $ExpectedState) {
                return $document
            }
            $lastRead = "state=$($document.state)"
        } catch {
            $lastRead = $_.Exception.Message
        }
        Start-Sleep -Seconds 1
    }
    throw "Runtime Provider did not reach expected state=$ExpectedState lastRead=$lastRead"
}

$currentStage = "preflight"
try {
    if ($PlatformVersion -notmatch '^[A-Za-z0-9._+-]+$' -or $RuntimeBundleVersion -notmatch '^[A-Za-z0-9._+-]+$') {
        throw "Windows acceptance release identity is invalid platformVersion=$PlatformVersion runtimeBundleVersion=$RuntimeBundleVersion"
    }
    $hostBootSessionId = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString("o")
    if (-not $hostBootSessionId) {
        throw "Windows host boot session owner is unavailable."
    }
    if (-not (Test-Path -LiteralPath $APITokenPath -PathType Leaf)) {
        throw "Platform API token owner file is missing: $APITokenPath"
    }
    if (-not (Test-Path -LiteralPath $HyperVImageManifestPath -PathType Leaf)) {
        throw "Hyper-V image manifest is missing: $HyperVImageManifestPath"
    }
    if (-not (Test-Path -LiteralPath $ReleaseManifestPath -PathType Leaf)) {
        throw "Installed release manifest is missing: $ReleaseManifestPath"
    }
    $installedRelease = Get-Content -LiteralPath $ReleaseManifestPath -Raw | ConvertFrom-Json
    if ($installedRelease.schemaVersion -ne 1 -or $installedRelease.platformVersion -ne $PlatformVersion -or $installedRelease.runtimeBundleVersion -ne $RuntimeBundleVersion -or $installedRelease.target.os -ne "windows" -or $installedRelease.target.architecture -ne "amd64" -or $installedRelease.target.provider -ne "hyperv") {
        throw "Installed release manifest does not match Windows acceptance target path=$ReleaseManifestPath"
    }
    $releaseManifestSHA256 = (Get-FileHash -LiteralPath $ReleaseManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $releaseInputs = [ordered]@{
        platformAgentSHA256 = [string]$installedRelease.inputs.platformAgentSHA256
        runtimeProviderSHA256 = [string]$installedRelease.inputs.runtimeProviderSHA256
        pwaTreeSHA256 = [string]$installedRelease.inputs.pwaTreeSHA256
        hyperVImageManifestSHA256 = [string]$installedRelease.inputs.hyperVImageManifestSHA256
        packagingTreeSHA256 = [string]$installedRelease.inputs.packagingTreeSHA256
    }
    if ($releaseInputs.Values | Where-Object { $_ -notmatch '^[0-9a-f]{64}$' }) {
        throw "Installed release manifest component input hashes are invalid path=$ReleaseManifestPath"
    }
    $imageManifest = Get-Content -LiteralPath $HyperVImageManifestPath -Raw | ConvertFrom-Json
    if ($imageManifest.schemaVersion -ne 1 -or $imageManifest.state -ne "compiled" -or $imageManifest.architecture -ne "amd64") {
        throw "Hyper-V image manifest is not a compiled amd64 image: $HyperVImageManifestPath"
    }
    $imageManifestSHA256 = (Get-FileHash -LiteralPath $HyperVImageManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $imageCompileRunId = $imageManifest.runId
    $apiToken = (Get-Content -LiteralPath $APITokenPath -Raw).Trim()
    if (-not $apiToken) {
        throw "Platform API token owner file is empty: $APITokenPath"
    }
    Add-Stage -Name $currentStage -Status "passed" -Message "Acceptance inputs are available."

    $currentStage = "runtime-provider-running"
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $lastProviderError = $null
    $provider = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            if (-not (Test-Path -LiteralPath $RuntimeProviderDocumentPath -PathType Leaf)) {
                throw "Runtime Provider document is missing."
            }
            $provider = Get-Content -LiteralPath $RuntimeProviderDocumentPath -Raw | ConvertFrom-Json
            if ($provider.schemaVersion -ne 1) {
                throw "Runtime Provider schemaVersion is unsupported: $($provider.schemaVersion)"
            }
            if ($provider.state -eq "failed") {
                throw "Runtime Provider reported failed terminalReason=$($provider.terminalReason) message=$($provider.message)"
            }
            if ($provider.state -eq "running") {
                break
            }
            $lastProviderError = "Runtime Provider state is $($provider.state)"
        } catch {
            $lastProviderError = $_.Exception.Message
        }
        Start-Sleep -Seconds 1
    }
    if ($null -eq $provider -or $provider.state -ne "running") {
        throw "Runtime Provider did not reach running before deadline lastRead=$lastProviderError"
    }
    Add-Stage -Name $currentStage -Status "passed" -Message "Runtime Provider reported running with explicit lifecycle state."

    $headers = @{ Authorization = "Bearer $apiToken" }
    $currentStage = "platform-contract"
    $platform = Invoke-RestMethod -Method Get -Uri "$BaseURL/platform" -Headers $headers -TimeoutSec 10
    if (-not $platform.runtimeInstallationState -or $null -eq $platform.services -or $null -eq $platform.readIssues) {
        throw "Platform response is missing required owner fields."
    }
    $requiredRoles = @("runtime-provider", "public-proxy", "log-sync", "sleep-prevention", "watchdog")
    $actualRoles = @($platform.services | ForEach-Object { $_.role } | Sort-Object -Unique)
    if (Compare-Object -ReferenceObject ($requiredRoles | Sort-Object) -DifferenceObject $actualRoles) {
        throw "Platform service roles differ expected=$($requiredRoles -join ',') actual=$($actualRoles -join ',')"
    }
    Add-Stage -Name $currentStage -Status "passed" -Message "Platform owner contract is complete."

    $currentStage = "runtime-capabilities"
    $capabilities = Invoke-RestMethod -Method Get -Uri "$BaseURL/runtime/capabilities" -Headers $headers -TimeoutSec 10
    if ($capabilities.schemaVersion -ne 1 -or $null -eq $capabilities.capabilities) {
        throw "Runtime capabilities response is incomplete."
    }
    $requiredRuntimeCapabilities = @("services:list", "settings:get", "settings:apply", "admin-password:apply", "redis-relay:settings:get", "redis-relay:settings:apply")
    $missingRuntimeCapabilities = @($requiredRuntimeCapabilities | Where-Object { $_ -notin $capabilities.capabilities })
    if ($missingRuntimeCapabilities.Count -gt 0) {
        throw "Runtime capabilities are missing: $($missingRuntimeCapabilities -join ',')"
    }
    Add-Stage -Name $currentStage -Status "passed" -Message "Runtime Controller capabilities are available."

    $currentStage = "runtime-services"
    $services = Invoke-RestMethod -Method Get -Uri "$BaseURL/runtime/services" -Headers $headers -TimeoutSec 10
    if ($null -eq $services.services -or @($services.services).Count -eq 0) {
        throw "Runtime Controller service list is empty or missing."
    }
    Add-Stage -Name $currentStage -Status "passed" -Message "Runtime Controller service list is non-empty."

    $currentStage = "runtime-stack"
    $stack = Invoke-RestMethod -Method Get -Uri "$BaseURL/runtime/stack" -Headers $headers -TimeoutSec 20
    if (-not $stack.state -or -not $stack.observedAt -or $null -eq $stack.services -or $null -eq $stack.probeErrors) {
        throw "Runtime stack response is missing explicit state fields."
    }
    $failedServices = @($stack.services | Where-Object { $_.state -in @("exited", "restarting", "failed") })
    if ($failedServices.Count -gt 0) {
        throw "Runtime stack contains failed services: $($failedServices.service -join ',')"
    }
    Add-Stage -Name $currentStage -Status "passed" -Message "Runtime stack has no failed required service."

    $currentStage = "runtime-settings"
    $settings = Invoke-RestMethod -Method Get -Uri "$BaseURL/runtime/settings" -Headers $headers -TimeoutSec 10
    if ($settings.state -ne "loaded" -or $null -eq $settings.settings -or $null -ne $settings.readError) {
        throw "Runtime settings owner is not loaded state=$($settings.state) readError=$($settings.readError)"
    }
    Add-Stage -Name $currentStage -Status "passed" -Message "Runtime Controller settings owner is loaded."

    $currentStage = "redis-relay-settings"
    $relaySettings = Invoke-RestMethod -Method Get -Uri "$BaseURL/runtime/redis-relay/settings" -Headers $headers -TimeoutSec 10
    if ($relaySettings.state -ne "loaded" -or $null -eq $relaySettings.settings -or $null -ne $relaySettings.readError) {
        throw "Redis Relay settings owner is not loaded state=$($relaySettings.state) readError=$($relaySettings.readError)"
    }
    $relayTargetFields = @($relaySettings.settings.target.PSObject.Properties.Name)
    if ("passwordConfigured" -notin $relayTargetFields -or "password" -in $relayTargetFields) {
        throw "Redis Relay settings secret state is not explicit or exposes password material."
    }
    Add-Stage -Name $currentStage -Status "passed" -Message "Runtime Controller Redis Relay settings owner is loaded without secret material."

    $currentStage = "runtime-events"
    $events = Invoke-RestMethod -Method Get -Uri "$BaseURL/runtime/events?limit=10" -Headers $headers -TimeoutSec 10
    $eventFields = @($events.PSObject.Properties.Name)
    if ("events" -notin $eventFields -or "nextCursor" -notin $eventFields -or "matchingCount" -notin $eventFields) {
        throw "Runtime event history is missing explicit page fields."
    }
    Add-Stage -Name $currentStage -Status "passed" -Message "Runtime Controller event history contract is available."

    $currentStage = "product-pwa"
    $pwa = Invoke-WebRequest -Method Get -Uri "$BaseURL/" -TimeoutSec 10 -UseBasicParsing
    if ($pwa.StatusCode -ne 200 -or -not $pwa.Content) {
        throw "Product PWA is unavailable status=$($pwa.StatusCode)"
    }
    Add-Stage -Name $currentStage -Status "passed" -Message "Common product PWA is served by Platform Agent."

    $currentStage = "platform-support-export"
    $platformCapabilities = Invoke-RestMethod -Method Get -Uri "$BaseURL/platform/capabilities" -Headers $headers -TimeoutSec 10
    if ($platformCapabilities.canExportLogs -ne $true) {
        throw "Platform support export capability is not available."
    }
    $support = Invoke-RestMethod -Method Post -Uri "$BaseURL/platform/support-exports" -Headers $headers -TimeoutSec 30
    if ($support.kind -ne 'support-export' -or $support.state -ne 'accepted' -or -not $support.operationId) {
        throw "Support export was not accepted response=$($support | ConvertTo-Json -Compress)"
    }
    $supportDeadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $supportOperation = $null
    while ([DateTime]::UtcNow -lt $supportDeadline) {
        $resource = Invoke-RestMethod -Method Get -Uri "$BaseURL/platform/workflows/current" -Headers $headers -TimeoutSec 10
        if ($resource.state -ne 'loaded' -or $null -eq $resource.operation) {
            throw "Support export workflow owner is not loaded."
        }
        $supportOperation = $resource.operation
        if ($supportOperation.operationId -ne $support.operationId) {
            throw "Support export workflow identity changed expected=$($support.operationId) actual=$($supportOperation.operationId)"
        }
        if ($supportOperation.state -eq 'completed') { break }
        if ($supportOperation.state -eq 'failed') {
            throw "Support export failed evidence=$($supportOperation.failure.message)"
        }
        Start-Sleep -Seconds 1
    }
    if ($null -eq $supportOperation -or $supportOperation.state -ne 'completed' -or $null -eq $supportOperation.artifact) {
        throw "Support export did not complete with artifact evidence operationId=$($support.operationId)"
    }
    $artifactPath = [IO.Path]::GetFullPath([string]$supportOperation.artifact.path)
    $supportRoot = [IO.Path]::GetFullPath((Join-Path $env:ProgramData 'VitalServer\support')).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if (-not $artifactPath.StartsWith($supportRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
        throw "Support artifact is outside managed root or missing path=$artifactPath"
    }
    $artifactFile = Get-Item -LiteralPath $artifactPath
    $artifactDigest = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($supportOperation.artifact.sha256 -ne $artifactDigest -or [Int64]$supportOperation.artifact.sizeBytes -ne [Int64]$artifactFile.Length) {
        throw "Support artifact digest or byte size differs from workflow evidence."
    }
    $supportExportOperationId = [string]$support.operationId
    $supportArtifactSHA256 = $artifactDigest
    $supportArtifactSizeBytes = [Int64]$artifactFile.Length
    Add-Stage -Name $currentStage -Status "passed" -Message "Managed support artifact completed operationId=$($support.operationId) sha256=$artifactDigest."

    $currentStage = "runtime-provider-stop"
    $stop = Invoke-RestMethod -Method Post -Uri "$BaseURL/platform/runtime-provider/stop" -Headers $headers -TimeoutSec $TimeoutSeconds
    if ($stop.action -ne "stop" -or $stop.state -ne "completed" -or $null -ne $stop.failure) {
        throw "Runtime Provider stop command failed action=$($stop.action) state=$($stop.state) failure=$($stop.failure.message)"
    }
    $null = Wait-RuntimeProviderState -ExpectedState "stopped" -Deadline ([DateTime]::UtcNow.AddSeconds($TimeoutSeconds))
    Add-Stage -Name $currentStage -Status "passed" -Message "Windows Service and Hyper-V Runtime Provider stopped through the Platform contract."

    $currentStage = "runtime-provider-start"
    $start = Invoke-RestMethod -Method Post -Uri "$BaseURL/platform/runtime-provider/start" -Headers $headers -TimeoutSec $TimeoutSeconds
    if ($start.action -ne "start" -or $start.state -ne "completed" -or $null -ne $start.failure) {
        throw "Runtime Provider start command failed action=$($start.action) state=$($start.state) failure=$($start.failure.message)"
    }
    $null = Wait-RuntimeProviderState -ExpectedState "running" -Deadline ([DateTime]::UtcNow.AddSeconds($TimeoutSeconds))
    Add-Stage -Name $currentStage -Status "passed" -Message "Windows Service and Hyper-V Runtime Provider restarted through the Platform contract."

    $currentStage = "runtime-after-provider-restart"
    $runtimeAfterRestart = Invoke-RestMethod -Method Get -Uri "$BaseURL/runtime/capabilities" -Headers $headers -TimeoutSec $TimeoutSeconds
    if ($runtimeAfterRestart.schemaVersion -ne 1 -or $null -eq $runtimeAfterRestart.capabilities) {
        throw "Runtime Controller did not become available after Runtime Provider restart."
    }
    Add-Stage -Name $currentStage -Status "passed" -Message "Runtime Controller is available after the Hyper-V stop/start round trip."

    Write-AcceptanceManifest -Status "passed" -FailureStage "" -FailureReason ""
    Write-Output "VitalServer Windows Hyper-V acceptance passed runId=$runID manifest=$OutputManifestPath"
} catch {
    $reason = $_.Exception.Message
    Add-Stage -Name $currentStage -Status "failed" -Message $reason
    Write-AcceptanceManifest -Status "failed" -FailureStage $currentStage -FailureReason $reason
    throw "VitalServer Windows Hyper-V acceptance failed runId=$runID stage=$currentStage reason=$reason manifest=$OutputManifestPath"
}
