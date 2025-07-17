#!/bin/bash

set -euo pipefail

TMP_DIR="tmp"
rm -rf "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

oogit() {
  powershell -ExecutionPolicy Bypass -File oogit.ps1 "$@"
}

mkdir -p "$TMP_DIR/bare-repo.git"
REPO=$(cd "$TMP_DIR/bare-repo.git" && pwd)
rm -rf "$REPO"
git init --bare "$REPO" >/dev/null

# may create parent directory if it does not exist
convert_path_windows() {
  if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    if [[ -d "$(dirname "$1")" ]]; then
      (cd "$(dirname "$1")" && (pwd -W | tr -d '[:space:]' && echo "/$(basename "$1")") | tr '/' '\\')
    else
      mkdir -p "$(dirname "$1")"
      (cd "$(dirname "$1")" && (pwd -W | tr -d '[:space:]' && echo "/$(basename "$1")") | tr '/' '\\')
      rm -rf "$(dirname "$1")"
    fi
  else
    echo "$1"
  fi
}

zip_dir() {
  local src_dir="$1"
  local out_file="$2"
  powershell.exe -NoProfile -Command \
    "Compress-Archive -Path '$(convert_path_windows "$src_dir")\\*' -DestinationPath '$(convert_path_windows "$TMP_DIR/output.zip")' -Force" || die "zip failed"
  mv "$TMP_DIR/output.zip" "$out_file"
}

unzip_file() {
  local zip_file="$1"
  local out_dir="$2"
  powershell.exe -NoProfile -Command \
    "Expand-Archive -Path '$(convert_path_windows "$zip_file")' -DestinationPath '$(convert_path_windows "$out_dir")' -Force" || die "unzip failed"
}

DOC_DIR="$TMP_DIR/doc"
prepare_doc() {
  local ooxml_file="$1"
  local content="$2"

  rm -rf "$ooxml_file"
  rm -rf "$DOC_DIR"
  mkdir "$DOC_DIR"
  echo "$content" > "$DOC_DIR/content.txt"
  zip_dir "$DOC_DIR" "$ooxml_file"
  rm -rf "$DOC_DIR"
}

# init command

prepare_doc "$TMP_DIR/root.docx" "hello"
oogit init -m "initial" "$(convert_path_windows "$TMP_DIR/root.docx")" "$(convert_path_windows "$REPO")" main

git clone --branch main "$REPO" "$TMP_DIR/tmp-repo"
echo "hello" | diff - "$TMP_DIR/tmp-repo/root/content.txt"
pushd "$TMP_DIR/tmp-repo" >/dev/null
COMMIT_HASH1=$(git rev-parse HEAD)
popd >/dev/null
rm -rf "$TMP_DIR/tmp-repo"
cat <<EOF | diff - "$TMP_DIR/root.docx.oogit/metadata"
1
$REPO
\root
main
$COMMIT_HASH1
EOF

prepare_doc "$TMP_DIR/other.docx" "hello"
oogit init -m "init other" "$(convert_path_windows "$TMP_DIR/other.docx")" "$(convert_path_windows "$REPO")" main other

git clone --branch main "$REPO" "$TMP_DIR/tmp-repo"
echo "hello" | diff - "$TMP_DIR/tmp-repo/root/content.txt"
echo "hello" | diff - "$TMP_DIR/tmp-repo/other/content.txt"
pushd "$TMP_DIR/tmp-repo" >/dev/null
COMMIT_HASH2=$(git rev-parse HEAD)
popd >/dev/null
rm -rf "$TMP_DIR/tmp-repo"
cat <<EOF | diff - "$TMP_DIR/root.docx.oogit/metadata"
1
$REPO
\root
main
$COMMIT_HASH1
EOF
cat <<EOF | diff - "$TMP_DIR/other.docx.oogit/metadata"
1
$REPO
\other
main
$COMMIT_HASH2
EOF

prepare_doc "$TMP_DIR/other.docx" "bye"
! oogit init -m "overwrite" "$(convert_path_windows "$TMP_DIR/other.docx")" "$(convert_path_windows "$REPO")" main 2>"$TMP_DIR/error.txt"

diff - "$TMP_DIR/error.txt" <<EOF
[oogit] tmp/other.docx.oogit/metadata already exists. Please run with --force option to overwrite.
EOF

oogit init -m "force overwrite" --force "$(convert_path_windows "$TMP_DIR/other.docx")" "$(convert_path_windows "$REPO")" main other

git clone --branch main "$REPO" "$TMP_DIR/tmp-repo"
pushd "$TMP_DIR/tmp-repo" >/dev/null
COMMIT_HASH2=$(git rev-parse HEAD)
popd >/dev/null
rm -rf "$TMP_DIR/tmp-repo"
cat <<EOF | diff - "$TMP_DIR/root.docx.oogit/metadata"
1
$REPO
\root
main
$COMMIT_HASH1
EOF
cat <<EOF | diff - "$TMP_DIR/other.docx.oogit/metadata"
1
$REPO
\other
main
$COMMIT_HASH2
EOF

