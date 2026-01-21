#!/bin/bash
# secrets.sh - Cross-platform secrets management
# Supports macOS Keychain and Linux libsecret with file fallback
#
# Usage:
#   secret KEY              - Get a secret from dotfiles service
#   secret -a KEY           - Get a secret from any service (--all)
#   secret_set KEY VALUE    - Store a secret
#   secret_list             - List dotfiles secrets
#   secret_list -a          - List ALL keychain secrets (--all)
#   secret_delete KEY       - Remove a secret
#   secret_fz               - Interactive fzf selection (dotfiles)
#   secret_fz -a            - Interactive fzf selection (all services)
#   secret_fz -p            - With preview pane showing values
#   secret_fz -c            - Select and copy to clipboard
#
# Aliases: sl (secret_list), sfz (secret_fz)
# Use -h or --help on any command for usage info

SECRETS_SERVICE="dotfiles"
SECRETS_MIGRATED_FLAG="$HOME/.cache/dotfiles-secrets-migrated"

# ─────────────────────────────────────────────────────────────────────────────
#   Backend Detection
# ─────────────────────────────────────────────────────────────────────────────

__secrets_backend() {
    if [[ "$OSTYPE" == darwin* ]] && command -v security &>/dev/null; then
        echo "keychain"
    elif command -v secret-tool &>/dev/null; then
        echo "libsecret"
    else
        echo "file"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
#   macOS Keychain Backend
#   Uses: service=dotfiles, account=KEY_NAME for unique lookups
# ─────────────────────────────────────────────────────────────────────────────

__secret_get_keychain() {
    local key="$1"
    # Use key as account for unique lookup (service+account is unique)
    security find-generic-password -a "$key" -s "$SECRETS_SERVICE" -w 2>/dev/null
}

__secret_set_keychain() {
    local key="$1"
    local value="$2"
    # -U updates if exists, otherwise creates
    # Use key as account, also set label for readability
    security add-generic-password -U -a "$key" -s "$SECRETS_SERVICE" -l "$key" -w "$value" 2>/dev/null
}

__secret_delete_keychain() {
    local key="$1"
    security delete-generic-password -a "$key" -s "$SECRETS_SERVICE" 2>/dev/null
}

__secret_list_keychain() {
    # Parse keychain dump for our service entries
    # Use account field (acct) which contains the key name
    security dump-keychain 2>/dev/null | \
        awk -v svc="$SECRETS_SERVICE" '
            /^keychain:/ { acct = "" }
            /"acct"<blob>=/ {
                gsub(/.*="/, ""); gsub(/".*/, "")
                acct = $0
            }
            /"svce"<blob>=/ && $0 ~ "=\"" svc "\"" {
                if (acct != "") print acct
            }
        '
}

__secret_list_keychain_all() {
    # List ALL generic password entries (service:account format)
    security dump-keychain 2>/dev/null | \
        awk '
            /^keychain:/ { svc = ""; acct = "" }
            /"acct"<blob>=/ {
                gsub(/.*="/, ""); gsub(/".*/, "")
                acct = $0
            }
            /"svce"<blob>=/ {
                gsub(/.*="/, ""); gsub(/".*/, "")
                svc = $0
                if (svc != "" && acct != "") print svc ":" acct
            }
        ' | sort -u
}

__secret_get_keychain_any() {
    # Get secret from any service
    # Supports: "service:account" format or plain key search
    local key="$1"

    # Check for service:account format (from secret_list -a output)
    if [[ "$key" == *:* ]]; then
        local svc="${key%:*}"    # Everything before last :
        local acct="${key##*:}"  # Everything after last :
        security find-generic-password -s "$svc" -a "$acct" -w 2>/dev/null && return 0
    fi

    # Try as account name
    security find-generic-password -a "$key" -w 2>/dev/null && return 0
    # Try as service name
    security find-generic-password -s "$key" -w 2>/dev/null && return 0
    # Try as label
    security find-generic-password -l "$key" -w 2>/dev/null && return 0
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
#   Linux libsecret Backend
# ─────────────────────────────────────────────────────────────────────────────

__secret_get_libsecret() {
    local key="$1"
    secret-tool lookup service "$SECRETS_SERVICE" key "$key" 2>/dev/null
}

__secret_set_libsecret() {
    local key="$1"
    local value="$2"
    echo -n "$value" | secret-tool store --label="$key" service "$SECRETS_SERVICE" key "$key" 2>/dev/null
}

__secret_delete_libsecret() {
    local key="$1"
    secret-tool clear service "$SECRETS_SERVICE" key "$key" 2>/dev/null
}

__secret_list_libsecret() {
    secret-tool search --all service "$SECRETS_SERVICE" 2>/dev/null | \
        awk -F' = ' '/^attribute\.key = / { print $2 }'
}

# ─────────────────────────────────────────────────────────────────────────────
#   File Fallback Backend
# ─────────────────────────────────────────────────────────────────────────────

__secrets_file() {
    # Check multiple locations for secrets file
    if [[ -f "$HOME/.accessTokens" ]]; then
        echo "$HOME/.accessTokens"
    elif [[ -n "$DOTFILES_DIR" && -f "$DOTFILES_DIR/.accessTokens" ]]; then
        echo "$DOTFILES_DIR/.accessTokens"
    fi
}

__secret_get_file() {
    local key="$1"
    local file
    file=$(__secrets_file)
    [[ -z "$file" ]] && return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            ''|\#*) continue ;;
            "$key="*)
                echo "${line#*=}"
                return 0
                ;;
        esac
    done < "$file"
    return 1
}

__secret_list_file() {
    local file
    file=$(__secrets_file)
    [[ -z "$file" ]] && return

    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            ''|\#*) continue ;;
            *=*)
                echo "${line%%=*}"
                ;;
        esac
    done < "$file"
}

