[CmdletBinding()]
param(
  [string]$Name,
  [string]$LocalPath,
  [string]$ConfigPath,
  [switch]$TestConnection,
  [switch]$TraceConnection
)

$ErrorActionPreference = "Stop"
$windowsRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$forgeRoot = Split-Path -Parent $windowsRoot
$script:TraceFtpConnection = [bool]$TraceConnection

if (-not $ConfigPath) {
  $ConfigPath = Join-Path $forgeRoot "config-local\local-store.json"
}
if (-not $LocalPath) {
  $LocalPath = (Get-Location).Path
}

function Get-PropertyValue($Object, [string]$Name, $Default = $null) {
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($property -and $null -ne $property.Value -and "$($property.Value)" -ne "") {
    return $property.Value
  }
  return $Default
}

function Test-Truthy($Value) {
  if ($Value -is [bool]) { return $Value }
  if ($null -eq $Value) { return $false }
  return "$Value" -match "^(1|true|yes|on)$"
}

function Get-DefaultPort([string]$Protocol) {
  switch ($Protocol) {
    "ftps" { 990; break }
    default { 21; break }
  }
}

function Resolve-Endpoint($Connection) {
  $encrypt = Test-Truthy (Get-PropertyValue $Connection "encrypt")
  $protocol = (Get-PropertyValue $Connection "protocol" $(if ($encrypt) { "ftpes" } else { "ftp" })).ToString().ToLowerInvariant()
  $hostName = Get-PropertyValue $Connection "host"
  $server = Get-PropertyValue $Connection "server"
  $remotePath = (Get-PropertyValue $Connection "remotePath" "/").ToString()
  $port = Get-PropertyValue $Connection "port"

  if ($protocol -eq "ftpes") {
    $protocol = "ftp"
    $encrypt = $true
  } elseif ($protocol -eq "ftps") {
    $encrypt = $true
  } elseif ($protocol -ne "ftp") {
    throw "Windows ftp supports FTP/FTPS only, not '$protocol'."
  }

  if (-not $hostName -and $server) {
    $serverText = $server.ToString()
    if ($serverText -match "^[a-z][a-z0-9+.-]*://") {
      $uri = [System.Uri]$serverText
      $scheme = $uri.Scheme.ToLowerInvariant()
      if ($scheme -eq "ftpes") {
        $protocol = "ftp"
        $encrypt = $true
      } elseif ($scheme -eq "ftps") {
        $protocol = "ftps"
        $encrypt = $true
      } elseif ($scheme -eq "ftp") {
        $protocol = "ftp"
      } else {
        throw "Windows ftp supports FTP/FTPS only, not '$scheme'."
      }
      $hostName = $uri.Host
      if (-not $port -and -not $uri.IsDefaultPort) {
        $port = $uri.Port
      }
      if ($uri.AbsolutePath -and $uri.AbsolutePath -ne "/") {
        $remotePath = [System.Uri]::UnescapeDataString($uri.AbsolutePath)
      }
    } else {
      $serverParts = $serverText -split "/", 2
      $hostPart = $serverParts[0]
      if ($serverParts.Count -gt 1 -and $serverParts[1]) {
        $remotePath = "/$($serverParts[1])"
      }
      if ($hostPart -match "^(.+):(\d+)$") {
        $hostName = $Matches[1]
        if (-not $port) {
          $port = [int]$Matches[2]
        }
      } else {
        $hostName = $hostPart
      }
    }
  }

  if (-not $port) {
    $port = Get-DefaultPort $protocol
  }

  [pscustomobject]@{
    Protocol = $protocol
    HostName = $hostName
    Port = [int]$port
    EnableSsl = $encrypt
    RemotePath = Normalize-RemoteDirectory $remotePath
  }
}

