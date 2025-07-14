#!/bin/bash

set -euo pipefail

TMP_DIR="tmp"
rm -rf "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bare-repo.git"
REPO=$(cd "$TMP_DIR/bare-repo.git" && pwd)
rm -rf "$REPO"
git init --bare "$REPO" >/dev/null

DOC_DIR="$TMP_DIR/doc"
prepare_doc() {
  local ooxml_file="$1"
  local content="$2"

  rm -rf "$ooxml_file"
  rm -rf "$DOC_DIR"
  mkdir "$DOC_DIR"
  echo "$content" > "$DOC_DIR/content.txt"
  pushd "$DOC_DIR" >/dev/null
  zip -q ../output.zip -r .
  popd >/dev/null
  rm -rf "$DOC_DIR"
  mv "$TMP_DIR/output.zip" "$ooxml_file"
}

# init command

prepare_doc "$TMP_DIR/root.docx" "hello"
bash oogit.sh init -m "initial" "$TMP_DIR/root.docx" "$REPO" main

git clone --branch main "$REPO" "$TMP_DIR/tmp-repo"
echo "hello" | diff - "$TMP_DIR/tmp-repo/root/content.txt"
pushd "$TMP_DIR/tmp-repo" >/dev/null
COMMIT_HASH1=$(git rev-parse HEAD)
popd >/dev/null
rm -rf "$TMP_DIR/tmp-repo"
cat <<EOF | diff - "$TMP_DIR/root.docx.oogit/metadata"
1
$REPO
/root
main
$COMMIT_HASH1
EOF

prepare_doc "$TMP_DIR/other.docx" "hello"
bash oogit.sh init -m "init other" "$TMP_DIR/other.docx" "$REPO" main other

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
/root
main
$COMMIT_HASH1
EOF
cat <<EOF | diff - "$TMP_DIR/other.docx.oogit/metadata"
1
$REPO
/other
main
$COMMIT_HASH2
EOF

prepare_doc "$TMP_DIR/other.docx" "bye"
! bash oogit.sh init -m "overwrite" "$TMP_DIR/other.docx" "$REPO" main 2>"$TMP_DIR/error.txt"

diff - "$TMP_DIR/error.txt" <<EOF
[oogit] tmp/other.docx.oogit/metadata already exists. Please run with --force option to overwrite.
EOF

bash oogit.sh init -m "force overwrite" --force "$TMP_DIR/other.docx" "$REPO" main other

git clone --branch main "$REPO" "$TMP_DIR/tmp-repo"
pushd "$TMP_DIR/tmp-repo" >/dev/null
COMMIT_HASH2=$(git rev-parse HEAD)
popd >/dev/null
rm -rf "$TMP_DIR/tmp-repo"
cat <<EOF | diff - "$TMP_DIR/root.docx.oogit/metadata"
1
$REPO
/root
main
$COMMIT_HASH1
EOF
cat <<EOF | diff - "$TMP_DIR/other.docx.oogit/metadata"
1
$REPO
/other
main
$COMMIT_HASH2
EOF

prepare_doc "$TMP_DIR/another.docx" "another"
bash oogit.sh init -m "init another" "$TMP_DIR/another.docx" "$REPO" main another

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
/root
main
$COMMIT_HASH1
EOF
cat <<EOF | diff - "$TMP_DIR/other.docx.oogit/metadata"
1
$REPO
/other
main
$COMMIT_HASH2
EOF
cat <<EOF | diff - "$TMP_DIR/another.docx.oogit/metadata"
1
$REPO
/another
main
$COMMIT_HASH3
EOF

prepare_doc "$TMP_DIR/branch.docx" "isolated"
bash oogit.sh init -m "init branch" "$TMP_DIR/branch.docx" "$REPO" branch

git clone --branch branch "$REPO" "$TMP_DIR/tmp-repo"
echo "isolated" | diff - "$TMP_DIR/tmp-repo/root/content.txt"
pushd "$TMP_DIR/tmp-repo" >/dev/null
git rev-list --max-count=3 HEAD | wc -l | tr -d '[:space:]' | grep -q 1
popd >/dev/null
rm -rf "$TMP_DIR/tmp-repo"

# checkout command

bash oogit.sh checkout "$TMP_DIR/checkout.docx" "$REPO" main

unzip -q "$TMP_DIR/checkout.docx" -d "$DOC_DIR"
echo "hello" | diff - "$DOC_DIR/content.txt"
rm -rf "$DOC_DIR"
cat <<EOF | diff - "$TMP_DIR/checkout.docx.oogit/metadata"
1
$REPO
/root
main
$COMMIT_HASH3
EOF

# update command

bash oogit.sh update -m "not needed" "$TMP_DIR/root.docx"

unzip -q "$TMP_DIR/root.docx" -d "$DOC_DIR"
echo "hello" | diff - "$DOC_DIR/content.txt"
rm -rf "$DOC_DIR"
cat <<EOF | diff - "$TMP_DIR/root.docx.oogit/metadata"
1
$REPO
/root
main
$COMMIT_HASH3
EOF

# commit command

prepare_doc "$TMP_DIR/commit.docx" "original"
bash oogit.sh init -m "init commit" --force "$TMP_DIR/commit.docx" "$REPO" main
prepare_doc "$TMP_DIR/commit.docx" "updated"
bash oogit.sh commit -m "update commit" "$TMP_DIR/commit.docx"
bash oogit.sh update -m "not needed" "$TMP_DIR/root.docx"

git clone --branch main "$REPO" "$TMP_DIR/tmp-repo"
echo "updated" | diff - "$TMP_DIR/tmp-repo/root/content.txt"
pushd "$TMP_DIR/tmp-repo" >/dev/null
COMMIT_HASH4=$(git rev-parse HEAD)
popd >/dev/null
rm -rf "$TMP_DIR/tmp-repo"
unzip -q "$TMP_DIR/commit.docx" -d "$DOC_DIR"
echo "updated" | diff - "$DOC_DIR/content.txt"
rm -rf "$DOC_DIR"
cat <<EOF | diff - "$TMP_DIR/commit.docx.oogit/metadata"
1
$REPO
/root
main
$COMMIT_HASH4
EOF

# reset command

bash oogit.sh reset "$TMP_DIR/root.docx" "$COMMIT_HASH1"

unzip -q "$TMP_DIR/root.docx" -d "$DOC_DIR"
echo "hello" | diff - "$DOC_DIR/content.txt"
rm -rf "$DOC_DIR"
cat <<EOF | diff - "$TMP_DIR/root.docx.oogit/metadata"
1
$REPO
/root
main
$COMMIT_HASH1
EOF
