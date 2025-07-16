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

silent_pushd() {
  local dir="$1"

  if [[ "$VERBOSE" == "true" ]]; then
    pushd "$dir"
  else
    pushd "$dir" > /dev/null
  fi
}

silent_popd() {
  if [[ "$VERBOSE" == "true" ]]; then
    popd
  else
    popd > /dev/null
  fi
}

silent_git() {
  if [[ "$VERBOSE" == "true" ]]; then
    git "$@"
  else
    git "$@" > /dev/null 2>&1
  fi
}

# Load metadata from $META_FILE and expose the result via global variables
load_metadata() {
  if [[ ! -f "$META_FILE" ]]; then
    echo "[oogit] $META_FILE not found. Please run init or checkout command first." >&2
    exit 1
  fi

  local lines=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    lines+=("$line")
  done < "$META_FILE"

  METADATA_VERSION="${lines[0]}"
  METADATA_REPO_URL="${lines[1]}"
  METADATA_PATH_IN_REPO="${lines[2]}"
  METADATA_BRANCH="${lines[3]}"
  METADATA_COMMIT_HASH="${lines[4]}"

  if [[ "$METADATA_VERSION" != "1" ]]; then
    echo "[oogit] Error: Unsupported file version: $METADATA_VERSION" >&2
    exit 1
  fi
}

