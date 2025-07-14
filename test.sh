#!/bin/bash
set -euo pipefail

# Simple test script for oogit using a fake OOXML file (regular zip archive).

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# create bare repository
REPO="$TMP_DIR/repo.git"
git init --bare "$REPO" >/dev/null

# create fake OOXML file (zip)
DOC_DIR="$TMP_DIR/doc"
mkdir "$DOC_DIR"
echo "hello" > "$DOC_DIR/hello.txt"
zip -q "$TMP_DIR/test.docx" -r "$DOC_DIR"

# default git user for automated commits
export GIT_AUTHOR_NAME="test"
export GIT_AUTHOR_EMAIL="test@example.com"
export GIT_COMMITTER_NAME="test"
export GIT_COMMITTER_EMAIL="test@example.com"

# path inside repo
PATH_IN_REPO="docs"

# init command
bash oogit.sh init -m "initial" "$TMP_DIR/test.docx" "$REPO" main "$PATH_IN_REPO"

# modify and commit
rm -rf "$DOC_DIR" && mkdir "$DOC_DIR"
unzip -q "$TMP_DIR/test.docx" -d "$DOC_DIR"
echo "change" >> "$DOC_DIR/hello.txt"
zip -q "$TMP_DIR/test.docx" -r "$DOC_DIR"
bash oogit.sh commit -m "update" "$TMP_DIR/test.docx"

# update using environment commit_message
rm -rf "$DOC_DIR" && mkdir "$DOC_DIR"
unzip -q "$TMP_DIR/test.docx" -d "$DOC_DIR"
echo "more" >> "$DOC_DIR/hello.txt"
zip -q "$TMP_DIR/test.docx" -r "$DOC_DIR"
commit_message="merge" bash oogit.sh update "$TMP_DIR/test.docx"

# reset to repo state
bash oogit.sh reset "$TMP_DIR/test.docx"

# checkout into new temp file
OUT_FILE="$TMP_DIR/checkout.docx"
bash oogit.sh checkout "$OUT_FILE" "$REPO" main "$PATH_IN_REPO"

echo "All commands executed"
