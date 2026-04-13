#!/usr/bin/env bash
# SDLC Framework — Dependency Checker
# Validates that required and recommended plugins are available.

set -euo pipefail

# Colors
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

header() {
  echo ""
  echo -e "${BOLD}${CYAN}SDLC Framework — Setup Check${NC}"
  echo "============================================"
  echo ""
}

check_plugin() {
  local name="$1"
  local level="$2"  # required | recommended
  local plugin_dir

  # Check common plugin locations
  for base_dir in \
    "${HOME}/.claude/plugins" \
    "${HOME}/repos/dotfiles/config/claude/plugins" \
    ".claude/plugins"; do
    plugin_dir="${base_dir}/${name}"
    if [[ -d "$plugin_dir" ]] && [[ -f "${plugin_dir}/plugin.json" ]]; then
      echo -e "  ${GREEN}[OK]${NC} ${name}"
      return 0
    fi
  done

  if [[ "$level" == "required" ]]; then
    echo -e "  ${RED}[MISSING]${NC} ${name} (required)"
    ((ERRORS++)) || true
  else
    echo -e "  ${YELLOW}[MISSING]${NC} ${name} (recommended)"
    ((WARNINGS++)) || true
  fi
  return 1
}

check_mcp_tool() {
  local tool_name="$1"
  local description="$2"

  # Check if MCP tools are available by looking at .mcp.json files
  local found=false
  for mcp_file in "${HOME}/.claude/.mcp.json" ".claude/.mcp.json" ".mcp.json"; do
    if [[ -f "$mcp_file" ]]; then
      if grep -qi "$tool_name" "$mcp_file" 2>/dev/null; then
        found=true
        break
      fi
    fi
  done

  if $found; then
    echo -e "  ${GREEN}[OK]${NC} ${description}"
  else
    echo -e "  ${YELLOW}[MISSING]${NC} ${description}"
    ((WARNINGS++)) || true
  fi
}

check_sdlc_config() {
  if [[ -f ".sdlc.json" ]]; then
    echo -e "  ${GREEN}[OK]${NC} .sdlc.json found in current directory"
    # Validate basic structure
    if command -v jq &>/dev/null; then
      if jq -e '.project.name' .sdlc.json &>/dev/null; then
        echo -e "  ${GREEN}[OK]${NC} .sdlc.json has valid project.name"
      else
        echo -e "  ${YELLOW}[WARN]${NC} .sdlc.json missing project.name field"
        ((WARNINGS++)) || true
      fi
    fi
  else
    echo -e "  ${CYAN}[INFO]${NC} No .sdlc.json in current directory"
    echo -e "         Create one for project-specific SDLC configuration."
    echo -e "         See DEVELOPER.md for schema reference."
  fi
}

# --- Main ---

header

echo -e "${BOLD}Required Plugins:${NC}"
check_plugin "superpowers" "required"
check_plugin "feature-dev" "required"
check_plugin "pr-review-toolkit" "required"
echo ""

echo -e "${BOLD}Recommended Plugins:${NC}"
check_plugin "pipeline-ops" "recommended"
check_plugin "code-review" "recommended"
check_plugin "code-review-suite" "recommended"
echo ""

echo -e "${BOLD}MCP Services:${NC}"
check_mcp_tool "azure-devops" "Azure DevOps MCP (work item fetching, pipeline triggers)"
check_mcp_tool "memory" "Memory MCP (persistent state across sessions)"
echo ""

echo -e "${BOLD}Project Configuration:${NC}"
check_sdlc_config
echo ""

# --- Summary ---

echo "============================================"
if [[ $ERRORS -gt 0 ]]; then
  echo -e "${RED}${BOLD}FAIL:${NC} ${ERRORS} required dependency missing"
  echo ""
  echo "Install missing required plugins before using the SDLC framework."
  echo "Refer to each plugin's README for installation instructions."
  exit 1
elif [[ $WARNINGS -gt 0 ]]; then
  echo -e "${YELLOW}${BOLD}PASS with warnings:${NC} ${WARNINGS} recommended items missing"
  echo ""
  echo "The SDLC framework will work but some features may be limited."
  echo "Missing recommended plugins will degrade gracefully."
  exit 0
else
  echo -e "${GREEN}${BOLD}PASS:${NC} All dependencies satisfied"
  exit 0
fi
