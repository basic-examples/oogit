# oogit.ps1 - Windows PowerShell implementation of oogit.sh

$ErrorActionPreference = 'Stop'

$Name = $MyInvocation.MyCommand.Name
if ($env:NAME_OVERRIDE) { $Name = $env:NAME_OVERRIDE }

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Write-Error "[oogit] git not found"
  exit 1
}

$VerboseEnabled = $false
if ($env:V -eq '1' -or $env:V -eq 'true' -or $env:VERBOSE -eq '1' -or $env:VERBOSE -eq 'true') {
  $VerboseEnabled = $true
  Set-PSDebug -Trace 1
}

function Run-Checked-Silent {
  param(
    [string] $Command,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Args
  )

  if ($VerboseEnabled) {
    & $Command @Args
  } else {
    # & $Command @Args 2>&1 | Out-Null // FIXME: this is not working
    & $Command @Args
  }

  if ($LASTEXITCODE -ne 0) {
    throw "Command '$($Command + ' ' + ($Args -join ' '))' failed with exit code $LASTEXITCODE"
  }
}

function Run-Checked {
  param(
    [string] $Command,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Args
  )

  & $Command @Args

  if ($LASTEXITCODE -ne 0) {
    throw "Command '$($Command + ' ' + ($Args -join ' '))' failed with exit code $LASTEXITCODE"
  }
}

function Load-Metadata {
  if (-not (Test-Path $META_FILE)) {
    Write-Error "[oogit] $META_FILE not found. Please run init or checkout command first."
    exit 1
  }
  $lines = Get-Content $META_FILE
  $global:METADATA_VERSION = $lines[0]
  $global:METADATA_REPO_URL = $lines[1]
  $global:METADATA_PATH_IN_REPO = $lines[2]
  $global:METADATA_BRANCH = $lines[3]
  $global:METADATA_COMMIT_HASH = $lines[4]
  if ($METADATA_VERSION -ne '1') {
    Write-Error "[oogit] Error: Unsupported file version: $METADATA_VERSION"
    exit 1
  }
}

function Ensure-Dirs {
  param($ooxmlFile)
  $global:META_DIR = "$ooxmlFile.oogit"
  $global:META_FILE = "$META_DIR\metadata"
  $global:REPO_DIR = "$META_DIR\repo"
  $global:TEMP_DIR = "$META_DIR\tmp"
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $TEMP_DIR
  if (-not (Test-Path $META_DIR)) {
    Write-Error "[oogit] Error: $META_DIR does not exist"
    exit 1
  }
}

function Setup-Dirs {
  param($ooxmlFile)
  $global:META_DIR = "$ooxmlFile.oogit"
  $global:META_FILE = "$META_DIR\metadata"
  $global:REPO_DIR = "$META_DIR\repo"
  $global:TEMP_DIR = "$META_DIR\tmp"
  New-Item -ItemType Directory -Force -Path $META_DIR | Out-Null
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $TEMP_DIR
}

function Zip-Dir {
  param($srcDir,$outFile)
  Compress-Archive -Path (Join-Path $srcDir '*') -DestinationPath $TEMP_DIR/output.zip -Force
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $outFile
  Move-Item -Force $TEMP_DIR/output.zip $outFile
}

function Unzip-File {
  param($zipFile,$outDir)
  New-Item -ItemType Directory -Force -Path $TEMP_DIR | Out-Null
  Copy-Item -Path $zipFile -Destination $TEMP_DIR\input.zip -Force
  Expand-Archive -Path $TEMP_DIR\input.zip -DestinationPath $outDir -Force
}

function Fetch-And-Reset {
  param($repoDir,$commitHash)
  Push-Location $repoDir
  Run-Checked-Silent -- git fetch
  Run-Checked-Silent -- git reset --hard $commitHash
  Pop-Location
}

function Unzip-File-To-Repo {
  param($repoDir,$pathInRepo,$ooxmlFile)
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue "$repoDir$pathInRepo"
  New-Item -ItemType Directory -Force -Path "$repoDir$pathInRepo" | Out-Null
  Unzip-File $ooxmlFile "$repoDir$pathInRepo"
}

