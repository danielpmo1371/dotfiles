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
- Run: `bash tests/test-docker.sh ubuntu` from the repo root
- This script handles build, install, and validation in a single container session
- Report: pass/fail for each installer component with error details

**Teammate 2 - "debian-tester"**: Test on Debian
- Run: `bash tests/test-docker.sh debian` from the repo root
- This script handles build, install, and validation in a single container session
- Report: pass/fail for each installer component with error details

**Teammate 3 - "fedora-tester"**: Test on Fedora
- Run: `bash tests/test-docker.sh fedora` from the repo root
- This script handles build, install, and validation in a single container session
- Report: pass/fail for each installer component with error details

### Completion

After all teammates finish:
1. Create a comparison matrix showing pass/fail per component per distro
2. Highlight any distro-specific failures
3. Flag package manager compatibility issues (apt vs dnf)
4. Summarize overall test results