# ─────────────────────────────────────────────────────────────────────────────
#   Public API
# ─────────────────────────────────────────────────────────────────────────────

secret() {
    local all_services=false
    local key=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                cat <<'EOF'
Usage: secret [-a|--all] KEY

Get a secret value from the secret store.

Options:
  -a, --all    Search across ALL services, not just dotfiles
  -h, --help   Show this help message

Examples:
  secret OPENAI_API_KEY                    # From dotfiles service
  secret -a "service:account"              # From any service (use format from sl -a)
EOF
                return 0 ;;
            -a|--all) all_services=true; shift ;;
            -*) echo "Unknown option: $1. Use -h for help." >&2; return 1 ;;
            *) key="$1"; shift ;;
        esac
    done

    [[ -z "$key" ]] && { echo "Usage: secret [-a|--all] KEY (use -h for help)" >&2; return 1; }

    local backend value
    backend=$(__secrets_backend)

    if [[ "$all_services" == true ]]; then
        # Search across all services
        case "$backend" in
            keychain)
                value=$(__secret_get_keychain_any "$key")
                ;;
            libsecret)
                # For libsecret, search without service filter
                value=$(secret-tool lookup key "$key" 2>/dev/null)
                ;;
        esac
    else
        # Search only in dotfiles service
        case "$backend" in
            keychain)
                value=$(__secret_get_keychain "$key")
                ;;
            libsecret)
                value=$(__secret_get_libsecret "$key")
                ;;
        esac
    fi

    # Fallback to file if native store returned empty
    if [[ -z "$value" ]]; then
        value=$(__secret_get_file "$key")
    fi

    if [[ -n "$value" ]]; then
        echo "$value"
    else
        echo "Secret '$key' not found" >&2
        return 1
    fi
}

secret_set() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat <<'EOF'
Usage: secret_set KEY VALUE

Store a secret in the native secret store (dotfiles service).

Examples:
  secret_set OPENAI_API_KEY "sk-..."
  secret_set MY_TOKEN "abc123"
EOF
        return 0
    fi

    local key="$1"
    local value="$2"
    [[ -z "$key" || -z "$value" ]] && { echo "Usage: secret_set KEY VALUE (use -h for help)" >&2; return 1; }

    local backend
    backend=$(__secrets_backend)

    case "$backend" in
        keychain)
            __secret_set_keychain "$key" "$value"
            ;;
        libsecret)
            __secret_set_libsecret "$key" "$value"
            ;;
        file)
            echo "No native secret store available. Install secret-tool or use macOS." >&2
            return 1
            ;;
    esac
}

secret_delete() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat <<'EOF'
Usage: secret_delete KEY

Remove a secret from the native secret store (dotfiles service).

Examples:
  secret_delete OLD_API_KEY
EOF
        return 0
    fi

    local key="$1"
    [[ -z "$key" ]] && { echo "Usage: secret_delete KEY (use -h for help)" >&2; return 1; }

    local backend
    backend=$(__secrets_backend)

    case "$backend" in
        keychain)
            __secret_delete_keychain "$key"
            ;;
        libsecret)
            __secret_delete_libsecret "$key"
            ;;
        file)
            echo "No native secret store available." >&2
            return 1
            ;;
    esac
}

secret_list() {
    local all_services=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                cat <<'EOF'
Usage: secret_list [-a|--all]

List secrets from the secret store.

Options:
  -a, --all    List ALL keychain entries (format: service:account)
  -h, --help   Show this help message

Alias: sl

Examples:
  secret_list              # List dotfiles secrets only
  sl -a                    # List all keychain entries
  sl -a | grep github      # Search all entries
EOF
                return 0 ;;
            -a|--all) all_services=true; shift ;;
            -*) echo "Unknown option: $1. Use -h for help." >&2; return 1 ;;
            *) shift ;;
        esac
    done

    local backend
    backend=$(__secrets_backend)

    if [[ "$all_services" == true ]]; then
        case "$backend" in
            keychain)
                __secret_list_keychain_all
                ;;
            libsecret)
                # List all libsecret entries
                secret-tool search --all 2>/dev/null | \
                    awk -F' = ' '/^attribute\./ { print $1 "=" $2 }' | sort -u
                ;;
            file)
                __secret_list_file
                ;;
        esac
    else
        case "$backend" in
            keychain)
                __secret_list_keychain
                ;;
            libsecret)
                __secret_list_libsecret
                ;;
            file)
                __secret_list_file
                ;;
        esac
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
#   Migration
# ─────────────────────────────────────────────────────────────────────────────

