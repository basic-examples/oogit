#!/bin/bash

set -euo pipefail

NAME=$0
if [[ -n "${NAME_OVERRIDE:-}" ]]; then
  NAME="$NAME_OVERRIDE"
fi

if ! command -v git >/dev/null 2>&1; then
  echo "[oogit] git not found" >&2
  exit 1
fi


if [[ "${V:-0}" == "1" || "${V:-false}" == "true" || "${VERBOSE:-0}" == "1" || "${VERBOSE:-false}" == "true" ]]; then
  set -x
  VERBOSE=true
else
  VERBOSE=false
fi

my_pushd() {
  local dir="$1"

  if [[ "$VERBOSE" == "true" ]]; then
    pushd "$dir"
  else
    pushd "$dir" > /dev/null
  fi
}

my_popd() {
  if [[ "$VERBOSE" == "true" ]]; then
    popd
  else
    popd > /dev/null
  fi
}

my_git() {
  if [[ "$VERBOSE" == "true" ]]; then
    git "$@"
  else
    git "$@" > /dev/null 2>&1
  fi
}

setup_dirs() {
  local ooxml_file="$1"
  META_DIR="${ooxml_file}.oogit"
  META_FILE="$META_DIR/metadata"
  REPO_DIR="$META_DIR/repo"
  TEMP_DIR="$META_DIR/tmp"
  mkdir -p "$META_DIR"
  rm -rf "$TEMP_DIR"
  mkdir -p "$TEMP_DIR"
}

# may create parent directory if it does not exist
convert_path_windows() {
  if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    if [[ -d "$1" ]]; then
      (cd "$1" && pwd -W | tr '/' '\\')
    else
      mkdir -p "$1"
      (cd "$1" && pwd -W | tr '/' '\\')
      rm -rf "$1"
    fi
  else
    echo "$1"
  fi
}

zip_dir() {
  local src_dir="$1"
  local out_file="$2"
  if command -v zip >/dev/null 2>&1; then
    (cd "$src_dir" && zip -qr "$out_file" .)
  elif command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -Command \
      "Compress-Archive -Path '$(convert_path_windows "$src_dir")\\*' -DestinationPath '$(convert_path_windows "$out_file")' -Force"
  else
    echo "[oogit] No zip or PowerShell found" >&2
    exit 1
  fi
}

unzip_file() {
  local zip_file="$1"
  local out_dir="$2"
  if command -v unzip >/dev/null 2>&1; then
    unzip -q "$zip_file" -d "$out_dir"
  elif command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -Command \
      "Expand-Archive -Path '$(convert_path_windows "$zip_file")' -DestinationPath '$(convert_path_windows "$out_dir")' -Force"
  else
    echo "[oogit] No unzip or PowerShell found" >&2
    exit 1
  fi
}

