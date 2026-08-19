[CmdletBinding()]
param(
  [string]$Drive,
  [int]$ChunkSizeMB = 256,
  [ValidateRange(1, 99)][int]$ReservePercent = 3,
  [long]$ReserveMB = 1024,
  [switch]$Random,
  [switch]$KeepFiller,
  [switch]$Force
)

$ErrorActionPreference = "Stop"

# drive-fill.ps1
# Occupy free space on a selected drive with filler data, up to a percentage cap.
# Intended for sanitizing a drive before sale: after deleting your files,
# overwrite previously-deleted sectors with meaningless filler so they cannot
# be recovered. Stops while a breathing-room percentage of the disk is still
# free, so the OS stays stable (safe to run on the system drive). Pair with
# Windows "Reset this PC -> fully clean the drive" to cover the remainder.
# This does NOT touch existing files; it only consumes free space, then
# removes the filler again (unless -KeepFiller).

function Get-CandidateDrives {
  [System.IO.DriveInfo]::GetDrives() | Where-Object {
    $_.IsReady -and $_.DriveType -in @([System.IO.DriveType]::Fixed, [System.IO.DriveType]::Removable)
  }
}

function Format-Bytes([double]$Bytes) {
  $units = "B", "KB", "MB", "GB", "TB"
  $i = 0
  while ($Bytes -ge 1024 -and $i -lt $units.Count - 1) {
    $Bytes /= 1024
    $i++
  }
  "{0:N1} {1}" -f $Bytes, $units[$i]
}

