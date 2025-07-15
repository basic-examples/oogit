param(
  [string]$Extension,
  [string]$FilePath
)

$destinationDir = "C:\Program Files\oogit"
$assocBackupPath = "$destinationDir\${Extension}_assoc_backup.txt"
$watcherPath = "$destinationDir\watcher.ps1"

$supportedExtensions = @(
  "docx", "docm", "dotx", "dotm",
  "xlsx", "xlsm", "xltx", "xltm", "xlsb", "xlam",
  "pptx", "pptm", "potx", "potm", "ppam", "ppsx", "ppsm",
  "sldx", "sldm", "thmx"
)

if (-not ($supportedExtensions -contains $Extension)) {
  Write-Error "Incorrect file extension: $Extension"
  exit 1
}

if (-not (Test-Path $assocBackupPath)) {
  Write-Error "Unsupported file extension: $Extension"
  exit 1
}

$originalCommand = Get-Content -Path $assocBackupPath -Raw
$expanded = [Environment]::ExpandEnvironmentVariables($originalCommand)

function Replace-CommandPlaceholders($command, $filePath) {
  $fileUrl = '"file:///' + $filePath + '"'
  $filePathQuoted = '"' + $filePath + '"'
  $command = $command -replace '(["\']?%1["\']?)', $filePathQuoted
  $command = $command -replace '(["\']?%l["\']?)', $filePathQuoted
  $command = $command -replace '(["\']?%L["\']?)', $filePathQuoted
  $command = $command -replace '(["\']?%u["\']?)', $fileUrl
  $command = $command -replace '(["\']?%U["\']?)', $fileUrl
  $command = $command -replace '(["\']?%\*["\']?)', $filePathQuoted
  return $command
}

$finalCommand = Replace-CommandPlaceholders $expanded $FilePath

$process = Start-Process -FilePath "cmd.exe" -ArgumentList "/C $finalCommand" -PassThru

$watcherProcess = Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File \"$watcherPath\" \"$FilePath\"" -PassThru

$process.WaitForExit()

try {
  Stop-Process -Id $watcherProcess.Id -Force
}
