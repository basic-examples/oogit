# oogit

A CLI tool for managing OOXML (Word, Excel, PowerPoint) files in Git repositories.

## Features

* Version control for OOXML file contents using Git
* Supports POSIX and Windows systems
* CLI-based workflow

## Installation

```bash
npm install -g oogit
```

## Usage

### `oogit overwrite`

```bash
oogit overwrite <file-path> <repository-url> [path-in-repository] [branch-name]
```

**Behavior**

* Clone the Git repository (specified branch)
* Clear contents under `path-in-repository`
* Unzip the OOXML file and place its contents there
* Commit the changes, then delete the local repository

**Options**

* `-m, --message <commit message>`: Use as commit message
* `-c, --commit-hash <hash>`: Exit with code 1 if latest commit hash does not match
* `-t, --tmp <tmp-path>`: Specify temporary working directory

### `oogit extract`

```bash
oogit extract <file-path> <repository-url> [path-in-repository] [branch-name-or-commit-hash]
```

**Behavior**

* Clone the Git repository
* Generate a new OOXML file from the contents of the specified path in the repository

**Options**

* `-f`: Overwrite existing OOXML file if it exists
* `-t, --tmp <tmp-path>`: Specify temporary working directory

### `oogit commit`

```bash
oogit commit <file-path>
```

**Behavior**

* Automatically run `oogit overwrite` using values from `<file-path>.oogit` JSON file

**Example `.oogit` JSON:**

```json
{
  "repository": "https://github.com/example/repo.git",
  "path": "documents/report",
  "branch": "main",
  "commit": "abc123"
}
```

* `-t, --tmp <tmp-path>`: Specify temporary working directory

## License

MIT License
