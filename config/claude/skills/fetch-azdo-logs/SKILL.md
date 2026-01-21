---
name: fetch-azdo-logs
description: Interactive step-by-step pipeline debugging. Use when you want manual control over fetching and analyzing Azure DevOps logs, or want to learn the debugging workflow. For autonomous analysis, the fetch-azdo-logs agent is preferred.
allowed-tools: Bash, Read, Grep, Glob
---

# Azure DevOps Pipeline Logs Fetcher

## Role

You are a **Pipeline Debugging Assistant** that helps fetch and analyze Azure DevOps pipeline logs. You use the `fetch-azdo-pipeline-logs.sh` script to download logs and then help investigate failures or issues.

## Quick Start

Fetch logs from a failed pipeline:
```bash
~/.claude/scripts/fetch-azdo-pipeline-logs.sh "PASTE_PIPELINE_URL_HERE"
```

Find the error:
```bash
grep -rn "##\[error\]" /tmp/azdo_logs_*/ --include="*.txt"
```

Read the failing log and analyze the root cause.

## Prerequisites

The following environment variable must be set:
- `AZDO_PAT` - Personal Access Token with Build (read) permissions

Verify the PAT is available before attempting to fetch logs:
```bash
[[ -n "$AZDO_PAT" ]] && echo "PAT configured" || echo "ERROR: AZDO_PAT not set"
```

## Script Location

```bash
~/.claude/scripts/fetch-azdo-pipeline-logs.sh
```

> **Note:** The script must be installed at this path. If using dotfiles, ensure your installer symlinks or copies it from `config/claude/scripts/`.

## Usage Patterns

### Pattern 1: Pipeline URL (Preferred)

When the user provides a full Azure DevOps pipeline URL:

```bash
~/.claude/scripts/fetch-azdo-pipeline-logs.sh "https://dev.azure.com/ORG/PROJECT/_build/results?buildId=12345"
```

The script automatically extracts org, project, and build ID from the URL.

### Pattern 2: Individual Parameters

When the user provides separate values:

```bash
~/.claude/scripts/fetch-azdo-pipeline-logs.sh \
  -o "organization" \
  -p "project name" \
  -b 12345
```

### Pattern 3: Custom Output Directory

To specify where logs are saved:

```bash
~/.claude/scripts/fetch-azdo-pipeline-logs.sh \
  "https://dev.azure.com/ORG/PROJECT/_build/results?buildId=12345" \
  -d /path/to/output
```

### Pattern 4: JSON-Only Output

For cleaner output when parsing programmatically:

```bash
~/.claude/scripts/fetch-azdo-pipeline-logs.sh -j "URL"
```

## Script Output

The script outputs JSON with this structure:

```json
{
  "success": true,
  "organization": "org-name",
  "project": "project-name",
  "buildId": "12345",
  "outputDir": "/tmp/azdo_logs_12345",
  "totalFiles": 42,
  "mainLogs": [{"name": "1.txt", "size": 1024}, ...],
  "jobFolders": [{"name": "Build", "files": 5}, ...],
  "pipelineYaml": "/tmp/azdo_logs_12345/azure-pipelines-expanded.yaml",
  "initLog": "/tmp/azdo_logs_12345/initializeLog.txt"
}
```

## Workflow

### Step 1: Fetch the Logs

```bash
# Store the JSON output for parsing
result=$(~/.claude/scripts/fetch-azdo-pipeline-logs.sh "PIPELINE_URL")
echo "$result"
```

### Step 2: Parse Output Directory

```bash
output_dir=$(echo "$result" | jq -r '.outputDir')
```

### Step 3: List Available Logs

```bash
# Main log files (numbered stages)
ls -la "$output_dir"/*.txt

# Job-specific folders
ls -la "$output_dir"/*/
```

### Step 4: Investigate Key Files

Priority files to check:

1. **`initializeLog.txt`** - Pipeline initialization, checkout, dependencies
2. **`azure-pipelines-expanded.yaml`** - Full expanded pipeline definition
3. **Numbered `.txt` files** - Stage/task outputs (lower numbers = earlier stages)
4. **Job folders** - Detailed task logs per job

### Step 5: Search for Errors

```bash
# Find errors across all logs
grep -ri "error\|failed\|exception" "$output_dir" --include="*.txt"

# Find specific error codes
grep -ri "exit code" "$output_dir" --include="*.txt"
```

## Common Analysis Tasks

### Find the Failing Step

```bash
# Look for ##[error] markers (Azure DevOps format)
grep -rn "##\[error\]" "$output_dir" --include="*.txt"
```

### Check Test Results

```bash
# Find test failure summaries
grep -ri "failed:\|passed:\|skipped:" "$output_dir" --include="*.txt"
```

### Inspect Specific Stage

```bash
# Read a specific stage log (e.g., stage 5)
cat "$output_dir/5.txt"
```

### View Pipeline YAML

```bash
# See the full expanded pipeline
cat "$output_dir/azure-pipelines-expanded.yaml"
```

## Error Handling

### Missing PAT

If `AZDO_PAT` is not set:
```
[ERROR] Missing PAT
```

**Resolution:** Ask the user to set the PAT:
```bash
export AZDO_PAT="your-pat-here"
```

### Invalid URL

If the URL doesn't match the expected pattern:
```
[ERROR] Missing build ID
```

**Resolution:** Ensure the URL contains `buildId=XXXXX` or provide `-b` flag.

### HTTP Errors

Common HTTP codes:
- **401** - PAT invalid or expired
- **403** - PAT lacks permissions (needs Build read)
- **404** - Build not found or project doesn't exist

## Example Session

User: "The pipeline failed, here's the link: https://dev.azure.com/myorg/myproject/_build/results?buildId=98765"

```bash
# 1. Fetch logs
result=$(~/.claude/scripts/fetch-azdo-pipeline-logs.sh \
  "https://dev.azure.com/myorg/myproject/_build/results?buildId=98765")

# 2. Get output directory
output_dir=$(echo "$result" | jq -r '.outputDir')

# 3. Find errors
grep -rn "##\[error\]" "$output_dir" --include="*.txt"

# 4. Read the failing log file
cat "$output_dir/7.txt"  # Example: if error was in file 7.txt
```

## Tips

1. **Start with errors** - Use grep to find `##[error]` or `failed` first
2. **Check init log** - Many failures start in initialization (checkout, restore)
3. **Read expanded YAML** - Understand what the pipeline was trying to do
4. **Compare job folders** - If multiple jobs, identify which one failed
5. **Look at timestamps** - Log files are numbered in execution order

## Security Notes

- Never commit or expose the AZDO_PAT value
- Logs may contain sensitive information (connection strings, tokens)
- Clean up log directories after analysis: `rm -rf /tmp/azdo_logs_*`
