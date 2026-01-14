#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

OUTPUT_DIR=""
ORG="${AZDO_ORG:-}"
PROJECT="${AZDO_PROJECT:-}"
BUILD_ID=""
PAT="${AZDO_PAT:-}"
JSON_OUTPUT=false

usage() {
    echo "Usage: $(basename "$0") [OPTIONS] <pipeline_url>"
    echo ""
    echo "Fetch Azure DevOps pipeline logs."
    echo ""
    echo "Options:"
    echo "  -o, --org <org>         Organization name"
    echo "  -p, --project <project> Project name"
    echo "  -b, --build-id <id>     Build ID"
    echo "  -d, --output <dir>      Output directory"
    echo "  -t, --pat <token>       PAT (or set AZDO_PAT)"
    echo "  -j, --json              JSON output only"
    echo "  -h, --help              Show help"
    exit 1
}

log_info() { [[ "$JSON_OUTPUT" == "false" ]] && echo -e "${GREEN}[INFO]${NC} $1" >&2 || true; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

parse_url() {
    local url="$1"
    if [[ "$url" =~ dev\.azure\.com/([^/]+)/([^/]+)/_build/results\?buildId=([0-9]+) ]]; then
        ORG="${BASH_REMATCH[1]}"
        PROJECT="${BASH_REMATCH[2]}"
        BUILD_ID="${BASH_REMATCH[3]}"
        PROJECT=$(echo "$PROJECT" | sed 's/%20/ /g')
        return 0
    fi
    return 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--org) ORG="$2"; shift 2 ;;
        -p|--project) PROJECT="$2"; shift 2 ;;
        -b|--build-id) BUILD_ID="$2"; shift 2 ;;
        -d|--output) OUTPUT_DIR="$2"; shift 2 ;;
        -t|--pat) PAT="$2"; shift 2 ;;
        -j|--json) JSON_OUTPUT=true; shift ;;
        -h|--help) usage ;;
        https://*) parse_url "$1" || true; shift ;;
        *) shift ;;
    esac
done

# Validate
[[ -z "$PAT" ]] && { log_error "Missing PAT"; exit 1; }
[[ -z "$ORG" ]] && { log_error "Missing org"; exit 1; }
[[ -z "$PROJECT" ]] && { log_error "Missing project"; exit 1; }
[[ -z "$BUILD_ID" ]] && { log_error "Missing build ID"; exit 1; }

[[ -z "$OUTPUT_DIR" ]] && OUTPUT_DIR="/tmp/azdo_logs_${BUILD_ID}"
mkdir -p "$OUTPUT_DIR"

# Fetch logs
encoded_project=$(echo "$PROJECT" | sed 's/ /%20/g')
api_url="https://dev.azure.com/${ORG}/${encoded_project}/_apis/build/builds/${BUILD_ID}/logs?\$format=zip&api-version=7.1"
zip_file="${OUTPUT_DIR}/pipeline_logs_${BUILD_ID}.zip"

log_info "Fetching logs from: ${ORG}/${PROJECT} build #${BUILD_ID}"

http_code=$(curl -s -o "$zip_file" -w "%{http_code}" -u ":${PAT}" "$api_url")

if [[ "$http_code" != "200" ]]; then
    log_error "Failed. HTTP $http_code"
    [[ -f "$zip_file" ]] && cat "$zip_file" >&2
    exit 1
fi

log_info "Extracting to: $OUTPUT_DIR"
unzip -q -o "$zip_file" -d "$OUTPUT_DIR"
rm -f "$zip_file"

# Generate summary
total_files=$(find "$OUTPUT_DIR" -type f | wc -l | tr -d ' ')

main_logs=""
for f in "$OUTPUT_DIR"/*.txt; do
    [[ -f "$f" ]] || continue
    name=$(basename "$f")
    size=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null)
    [[ -n "$main_logs" ]] && main_logs+=","
    main_logs+="{\"name\":\"$name\",\"size\":$size}"
done

job_folders=""
for d in "$OUTPUT_DIR"/*/; do
    [[ -d "$d" ]] || continue
    name=$(basename "$d")
    [[ "$name" == "Agent Diagnostic Logs" ]] && continue
    count=$(find "$d" -type f | wc -l | tr -d ' ')
    [[ -n "$job_folders" ]] && job_folders+=","
    job_folders+="{\"name\":\"$name\",\"files\":$count}"
done

log_info "Done! $total_files files extracted."

cat << ENDJSON
{
  "success": true,
  "organization": "$ORG",
  "project": "$PROJECT",
  "buildId": "$BUILD_ID",
  "outputDir": "$OUTPUT_DIR",
  "totalFiles": $total_files,
  "mainLogs": [$main_logs],
  "jobFolders": [$job_folders],
  "pipelineYaml": "$OUTPUT_DIR/azure-pipelines-expanded.yaml",
  "initLog": "$OUTPUT_DIR/initializeLog.txt"
}
ENDJSON