ensure_dirs() {
  local ooxml_file="$1"

  META_DIR="${ooxml_file}.oogit"
  META_FILE="$META_DIR/metadata"
  REPO_DIR="$META_DIR/repo"
  TEMP_DIR="$META_DIR/tmp"

  rm -rf "$TEMP_DIR"
  trap 'rm -rf "$TEMP_DIR"' EXIT INT TERM

  if [[ ! -d "$META_DIR" ]]; then
    echo "[oogit] Error: $META_DIR does not exist" >&2
    exit 1
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
  trap 'rm -rf "$TEMP_DIR"' EXIT INT TERM
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
    local out_file_absolute=$(cd "$(dirname "$out_file")" && pwd)/$(basename "$out_file")
    (cd "$src_dir" && zip -qr "$out_file_absolute" .)
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


fetch_and_reset() {
  local repo_dir="$1"
  local commit_hash="$2"

  silent_pushd "$repo_dir"
  silent_git fetch
  silent_git reset --hard "$commit_hash"
  silent_popd
}

unzip_file_to_repo() {
  local repo_dir="$1"
  local path_in_repo="$2"
  local ooxml_file="$3"

  rm -rf "$repo_dir$path_in_repo"
  mkdir -p "$repo_dir$path_in_repo"
  unzip_file "$ooxml_file" "$repo_dir$path_in_repo"
}

my_git_commit() {
  local repo_dir="$1"
  local path_in_repo="$2"
  local commit_message="$3"

  silent_pushd "$repo_dir$path_in_repo"
  silent_git add .
  if ! silent_git diff-index --quiet HEAD; then
    if [[ -n "$commit_message" ]]; then
      silent_git commit -m "$commit_message"
    else
      git commit
    fi
  fi
  silent_popd
}

my_git_commit_intermediate() {
  local repo_dir="$1"
  local path_in_repo="$2"

  silent_pushd "$repo_dir$path_in_repo"
  silent_git add .
  silent_popd
  silent_pushd "$repo_dir"
  TMP_INDEX=0
  while true; do
    IFS= read -r -d '' status || break
    IFS= read -r -d '' file || break
    if [[ "$status" == A || "$status" == M || "$status" == R ]] && [[ -f "$file" ]]; then
      mv "$file" "${path_in_repo#/}/oogit-intermediate-name-$TMP_INDEX"
      ((TMP_INDEX++)) || true
    fi
  done < <(git diff --cached --name-status -z)
  if [[ "$TMP_INDEX" -gt 0 ]]; then
    silent_git add .
    if ! silent_git diff-index --quiet HEAD; then
      silent_git commit -m "[oogit-intermediate-commit]"
    fi
  fi
  silent_popd
}

git_pull() {
  local repo_dir="$1"

  silent_pushd "$REPO_DIR"
  silent_git pull --no-rebase
  silent_popd
}

git_push() {
  local repo_dir="$1"
  local branch="$2"

  silent_pushd "$REPO_DIR"

  local remote_name=$(git remote | head -n1)
  if [[ -z "$remote_name" ]]; then
    echo "[oogit] Error: No remote found" >&2
    exit 1
  fi
  silent_git push --set-upstream "$remote_name" "$branch"
  silent_popd
}

git_get_commit_hash() {
  local repo_dir="$1"

  silent_pushd "$repo_dir"
  git rev-parse HEAD
  silent_popd
}

zip_dir_from_repo() {
  local repo_dir="$1"
  local path_in_repo="$2"
  local ooxml_file="$3"

  mkdir -p "$TEMP_DIR"
  zip_dir "$repo_dir$path_in_repo" "$TEMP_DIR/output.zip"
  mv "$TEMP_DIR/output.zip" "$ooxml_file"
}

write_metadata() {
  local repo_url="$1"
  local path_in_repo="$2"
  local branch="$3"
  local commit_hash="$4"

  cat > "$META_FILE" <<EOF
1
$repo_url
$path_in_repo
$branch
$commit_hash
EOF
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

  if [[ "$force" == "false" ]]; then
    if [[ -f "$META_FILE" ]]; then
      echo "[oogit] $META_FILE already exists. Please run with --force option to overwrite." >&2
      exit 1
    fi
    if [[ -d "$REPO_DIR" ]]; then
      echo "[oogit] $REPO_DIR already exists. Please run with --force option to overwrite." >&2
      exit 1
    fi
  fi

  rm -rf "$REPO_DIR"

  if [[ -n "$branch" ]]; then
    if ! silent_git clone --branch "$branch" --single-branch -- "$repo_url" "$REPO_DIR" 2>/dev/null; then
      echo "[oogit] Branch '$branch' not found, creating new branch"
      silent_git clone --single-branch --depth 1 -- "$repo_url" "$REPO_DIR"
      silent_pushd "$REPO_DIR"
      silent_git checkout --orphan "$branch"
      silent_git reset --hard
      silent_popd
    fi
  else
    silent_git clone --single-branch -- "$repo_url" "$REPO_DIR"
    silent_pushd "$REPO_DIR"
    branch=$(git branch --show-current)
    silent_popd
  fi

  if [[ -n "$expected_commit_hash" ]]; then
    silent_pushd "$REPO_DIR"
    local current_commit_hash=$(git rev-parse HEAD)
    silent_popd
    if [[ "$current_commit_hash" != "$expected_commit_hash" ]]; then
      echo "[oogit] Error: Commit hash mismatch" >&2
      exit 1
    fi
  fi

  unzip_file_to_repo "$REPO_DIR" "$path_in_repo" "$ooxml_file"
  my_git_commit_intermediate "$REPO_DIR" "$path_in_repo"
  unzip_file_to_repo "$REPO_DIR" "$path_in_repo" "$ooxml_file"
  my_git_commit "$REPO_DIR" "$path_in_repo" "$commit_message"
  git_push "$REPO_DIR" "$branch"
  local commit_hash=$(git_get_commit_hash "$REPO_DIR")
  write_metadata "$repo_url" "$path_in_repo" "$branch" "$commit_hash"
}

checkout_command() {
  local ooxml_file=""
  local repo_url=""
  local branch=""
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

  if [[ "$force" == "false" ]]; then
    if [[ -f "$ooxml_file" ]]; then
      echo "[oogit] $ooxml_file already exists. Please run with --force option to overwrite." >&2
      exit 1
    fi
    if [[ -f "$META_FILE" ]]; then
      echo "[oogit] $META_FILE already exists. Please run with --force option to overwrite." >&2
      exit 1
    fi
  fi

  if [[ -n "$branch" ]]; then
    silent_git clone --branch "$branch" --single-branch -- "$repo_url" "$REPO_DIR"
  else
    silent_git clone --single-branch -- "$repo_url" "$REPO_DIR"
    silent_pushd "$REPO_DIR"
    branch=$(git branch --show-current)
    silent_popd
  fi

  zip_dir_from_repo "$REPO_DIR" "$path_in_repo" "$ooxml_file"
  local commit_hash=$(git_get_commit_hash "$REPO_DIR")
  write_metadata "$repo_url" "$path_in_repo" "$branch" "$commit_hash"
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

  ensure_dirs "$ooxml_file"

  if [[ ! -f "$ooxml_file" ]]; then
    echo "[oogit] $ooxml_file not found. Please run checkout command first." >&2
    exit 1
  fi
  load_metadata
  local repo_url="$METADATA_REPO_URL"
  local path_in_repo="$METADATA_PATH_IN_REPO"
  local branch="$METADATA_BRANCH"
  local commit_hash="$METADATA_COMMIT_HASH"

  fetch_and_reset "$REPO_DIR" "$commit_hash"
  unzip_file_to_repo "$REPO_DIR" "$path_in_repo" "$ooxml_file"
  my_git_commit_intermediate "$REPO_DIR" "$path_in_repo"
  unzip_file_to_repo "$REPO_DIR" "$path_in_repo" "$ooxml_file"
  my_git_commit "$REPO_DIR" "$path_in_repo" "$commit_message"
  git_pull "$REPO_DIR"
  git_push "$REPO_DIR" "$branch"
  local commit_hash=$(git_get_commit_hash "$REPO_DIR")
  write_metadata "$repo_url" "$path_in_repo" "$branch" "$commit_hash"
}

update_command() {
  local ooxml_file=""

  local commit_message=""
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

  ensure_dirs "$ooxml_file"

  if [[ ! -f "$ooxml_file" ]]; then
    echo "[oogit] $ooxml_file not found. Please run checkout command first." >&2
    exit 1
  fi
  load_metadata
  local repo_url="$METADATA_REPO_URL"
  local path_in_repo="$METADATA_PATH_IN_REPO"
  local branch="$METADATA_BRANCH"
  local commit_hash="$METADATA_COMMIT_HASH"

  fetch_and_reset "$REPO_DIR" "$commit_hash"
  unzip_file_to_repo "$REPO_DIR" "$path_in_repo" "$ooxml_file"
  my_git_commit_intermediate "$REPO_DIR" "$path_in_repo"
  unzip_file_to_repo "$REPO_DIR" "$path_in_repo" "$ooxml_file"
  my_git_commit "$REPO_DIR" "$path_in_repo" "$commit_message"
  git_pull "$REPO_DIR"
  git_push "$REPO_DIR" "$branch"
  local commit_hash=$(git_get_commit_hash "$REPO_DIR")
  write_metadata "$repo_url" "$path_in_repo" "$branch" "$commit_hash"
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

  ensure_dirs "$ooxml_file"

  if [[ ! -f "$ooxml_file" ]]; then
    echo "[oogit] $ooxml_file not found. Please run checkout command first." >&2
    exit 1
  fi
  load_metadata
  local repo_url="$METADATA_REPO_URL"
  local path_in_repo="$METADATA_PATH_IN_REPO"
  local branch="$METADATA_BRANCH"
  local commit_hash="$METADATA_COMMIT_HASH"

  silent_pushd "$REPO_DIR"
  silent_git fetch
  silent_git reset --hard "$tag_or_commit"
  local new_commit_hash=$(git rev-parse HEAD)
  silent_popd

  zip_dir_from_repo "$REPO_DIR" "$path_in_repo" "$ooxml_file"
  write_metadata "$repo_url" "$path_in_repo" "$branch" "$new_commit_hash"
}

version_command() {
  echo "oogit 0.2.2"
}

help_command() {
  local exit_code="$1"

  version_command

  cat <<EOF
Usage: $NAME {help|init|checkout|commit|update|reset} ...

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
  --                        End of optionstreat remaining arguments as positional
  -m, --message <message>   Specify commit message
                            for init/commit/update command
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