function My-Git-Commit {
  param($repoDir, $pathInRepo, $message)
  Push-Location "$repoDir$pathInRepo"
  Run-Checked-Silent -- git add .

  git rev-parse --verify HEAD >$null 2>&1
  if ($LASTEXITCODE -eq 0) {
    Pop-Location
    return
  } else {
    git diff-index --quiet HEAD 2>$null
    if ($LASTEXITCODE -eq 0) {
      Pop-Location
      return
    }
  }

  if ($message) {
    Run-Checked-Silent -- git commit -m $message
  } else {
    git commit
    if ($LASTEXITCODE -ne 0) { throw "git commit failed" }
  }

  Pop-Location
}

function My-Git-Commit-Intermediate {
  param($repoDir,$pathInRepo)
  Run-Checked-Silent -- git -C "$repoDir$pathInRepo" add .
  Push-Location $repoDir
  $tmpIndex = 0
  $output = git diff --cached --name-status -z
  $parts = $output -split "`0"
  for ($i=0; $i+1 -lt $parts.Length; $i+=2) {
    $status = $parts[$i]
    $file = $parts[$i+1]
    if (($status -match '^[AMR]') -and (Test-Path $file)) {
      Move-Item $file "$($pathInRepo.Substring(1))\oogit-intermediate-name-$tmpIndex" -Force
      $tmpIndex++
    }
  }
  if ($tmpIndex -gt 0) {
    Run-Checked-Silent -- git add .
    git rev-parse --verify HEAD >$null 2>&1
    if ($LASTEXITCODE -eq 0) {
      Pop-Location
      return
    } else {
      git diff-index --quiet HEAD 2>$null
      if ($LASTEXITCODE -eq 0) {
        Pop-Location
        return
      }
    }
    Run-Checked-Silent -- git commit -m "[oogit-intermediate-commit]"
  }
  Pop-Location
}

function Git-Pull {
  param($repoDir)
  Push-Location $repoDir
  Run-Checked-Silent -- git pull --no-rebase
  Pop-Location
}

function Git-Push {
  param($repoDir,$branch)
  Push-Location $repoDir
  $remoteName = git remote | Select-Object -First 1
  if (-not $remoteName) { Write-Error "[oogit] Error: No remote found"; exit 1 }
  Run-Checked-Silent -- git push --set-upstream $remoteName $branch
  Pop-Location
}

function Git-Get-Commit-Hash {
  param($repoDir)
  Push-Location $repoDir
  $hash = git rev-parse HEAD
  Pop-Location
  return $hash
}

function Zip-Dir-From-Repo {
  param($repoDir,$pathInRepo,$ooxmlFile)
  New-Item -ItemType Directory -Force -Path $TEMP_DIR | Out-Null
  Zip-Dir "$repoDir$pathInRepo" "$TEMP_DIR\output.zip"
  Move-Item -Force "$TEMP_DIR\output.zip" $ooxmlFile
}

function Write-Metadata {
  param($repoUrl,$pathInRepo,$branch,$commitHash)
  "1`n$repoUrl`n$pathInRepo`n$branch`n$commitHash" | Set-Content $META_FILE
}