prepare_doc "$TMP_DIR/another.docx" "another"
oogit init -m "init another" "$(convert_path_windows "$TMP_DIR/another.docx")" "$(convert_path_windows "$REPO")" main another

git clone --branch main "$REPO" "$TMP_DIR/tmp-repo"
echo "hello" | diff - "$TMP_DIR/tmp-repo/root/content.txt"
echo "bye" | diff - "$TMP_DIR/tmp-repo/other/content.txt"
echo "another" | diff - "$TMP_DIR/tmp-repo/another/content.txt"
pushd "$TMP_DIR/tmp-repo" >/dev/null
COMMIT_HASH3=$(git rev-parse HEAD)
popd >/dev/null
rm -rf "$TMP_DIR/tmp-repo"
cat <<EOF | diff - "$TMP_DIR/root.docx.oogit/metadata"
1
$REPO
\root
main
$COMMIT_HASH1
EOF
cat <<EOF | diff - "$TMP_DIR/other.docx.oogit/metadata"
1
$REPO
\other
main
$COMMIT_HASH2
EOF
cat <<EOF | diff - "$TMP_DIR/another.docx.oogit/metadata"
1
$REPO
\another
main
$COMMIT_HASH3
EOF

prepare_doc "$TMP_DIR/branch.docx" "isolated"
oogit init -m "init branch" "$(convert_path_windows "$TMP_DIR/branch.docx")" "$(convert_path_windows "$REPO")" branch

git clone --branch branch "$REPO" "$TMP_DIR/tmp-repo"
echo "isolated" | diff - "$TMP_DIR/tmp-repo/root/content.txt"
pushd "$TMP_DIR/tmp-repo" >/dev/null
git rev-list --max-count=3 HEAD | wc -l | tr -d '[:space:]' | grep -q 2
popd >/dev/null
rm -rf "$TMP_DIR/tmp-repo"

# checkout command

oogit checkout "$(convert_path_windows "$TMP_DIR/checkout.docx")" "$(convert_path_windows "$REPO")" main

unzip_file "$TMP_DIR/checkout.docx" "$DOC_DIR"
echo "hello" | diff - "$DOC_DIR/content.txt"
rm -rf "$DOC_DIR"
cat <<EOF | diff - "$TMP_DIR/checkout.docx.oogit/metadata"
1
$REPO
\root
main
$COMMIT_HASH3
EOF

# update command

oogit update -m "not needed" "$(convert_path_windows "$TMP_DIR/root.docx")"

unzip_file "$TMP_DIR/checkout.docx" "$DOC_DIR"

echo "hello" | diff - "$DOC_DIR/content.txt"
rm -rf "$DOC_DIR"
cat <<EOF | diff - "$TMP_DIR/root.docx.oogit/metadata"
1
$REPO
\root
main
$COMMIT_HASH3
EOF

# commit command

prepare_doc "$TMP_DIR/commit.docx" "original"
oogit init -m "init commit" --force $(convert_path_windows "$TMP_DIR/commit.docx") "$(convert_path_windows "$REPO")" main
prepare_doc "$TMP_DIR/commit.docx" "updated"
oogit commit -m "update commit" $(convert_path_windows "$TMP_DIR/commit.docx")
oogit update -m "not needed" "$(convert_path_windows "$TMP_DIR/root.docx")"

git clone --branch main "$REPO" "$TMP_DIR/tmp-repo"
echo "updated" | diff - "$TMP_DIR/tmp-repo/root/content.txt"
pushd "$TMP_DIR/tmp-repo" >/dev/null
COMMIT_HASH4=$(git rev-parse HEAD)
popd >/dev/null
rm -rf "$TMP_DIR/tmp-repo"
unzip_file "$TMP_DIR/commit.docx" "$DOC_DIR"
echo "updated" | diff - "$DOC_DIR/content.txt"
rm -rf "$DOC_DIR"
cat <<EOF | diff - "$TMP_DIR/commit.docx.oogit/metadata"
1
$REPO
\root
main
$COMMIT_HASH4
EOF

# reset command

oogit reset "$(convert_path_windows "$TMP_DIR/root.docx")" "$COMMIT_HASH1"

unzip_file "$TMP_DIR/checkout.docx" "$DOC_DIR"

echo "hello" | diff - "$DOC_DIR/content.txt"
rm -rf "$DOC_DIR"
cat <<EOF | diff - "$TMP_DIR/root.docx.oogit/metadata"
1
$REPO
\root
main
$COMMIT_HASH1
EOF
