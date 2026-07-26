param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^vitalserver-[A-Za-z0-9_]+-[0-9a-f]{12}$')]
    [string]$TaskName,
    [Parameter(Mandatory = $true)]
    [string]$Tool,
    [Parameter(Mandatory = $true)]
    [string]$ArgumentsBase64,
    [Parameter(Mandatory = $true)]
    [string]$PowerShellExecutable,
    [switch]$RunTask
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Decode-Arguments {
    try {
        $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ArgumentsBase64))
        $values = @($json | ConvertFrom-Json)
    } catch {
        throw "Windows workflow task arguments decode failed: $($_.Exception.Message)"
    }
    foreach ($value in $values) {
        if ($value -isnot [string]) {
            throw "Windows workflow task arguments must all be strings."
        }
    }
    return [string[]]$values
}

function Argument-Value {
    param([string[]]$Arguments, [string]$Name)
    for ($index = 0; $index -lt $Arguments.Count - 1; $index += 1) {
        if ($Arguments[$index] -eq $Name) {
            return $Arguments[$index + 1]
        }
    }
    return $null
}

function Write-TaskFailure {
    param([string[]]$Arguments, [string]$Reason)
    $operationID = Argument-Value -Arguments $Arguments -Name "-OperationId"
    $operationPath = Argument-Value -Arguments $Arguments -Name "-OperationDocument"
    if (-not $operationID -or -not $operationPath -or -not (Test-Path -LiteralPath $operationPath -PathType Leaf)) {
        return
    }
    try {
        $operation = Get-Content -LiteralPath $operationPath -Raw | ConvertFrom-Json
        if ($operation.schemaVersion -ne 1 -or $operation.operationId -ne $operationID) {
            return
        }
        $operation.state = "failed"
        $operation.updatedAt = [DateTime]::UtcNow.ToString("o")
        $operation.failure = [ordered]@{ kind = "workflowTaskFailed"; message = $Reason }
        $temporary = "$operationPath.tmp.$PID"
        $json = $operation | ConvertTo-Json -Depth 8
        [IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $operationPath -Force
    } catch {
        Write-Warning "Windows workflow task failure owner write failed operationId=$operationID path=$operationPath reason=$($_.Exception.Message)"
    }
}

$toolArguments = Decode-Arguments
if ($RunTask) {
    $exitCode = 1
    try {
        if (-not (Test-Path -LiteralPath $Tool -PathType Leaf)) {
            throw "Windows workflow tool is missing path=$Tool"
        }
        & $PowerShellExecutable -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Tool @toolArguments
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            throw "Windows workflow tool failed path=$Tool exitCode=$exitCode"
        }
    } catch {
        $reason = $_.Exception.Message
        Write-TaskFailure -Arguments $toolArguments -Reason $reason
        Write-Error $reason
        $exitCode = 1
    } finally {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
    exit $exitCode
}

if (-not (Test-Path -LiteralPath $PowerShellExecutable -PathType Leaf)) {
    throw "Windows workflow PowerShell executable is missing path=$PowerShellExecutable"
}
if (-not (Test-Path -LiteralPath $Tool -PathType Leaf)) {
    throw "Windows workflow tool is missing path=$Tool"
}
$schedulerScript = $MyInvocation.MyCommand.Path
if (-not $schedulerScript) {
    throw "Windows workflow scheduler script path is unavailable."
}

# Windows paths cannot contain a double quote. Quoting these fixed path values
# is therefore sufficient; workflow arguments remain base64 JSON until RunTask.
$taskArgument = @(
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy Bypass",
    "-File `"$schedulerScript`"",
    "-RunTask",
    "-TaskName `"$TaskName`"",
    "-Tool `"$Tool`"",
    "-ArgumentsBase64 $ArgumentsBase64",
    "-PowerShellExecutable `"$PowerShellExecutable`""
) -join " "
$action = New-ScheduledTaskAction -Execute $PowerShellExecutable -Argument $taskArgument
$trigger = New-ScheduledTaskTrigger -Once -At ([DateTime]::Now.AddMinutes(1))
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 6) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName
Write-Output "Windows Platform workflow task started task=$TaskName tool=$Tool"
