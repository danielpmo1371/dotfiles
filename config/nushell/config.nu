# ~/.config/nushell/config.nu
# Nushell configuration - mirrors zsh setup

# ─────────────────────────────────────────────────────────────────────────────
#   Shell Options (merge with defaults, don't replace)
# ─────────────────────────────────────────────────────────────────────────────
$env.config = ($env.config | merge {
    show_banner: false
    edit_mode: vi

    history: {
        max_size: 10000
        sync_on_enter: true
        file_format: "sqlite"
    }

    completions: {
        case_sensitive: false
        quick: true
        partial: true
        algorithm: "fuzzy"
    }

    table: {
        mode: rounded
        index_mode: auto
        trim: {
            methodology: wrapping
            wrapping_try_keep_words: true
        }
    }

    cursor_shape: {
        vi_insert: line
        vi_normal: block
    }

    keybindings: [
        {
            name: history_search
            modifier: control
            keycode: char_r
            mode: [emacs, vi_insert, vi_normal]
            event: { send: SearchHistory }
        }
    ]
})

# ─────────────────────────────────────────────────────────────────────────────
#   Source modular configs
# ─────────────────────────────────────────────────────────────────────────────
source ($nu.default-config-dir | path join "aliases.nu")

# ─────────────────────────────────────────────────────────────────────────────
#   Zoxide (z command - smart cd)
#   Generate: zoxide init nushell | save -f ~/.zoxide.nu
# ─────────────────────────────────────────────────────────────────────────────
source ~/.zoxide.nu

# ─────────────────────────────────────────────────────────────────────────────
#   Startup
# ─────────────────────────────────────────────────────────────────────────────
# Show image on startup (like zsh with chafa)
# if (which chafa | is-not-empty) and ($"($env.HOME)/linux.png" | path exists) {
#     chafa -f symbols $"($env.HOME)/linux.png"
# }