function Normalize-RemoteDirectory([string]$Path) {
  if (-not $Path) { return "/" }
  $normalized = $Path.Replace("\", "/")
  if (-not $normalized.StartsWith("/")) {
    $normalized = "/$normalized"
  }
  if (-not $normalized.EndsWith("/")) {
    $normalized = "$normalized/"
  }
  while ($normalized -match "//") {
    $normalized = $normalized.Replace("//", "/")
  }
  return $normalized
}

function Join-RemotePath([string]$Directory, [string]$Name, [switch]$AsDirectory) {
  $base = Normalize-RemoteDirectory $Directory
  $path = "$base$Name"
  if ($AsDirectory -and -not $path.EndsWith("/")) {
    $path = "$path/"
  }
  return $path
}

function Get-RemoteParent([string]$Path) {
  $trimmed = (Normalize-RemoteDirectory $Path).TrimEnd("/")
  if (-not $trimmed -or $trimmed -eq "") { return "/" }
  $parent = Split-Path -Path $trimmed -Parent
  if (-not $parent -or $parent -eq "\") { return "/" }
  return Normalize-RemoteDirectory ($parent.Replace("\", "/"))
}

function ConvertTo-FtpUriPath([string]$Path) {
  $isDirectory = $Path.EndsWith("/")
  $parts = $Path.Replace("\", "/").Split("/", [System.StringSplitOptions]::RemoveEmptyEntries) |
    ForEach-Object { [System.Uri]::EscapeDataString($_) }
  $encoded = "/" + ($parts -join "/")
  if ($isDirectory -and -not $encoded.EndsWith("/")) {
    $encoded = "$encoded/"
  }
  return $encoded
}

function Read-FtpReply($Control) {
  $line = $Control.Reader.ReadLine()
  if ($null -eq $line) {
    throw "FTP server closed the connection."
  }
  if ($line -notmatch "^(?<code>\d{3})(?<sep>[ -])(?<text>.*)$") {
    throw "Unexpected FTP reply: $line"
  }
  $code = [int]$Matches.code
  $text = @($line)
  if ($Matches.sep -eq "-") {
    do {
      $line = $Control.Reader.ReadLine()
      if ($null -eq $line) { break }
      $text += $line
    } while ($line -notmatch "^$code\s")
  }
  [pscustomobject]@{ Code = $code; Text = ($text -join "`n") }
}

function Write-FtpTrace([string]$Message) {
  if ($script:TraceFtpConnection) {
    Write-Host "trace=$Message"
  }
}

function Assert-FtpReply($Reply, [int[]]$Expected, [string]$Action) {
  if ($Reply.Code -notin $Expected) {
    throw "$Action failed: $($Reply.Text)"
  }
}

function Send-FtpCommand($Control, [string]$Command, [int[]]$Expected, [string]$Action) {
  Write-FtpTrace $Action
  $Control.Writer.WriteLine($Command)
  $Control.Writer.Flush()
  $reply = Read-FtpReply $Control
  Write-FtpTrace "$Action code=$($reply.Code)"
  Assert-FtpReply $reply $Expected $Action
  return $reply
}

function New-FtpControlConnection($Session) {
  if ($Session.EnableSsl) {
    throw "Windows ftp currently supports plain FTP only for terminal panels."
  }
  $client = [System.Net.Sockets.TcpClient]::new()
  Write-FtpTrace "control-connect"
  $client.Connect($Session.HostName, $Session.Port)
  $stream = $client.GetStream()
  $encoding = [System.Text.Encoding]::ASCII
  $reader = [System.IO.StreamReader]::new($stream, $encoding)
  $writer = [System.IO.StreamWriter]::new($stream, $encoding)
  $writer.NewLine = "`r`n"
  $writer.AutoFlush = $true

  $control = [pscustomobject]@{ Client = $client; Stream = $stream; Reader = $reader; Writer = $writer }
  $welcome = Read-FtpReply $control
  Write-FtpTrace "welcome code=$($welcome.Code)"
  Assert-FtpReply $welcome @(120, 220) "FTP connect"
  $userReply = Send-FtpCommand $control "USER $($Session.User)" @(230, 331) "FTP user"
  if ($userReply.Code -eq 331) {
    Send-FtpCommand $control "PASS $($Session.Password)" @(230, 202) "FTP password" | Out-Null
  }
  Send-FtpCommand $control "TYPE I" @(200) "FTP binary mode" | Out-Null
  return $control
}

function Close-FtpControlConnection($Control) {
  if (-not $Control) { return }
  try { Send-FtpCommand $Control "QUIT" @(221, 226, 200) "FTP quit" | Out-Null } catch {}
  try { $Control.Writer.Dispose() } catch {}
  try { $Control.Reader.Dispose() } catch {}
  try { $Control.Stream.Dispose() } catch {}
  try { $Control.Client.Dispose() } catch {}
}

function Open-FtpDataConnection($Control) {
  $reply = Send-FtpCommand $Control "PASV" @(227) "FTP passive mode"
  if ($reply.Text -notmatch "\((?<data>\d+,\d+,\d+,\d+,\d+,\d+)\)") {
    throw "Could not parse FTP passive reply: $($reply.Text)"
  }
  $parts = $Matches.data.Split(",") | ForEach-Object { [int]$_ }
  $hostName = "{0}.{1}.{2}.{3}" -f $parts[0], $parts[1], $parts[2], $parts[3]
  $port = ($parts[4] * 256) + $parts[5]
  $dataClient = [System.Net.Sockets.TcpClient]::new()
  Write-FtpTrace "data-connect"
  $dataClient.Connect($hostName, $port)
  return $dataClient
}

function Invoke-FtpList($Session, [string]$Path) {
  $control = $null
  $dataClient = $null
  $reader = $null
  try {
    Write-FtpTrace "list-open-control"
    $control = New-FtpControlConnection $Session
    Write-FtpTrace "list-open-data"
    $dataClient = Open-FtpDataConnection $control
    Write-FtpTrace "list-command"
    Send-FtpCommand $control "LIST $Path" @(125, 150) "FTP list" | Out-Null
    Write-FtpTrace "list-read-data"
    $reader = [System.IO.StreamReader]::new($dataClient.GetStream(), [System.Text.Encoding]::UTF8)
    $text = $reader.ReadToEnd()
    Write-FtpTrace "list-read-data length=$($text.Length)"
    Assert-FtpReply (Read-FtpReply $control) @(226, 250) "FTP list complete"
    Write-FtpTrace "list-complete"
    return $text
  } finally {
    if ($reader) { $reader.Dispose() }
    if ($dataClient) { $dataClient.Dispose() }
    Close-FtpControlConnection $control
  }
}

function Parse-RemoteListLine([string]$Line) {
  if ($Line -match "^(?<perm>[dl-])\S*\s+\d+\s+\S+\s+\S+\s+(?<size>\d+)\s+\S+\s+\d+\s+[\d:]{4,5}\s+(?<name>.+)$") {
    return [pscustomobject]@{
      Name = $Matches.name
      IsDir = $Matches.perm -eq "d"
      Size = [int64]$Matches.size
    }
  }
  if ($Line -match "^\d{2}-\d{2}-\d{2}\s+\d{2}:\d{2}[AP]M\s+(?<dir><DIR>)?\s*(?<size>\d+)?\s+(?<name>.+)$") {
    return [pscustomobject]@{
      Name = $Matches.name
      IsDir = [bool]$Matches.dir
      Size = if ($Matches.size) { [int64]$Matches.size } else { 0 }
    }
  }
  if ($Line.Trim()) {
    return [pscustomobject]@{ Name = $Line.Trim(); IsDir = $false; Size = 0 }
  }
  return $null
}

function Get-RemoteItems($Session, [string]$Path) {
  try {
    $text = Invoke-FtpList $Session $Path
  } catch {
    throw "FTP listing failed for '$($Session.Display)': $($_.Exception.Message)"
  }
  $items = @(
    foreach ($line in ($text -split "`r?`n")) {
      $item = Parse-RemoteListLine $line
      if ($item -and $item.Name -notin @(".", "..")) { $item }
    }
  )
  @([pscustomobject]@{ Name = ".."; IsDir = $true; Size = 0; Parent = $true }) +
    @($items | Sort-Object @{ Expression = "IsDir"; Descending = $true }, Name)
}

function Get-LocalItems([string]$Path) {
  $items = Get-ChildItem -LiteralPath $Path -Force |
    Sort-Object @{ Expression = "PSIsContainer"; Descending = $true }, Name |
    ForEach-Object {
      [pscustomobject]@{
        Name = $_.Name
        IsDir = $_.PSIsContainer
        Size = if ($_.PSIsContainer) { 0 } else { $_.Length }
        FullName = $_.FullName
      }
    }
  @([pscustomobject]@{ Name = ".."; IsDir = $true; Size = 0; Parent = $true }) + @($items)
}

function Format-Size([int64]$Size, [bool]$IsDir) {
  if ($IsDir) { return "<DIR>" }
  if ($Size -ge 1GB) { return "{0:n1}G" -f ($Size / 1GB) }
  if ($Size -ge 1MB) { return "{0:n1}M" -f ($Size / 1MB) }
  if ($Size -ge 1KB) { return "{0:n1}K" -f ($Size / 1KB) }
  return "$Size"
}

function Clip([string]$Text, [int]$Width) {
  if ($Width -le 0) { return "" }
  if ($null -eq $Text) { $Text = "" }
  if ($Text.Length -le $Width) { return $Text.PadRight($Width) }
  if ($Width -le 1) { return $Text.Substring(0, $Width) }
  return ($Text.Substring(0, $Width - 1) + "~")
}

function Draw-PanelLine($Item, [int]$Width, [bool]$Selected, [bool]$Active) {
  $prefix = if ($Selected -and $Active) { ">" } elseif ($Selected) { "-" } else { " " }
  $kind = if ($Item.IsDir) { "/" } else { " " }
  $size = Format-Size $Item.Size $Item.IsDir
  Clip "$prefix$kind $($Item.Name) $size" $Width
}

function Write-FixedLine([string]$Text, [int]$Width, [bool]$Selected) {
  $line = Clip $Text $Width
  if ($Selected) {
    $previousForeground = [Console]::ForegroundColor
    $previousBackground = [Console]::BackgroundColor
    [Console]::ForegroundColor = [ConsoleColor]::Black
    [Console]::BackgroundColor = [ConsoleColor]::Cyan
    [Console]::Write($line)
    [Console]::ForegroundColor = $previousForeground
    [Console]::BackgroundColor = $previousBackground
  } else {
    [Console]::Write($line)
  }
}

function Set-FtpLayout($State) {
  try {
    $width = [Math]::Max([Console]::WindowWidth, 80)
    $height = [Math]::Max([Console]::WindowHeight, 20)
  } catch {
    $width = 120
    $height = 30
  }
  $State.Width = $width
  $State.Height = $height
  $State.LeftWidth = [Math]::Floor(($width - 3) / 2)
  $State.RightWidth = $width - $State.LeftWidth - 3
  $State.Rows = $height - 5
}

function Get-FtpPanelItem($State, [string]$Panel, [int]$AbsoluteIndex) {
  if ($Panel -eq "remote") {
    if ($AbsoluteIndex -lt $State.RemoteItems.Count) { return $State.RemoteItems[$AbsoluteIndex] }
  } else {
    if ($AbsoluteIndex -lt $State.LocalItems.Count) { return $State.LocalItems[$AbsoluteIndex] }
  }
  return $null
}

function Write-FtpPanelRow($State, [int]$Row, [string]$Panel) {
  $isRemote = $Panel -eq "remote"
  $width = if ($isRemote) { $State.LeftWidth } else { $State.RightWidth }
  $column = if ($isRemote) { 0 } else { $State.LeftWidth + 3 }
  $offset = if ($isRemote) { $State.RemoteOffset } else { $State.LocalOffset }
  $selectedIndex = if ($isRemote) { $State.RemoteIndex } else { $State.LocalIndex }
  $absoluteIndex = $offset + $Row
  $item = Get-FtpPanelItem $State $Panel $absoluteIndex
  $line = if ($item) {
    Draw-PanelLine $item $width ($absoluteIndex -eq $selectedIndex) ($State.Active -eq $Panel)
  } else {
    Clip "" $width
  }

  [Console]::SetCursorPosition($column, 2 + $Row)
  Write-FixedLine $line $width ($item -and $absoluteIndex -eq $selectedIndex -and $State.Active -eq $Panel)
}

function Write-FtpStatus($State) {
  [Console]::SetCursorPosition(0, $State.Height - 1)
  [Console]::Write((Clip $State.Message ($State.Width - 1)))
}

function Draw-FtpUi($State) {
  Set-FtpLayout $State
  [Console]::Clear()
  [Console]::SetCursorPosition(0, 0)

  $remoteTitle = "REMOTE $($State.RemotePath)"
  $localTitle = "LOCAL $($State.LocalPath)"
  [Console]::WriteLine("$(Clip $remoteTitle $State.LeftWidth) | $(Clip $localTitle $State.RightWidth)")
  [Console]::WriteLine("$(("-" * $State.LeftWidth)) | $(("-" * $State.RightWidth))")

  for ($i = 0; $i -lt $State.Rows; $i++) {
    Write-FtpPanelRow $State $i "remote"
    [Console]::SetCursorPosition($State.LeftWidth, 2 + $i)
    [Console]::Write(" | ")
    Write-FtpPanelRow $State $i "local"
  }

  [Console]::SetCursorPosition(0, $State.Height - 3)
  [Console]::WriteLine("$(("-" * $State.LeftWidth)) | $(("-" * $State.RightWidth))")
  [Console]::WriteLine("Tab switch  Enter open  Backspace parent  F5 download  F6 upload  PgUp/PgDn  R refresh  Q quit")
  Write-FtpStatus $State
  $State.LastWidth = $State.Width
  $State.LastHeight = $State.Height
}

function Get-VisibleRows {
  try {
    return [Math]::Max([Console]::WindowHeight, 20) - 5
  } catch {
    return 25
  }
}

function Ensure-SelectionVisible($State) {
  $rows = Get-VisibleRows
  if ($State.RemoteIndex -lt $State.RemoteOffset) {
    $State.RemoteOffset = $State.RemoteIndex
  }
  if ($State.RemoteIndex -ge ($State.RemoteOffset + $rows)) {
    $State.RemoteOffset = $State.RemoteIndex - $rows + 1
  }
  if ($State.LocalIndex -lt $State.LocalOffset) {
    $State.LocalOffset = $State.LocalIndex
  }
  if ($State.LocalIndex -ge ($State.LocalOffset + $rows)) {
    $State.LocalOffset = $State.LocalIndex - $rows + 1
  }
  $State.RemoteOffset = [Math]::Max(0, $State.RemoteOffset)
  $State.LocalOffset = [Math]::Max(0, $State.LocalOffset)
}

function Test-FuzzyMatch([string]$Query, [string]$Text) {
  if (-not $Query) { return $true }
  $queryIndex = 0
  $queryText = $Query.ToLowerInvariant()
  $targetText = $Text.ToLowerInvariant()
  foreach ($char in $targetText.ToCharArray()) {
    if ($char -eq $queryText[$queryIndex]) {
      $queryIndex += 1
      if ($queryIndex -ge $queryText.Length) {
        return $true
      }
    }
  }
  return $false
}

function Get-ActiveQuery($State) {
  if ($State.Active -eq "remote") { return $State.RemoteQuery }
  return $State.LocalQuery
}

function Set-ActiveQuery($State, [string]$Query) {
  if ($State.Active -eq "remote") { $State.RemoteQuery = $Query }
  else { $State.LocalQuery = $Query }
}

function Find-FuzzyItemIndex($Items, [string]$Query) {
  if (-not $Query) { return -1 }
  for ($i = 0; $i -lt $Items.Count; $i++) {
    $item = $Items[$i]
    if ($item.Parent) { continue }
    if (Test-FuzzyMatch $Query $item.Name) {
      return $i
    }
  }
  return -1
}

function Update-QueryStatus($State) {
  $query = Get-ActiveQuery $State
  if ($query) {
    $State.Message = "$($State.Active) filter: $query"
  } else {
    $State.Message = "Active panel: $($State.Active)"
  }
  Write-FtpStatus $State
}

function Invoke-FtpQuery($State, [string]$Query) {
  Set-ActiveQuery $State $Query
  $items = if ($State.Active -eq "remote") { $State.RemoteItems } else { $State.LocalItems }
  $match = Find-FuzzyItemIndex $items $Query
  if ($match -ge 0) {
    if ($State.Active -eq "remote") { $State.RemoteIndex = $match }
    else { $State.LocalIndex = $match }
    Ensure-SelectionVisible $State
    Draw-FtpUi $State
  } else {
    $State.Message = "$($State.Active) filter: $Query (no match)"
    Write-FtpStatus $State
  }
}

function Invoke-FtpSelectionMove($State, [int]$Delta) {
  $oldIndex = if ($State.Active -eq "remote") { $State.RemoteIndex } else { $State.LocalIndex }
  $oldOffset = if ($State.Active -eq "remote") { $State.RemoteOffset } else { $State.LocalOffset }
  $maxIndex = if ($State.Active -eq "remote") { $State.RemoteItems.Count - 1 } else { $State.LocalItems.Count - 1 }
  $newIndex = [Math]::Min($maxIndex, [Math]::Max(0, $oldIndex + $Delta))

  if ($State.Active -eq "remote") { $State.RemoteIndex = $newIndex }
  else { $State.LocalIndex = $newIndex }

  Ensure-SelectionVisible $State
  $newOffset = if ($State.Active -eq "remote") { $State.RemoteOffset } else { $State.LocalOffset }
  if ($oldOffset -ne $newOffset) {
    Draw-FtpUi $State
    return
  }

  $oldRow = $oldIndex - $oldOffset
  $newRow = $newIndex - $newOffset
  if ($oldRow -ge 0 -and $oldRow -lt $State.Rows) {
    Write-FtpPanelRow $State $oldRow $State.Active
  }
  if ($newRow -ge 0 -and $newRow -lt $State.Rows -and $newRow -ne $oldRow) {
    Write-FtpPanelRow $State $newRow $State.Active
  }
}

function Switch-FtpPanel($State) {
  $previous = $State.Active
  $State.Active = if ($State.Active -eq "remote") { "local" } else { "remote" }
  $remoteRow = $State.RemoteIndex - $State.RemoteOffset
  $localRow = $State.LocalIndex - $State.LocalOffset
  if ($remoteRow -ge 0 -and $remoteRow -lt $State.Rows) { Write-FtpPanelRow $State $remoteRow "remote" }
  if ($localRow -ge 0 -and $localRow -lt $State.Rows) { Write-FtpPanelRow $State $localRow "local" }
  Update-QueryStatus $State
}

function Confirm-ConsoleAction([string]$Message) {
  Write-Host ""
  $answer = Read-Host "$Message [y/N]"
  return $answer -match "^(y|yes)$"
}

function Format-Bytes([int64]$Bytes) {
  if ($Bytes -ge 1GB) { return "{0:n1}G" -f ($Bytes / 1GB) }
  if ($Bytes -ge 1MB) { return "{0:n1}M" -f ($Bytes / 1MB) }
  if ($Bytes -ge 1KB) { return "{0:n1}K" -f ($Bytes / 1KB) }
  return "$Bytes B"
}

function Copy-StreamWithProgress($InputStream, $OutputStream, [int64]$TotalBytes, [string]$Label, $State) {
  $buffer = [byte[]]::new(131072)
  $copied = [int64]0
  $lastUpdate = [DateTime]::UtcNow.AddSeconds(-1)
  while ($true) {
    $read = $InputStream.Read($buffer, 0, $buffer.Length)
    if ($read -le 0) { break }
    $OutputStream.Write($buffer, 0, $read)
    $copied += $read

    $now = [DateTime]::UtcNow
    if (($now - $lastUpdate).TotalMilliseconds -ge 250) {
      if ($TotalBytes -gt 0) {
        $percent = [Math]::Min(100, [Math]::Round(($copied / $TotalBytes) * 100, 1))
        $State.Message = "$Label $(Format-Bytes $copied) / $(Format-Bytes $TotalBytes) ($percent%)"
      } else {
        $State.Message = "$Label $(Format-Bytes $copied)"
      }
      Write-FtpStatus $State
      $lastUpdate = $now
    }
  }
}

function Receive-FtpFile($Session, [string]$RemotePath, [string]$LocalPath, [int64]$Size, $State) {
  $control = $null
  $dataClient = $null
  $outputStream = $null
  try {
    $control = New-FtpControlConnection $Session
    $dataClient = Open-FtpDataConnection $control
    Send-FtpCommand $control "RETR $RemotePath" @(125, 150) "FTP download" | Out-Null
    $outputStream = [System.IO.File]::Open($LocalPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
    Copy-StreamWithProgress $dataClient.GetStream() $outputStream $Size "Downloading" $State
    Assert-FtpReply (Read-FtpReply $control) @(226, 250) "FTP download complete"
  } finally {
    if ($outputStream) { $outputStream.Dispose() }
    if ($dataClient) { $dataClient.Dispose() }
    Close-FtpControlConnection $control
  }
}

function Send-FtpFile($Session, [string]$LocalPath, [string]$RemotePath, [int64]$Size, $State) {
  $control = $null
  $dataClient = $null
  $inputStream = $null
  try {
    $control = New-FtpControlConnection $Session
    $dataClient = Open-FtpDataConnection $control
    Send-FtpCommand $control "STOR $RemotePath" @(125, 150) "FTP upload" | Out-Null
    $inputStream = [System.IO.File]::OpenRead($LocalPath)
    Copy-StreamWithProgress $inputStream $dataClient.GetStream() $Size "Uploading" $State
    $dataClient.Close()
    Assert-FtpReply (Read-FtpReply $control) @(226, 250) "FTP upload complete"
  } finally {
    if ($inputStream) { $inputStream.Dispose() }
    if ($dataClient) { $dataClient.Dispose() }
    Close-FtpControlConnection $control
  }
}

function Update-LocalPanelFile($State, [string]$Path) {
  $file = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $file -or $file.PSIsContainer) { return }

  $entry = [pscustomobject]@{
    Name = $file.Name
    IsDir = $false
    Size = $file.Length
    FullName = $file.FullName
  }
  $items = @($State.LocalItems | Where-Object { -not $_.Parent -and $_.FullName -ne $file.FullName })
  $State.LocalItems = @([pscustomobject]@{ Name = ".."; IsDir = $true; Size = 0; Parent = $true }) +
    @($items + $entry | Sort-Object @{ Expression = "IsDir"; Descending = $true }, Name)
  $match = 0
  for ($i = 0; $i -lt $State.LocalItems.Count; $i++) {
    if ($State.LocalItems[$i].FullName -eq $file.FullName) {
      $match = $i
      break
    }
  }
  $State.LocalIndex = $match
  Ensure-SelectionVisible $State
}

function Select-FtpConnection($Connections, [string]$Name) {
  if ($Name) {
    $selected = @($Connections | Where-Object { (Get-PropertyValue $_ "display") -eq $Name })
    if ($selected.Count -eq 0) { throw "FTP connection not found: $Name" }
    if ($selected.Count -gt 1) { throw "Multiple FTP connections matched: $Name" }
    return $selected[0]
  }
  if ($Connections.Count -eq 1) {
    return $Connections[0]
  }

  $fzf = Get-Command fzf.exe -ErrorAction SilentlyContinue
  if ($fzf) {
    $selection = $Connections |
      ForEach-Object { Get-PropertyValue $_ "display" } |
      & $fzf.Source --prompt "ftp > " --height "40%" --reverse
    if (-not $selection) { return $null }
    return @($Connections | Where-Object { (Get-PropertyValue $_ "display") -eq $selection })[0]
  }

  $Connections | ForEach-Object -Begin { $i = 1 } -Process {
    [pscustomobject]@{ Index = $i; Display = Get-PropertyValue $_ "display" }
    $i += 1
  } | Format-Table -AutoSize
  $choice = Read-Host "ftp"
  if (-not $choice) { return $null }

  $index = 0
  if ([int]::TryParse($choice, [ref]$index)) {
    if ($index -lt 1 -or $index -gt $Connections.Count) {
      throw "Invalid FTP selection: $choice"
    }
    return $Connections[$index - 1]
  }

  return @($Connections | Where-Object { (Get-PropertyValue $_ "display") -eq $choice })[0]
}

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
  throw "Missing config file: $ConfigPath"
}
if (-not (Test-Path -LiteralPath $LocalPath -PathType Container)) {
  throw "Local path not found: $LocalPath"
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$connections = @($config."ftp-connections") | Where-Object { Get-PropertyValue $_ "display" }
if ($connections.Count -eq 0) {
  throw "No ftp-connections found in $ConfigPath"
}

$connection = Select-FtpConnection $connections $Name
if (-not $connection) { return }

$display = Get-PropertyValue $connection "display"
$user = Get-PropertyValue $connection "user"
$password = Get-PropertyValue $connection "password"
$endpoint = Resolve-Endpoint $connection
if (-not $endpoint.HostName) { throw "Connection '$display' has no host/server." }
if (-not $user) { throw "Connection '$display' has no user." }

$session = [pscustomobject]@{
  Display = $display
  Protocol = $endpoint.Protocol
  HostName = $endpoint.HostName
  Port = $endpoint.Port
  EnableSsl = $endpoint.EnableSsl
  User = $user
  Password = $password
}

$state = [pscustomobject]@{
  Active = "remote"
  RemotePath = $endpoint.RemotePath
  LocalPath = (Resolve-Path -LiteralPath $LocalPath).Path
  RemoteItems = @()
  LocalItems = @()
  RemoteIndex = 0
  LocalIndex = 0
  RemoteOffset = 0
  LocalOffset = 0
  RemoteQuery = ""
  LocalQuery = ""
  Width = 0
  Height = 0
  LeftWidth = 0
  RightWidth = 0
  Rows = 0
  LastWidth = 0
  LastHeight = 0
  Message = "Connecting to $display..."
}

function Refresh-Remote {
  $state.RemoteItems = @(Get-RemoteItems $session $state.RemotePath)
  if ($state.RemoteIndex -ge $state.RemoteItems.Count) { $state.RemoteIndex = [Math]::Max(0, $state.RemoteItems.Count - 1) }
  Ensure-SelectionVisible $state
}

function Refresh-Local {
  $state.LocalItems = @(Get-LocalItems $state.LocalPath)
  if ($state.LocalIndex -ge $state.LocalItems.Count) { $state.LocalIndex = [Math]::Max(0, $state.LocalItems.Count - 1) }
  Ensure-SelectionVisible $state
}

function Refresh-State {
  Refresh-Remote
  Refresh-Local
}

Write-Host "Connecting to $display..." -ForegroundColor Cyan
try {
  Refresh-State
} catch {
  throw "FTP login/listing failed for '$display': $($_.Exception.Message)"
}
$state.Message = "Connected to $display."
if ($TestConnection) {
  Write-Host "Connected to $display. Remote entries: $($state.RemoteItems.Count). Local entries: $($state.LocalItems.Count)."
  return
}

$done = $false
try {
  [Console]::Clear()
  [Console]::CursorVisible = $false
  Draw-FtpUi $state
  while (-not $done) {
    $key = [Console]::ReadKey($true)
    try {
      if ($key.Key -eq [ConsoleKey]::Q -or $key.Key -eq [ConsoleKey]::Escape) {
        if ($key.Key -eq [ConsoleKey]::Escape -and (Get-ActiveQuery $state)) {
          Invoke-FtpQuery $state ""
        } else {
          $done = $true
        }
      } elseif ($key.Key -eq [ConsoleKey]::Tab) {
        Switch-FtpPanel $state
      } elseif ($key.Key -eq [ConsoleKey]::UpArrow) {
        Set-ActiveQuery $state ""
        Invoke-FtpSelectionMove $state -1
      } elseif ($key.Key -eq [ConsoleKey]::DownArrow) {
        Set-ActiveQuery $state ""
        Invoke-FtpSelectionMove $state 1
      } elseif ($key.Key -eq [ConsoleKey]::PageUp) {
        $rows = Get-VisibleRows
        Invoke-FtpSelectionMove $state (-1 * $rows)
      } elseif ($key.Key -eq [ConsoleKey]::PageDown) {
        $rows = Get-VisibleRows
        Invoke-FtpSelectionMove $state $rows
      } elseif ($key.Key -eq [ConsoleKey]::R) {
        $state.Message = "Refreshing remote and local panels..."
        Write-FtpStatus $state
        Refresh-State
        $state.Message = "Refreshed."
        Draw-FtpUi $state
      } elseif ($key.Key -eq [ConsoleKey]::Backspace) {
        $query = Get-ActiveQuery $state
        if ($query) {
          Invoke-FtpQuery $state $query.Substring(0, $query.Length - 1)
        } elseif ($state.Active -eq "remote") {
          $state.RemotePath = Get-RemoteParent $state.RemotePath
          $state.RemoteIndex = 0
          $state.Message = "Loading remote folder..."
          Write-FtpStatus $state
          Refresh-Remote
        } else {
          $parent = Split-Path -Parent $state.LocalPath
          if ($parent) { $state.LocalPath = $parent; $state.LocalIndex = 0 }
          Refresh-Local
        }
        Draw-FtpUi $state
      } elseif ($key.Key -eq [ConsoleKey]::Enter) {
        Set-ActiveQuery $state ""
        if ($state.Active -eq "remote") {
          $item = $state.RemoteItems[$state.RemoteIndex]
          if ($item) {
            $candidatePath = if ($item.Parent) { Get-RemoteParent $state.RemotePath } else { Join-RemotePath $state.RemotePath $item.Name -AsDirectory }
            $previousPath = $state.RemotePath
            $state.RemotePath = $candidatePath
            $state.RemoteIndex = 0
            $state.Message = "Loading remote folder..."
            Write-FtpStatus $state
            try {
              Refresh-Remote
              Draw-FtpUi $state
            } catch {
              $state.RemotePath = $previousPath
              Refresh-Remote
              $state.Message = "Not a remote directory: $($item.Name)"
              Draw-FtpUi $state
            }
          }
        } else {
          $item = $state.LocalItems[$state.LocalIndex]
          if ($item -and $item.IsDir) {
            $state.LocalPath = if ($item.Parent) { Split-Path -Parent $state.LocalPath } else { $item.FullName }
            $state.LocalIndex = 0
            Refresh-Local
            Draw-FtpUi $state
          }
        }
      } elseif ($key.Key -eq [ConsoleKey]::F5) {
        Set-ActiveQuery $state ""
        $item = $state.RemoteItems[$state.RemoteIndex]
        if (-not $item -or $item.IsDir) {
          $state.Message = "Select a remote file to download."
          Write-FtpStatus $state
          continue
        }
        $target = Join-Path $state.LocalPath $item.Name
        if ((Test-Path -LiteralPath $target) -and -not (Confirm-ConsoleAction "Overwrite local file '$target'?")) {
          $state.Message = "Download cancelled."
          Draw-FtpUi $state
          continue
        }
        $state.Message = "Downloading $($item.Name)..."
        Write-FtpStatus $state
        Receive-FtpFile $session (Join-RemotePath $state.RemotePath $item.Name) $target $item.Size $state
        Update-LocalPanelFile $state $target
        $state.Message = "Downloaded $($item.Name)."
        Draw-FtpUi $state
      } elseif ($key.Key -eq [ConsoleKey]::F6) {
        Set-ActiveQuery $state ""
        $item = $state.LocalItems[$state.LocalIndex]
        if (-not $item -or $item.IsDir) {
          $state.Message = "Select a local file to upload."
          Write-FtpStatus $state
          continue
        }
        $state.Message = "Uploading $($item.Name)..."
        Write-FtpStatus $state
        Send-FtpFile $session $item.FullName (Join-RemotePath $state.RemotePath $item.Name) $item.Size $state
        Refresh-Remote
        $state.Message = "Uploaded $($item.Name)."
        Draw-FtpUi $state
      } else {
        if (-not [char]::IsControl($key.KeyChar)) {
          Invoke-FtpQuery $state ((Get-ActiveQuery $state) + $key.KeyChar)
        } else {
          Update-QueryStatus $state
        }
      }
    } catch {
      $state.Message = $_.Exception.Message
      Write-FtpStatus $state
    }
  }
} finally {
  [Console]::CursorVisible = $true
}
