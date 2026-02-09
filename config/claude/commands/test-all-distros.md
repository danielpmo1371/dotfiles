---
allowed-tools: Bash(*), Read(*), Glob(*), Grep(*)
description: Agent team for parallel Docker e2e tests across distros
---

## Agent Team: Cross-Distro E2E Testing

Create an agent team to test dotfiles installation across multiple Linux distributions using Docker. Each teammate tests one distro independently.

The dotfiles repo is at: $CWD
The Dockerfiles are in: $CWD/tests/docker/
The test script is at: $CWD/tests/test-docker.sh

### Team Structure

Spawn 3 teammates. Each teammate builds and tests a different distro. These are fully independent - no dependencies between them.

**Teammate 1 - "ubuntu-tester"**: Test on Ubuntu 22.04
- Build: `docker build -f tests/docker/Dockerfile.ubuntu -t dotfiles-test-ubuntu .`
- Run full install: `docker run --rm dotfiles-test-ubuntu bash -c "./install.sh --all 2>&1"`
- Run validation: `docker run --rm dotfiles-test-ubuntu bash tests/test-installer.sh all`
- If test-installer.sh doesn't exist, manually validate:
  - Check symlinks: ~/.bashrc, ~/.zshrc, ~/.tmux.conf, ~/.config/nvim
  - Check tools installed: git, nvim, tmux, chafa, rg
  - Check shell configs source without errors
- Report: pass/fail for each installer component with error details

**Teammate 2 - "debian-tester"**: Test on Debian
- Build: `docker build -f tests/docker/Dockerfile.debian -t dotfiles-test-debian .`
- Run full install: `docker run --rm dotfiles-test-debian bash -c "./install.sh --all 2>&1"`
- Run validation: `docker run --rm dotfiles-test-debian bash tests/test-installer.sh all`
- Same validation steps as ubuntu-tester
- Report: pass/fail for each installer component with error details

**Teammate 3 - "fedora-tester"**: Test on Fedora
- Build: `docker build -f tests/docker/Dockerfile.fedora -t dotfiles-test-fedora .`
- Run full install: `docker run --rm dotfiles-test-fedora bash -c "./install.sh --all 2>&1"`
- Run validation: `docker run --rm dotfiles-test-fedora bash tests/test-installer.sh all`
- Same validation steps as ubuntu-tester
- Report: pass/fail for each installer component with error details

### Completion

After all teammates finish:
1. Create a comparison matrix showing pass/fail per component per distro
2. Highlight any distro-specific failures
3. Flag package manager compatibility issues (apt vs dnf)
4. Summarize overall test results
