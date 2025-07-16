# oogit_uninstall.ps1

$destinationDir = "C:\Program Files\oogit"
$binDir = "$destinationDir\bin"
$batPath = "$binDir\oogit.bat"

$supportedExtensions = @(
  "docx", "docm", "dotx", "dotm",
  "xlsx", "xlsm", "xltx", "xltm", "xlsb", "xlam",
  "pptx", "pptm", "potx", "potm", "ppam", "ppsx", "ppsm",
  "sldx", "sldm", "thmx"
)

foreach ($ext in $supportedExtensions) {
  $assocBackupPath = "$destinationDir\${ext}_assoc_backup.txt"
  $extension = ".$ext"
  $assoc = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Classes\$extension")."(default)"
  $openCommandPath = "HKLM:\SOFTWARE\Classes\$assoc\shell\open\command"

  if (Test-Path $assocBackupPath) {
    $originalCommand = Get-Content -Path $assocBackupPath -Raw
    Set-ItemProperty -Path $openCommandPath -Name "(default)" -Value $originalCommand
    Remove-Item -Force $assocBackupPath
  }

  $contextMenuPath = "HKLM:\SOFTWARE\Classes\$assoc\shell\oogit"
  if (Test-Path $contextMenuPath) {
    Remove-Item -Path $contextMenuPath -Recurse -Force
  }
}

$envPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($envPath -and $envPath.Contains($binDir)) {
  $newPath = ($envPath -split ";") -ne $binDir -join ";"
  [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
}

Remove-Item -Path $destinationDir -Recurse -Force

Write-Host "uninstallation complete."
