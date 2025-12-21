# Nushell Quick Start

## Verify Installation

```bash
# Check nushell version
nu --version

# Check config paths
nu -c '$nu.config-path'
nu -c '$nu.env-path'

# Check symlink
ls -la ~/.config/nushell
```

## Test Configuration

### Interactive Shell (Recommended)
Start nushell interactively to use all features:
```bash
nu
```

Then test:
```nu
# Test aliases
which n
which gs
which z

# Test environment
$env.EDITOR
$env.config.edit_mode

# Test vi mode (press ESC, then try vi commands)
```

### Command Line Testing
For testing from bash/zsh, use `--login` flag:
```bash
nu --login -c 'which n'
nu --login -c '$env.config.edit_mode'
nu --login -c 'which z'
```

## Common Commands

### Navigation
- `z <partial-name>` - Smart cd using zoxide
- `root` - cd to ~/repos/
- `..` - cd ..
- `...` - cd ../..

### Editor
- `n` - Open nvim
- `nz` or `fvim` - Open file selected with fzf in nvim
- `setup-vim` - Edit nvim config
- `setup-nu` - Edit nushell config

### Git
- `gs` - git status
- `lg` - git log (pretty)
- `lz` - Launch lazygit
- `flg` - Fuzzy search git log with preview
- `cm "message"` - git commit -m
- `psh` - git push

### AI Tools
- `cc` - Claude with -p flag
- `gg` - Gemini with -p flag  
- `g "prompt"` - Gemini flash model

### Shell
- `reterm` - Restart nushell (config changes)
- `cls` - Clear screen

## Vi Mode

Vi mode is enabled by default. Press:
- `ESC` - Enter normal mode (cursor becomes block)
- `i` - Enter insert mode (cursor becomes line)
- `Ctrl+R` - Search history (works in both modes)

Vi keybindings work in normal mode: `h,j,k,l`, `w,b`, `0,$`, etc.

## Structured Data Features

Nushell works with structured data:

```nu
# Git status as table
gst

# Process search
psg firefox

# Find large files
big 100mb

# Azure account list
azl

# Docker containers as structured data
dps

# Explore JSON interactively
jq-explore config.json
```

## Troubleshooting

### Aliases not working?
Make sure you're in an interactive or login shell:
```bash
nu --login  # Start login shell
```

### Zoxide not working?
Generate the init file:
```bash
zoxide init nushell | save -f ~/.zoxide.nu
```

### Want to reload config?
Nushell can't reload config in place. Use:
```nu
reterm  # or just: exec nu
```

### Config not loading?
Check the files exist and are readable:
```bash
ls -la ~/.config/nushell/
cat ~/.config/nushell/config.nu
```

## Differences from Bash/Zsh

1. **Pipes work on data structures**, not just text
2. **String interpolation**: Use `$"Hello ($name)"` or `$'Path: ($env.PATH)'`
3. **No command substitution `$()`**: Use parentheses `(command)`
4. **Boolean logic**: Use `and`, `or`, `not` instead of `&&`, `||`, `!`
5. **Each loop**: `ls | each { |file| print $file.name }`
6. **Where filter**: `ls | where size > 1mb`

## Resources

- [Nushell Book](https://www.nushell.sh/book/)
- [Nushell Cookbook](https://www.nushell.sh/cookbook/)
- Local config: `~/.config/nushell/README.md`