init_command() {
  local ooxml_file=""
  local repo_url=""
  local branch=""
  local path_in_repo="/root"

  local commit_message=""
  local expected_commit_hash=""
  local force=false

  local args=()
  local parsing_options=true

  while [[ $# -gt 0 ]]; do
    if [[ "$parsing_options" == "true" ]]; then
      case $1 in
        --)
          parsing_options=false
          shift
          ;;
        -m|--message)
          if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
            commit_message="$2"
            shift 2
          else
            echo "[oogit] Error: -m/--message requires a value" >&2
            exit 1
          fi
          ;;
        -c|--commit-hash)
          if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
            expected_commit_hash="$2"
            shift 2
          else
            echo "[oogit] Error: -c/--commit-hash requires a value" >&2
            exit 1
          fi
          ;;
        -f|--force)
          force=true
          shift
          ;;
        -*)
          echo "[oogit] Error: Unknown option $1" >&2
          exit 1
          ;;
        *)
          parsing_options=false
          args+=("$1")
          shift
          ;;
      esac
    else
      args+=("$1")
      shift
    fi
  done

  if [[ ${#args[@]} -lt 2 ]]; then
    echo "[oogit] Error: init requires at least ooxml-file and git-repo arguments" >&2
    exit 1
  fi

  ooxml_file="${args[0]}"
  repo_url="${args[1]}"

  if [[ ${#args[@]} -gt 2 ]]; then
    branch="${args[2]}"
  fi

  if [[ ${#args[@]} -gt 3 ]]; then
    path_in_repo="${args[3]}"
  fi

  # ================================================================ parsing end

  if [[ "${path_in_repo:0:1}" != "/" ]]; then
    path_in_repo="/$path_in_repo"
  fi
  if [[ "$path_in_repo" == "/" ]]; then
    echo "[oogit] Error: path_in_repo cannot be /" >&2
    exit 1
  fi

  setup_dirs "$ooxml_file"
  local meta_file="$META_FILE"
  rm -rf "$REPO_DIR"

  if [[ "$force" == "false" ]]; then
    if [[ -f "$meta_file" ]]; then
      echo "[oogit] $meta_file already exists. Please run with --force option to overwrite." >&2
      exit 1
    fi
  fi

  if [[ -n "$branch" ]]; then
    if ! my_git clone --branch "$branch" --single-branch -- "$repo_url" "$REPO_DIR" 2>/dev/null; then
      echo "[oogit] Branch '$branch' not found, creating new branch"
      my_git clone --single-branch --depth 1 -- "$repo_url" "$REPO_DIR"
      my_pushd "$REPO_DIR"
      my_git checkout --orphan "$branch"
      my_git reset --hard
      my_popd
    fi
  else
    my_git clone --single-branch -- "$repo_url" "$REPO_DIR"
    my_pushd "$REPO_DIR"
    branch=$(git branch --show-current)
    my_popd
  fi

  if [[ -n "$expected_commit_hash" ]]; then
    my_pushd "$REPO_DIR"
    local current_commit_hash=$(git rev-parse HEAD)
    my_popd
    if [[ "$current_commit_hash" != "$expected_commit_hash" ]]; then
      echo "[oogit] Error: Commit hash mismatch" >&2
      exit 1
    fi
  fi

  rm -rf "$REPO_DIR$path_in_repo"
  mkdir -p "$REPO_DIR$path_in_repo"

  unzip_file "$ooxml_file" "$REPO_DIR$path_in_repo"

  my_pushd "$REPO_DIR"
  my_git add .
  if [[ -n "$commit_message" ]]; then
    my_git commit -m "$commit_message"
  else
    git commit
  fi

  local remote_name=$(git remote | head -n1)
  if [[ -z "$remote_name" ]]; then
    echo "[oogit] Error: No remote found" >&2
    exit 1
  fi
  my_git push --set-upstream "$remote_name" "$branch"

  local commit_hash=$(git rev-parse HEAD)
  my_popd

  cat > "$meta_file" <<EOF
1
$repo_url
$path_in_repo
${branch}
$commit_hash
EOF
}

checkout_command() {
  local ooxml_file=""
  local repo_url=""
  local branch_or_commit=""
  local path_in_repo="/root"

  local force=false

  local args=()
  local parsing_options=true

  while [[ $# -gt 0 ]]; do
    if [[ "$parsing_options" == "true" ]]; then
      case $1 in
        --)
          parsing_options=false
          shift
          ;;
        -f|--force)
          force=true
          shift
          ;;
        -*)
          echo "[oogit] Error: Unknown option $1" >&2
          exit 1
          ;;
        *)
          parsing_options=false
          args+=("$1")
          shift
          ;;
      esac
    else
      args+=("$1")
      shift
    fi
  done

  if [[ ${#args[@]} -lt 2 ]]; then
    echo "[oogit] Error: checkout requires at least ooxml-file and git-repo arguments" >&2
    exit 1
  fi

  ooxml_file="${args[0]}"
  repo_url="${args[1]}"

  if [[ ${#args[@]} -gt 2 ]]; then
    branch_or_commit="${args[2]}"
  fi

  if [[ ${#args[@]} -gt 3 ]]; then
    path_in_repo="${args[3]}"
  fi

  # ================================================================ parsing end

  if [[ "${path_in_repo:0:1}" != "/" ]]; then
    path_in_repo="/$path_in_repo"
  fi
  if [[ "$path_in_repo" == "/" ]]; then
    echo "[oogit] Error: path_in_repo cannot be /" >&2
    exit 1
  fi

  setup_dirs "$ooxml_file"
  local meta_file="$META_FILE"

  if [[ "$force" == "false" ]]; then
    if [[ -f "$ooxml_file" ]]; then
      echo "[oogit] $ooxml_file already exists. Please run with --force option to overwrite." >&2
      exit 1
    fi
    if [[ -f "$meta_file" ]]; then
      echo "[oogit] $meta_file already exists. Please run with --force option to overwrite." >&2
      exit 1
    fi
  fi

  rm -rf "$REPO_DIR"
  my_git init "$REPO_DIR"
  my_pushd "$REPO_DIR"
  my_git remote add origin "$repo_url"
  if [[ -n "$branch_or_commit" ]]; then
    my_git fetch --depth 1 origin "$branch_or_commit"
  else
    my_git fetch --depth 1 origin
  fi
  my_git checkout FETCH_HEAD

  local commit_hash=$(git rev-parse HEAD)
  my_popd

  if [[ "$path_in_repo" = "/" ]]; then
    zip_dir "$REPO_DIR" "$TEMP_DIR/output.zip"
    mv "$TEMP_DIR/output.zip" "$ooxml_file"
  else
    zip_dir "$REPO_DIR$path_in_repo" "$TEMP_DIR/output.zip"
    mv "$TEMP_DIR/output.zip" "$ooxml_file"
  fi

  cat > "$meta_file" <<EOF
1
$repo_url
$path_in_repo
${branch_or_commit}
$commit_hash
EOF
}

commit_command() {
  local ooxml_file=""
  local commit_message=""

  local expected_commit_hash=""

  local args=()
  local parsing_options=true

  while [[ $# -gt 0 ]]; do
    if [[ "$parsing_options" == "true" ]]; then
      case $1 in
        --)
          parsing_options=false
          shift
          ;;
        -m|--message)
          if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
            commit_message="$2"
            shift 2
          else
            echo "[oogit] Error: -m/--message requires a value" >&2
            exit 1
          fi
          ;;
        -*)
          echo "[oogit] Error: Unknown option $1" >&2
          exit 1
          ;;
        *)
          parsing_options=false
          args+=("$1")
          shift
          ;;
      esac
    else
      args+=("$1")
      shift
    fi
  done

  if [[ ${#args[@]} -lt 1 ]]; then
    echo "[oogit] Error: commit requires ooxml-file argument" >&2
    exit 1
  fi

  ooxml_file="${args[0]}"

  # ================================================================ parsing end

  setup_dirs "$ooxml_file"
  local meta_file="$META_FILE"

  if [[ ! -f "$ooxml_file" ]]; then
    echo "[oogit] $ooxml_file not found. Please run checkout command first." >&2
    exit 1
  fi
  if [[ ! -f "$meta_file" ]]; then
    echo "[oogit] $meta_file not found. Please run init or checkout command first." >&2
    exit 1
  fi

  local lines=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    lines+=("$line")
  done < "$meta_file"

  local file_version="${lines[0]}"
  local repo_url="${lines[1]}"
  local path_in_repo="${lines[2]}"
  local branch="${lines[3]}"
  local commit_hash="${lines[4]}"

  if [[ "$file_version" != "1" ]]; then
    echo "[oogit] Error: Unsupported file version: $file_version" >&2
    exit 1
  fi

  local init_args=()

  if [[ -n "$commit_message" ]]; then
    init_args+=("-m" "$commit_message")
  fi

  if [[ -n "$commit_hash" ]]; then
    init_args+=("-c" "$commit_hash")
  fi

  init_args+=("--force" "--" "$ooxml_file" "$repo_url" "$branch" "$path_in_repo")

  init_command "${init_args[@]}"
}

update_command() {
  local ooxml_file=""

  local force=false

  local args=()
  local parsing_options=true

  while [[ $# -gt 0 ]]; do
    if [[ "$parsing_options" == "true" ]]; then
      case $1 in
        --)
          parsing_options=false
          shift
          ;;
        -f|--force)
          force=true
          shift
          ;;
        -*)
          echo "[oogit] Error: Unknown option $1" >&2
          exit 1
          ;;
        *)
          parsing_options=false
          args+=("$1")
          shift
          ;;
      esac
    else
      args+=("$1")
      shift
    fi
  done

  if [[ ${#args[@]} -lt 1 ]]; then
    echo "[oogit] Error: commit requires ooxml-file argument" >&2
    exit 1
  fi

  ooxml_file="${args[0]}"

  # ================================================================ parsing end

  setup_dirs "$ooxml_file"
  local meta_file="$META_FILE"

  if [[ ! -f "$ooxml_file" ]]; then
    echo "[oogit] $ooxml_file not found. Please run checkout command first." >&2
    exit 1
  fi
  if [[ ! -f "$meta_file" ]]; then
    echo "[oogit] $meta_file not found. Please run init or checkout command first." >&2
    exit 1
  fi

  local lines=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    lines+=("$line")
  done < "$meta_file"

  local file_version="${lines[0]}"
  local repo_url="${lines[1]}"
  local path_in_repo="${lines[2]}"
  local branch="${lines[3]}"
  local commit_hash="${lines[4]}"

  if [[ "$file_version" != "1" ]]; then
    echo "[oogit] Error: Unsupported file version: $file_version" >&2
    exit 1
  fi

  rm -rf "$REPO_DIR"
  if [[ -n "$branch" ]]; then
    my_git clone --branch "$branch" --single-branch -- "$repo_url" "$REPO_DIR"
  else
    my_git clone --single-branch -- "$repo_url" "$REPO_DIR"
  fi

  my_pushd "$REPO_DIR"
  my_git reset --hard "$commit_hash"
  my_popd

  rm -rf "$REPO_DIR$path_in_repo"
  mkdir -p "$REPO_DIR$path_in_repo"

  unzip_file "$ooxml_file" "$REPO_DIR$path_in_repo"

  my_pushd "$REPO_DIR"
  my_git add .
  if [[ -n "$commit_message" ]]; then
    my_git commit -m "$commit_message"
  else
    git commit
  fi

  my_git pull

  local commit_hash=$(git rev-parse HEAD)
  my_popd

  cat > "$meta_file" <<EOF
1
$repo_url
$path_in_repo
${branch}
$commit_hash
EOF
}

reset_command() {
  local ooxml_file=""
  local tag_or_commit=""

  local args=()
  local parsing_options=true

  while [[ $# -gt 0 ]]; do
    if [[ "$parsing_options" == "true" ]]; then
      case $1 in
        --)
          parsing_options=false
          shift
          ;;
        -*)
          echo "[oogit] Error: Unknown option $1" >&2
          exit 1
          ;;
        *)
          parsing_options=false
          args+=("$1")
          shift
          ;;
      esac
    else
      args+=("$1")
      shift
    fi
  done

  if [[ ${#args[@]} -lt 1 ]]; then
    echo "[oogit] Error: commit requires ooxml-file argument" >&2
    exit 1
  fi

  ooxml_file="${args[0]}"

  if [[ ${#args[@]} -gt 1 ]]; then
    tag_or_commit="${args[1]}"
  fi

  # ================================================================ parsing end

  setup_dirs "$ooxml_file"
  local meta_file="$META_FILE"

  if [[ ! -f "$ooxml_file" ]]; then
    echo "[oogit] $ooxml_file not found. Please run checkout command first." >&2
    exit 1
  fi
  if [[ ! -f "$meta_file" ]]; then
    echo "[oogit] $meta_file not found. Please run init or checkout command first." >&2
    exit 1
  fi

  local lines=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    lines+=("$line")
  done < "$meta_file"

  local file_version="${lines[0]}"
  local repo_url="${lines[1]}"
  local path_in_repo="${lines[2]}"
  local branch="${lines[3]}"
  local commit_hash="${lines[4]}"

  if [[ "$file_version" != "1" ]]; then
    echo "[oogit] Error: Unsupported file version: $file_version" >&2
    exit 1
  fi

  rm -rf "$REPO_DIR"
  my_git init "$REPO_DIR"
  my_pushd "$REPO_DIR"
  my_git remote add origin "$repo_url"
  if [[ -n "$tag_or_commit" ]]; then
    my_git fetch --depth 1 origin "$tag_or_commit"
  else
    my_git fetch --depth 1 origin
  fi
  my_git checkout FETCH_HEAD

  local new_commit_hash=$(git rev-parse HEAD)
  my_popd

  if [[ "$path_in_repo" = "/" ]]; then
    zip_dir "$REPO_DIR" "$TEMP_DIR/output.zip"
    mv "$TEMP_DIR/output.zip" "$ooxml_file"
  else
    zip_dir "$REPO_DIR$path_in_repo" "$TEMP_DIR/output.zip"
    mv "$TEMP_DIR/output.zip" "$ooxml_file"
  fi

  cat > "$meta_file" <<EOF
1
$repo_url
$path_in_repo
${branch}
$new_commit_hash
EOF
}

version_command() {
  echo "oogit 0.0.2"
}

help_command() {
  local exit_code="$1"

  version_command

  cat <<EOF
Usage: $NAME {help|init|checkout|commit|update|reset} ...

Commands:
  help
  init [...options] <ooxml-file> <git-repo> [branch] [path-in-repo]
  checkout [...options] <ooxml-file> <git-repo> [branch-or-commit] [path-in-repo]
  commit [...options] <ooxml-file>
  update [...options] <ooxml-file>
  reset [...options] <ooxml-file> [tag-or-commit]

Options:
  -v, --version             Show version and exit
  -h, --help                Show this help message and exit
  --                        End of optionstreat remaining arguments as positional
  -m, --message <message>   Specify commit message
                            for init/commit command
  -c, --commit-hash <hash>  Exit with code 1 if latest commit hash does not match
                            for init command
  -f, --force               Overwrite existing file
                            for init/checkout/update command

Environment Variables:
  V, VERBOSE                1/true: show verbose output
                            others: show only errors

Examples:
  # initial commit on your machine (it will generate report.pptx.oogit file as well)
  $NAME init report.pptx https://github.com/example/repo.git documents/report
  # init with custom commit message
  $NAME init -m "Initial commit" report.pptx https://github.com/example/repo.git documents/report
  # init with filename starting with dash (use -- separator)
  $NAME init -m "Initial commit" -- -filename-starts-with-dash.pptx https://github.com/example/repo.git
  # checkout/clone/pull (it will generate report.pptx.oogit file as well)
  $NAME checkout report.pptx https://github.com/example/repo.git documents/report
  # usual commit - requires report.pptx.oogit file
  $NAME commit report.pptx
  # usual update - requires report.pptx.oogit file, conflicts will not be resolved
  $NAME update report.pptx
  # reset when you want to revert to the original state
  $NAME reset report.pptx
EOF

  exit "$exit_code"
}

# Entry Point

if [[ $# -eq 0 ]]; then
  help_command 0
fi

COMMAND=$1
shift || true

case "$COMMAND" in
  init)
    init_command "$@"
    ;;
  checkout)
    checkout_command "$@"
    ;;
  commit)
    commit_command "$@"
    ;;
  update)
    update_command "$@"
    ;;
  reset)
    reset_command "$@"
    ;;
  version|--version|-v)
    version_command
    ;;
  help|--help|-h)
    help_command 0
    ;;
  *)
    help_command 1
    ;;
esac
