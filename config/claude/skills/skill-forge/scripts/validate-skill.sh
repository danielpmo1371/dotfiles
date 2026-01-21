#!/bin/bash
# validate-skill.sh - Validate Claude Code skill structure and content
# Usage: validate-skill.sh /path/to/skill/directory

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
ERRORS=0
WARNINGS=0
PASSES=0

# Functions
log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    PASSES=$((PASSES + 1))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ERRORS=$((ERRORS + 1))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    WARNINGS=$((WARNINGS + 1))
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check arguments
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 /path/to/skill/directory"
    echo ""
    echo "Validates a Claude Code skill against best practices."
    exit 1
fi

SKILL_DIR="$1"
SKILL_FILE="$SKILL_DIR/SKILL.md"

echo ""
echo "=========================================="
echo "  Claude Skill Validator"
echo "=========================================="
echo ""
log_info "Validating skill at: $SKILL_DIR"
echo ""

# Check skill directory exists
if [[ ! -d "$SKILL_DIR" ]]; then
    log_fail "Skill directory does not exist: $SKILL_DIR"
    exit 1
fi

# Check SKILL.md exists
if [[ ! -f "$SKILL_FILE" ]]; then
    log_fail "SKILL.md not found in $SKILL_DIR"
    exit 1
fi
log_pass "SKILL.md exists"

# Read SKILL.md content
CONTENT=$(cat "$SKILL_FILE")

# Extract frontmatter (between --- markers)
FRONTMATTER=$(awk '/^---$/{if(f)exit;f=1;next}f' "$SKILL_FILE")

if [[ -z "$FRONTMATTER" ]]; then
    log_fail "No YAML frontmatter found (missing --- delimiters)"
else
    log_pass "YAML frontmatter present"
fi

echo ""
echo "--- Metadata Validation ---"

# Extract name field
NAME=$(echo "$FRONTMATTER" | grep -E "^name:" | sed 's/^name:[[:space:]]*//' | tr -d '"' | tr -d "'" || true)

if [[ -z "$NAME" ]]; then
    log_fail "name field is missing"
