# ~/.config/nushell/env.nu
# Environment variables - mirrors config/shell/env.sh and path.sh

# ─────────────────────────────────────────────────────────────────────────────
#   Dotfiles location
# ─────────────────────────────────────────────────────────────────────────────
$env.DOTFILES_DIR = ($env.HOME | path join "repos" "dotfiles")

# ─────────────────────────────────────────────────────────────────────────────
#   XDG Base Directories
# ─────────────────────────────────────────────────────────────────────────────
$env.XDG_CONFIG_HOME = ($env.HOME | path join ".config")
$env.XDG_DATA_HOME = ($env.HOME | path join ".local" "share")
$env.XDG_CACHE_HOME = ($env.HOME | path join ".cache")

# ─────────────────────────────────────────────────────────────────────────────
#   Editor
# ─────────────────────────────────────────────────────────────────────────────
$env.EDITOR = "nvim"
$env.VISUAL = "nvim"

# ─────────────────────────────────────────────────────────────────────────────
#   FZF
# ─────────────────────────────────────────────────────────────────────────────
$env.FZF_COMPLETION_TRIGGER = "**"
$env.FZF_DEFAULT_OPTS = "--height 40% --layout=reverse --border"

# ─────────────────────────────────────────────────────────────────────────────
#   AI Tools
# ─────────────────────────────────────────────────────────────────────────────
$env.GEMINI_MODEL = "gemini-2.5-flash"
$env.AI_PROVIDER = "openai"
$env.AI_ENDPOINT = "https://api.openai.com/v1"
$env.AI_MODEL = "o4-mini"
$env.AI_TEMPERATURE = "0.7"
$env.AI_MAX_TOKENS = "2000"

# ─────────────────────────────────────────────────────────────────────────────
#   Custom tools
# ─────────────────────────────────────────────────────────────────────────────
$env.TALKING_AGENT = "1"
$env.TTALK_WORD_COUNT = "20"

# ─────────────────────────────────────────────────────────────────────────────
#   PATH - build it directly (cross-platform: macOS + Linux/WSL)
# ─────────────────────────────────────────────────────────────────────────────
$env.PATH = (
    $env.PATH
    | split row (char esep)
    # Homebrew - macOS (Apple Silicon)
    | prepend "/opt/homebrew/bin"
    | prepend "/opt/homebrew/sbin"
    # Homebrew - Linux
    | prepend "/home/linuxbrew/.linuxbrew/bin"
    | prepend "/home/linuxbrew/.linuxbrew/sbin"
    # Standard paths
    | prepend "/usr/local/bin"
    | prepend "/usr/bin"
    | prepend "/bin"
    | prepend "/usr/sbin"
    | prepend "/sbin"
    # Development tools
    | prepend "/opt/nvim"
    | prepend ($env.HOME | path join ".dotnet")
    | prepend ($env.HOME | path join ".dotnet" "tools")
    | prepend ($env.HOME | path join ".cargo" "bin")
    | prepend ($env.HOME | path join ".local" "bin")
    # Dotfiles utilities
    | prepend ($env.DOTFILES_DIR | path join "util-scripts")
    | prepend ($env.DOTFILES_DIR | path join "azcli-scripts")
    # App-specific
    | append ($env.HOME | path join ".lmstudio" "bin")
    | append ($env.HOME | path join ".console-ninja" ".bin")
    # Clean up: remove duplicates and non-existent paths
    | uniq
    | where { |p| $p | path exists }
)

# ─────────────────────────────────────────────────────────────────────────────
#   Pyenv (Python version manager)
# ─────────────────────────────────────────────────────────────────────────────
if ($env.HOME | path join ".pyenv" | path exists) {
    $env.PYENV_ROOT = ($env.HOME | path join ".pyenv")
    $env.PATH = ($env.PATH | prepend ($env.PYENV_ROOT | path join "bin"))
}

# ─────────────────────────────────────────────────────────────────────────────
#   Secrets loader
# ─────────────────────────────────────────────────────────────────────────────
def load-access-tokens [file: string] {
    if ($file | path exists) {
        open $file
        | lines
        | where { |line| not ($line | str starts-with "#") and ($line | str length) > 0 }
        | where { |line| $line =~ "^[A-Za-z_][A-Za-z0-9_]*=" }
        | each { |line|
            let parts = ($line | split column "=" key value)
            let key = ($parts | get key.0)
            let value = ($parts | get value.0)
            load-env { $key: $value }
        }
    }
}

# Load secrets from home directory
load-access-tokens ($env.HOME | path join ".accessTokens")

# Also try dotfiles location (for WSL convenience)
if ($env.DOTFILES_DIR | path join ".accessTokens" | path exists) {
    load-access-tokens ($env.DOTFILES_DIR | path join ".accessTokens")
}

# ─────────────────────────────────────────────────────────────────────────────
#   Prompt (simple, or use starship)
# ─────────────────────────────────────────────────────────────────────────────
$env.PROMPT_COMMAND = {||
    let dir = ($env.PWD | path basename)
    let git_branch = (do { git branch --show-current } | complete | get stdout | str trim)
    if ($git_branch | is-empty) {
        $"(ansi cyan)($dir)(ansi reset) > "
    } else {
        $"(ansi cyan)($dir)(ansi reset) (ansi yellow)($git_branch)(ansi reset) > "
    }
}

$env.PROMPT_INDICATOR = ""
$env.PROMPT_INDICATOR_VI_INSERT = ": "
$env.PROMPT_INDICATOR_VI_NORMAL = "> "

# ─────────────────────────────────────────────────────────────────────────────
#   Starship prompt (optional - comment out if not using)
#   Generate: mkdir ~/.cache/starship; starship init nu | save -f ~/.cache/starship/init.nu
# ─────────────────────────────────────────────────────────────────────────────
# use ~/.cache/starship/init.nu
