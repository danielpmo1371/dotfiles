#!/bin/bash

# Docker-based e2e test runner for dotfiles
# Usage: ./tests/test-docker.sh <distro|all>
# Distros: ubuntu, debian, fedora

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

DOCKER_DIR="$SCRIPT_DIR/docker"

test_distro() {
    local distro="$1"
    local dockerfile="$DOCKER_DIR/Dockerfile.$distro"
    local image_name="dotfiles-test-$distro"

    if [ ! -f "$dockerfile" ]; then
        echo -e "${RED}Dockerfile not found: $dockerfile${NC}"
        return 1
    fi

    echo -e "\n${BLUE}=== Testing on $distro ===${NC}"

    # Build the image
    echo -e "${BLUE}Building $distro image...${NC}"
    if ! docker build -f "$dockerfile" -t "$image_name" "$DOTFILES_ROOT" 2>&1; then
        echo -e "${RED}FAIL: Docker build failed for $distro${NC}"
        return 1
    fi
    echo -e "${GREEN}Build complete${NC}"

    # Run the full installation
    echo -e "${BLUE}Running install.sh --all...${NC}"
    local install_exit_code=0
    docker run --rm "$image_name" bash -c "./install.sh --all 2>&1" || install_exit_code=$?

    if [ "$install_exit_code" -ne 0 ]; then
        echo -e "${RED}FAIL: install.sh exited with code $install_exit_code on $distro${NC}"
    else
        echo -e "${GREEN}Installation completed successfully${NC}"
    fi

    # Run the test harness inside the container
    echo -e "${BLUE}Running test harness...${NC}"
    local test_exit_code=0
    docker run --rm "$image_name" bash -c "./install.sh --all 2>&1 >/dev/null; bash tests/test-installer.sh all 2>&1" || test_exit_code=$?

    if [ "$test_exit_code" -ne 0 ]; then
        echo -e "${RED}FAIL: Test harness found failures on $distro${NC}"
    else
        echo -e "${GREEN}All tests passed on $distro${NC}"
    fi

    # Cleanup image
    docker rmi "$image_name" 2>/dev/null || true

    return $test_exit_code
}

# Main dispatch
distro="${1:-all}"
overall_exit=0

echo -e "${BLUE}Dotfiles Docker E2E Test Runner${NC}"
echo "Dotfiles root: $DOTFILES_ROOT"

case "$distro" in
    ubuntu|debian|fedora)
        test_distro "$distro" || overall_exit=1
        ;;
    all)
        for d in ubuntu debian fedora; do
            test_distro "$d" || overall_exit=1
        done
        ;;
    *)
        echo "Unknown distro: $distro"
        echo "Usage: $0 <ubuntu|debian|fedora|all>"
        exit 1
        ;;
esac

echo ""
if [ "$overall_exit" -eq 0 ]; then
    echo -e "${GREEN}All distro tests passed${NC}"
else
    echo -e "${RED}Some distro tests failed${NC}"
fi

exit $overall_exit
