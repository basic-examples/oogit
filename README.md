# oogit

A CLI tool for managing OOXML (Word, Excel, PowerPoint) files in Git repositories.

## Features

* Version control for OOXML file contents using Git
* Supports POSIX and Windows systems
* CLI-based workflow

## Installation

```bash
# Clone the repository and make the script executable
git clone https://github.com/oogit/oogit.git
chmod +x oogit/oogit.sh
cp oogit/oogit.sh /usr/local/bin/oogit
```

## Usage

### `oogit init`

```bash
oogit init [...options] <ooxml-file> <git-repo> [path-in-repo] [branch]
```

**Behavior**

* Clone the Git repository (specified branch)
* Clear contents under `path-in-repo`
* Unzip the OOXML file and place its contents there
* Commit the changes, then delete the local repository
* Generate a `.oogit` metadata file

### `oogit checkout`

```bash
oogit checkout [...options] <ooxml-file> <git-repo> [repo-path] [branch-or-commit]
```

**Behavior**

* Clone the Git repository
* Checkout the specified branch or commit
* Generate a new OOXML file from the contents of the specified path in the repository
* Generate a `.oogit` metadata file

### `oogit commit`

```bash
oogit commit [...options] <ooxml-file>
```

**Behavior**

* Automatically run `oogit init` using values from `<ooxml-file>.oogit` file

### `oogit update`

```bash
oogit update [...options] <ooxml-file>
```

**Behavior**

* Update the OOXML file using values from `<ooxml-file>.oogit` file
* Conflicts will not be resolved

### `oogit reset`

```bash
oogit reset [...options] <ooxml-file>
```

**Behavior**

* Reset the OOXML file to the original state using values from `<ooxml-file>.oogit` file

### Examples

```bash
# Initial commit on your machine (it will generate report.pptx.oogit file as well)
oogit init report.pptx https://github.com/example/repo.git documents/report

# Init with custom commit message
oogit init -m "Initial commit" report.pptx https://github.com/example/repo.git documents/report

# Init with filename starting with dash (use -- separator)
oogit init -m "Initial commit" -- -filename-starts-with-dash.pptx https://github.com/example/repo.git

# Checkout/clone/pull (it will generate report.pptx.oogit file as well)
oogit checkout report.pptx https://github.com/example/repo.git documents/report

# Usual commit - requires report.pptx.oogit file
oogit commit report.pptx

# Usual update - requires report.pptx.oogit file, conflicts will not be resolved
oogit update report.pptx

# Reset when you want to revert to the original state
oogit reset report.pptx
```

### Metadata File Format

The `.oogit` file contains metadata in the following format (one value per line):

```text
1
https://github.com/example/repo.git
documents/report
main
abc123
```

Each line represents:
1. File version (currently "1")
2. Repository URL
3. Path in repository
4. Branch name
5. Commit hash

## License

MIT License
