$source = "$PSScriptRoot\oogit.ps1"
$destinationDir = "C:\Program Files\oogit"
$destination = "$destinationDir\oogit.ps1"

$supportedExtensions = @(
  "docx", "docm", "dotx", "dotm",
  "xlsx", "xlsm", "xltx", "xltm", "xlsb", "xlam",
  "pptx", "pptm", "potx", "potm", "ppam", "ppsx", "ppsm",
  "sldx", "sldm", "thmx"
)

New-Item -ItemType Directory -Force -Path $destinationDir
Copy-Item -Force $source -Destination $destination
$guiSource = "$PSScriptRoot\gui.ps1"
$guiDestination = "$destinationDir\gui.ps1"
Copy-Item -Force $guiSource -Destination $guiDestination

$binDir = "$destinationDir\bin"
New-Item -ItemType Directory -Force -Path $binDir
$batPath = "$binDir\oogit.bat"

Set-Content -Path $batPath -Value "powershell -ExecutionPolicy Bypass -File \"$destination\" %*"

$envPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if (-not $envPath.Contains($binDir)) {
  [Environment]::SetEnvironmentVariable("Path", "$envPath;$binDir", "Machine")
}

foreach ($ext in $supportedExtensions) {
  $extension = ".$ext"
  $assoc = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Classes\$extension")."(default)"
  $assocBackupPath = "$destinationDir\${ext}_assoc_backup.txt"
  $openCommandPath = "HKLM:\SOFTWARE\Classes\$assoc\shell\open\command"

  (Get-ItemProperty -Path $openCommandPath)."(default)" | Out-File -Encoding UTF8 -FilePath $assocBackupPath
  Set-ItemProperty -Path $openCommandPath -Name "(default)" -Value "\"$batPath\" open $ext \"%1\""

  $contextMenuPathPrefix = "HKLM:\SOFTWARE\Classes\$assoc\shell\oogit-"

  $contextMenuPathCommit = "${contextMenuPathPrefix}commit"
  New-Item -Path $contextMenuPathCommit -Force | Out-Null
  Set-ItemProperty -Path $contextMenuPathCommit -Name "(default)" -Value "oogit commit"
  $commandPathCommit = "${contextMenuPathCommit}\command"
  New-Item -Path $commandPathCommit -Force | Out-Null
  Set-ItemProperty -Path $commandPathCommit -Name "(default)" -Value "powershell -ExecutionPolicy Bypass -File \"$guiDestination\" commit $ext \"%1\""

  $contextMenuPathUpdate = "${contextMenuPathPrefix}update"
  New-Item -Path $contextMenuPathUpdate -Force | Out-Null
  Set-ItemProperty -Path $contextMenuPathUpdate -Name "(default)" -Value "oogit update"
  $commandPathUpdate = "${contextMenuPathUpdate}\command"
  New-Item -Path $commandPathUpdate -Force | Out-Null
  Set-ItemProperty -Path $commandPathUpdate -Name "(default)" -Value "powershell -ExecutionPolicy Bypass -File \"$guiDestination\" update $ext \"%1\""
}

Write-Host "Installation complete. You need to log out and log in again or restart explorer.exe for PATH to take effect."
pause