function Init-Command {
  param([string[]]$ArgList)
  $ooxmlFile=""
  $repoUrl=""
  $branch=""
  $pathInRepo="\root"
  $commitMessage=""
  $expectedCommitHash=""
  $force=$false
  $args=@()
  $parsing=$true
  while($ArgList.Length -gt 0) {
    $arg=$ArgList[0]
    if ($ArgList.Length -gt 1) {
      $ArgList = $ArgList[1..($ArgList.Length - 1)]
    } else {
      $ArgList = @()
    }
    if($parsing){
      switch($arg){
        '--' {
          $parsing = $false
          break
        }
        '-m' {
          if($ArgList.Length -gt 0 -and $ArgList[0] -notmatch '^-'){
            $commitMessage = $ArgList[0]
            if ($ArgList.Length -gt 1) {
              $ArgList = $ArgList[1..($ArgList.Length - 1)]
            } else {
              $ArgList = @()
            }
          } else {
            Write-Error "[oogit] Error: -m/--message requires a value"
            exit 1
          }
          break
        }
        '--message' {
          if($ArgList.Length -gt 0 -and $ArgList[0] -notmatch '^-'){
            $commitMessage = $ArgList[0]
            if ($ArgList.Length -gt 1) {
              $ArgList = $ArgList[1..($ArgList.Length - 1)]
            } else {
              $ArgList = @()
            }
          } else {
            Write-Error "[oogit] Error: -m/--message requires a value"
            exit 1
          }
          break
        }
        '-c' {
          if($ArgList.Length -gt 0 -and $ArgList[0] -notmatch '^-'){
            $expectedCommitHash = $ArgList[0]
            if ($ArgList.Length -gt 1) {
              $ArgList = $ArgList[1..($ArgList.Length - 1)]
            } else {
              $ArgList = @()
            }
          } else {
            Write-Error "[oogit] Error: -c/--commit-hash requires a value"
            exit 1
          }
          break
        }
        '--commit-hash' {
          if($ArgList.Length -gt 0 -and $ArgList[0] -notmatch '^-'){
            $expectedCommitHash = $ArgList[0]
            if ($ArgList.Length -gt 1) {
              $ArgList = $ArgList[1..($ArgList.Length - 1)]
            } else {
              $ArgList = @()
            }
          } else {
            Write-Error "[oogit] Error: -c/--commit-hash requires a value"
            exit 1
          }
          break
        }
        '-f' {
          $force = $true
          break
        }
        '--force' {
          $force = $true
          break
        }
        default {
          if($arg -like '-*'){
            Write-Error "[oogit] Error: Unknown option $arg"
            exit 1
          }
          $parsing = $false
          $args += $arg
        }
      }
    } else {
      $args += $arg
    }
  }
  if($args.Count -lt 2){ Write-Error "[oogit] Error: init requires at least ooxml-file and git-repo arguments"; exit 1 }
  $ooxmlFile=$args[0]
  $repoUrl=$args[1]
  if($args.Count -ge 3){ $branch=$args[2] }
  if($args.Count -ge 4){ $pathInRepo=$args[3] }
  if($pathInRepo[0] -ne '\'){ $pathInRepo="\$pathInRepo" }
  if($pathInRepo -eq '\'){ Write-Error "[oogit] Error: path_in_repo cannot be \"; exit 1 }
  Setup-Dirs $ooxmlFile
  if(-not $force){
    if(Test-Path $META_FILE){ Write-Error "[oogit] $META_FILE already exists. Please run with --force option to overwrite."; exit 1 }
    if(Test-Path $REPO_DIR){ Write-Error "[oogit] $REPO_DIR already exists. Please run with --force option to overwrite."; exit 1 }
  }
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $REPO_DIR
  if($branch){
    try { Run-Checked-Silent -- git clone --branch $branch --single-branch -- $repoUrl $REPO_DIR } catch {
      Write-Host "[oogit] Branch '$branch' not found, creating new branch"
      Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $REPO_DIR
      Run-Checked-Silent -- git clone --single-branch --depth 1 -- $repoUrl $REPO_DIR
      Push-Location $REPO_DIR
      Run-Checked-Silent -- git checkout --orphan $branch
      Run-Checked-Silent -- git reset --hard
      Pop-Location
    }
  } else {
    Run-Checked-Silent -- git clone --single-branch -- $repoUrl $REPO_DIR
    Push-Location $REPO_DIR
    $branch = git branch --show-current
    Pop-Location
  }
  if($expectedCommitHash){
    Push-Location $REPO_DIR
    $current = git rev-parse HEAD
    Pop-Location
    if($current -ne $expectedCommitHash){ Write-Error "[oogit] Error: Commit hash mismatch"; exit 1 }
  }
  Unzip-File-To-Repo $REPO_DIR $pathInRepo $ooxmlFile
  My-Git-Commit-Intermediate $REPO_DIR $pathInRepo
  Unzip-File-To-Repo $REPO_DIR $pathInRepo $ooxmlFile
  My-Git-Commit $REPO_DIR $pathInRepo $commitMessage
  Git-Push $REPO_DIR $branch
  $commitHash = Git-Get-Commit-Hash $REPO_DIR
  Write-Metadata $repoUrl $pathInRepo $branch $commitHash
}

function Checkout-Command {
  param([string[]]$ArgList)
  $ooxmlFile=""; $repoUrl=""; $branch=""; $pathInRepo="\root"; $force=$false
  $args=@(); $parsing=$true
  while($ArgList.Length -gt 0){
    $arg=$ArgList[0]
    if ($ArgList.Length -gt 1) {
      $ArgList = $ArgList[1..($ArgList.Length - 1)]
    } else {
      $ArgList = @()
    }

    if($parsing){
      switch($arg){
        '--' {
          $parsing = $false
          break
        }
        '-f' {
          $force = $true
          break
        }
        '--force' {
          $force = $true
          break
        }
        default{ if($arg -like '-*'){ Write-Error "[oogit] Error: Unknown option $arg"; exit 1 } $parsing=$false; $args+=$arg }
      }
    } else { $args+=$arg }
  }
  if($args.Count -lt 2){ Write-Error "[oogit] Error: checkout requires at least ooxml-file and git-repo arguments"; exit 1 }
  $ooxmlFile=$args[0]; $repoUrl=$args[1]
  if($args.Count -ge 3){ $branch=$args[2] }
  if($args.Count -ge 4){ $pathInRepo=$args[3] }
  if($pathInRepo[0] -ne '\'){ $pathInRepo="\$pathInRepo" }
  if($pathInRepo -eq '\'){ Write-Error "[oogit] Error: path_in_repo cannot be \"; exit 1 }
  Setup-Dirs $ooxmlFile
  if(-not $force){
    if(Test-Path $ooxmlFile){ Write-Error "[oogit] $ooxmlFile already exists. Please run with --force option to overwrite."; exit 1 }
    if(Test-Path $META_FILE){ Write-Error "[oogit] $META_FILE already exists. Please run with --force option to overwrite."; exit 1 }
  }
  if($branch) {
    Run-Checked-Silent -- git clone --branch $branch --single-branch -- $repoUrl $REPO_DIR
  } else {
    Run-Checked-Silent -- git clone --single-branch -- $repoUrl $REPO_DIR
    Push-Location $REPO_DIR
    $branch = git branch --show-current
    Pop-Location
  }
  Zip-Dir-From-Repo $REPO_DIR $pathInRepo $ooxmlFile
  $commitHash = Git-Get-Commit-Hash $REPO_DIR
  Write-Metadata $repoUrl $pathInRepo $branch $commitHash
}

function Commit-Command {
  param([string[]]$ArgList)
  $ooxmlFile=""; $commitMessage=""; $args=@(); $parsing=$true
  while($ArgList.Length -gt 0){
    $arg=$ArgList[0]
    if ($ArgList.Length -gt 1) {
      $ArgList = $ArgList[1..($ArgList.Length - 1)]
    } else {
      $ArgList = @()
    }
    if($parsing){
      switch($arg){
        '--' {
          $parsing = $false
          break
        }
        '-m' {
          if($ArgList.Length -gt 0 -and $ArgList[0] -notmatch '^-') {
            $commitMessage=$ArgList[0]
            if ($ArgList.Length -gt 1) {
              $ArgList = $ArgList[1..($ArgList.Length - 1)]
            } else {
              $ArgList = @()
            }
          } else {
            Write-Error "[oogit] Error: -m/--message requires a value"; exit 1
          }
          break
        }
        '--message' {
          if($ArgList.Length -gt 0 -and $ArgList[0] -notmatch '^-') {
            $commitMessage=$ArgList[0]
            if ($ArgList.Length -gt 1) {
              $ArgList = $ArgList[1..($ArgList.Length - 1)]
            } else {
              $ArgList = @()
            }
          } else {
            Write-Error "[oogit] Error: -m/--message requires a value"; exit 1
          }
          break
        }
        default{ if($arg -like '-*'){ Write-Error "[oogit] Error: Unknown option $arg"; exit 1 } $parsing=$false; $args+=$arg }
      }
    } else { $args+=$arg }
  }
  if($args.Count -lt 1){ Write-Error "[oogit] Error: commit requires ooxml-file argument"; exit 1 }
  $ooxmlFile=$args[0]
  Ensure-Dirs $ooxmlFile
  if(-not (Test-Path $ooxmlFile)){ Write-Error "[oogit] $ooxmlFile not found. Please run checkout command first."; exit 1 }
  Load-Metadata
  $repoUrl=$METADATA_REPO_URL; $pathInRepo=$METADATA_PATH_IN_REPO; $branch=$METADATA_BRANCH; $commitHash=$METADATA_COMMIT_HASH
  Fetch-And-Reset $REPO_DIR $commitHash
  Unzip-File-To-Repo $REPO_DIR $pathInRepo $ooxmlFile
  My-Git-Commit-Intermediate $REPO_DIR $pathInRepo
  Unzip-File-To-Repo $REPO_DIR $pathInRepo $ooxmlFile
  My-Git-Commit $REPO_DIR $pathInRepo $commitMessage
  Git-Pull $REPO_DIR
  Git-Push $REPO_DIR $branch
  $newHash = Git-Get-Commit-Hash $REPO_DIR
  Write-Metadata $repoUrl $pathInRepo $branch $newHash
}

function Update-Command {
  param([string[]]$ArgList)
  $ooxmlFile=""; $commitMessage=""; $force=$false; $args=@(); $parsing=$true
  while($ArgList.Length -gt 0){
    $arg=$ArgList[0]
    if ($ArgList.Length -gt 1) {
      $ArgList = $ArgList[1..($ArgList.Length - 1)]
    } else {
      $ArgList = @()
    }
    if($parsing){
      switch($arg){
        '--' {
          $parsing = $false
          break
        }
        '-m' {
          if($ArgList.Length -gt 0 -and $ArgList[0] -notmatch '^-'){
            $commitMessage=$ArgList[0]
            if ($ArgList.Length -gt 1) {
              $ArgList = $ArgList[1..($ArgList.Length - 1)]
            } else {
              $ArgList = @()
            }
          } else { Write-Error "[oogit] Error: -m/--message requires a value"; exit 1 }
          break
        }
        '--message' {
          if($ArgList.Length -gt 0 -and $ArgList[0] -notmatch '^-'){
            $commitMessage=$ArgList[0]
            if ($ArgList.Length -gt 1) {
              $ArgList = $ArgList[1..($ArgList.Length - 1)]
            } else {
              $ArgList = @()
            }
          } else { Write-Error "[oogit] Error: -m/--message requires a value"; exit 1 }
          break
        }
        '-f' {
          $force=$true
          break
        }
        '--force' {
          $force=$true
          break
        }
        default{ if($arg -like '-*'){ Write-Error "[oogit] Error: Unknown option $arg"; exit 1 } $parsing=$false; $args+=$arg }
      }
    } else { $args+=$arg }
  }
  if($args.Count -lt 1){ Write-Error "[oogit] Error: commit requires ooxml-file argument"; exit 1 }
  $ooxmlFile=$args[0]
  Ensure-Dirs $ooxmlFile
  if(-not (Test-Path $ooxmlFile)){ Write-Error "[oogit] $ooxmlFile not found. Please run checkout command first."; exit 1 }
  Load-Metadata
  $repoUrl=$METADATA_REPO_URL; $pathInRepo=$METADATA_PATH_IN_REPO; $branch=$METADATA_BRANCH; $commitHash=$METADATA_COMMIT_HASH
  Fetch-And-Reset $REPO_DIR $commitHash
  Unzip-File-To-Repo $REPO_DIR $pathInRepo $ooxmlFile
  My-Git-Commit-Intermediate $REPO_DIR $pathInRepo
  Unzip-File-To-Repo $REPO_DIR $pathInRepo $ooxmlFile
  My-Git-Commit $REPO_DIR $pathInRepo $commitMessage
  Git-Pull $REPO_DIR
  Git-Push $REPO_DIR $branch
  $newHash = Git-Get-Commit-Hash $REPO_DIR
  Write-Metadata $repoUrl $pathInRepo $branch $newHash
}

function Reset-Command {
  param([string[]]$ArgList)
  $ooxmlFile=""; $tagOrCommit=""; $args=@(); $parsing=$true
  while($ArgList.Length -gt 0){
    $arg=$ArgList[0]
    if ($ArgList.Length -gt 1) {
      $ArgList = $ArgList[1..($ArgList.Length - 1)]
    } else {
      $ArgList = @()
    }
    if($parsing){
      switch($arg){
        '--' {
          $parsing = $false
          break
        }
        default{ if($arg -like '-*'){ Write-Error "[oogit] Error: Unknown option $arg"; exit 1 } $parsing=$false; $args+=$arg }
      }
    } else { $args+=$arg }
  }
  if($args.Count -lt 1){ Write-Error "[oogit] Error: commit requires ooxml-file argument"; exit 1 }
  $ooxmlFile=$args[0]
  if($args.Count -ge 2){ $tagOrCommit=$args[1] }
  Ensure-Dirs $ooxmlFile
  if(-not (Test-Path $ooxmlFile)){ Write-Error "[oogit] $ooxmlFile not found. Please run checkout command first."; exit 1 }
  Load-Metadata
  $repoUrl=$METADATA_REPO_URL; $pathInRepo=$METADATA_PATH_IN_REPO; $branch=$METADATA_BRANCH; $commitHash=$METADATA_COMMIT_HASH
  Push-Location $REPO_DIR
  Run-Checked-Silent -- git fetch
  Run-Checked-Silent -- git reset --hard $tagOrCommit
  $newHash = git rev-parse HEAD
  Pop-Location
  Zip-Dir-From-Repo $REPO_DIR $pathInRepo $ooxmlFile
  Write-Metadata $repoUrl $pathInRepo $branch $newHash
}

function Version-Command { Write-Output "oogit 0.2.2" }

function Help-Command {
  param($exitCode)
  Version-Command
  @"
Usage: $Name {help|init|checkout|commit|update|reset} ...

Commands:
  help
  init [...options] <ooxml-file> <git-repo> [branch] [path-in-repo]
  checkout [...options] <ooxml-file> <git-repo> [branch] [path-in-repo]
  commit [...options] <ooxml-file>
  update [...options] <ooxml-file>
  reset [...options] <ooxml-file> [tag-or-commit]

Options:
  -v, --version             Show version and exit
  -h, --help                Show this help message and exit
  --                        End of options; treat remaining arguments as positional
  -m, --message <message>   Specify commit message
                            for init/commit/update command
  -c, --commit-hash <hash>  Exit with code 1 if latest commit hash does not match
                            for init command
  -f, --force               Overwrite existing file
                            for init/checkout/update command

Environment Variables:
  V, VERBOSE                1/true: show verbose output
                            others: show only errors
"@ | Write-Output
  exit $exitCode
}

if ($args.Count -eq 0) { Help-Command 0 }
$command = $args[0]
$rest = $args[1..($args.Count-1)]

switch ($command) {
  'init' { Init-Command $rest }
  'checkout' { Checkout-Command $rest }
  'commit' { Commit-Command $rest }
  'update' { Update-Command $rest }
  'reset' { Reset-Command $rest }
  'version' { Version-Command }
  '--version' { Version-Command }
  '-v' { Version-Command }
  'help' { Help-Command 0 }
  '--help' { Help-Command 0 }
  '-h' { Help-Command 0 }
  default { Help-Command 1 }
}
