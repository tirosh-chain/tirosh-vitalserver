Set-StrictMode -Version Latest

function Expand-VitalServerWindowsBundle {
    param([Parameter(Mandatory = $true)][string]$ArchivePath, [Parameter(Mandatory = $true)][string]$OutputDirectory)
    if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
        throw "Windows update bundle is missing path=$ArchivePath"
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    $outputRoot = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    [UInt64]$expandedBytes = 0
    try {
        if ($archive.Entries.Count -eq 0 -or $archive.Entries.Count -gt 100000) {
            throw "Windows update bundle entry count is invalid count=$($archive.Entries.Count)"
        }
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName
            if (-not $name -or $name.Contains('\') -or $name.Contains('//') -or $name.StartsWith('/') -or -not $name.StartsWith('VitalServer-Windows/', [StringComparison]::Ordinal)) {
                throw "Windows update bundle entry path is unsafe path=$name"
            }
            $parts = @($name.Split('/') | Where-Object { $_ -ne '' })
            if ($parts.Count -lt 1 -or $parts[0] -ne 'VitalServer-Windows' -or @($parts | Where-Object { $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) {
                throw "Windows update bundle entry path is unsafe path=$name"
            }
            if (-not $seen.Add($name)) {
                throw "Windows update bundle entry is duplicated path=$name"
            }
            $externalAttributes = [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$entry.ExternalAttributes), 0)
            $unixMode = ($externalAttributes -shr 16) -band 0xF000
            if ($unixMode -notin @(0, 0x4000, 0x8000)) {
                throw "Windows update bundle entry type is unsupported path=$name mode=$unixMode"
            }
            $destination = [IO.Path]::GetFullPath((Join-Path $outputRoot ($name.Replace([char]'/', [IO.Path]::DirectorySeparatorChar))))
            if (-not $destination.StartsWith($outputRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Windows update bundle entry escapes extraction root path=$name"
            }
            if ($name.EndsWith('/')) {
                New-Item -ItemType Directory -Path $destination -Force | Out-Null
                continue
            }
            $expandedBytes += [UInt64]$entry.Length
            if ($expandedBytes -gt 107374182400) {
                throw "Windows update bundle expanded size exceeds 100 GiB"
            }
            $parent = Split-Path -Parent $destination
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
            $source = $entry.Open()
            $target = [IO.File]::Open($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try {
                $source.CopyTo($target)
                $target.Flush($true)
            } finally {
                $target.Dispose()
                $source.Dispose()
            }
        }
    } finally {
        $archive.Dispose()
    }
    $bundleRoot = Join-Path $outputRoot 'VitalServer-Windows'
    if (-not (Test-Path -LiteralPath $bundleRoot -PathType Container)) {
        throw "Windows update bundle root directory is missing after extraction"
    }
    return $bundleRoot
}

function Assert-VitalServerWindowsBundle {
    param([Parameter(Mandatory = $true)][string]$BundleRoot)
    $rootPath = [IO.Path]::GetFullPath($BundleRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $checksumPath = Join-Path $rootPath 'checksums.sha256'
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
        $candidate = [IO.Path]::GetFullPath((Join-Path $rootPath $relative.Replace([char]'/', [IO.Path]::DirectorySeparatorChar)))
        if (-not $candidate.StartsWith($rootPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "Windows bundle checksum member is missing or unsafe path=$relative"
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

function Read-VitalServerWindowsRelease {
    param([Parameter(Mandatory = $true)][string]$BundleRoot)
    $path = Join-Path $BundleRoot 'release.json'
    try {
        $release = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    } catch {
        throw "Windows release owner decode failed path=$path reason=$($_.Exception.Message)"
    }
    if ($release.schemaVersion -ne 1 -or $release.state -ne 'releaseCandidate' -or $release.target.os -ne 'windows' -or $release.target.architecture -ne 'amd64' -or $release.target.provider -ne 'hyperv') {
        throw "Windows release owner is not a windows/amd64 Hyper-V release path=$path"
    }
    if ([string]$release.platformVersion -notmatch '^[A-Za-z0-9._+-]+$' -or [string]$release.runtimeBundleVersion -notmatch '^[A-Za-z0-9._+-]+$') {
        throw "Windows release identity is invalid path=$path"
    }
    return $release
}

Export-ModuleMember -Function Expand-VitalServerWindowsBundle, Assert-VitalServerWindowsBundle, Read-VitalServerWindowsRelease
