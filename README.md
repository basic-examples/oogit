# oogit

Manage Word, Excel, and PowerPoint files with Git — like you would with SVN.

`oogit` unpacks an OOXML file,
stores its contents in a regular Git repository,
and reassembles the file when you are done.

Works on both POSIX and Windows systems.

## Installation

```sh
# clone the project and expose the script
git clone https://github.com/basic-examples/oogit.git
chmod +x oogit/oogit.sh
sudo cp oogit/oogit.sh /usr/local/bin/oogit
```

Or install the published package from npm:

```sh
npm install -g oogit
```

## Quick start

```sh
# Initial upload: if you already have the OOXML file and it’s not under version control yet
oogit init report.pptx "https://github.com/<your-name>/<repo-name>.git"

# Or clone the file from a remote Git repository (like 'svn checkout')
oogit checkout report.pptx "https://github.com/<your-name>/<repo-name>.git"

# Edit the document as usual...

# Save your changes back to the Git repository (like `svn commit`)
oogit commit report.pptx

# ==============================================================================

# Did the file change on the remote repository?
oogit update report.pptx
```

A directory named `report.pptx.oogit` stores local Git repository,
tracks the remote Git repository url, branch and path,
for the next time you run `oogit commit` or `oogit update`, etc.

## Commands

### `init`

Unpack an OOXML file into a Git repository and make the initial commit.

```sh
oogit init [options] <ooxml-file> <git-repo> [branch] [path-in-repo]
```

### `checkout`

Reconstruct an OOXML file from a Git repository at a specific branch or commit.

```sh
oogit checkout [options] <ooxml-file> <git-repo> [branch-or-commit] [path-in-repo]
```

### `commit`

Commit changes to the repository using the metadata stored by `init` or `checkout`.

```sh
oogit commit [options] <ooxml-file>
```

### `update`

Update the local OOXML file with the latest version from the repository. (Does not resolve conflicts.)

```sh
oogit update [options] <ooxml-file>
```

### `reset`

Restore the OOXML file to a specific tag or commit from the repository.

```sh
oogit reset [options] <ooxml-file> [tag-or-commit]
```

## License

MIT License