function Get-DriveDisplay($DriveInfo) {
  $label = if ($DriveInfo.VolumeLabel) { $DriveInfo.VolumeLabel } else { "(no label)" }
  "{0}  {1,-16} {2} free / {3} total  [{4}]" -f `
    $DriveInfo.Name.TrimEnd('\'), $label,
  (Format-Bytes $DriveInfo.AvailableFreeSpace),
  (Format-Bytes $DriveInfo.TotalSize),
    $DriveInfo.DriveType
}

function Select-Drive([string]$Requested) {
  $drives = @(Get-CandidateDrives)
  if ($drives.Count -eq 0) { throw "No ready fixed/removable drives found." }

  if ($Requested) {
    $needle = $Requested.TrimEnd('\', ':').ToUpperInvariant()
    $match = @($drives | Where-Object { $_.Name.TrimEnd('\', ':').ToUpperInvariant() -eq $needle })
    if ($match.Count -eq 0) { throw "Drive not found: $Requested" }
    return $match[0]
  }

  $fzf = Get-Command fzf.exe -ErrorAction SilentlyContinue
  if ($fzf) {
    $map = @{}
    foreach ($d in $drives) { $map[(Get-DriveDisplay $d)] = $d }
    $selection = $map.Keys | & $fzf.Source --prompt "fill drive > " --height "40%" --reverse
    if (-not $selection) { return $null }
    return $map[$selection]
  }

  $drives | ForEach-Object -Begin { $i = 1 } -Process {
    [pscustomobject]@{ Index = $i; Drive = Get-DriveDisplay $_ }
    $i++
  } | Format-Table -AutoSize
  $choice = Read-Host "drive #"
  if (-not $choice) { return $null }
  $index = 0
  if (-not [int]::TryParse($choice, [ref]$index) -or $index -lt 1 -or $index -gt $drives.Count) {
    throw "Invalid selection: $choice"
  }
  return $drives[$index - 1]
}

$selected = Select-Drive $Drive
if (-not $selected) {
  Write-Host "No drive selected."
  return
}

$root = $selected.Name
$fillerDir = Join-Path $root "__forge_fill__"

# Keep the larger of: an absolute MB floor, or a percentage of total capacity.
# The percentage guarantees the OS always has breathing room, even on huge drives.
$reserveBytes = [long][Math]::Max(
  [long]($ReserveMB * 1MB),
  [long][Math]::Ceiling($selected.TotalSize * ($ReservePercent / 100.0))
)

Write-Host ""
Write-Host "Selected drive : $($selected.Name.TrimEnd('\'))"
Write-Host "Total size     : $(Format-Bytes $selected.TotalSize)"
Write-Host "Free space     : $(Format-Bytes $selected.AvailableFreeSpace)"
Write-Host "Reserve (keep) : $(Format-Bytes $reserveBytes)  (~$ReservePercent% of disk, min ${ReserveMB}MB)"
Write-Host "Filler folder  : $fillerDir"
Write-Host "Mode           : $(if ($Random) { 'random per chunk (slower, more entropy)' } else { 'single random buffer reused (fast)' })"
Write-Host ""

if ($selected.AvailableFreeSpace -le $reserveBytes) {
  Write-Host "Free space is already at or below the reserve target. Nothing to do."
  return
}

if (-not $Force) {
  Write-Warning "This will write filler until only ~$ReservePercent% of $($selected.Name.TrimEnd('\')) remains free."
  Write-Warning "Existing files are not modified. Filler is removed at the end unless -KeepFiller is set."
  $answer = Read-Host "Type the drive letter to confirm (e.g. $($selected.Name.Substring(0,1)))"
  if ($answer.Trim().ToUpperInvariant() -ne $selected.Name.Substring(0, 1).ToUpperInvariant()) {
    Write-Host "Aborted."
    return
  }
}

$chunkBytes = [long]$ChunkSizeMB * 1MB
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$buffer = New-Object byte[] $chunkBytes
$rng.GetBytes($buffer)

if (-not (Test-Path -LiteralPath $fillerDir)) {
  New-Item -ItemType Directory -Path $fillerDir | Out-Null
}

$totalWritten = [long]0
$fileIndex = 0
$sw = [System.Diagnostics.Stopwatch]::StartNew()

try {
  while ($true) {
    $drive = New-Object System.IO.DriveInfo($root)
    $free = [long]$drive.AvailableFreeSpace
    if ($free -le $reserveBytes) { break }

    $writeSize = [long][Math]::Min($chunkBytes, $free - $reserveBytes)
    if ($writeSize -le 0) { break }

    $fileIndex++
    $path = Join-Path $fillerDir ("fill_{0:D5}.bin" -f $fileIndex)
    $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
    try {
      $remaining = $writeSize
      while ($remaining -gt 0) {
        $part = [int][Math]::Min([long]$buffer.Length, $remaining)
        if ($Random) { $rng.GetBytes($buffer) }
        $stream.Write($buffer, 0, $part)
        $remaining -= $part
      }
      $stream.Flush($true)
    }
    finally {
      $stream.Dispose()
    }

    $totalWritten += $writeSize
    $rate = if ($sw.Elapsed.TotalSeconds -gt 0) { $totalWritten / $sw.Elapsed.TotalSeconds } else { 0 }
    $nowFree = [long](New-Object System.IO.DriveInfo($root)).AvailableFreeSpace
    $remaining = [long][Math]::Max(0, $nowFree - $reserveBytes)
    $eta = if ($rate -gt 0) { [TimeSpan]::FromSeconds($remaining / $rate) } else { [TimeSpan]::Zero }
    Write-Host ("  wrote {0} total  |  {1}/s  |  {2} free  |  ETA {3:hh\:mm\:ss}" -f `
      (Format-Bytes $totalWritten), (Format-Bytes $rate), (Format-Bytes $nowFree), $eta)
  }
}
catch [System.IO.IOException] {
  Write-Host "Drive is full (IOException): $($_.Exception.Message)"
}
finally {
  $sw.Stop()
  $rng.Dispose()
}

Write-Host ""
Write-Host ("Done. Filler written: {0} in {1:N0}s." -f (Format-Bytes $totalWritten), $sw.Elapsed.TotalSeconds)

if ($KeepFiller) {
  Write-Host "Filler kept at: $fillerDir"
}
else {
  Write-Host "Removing filler..."
  Remove-Item -LiteralPath $fillerDir -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host "Filler removed. Free space reclaimed."
}