__secrets_auto_migrate() {
    local file="$HOME/.accessTokens"
    local backend
    backend=$(__secrets_backend)

    # Skip if no file to migrate
    [[ ! -f "$file" ]] && return 0

    # Skip if file backend (no point migrating to itself)
    [[ "$backend" == "file" ]] && return 0

    # Skip if already migrated this file (check marker)
    [[ -f "$SECRETS_MIGRATED_FLAG" ]] && return 0

    local migrated=0
    local skipped=0
    local key value existing

    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            ''|\#*) continue ;;
            *=*)
                key="${line%%=*}"
                value="${line#*=}"

                # Validate key name
                if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
                    continue
                fi

                # Check if already exists
                case "$backend" in
                    keychain) existing=$(__secret_get_keychain "$key") ;;
                    libsecret) existing=$(__secret_get_libsecret "$key") ;;
                esac

                if [[ -z "$existing" ]]; then
                    # Add to secret store
                    secret_set "$key" "$value" && ((migrated++))
                elif [[ "$existing" != "$value" ]]; then
                    echo "[secrets] Warning: $key exists with different value, skipping" >&2
                    ((skipped++))
                fi
                ;;
        esac
    done < "$file"

    # Rename the file after migration
    if [[ $migrated -gt 0 || $skipped -eq 0 ]]; then
        local backup="$HOME/.accessTokens.importedtosecretsstore-$(date +%Y%m%d).bkup"
        mv "$file" "$backup"
        echo "[secrets] Migrated $migrated secrets to $backend, backed up to $backup"
    fi

    # Mark as migrated
    mkdir -p "$(dirname "$SECRETS_MIGRATED_FLAG")"
    touch "$SECRETS_MIGRATED_FLAG"
}

secrets_migrate() {
    # Manual migration command - remove flag and re-run
    rm -f "$SECRETS_MIGRATED_FLAG"
    __secrets_auto_migrate
}

# ─────────────────────────────────────────────────────────────────────────────
#   Interactive Selection
# ─────────────────────────────────────────────────────────────────────────────

secret_fz() {
    # Interactive secret selection with fzf
    local all_flag=""
    local copy=false
    local preview=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                cat <<'EOF'
Usage: secret_fz [-a|--all] [-p|--preview] [-c|--copy]

Interactive secret selection using fzf.

Options:
  -a, --all      Browse ALL keychain entries, not just dotfiles
  -p, --preview  Show secret value in preview pane
  -c, --copy     Copy selected secret to clipboard (instead of printing)
  -h, --help     Show this help message

Alias: sfz

Examples:
  sfz                # Browse dotfiles secrets
  sfz -a -p          # Browse all with preview
  sfz -c             # Select and copy to clipboard
  sfz -a -p -c       # All options combined
EOF
                return 0 ;;
            -a|--all) all_flag="-a"; shift ;;
            -c|--copy) copy=true; shift ;;
            -p|--preview) preview=true; shift ;;
            -*) echo "Unknown option: $1. Use -h for help." >&2; return 1 ;;
            *) shift ;;
        esac
    done

    if ! command -v fzf &>/dev/null; then
        echo "fzf is required for secret_fz" >&2
        return 1
    fi

    local fzf_opts=(--header="Select secret (Enter=print, Ctrl-C=cancel)")
    if [[ "$preview" == true ]]; then
        fzf_opts+=(
            --preview="source '$DOTFILES_DIR/lib/secrets.sh' 2>/dev/null; secret $all_flag '{}' 2>/dev/null || echo '[Access denied or not found]'"
            --preview-window=down:3:wrap
        )
    fi

    local selected
    selected=$(secret_list $all_flag | fzf "${fzf_opts[@]}")

    [[ -z "$selected" ]] && return 0

    local value
    value=$(secret $all_flag "$selected" 2>/dev/null)

    if [[ -n "$value" ]]; then
        if [[ "$copy" == true ]] && command -v pbcopy &>/dev/null; then
            echo -n "$value" | pbcopy
            echo "Copied to clipboard: $selected"
        elif [[ "$copy" == true ]] && command -v xclip &>/dev/null; then
            echo -n "$value" | xclip -selection clipboard
            echo "Copied to clipboard: $selected"
        else
            echo "$value"
        fi
    else
        echo "Could not retrieve secret" >&2
        return 1
    fi
}

# Short aliases (as functions for better compatibility)
sl() { secret_list "$@"; }
sfz() { secret_fz "$@"; }
