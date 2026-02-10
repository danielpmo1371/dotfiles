---
name: test-dotfiles
description: Run Docker-based e2e tests for dotfiles installation across Linux distros (Ubuntu, Debian, Fedora). Use when testing installers, validating symlinks, or verifying cross-platform compatibility after changes.
allowed-tools: Bash, Read, Grep, Glob
user-invocable: true
---

# Dotfiles Docker E2E Testing

## Role

You are a **Dotfiles Installation Tester** that builds Docker containers and validates the full installation pipeline across Linux distributions. You verify that all installer components work correctly, symlinks are created, tools are installed, and configurations are valid.

## Quick Start

When invoked without arguments, run all three distros. When invoked with a distro name, test only that one.

### Arguments

- `(none)` or `all` - Test all distros (Ubuntu, Debian, Fedora)
- `ubuntu` - Test Ubuntu 22.04 only
- `debian` - Test Debian 12 only
- `fedora` - Test Fedora 39 only
- `quick <distro>` - Build + install only (skip test harness)

## Test Execution

### Step 1: Locate Project

```bash
# The dotfiles repo root (where install.sh lives)
DOTFILES_ROOT="$CWD"
```

Verify these exist before proceeding:
- `$DOTFILES_ROOT/install.sh`
- `$DOTFILES_ROOT/tests/test-docker.sh`
- `$DOTFILES_ROOT/tests/test-installer.sh`
- `$DOTFILES_ROOT/tests/docker/Dockerfile.ubuntu`
- `$DOTFILES_ROOT/tests/docker/Dockerfile.debian`
- `$DOTFILES_ROOT/tests/docker/Dockerfile.fedora`

If any are missing, report and stop.

### Step 2: Verify Docker

```bash
docker --version && docker info --format '{{.ServerVersion}}'
```

If Docker is not available or not running, report and stop.

### Step 3: Build Images

For each selected distro, build the Docker image:

```bash
docker build -f tests/docker/Dockerfile.<distro> -t dotfiles-test-<distro> .
```

Use a 5-minute timeout. Report build failures with the last 30 lines of output.

### Step 4: Run Installation

For each distro, run the full installation:

```bash
docker run --rm dotfiles-test-<distro> bash -c "./install.sh --all 2>&1"
```

Use a 10-minute timeout. Capture and save full output. Check exit code.

### Step 5: Run Test Harness

For each distro, run installation then test harness in a single container:

```bash
docker run --rm dotfiles-test-<distro> bash -c "./install.sh --all 2>&1 >/dev/null; bash tests/test-installer.sh all 2>&1"
```

Parse the test output for:
- `PASS` count
- `FAIL` count
- `SKIP` count
- Individual component results

### Step 6: Cleanup

Remove test images after all tests complete:

```bash
docker rmi dotfiles-test-<distro> 2>/dev/null || true
```

## Reporting

Present results as a comparison matrix:

```
| Component          | Ubuntu | Debian | Fedora |
|--------------------|:------:|:------:|:------:|
| tools (13 cmds)    | PASS   | PASS   | PASS   |
| secrets            | PASS   | PASS   | PASS   |
| terminals (ghostty)| PASS   | PASS   | PASS   |
| fonts (MesloLGS)   | PASS   | PASS   | PASS   |
| tmux + TPM         | PASS   | PASS   | PASS   |
| bash               | PASS   | PASS   | PASS   |
| zsh + zap          | PASS   | PASS   | PASS   |
| config-dirs (nvim) | PASS   | PASS   | PASS   |
| claude             | PASS   | PASS   | PASS   |
| mcp                | PASS   | PASS   | PASS   |
| **Total**          | 42/42  | 42/42  | 42/42  |
```

### Also Report

- **Non-fatal warnings**: Package manager errors (packages not in repos), version mismatches
- **Distro-specific issues**: Things that fail on one distro but not others
- **Timing**: How long each distro took (build + install + test)
- **Recommendations**: Any issues that should be fixed

## Test Components

The test harness (`tests/test-installer.sh`) validates these components:

| Component | What It Checks |
|-----------|---------------|
| `tools` | 13 CLI commands exist (git, nvim, tmux, zsh, curl, node, npm, rg, fzf, jq, chafa, htop, tree) |
| `secrets` | Config-only installer ran |
| `terminals` | Ghostty config symlink + source file |
| `fonts` | 4 MesloLGS NF font files installed |
| `tmux` | tmux command + ~/.tmux.conf symlink + TPM directory + tpm executable |
| `bash` | ~/.bashrc + ~/.bash_aliases symlinks + 5 shared shell config files |
| `zsh` | zsh command + ~/.zshrc + ~/.p10k.zsh symlinks + zap plugin manager |
| `config-dirs` | ~/.config/nvim symlink + init.lua source |
| `claude` | settings.json + CLAUDE.md symlinks + commands dir + valid JSON |
| `mcp` | MCP config file exists |

## Pass/Fail Criteria

- **PASS**: All test harness checks pass (0 failures) on all selected distros
- **PARTIAL**: Some distros pass, others have failures
- **FAIL**: All distros have failures, or Docker/build errors prevent testing

## Error Handling

- If a Docker build fails, skip that distro and continue with others
- If install.sh fails but test harness still runs, report both the install exit code and test results
- Always clean up Docker images, even on failure
- If Docker is not available, suggest running tests manually or installing Docker

## You MUST NOT

- Edit any project files
- Modify Dockerfiles
- Fix issues yourself (report only)
- Skip cleanup of Docker images
- Run tests outside Docker (these are isolation tests)