else
    log_pass "name field exists: $NAME"

    # Validate name format
    NAME_LENGTH=${#NAME}
    if [[ $NAME_LENGTH -gt 64 ]]; then
        log_fail "name exceeds 64 characters ($NAME_LENGTH chars)"
    else
        log_pass "name length OK ($NAME_LENGTH/64 chars)"
    fi

    if [[ ! "$NAME" =~ ^[a-z0-9-]+$ ]]; then
        log_fail "name must be lowercase letters, numbers, and hyphens only"
    else
        log_pass "name format valid"
    fi

    if [[ "$NAME" =~ ^(anthropic|claude) ]]; then
        log_fail "name cannot start with 'anthropic' or 'claude' (reserved)"
    else
        log_pass "name does not use reserved prefixes"
    fi

    if [[ "$NAME" =~ [\<\>] ]]; then
        log_fail "name contains XML tags (< or >)"
    else
        log_pass "name has no XML tags"
    fi
fi

# Extract description field
DESCRIPTION=$(echo "$FRONTMATTER" | grep -E "^description:" | sed 's/^description:[[:space:]]*//' | tr -d '"' | tr -d "'" || true)

if [[ -z "$DESCRIPTION" ]]; then
    log_fail "description field is missing"
else
    log_pass "description field exists"

    DESC_LENGTH=${#DESCRIPTION}
    if [[ $DESC_LENGTH -gt 1024 ]]; then
        log_fail "description exceeds 1024 characters ($DESC_LENGTH chars)"
    else
        log_pass "description length OK ($DESC_LENGTH/1024 chars)"
    fi

    if [[ "$DESCRIPTION" =~ [\<\>] ]]; then
        log_fail "description contains XML tags (< or >)"
    else
        log_pass "description has no XML tags"
    fi

    # Best practice checks
    if [[ "$DESCRIPTION" =~ [Uu]se[[:space:]]when || "$DESCRIPTION" =~ [Ww]hen ]]; then
        log_pass "description includes trigger context (when to use)"
    else
        log_warn "description should include 'when to use' triggers"
    fi

    if [[ "$DESCRIPTION" =~ ^[Ii][[:space:]]can || "$DESCRIPTION" =~ [Yy]ou[[:space:]]can ]]; then
        log_warn "description uses first/second person (prefer third person)"
    else
        log_pass "description uses appropriate voice"
    fi
fi

echo ""
echo "--- Structure Validation ---"

# Check line count
LINE_COUNT=$(wc -l < "$SKILL_FILE" | tr -d ' ')
if [[ $LINE_COUNT -gt 500 ]]; then
    log_warn "SKILL.md has $LINE_COUNT lines (recommended: <500)"
else
    log_pass "SKILL.md line count OK ($LINE_COUNT/500)"
fi

# Check for backslashes in paths
if grep -q '\\' "$SKILL_FILE"; then
    BACKSLASH_COUNT=$(grep -c '\\' "$SKILL_FILE" || echo "0")
    log_warn "Found $BACKSLASH_COUNT lines with backslashes (use forward slashes for paths)"
else
    log_pass "No backslash paths found"
fi

# Check for referenced files
echo ""
echo "--- Reference Validation ---"

# Find markdown links to local files
REFS=$(grep -oE '\[.*\]\([^)]+\)' "$SKILL_FILE" | grep -oE '\([^)]+\)' | tr -d '()' | grep -v '^http' || echo "")

if [[ -n "$REFS" ]]; then
    while IFS= read -r ref; do
        if [[ -n "$ref" ]]; then
            REF_PATH="$SKILL_DIR/$ref"
            if [[ -f "$REF_PATH" ]]; then
                log_pass "Referenced file exists: $ref"
            else
                log_fail "Referenced file not found: $ref"
            fi
        fi
    done <<< "$REFS"
else
    log_info "No local file references found"
fi

# Check scripts directory
if [[ -d "$SKILL_DIR/scripts" ]]; then
    log_pass "scripts/ directory exists"
    SCRIPT_COUNT=$(find "$SKILL_DIR/scripts" -type f \( -name "*.sh" -o -name "*.py" \) | wc -l | tr -d ' ')
    log_info "Found $SCRIPT_COUNT script(s)"

    # Check script executability
    shopt -s nullglob
    for script in "$SKILL_DIR/scripts"/*.sh; do
        if [[ -f "$script" ]]; then
            if [[ -x "$script" ]]; then
                log_pass "$(basename "$script") is executable"
            else
                log_warn "$(basename "$script") is not executable"
            fi
        fi
    done
    shopt -u nullglob
else
    log_info "No scripts/ directory"
fi

echo ""
echo "--- Content Analysis ---"

# Check for quick start section
if grep -qi "quick start" "$SKILL_FILE"; then
    log_pass "Quick start section present"
else
    log_warn "Consider adding a 'Quick Start' section"
fi

# Check for examples
if grep -qE "^## Example|^### Example|example|Example:" "$SKILL_FILE"; then
    log_pass "Examples present"
else
    log_warn "Consider adding examples"
fi

# Check for TODO/FIXME/placeholder markers
if grep -qiE "TODO|FIXME|XXX|\[placeholder\]|\[fill in\]" "$SKILL_FILE"; then
    log_warn "Found TODO/FIXME/placeholder markers"
else
    log_pass "No incomplete markers found"
fi

# Summary
echo ""
echo "=========================================="
echo "  Validation Summary"
echo "=========================================="
echo ""
echo -e "${GREEN}Passed:${NC}   $PASSES"
echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
echo -e "${RED}Errors:${NC}   $ERRORS"
echo ""

if [[ $ERRORS -eq 0 ]]; then
    if [[ $WARNINGS -eq 0 ]]; then
        echo -e "${GREEN}Result: EXCELLENT - Skill passes all validations${NC}"
        exit 0
    else
        echo -e "${YELLOW}Result: GOOD - Skill valid but has warnings to address${NC}"
        exit 0
    fi
else
    echo -e "${RED}Result: NEEDS FIXES - Skill has $ERRORS error(s) to resolve${NC}"
    exit 1
fi
