# High-Res Logo Display in Ghostty/Tmux

## Setup Complete ✅

### What Was Configured

1. **Tmux Passthrough** - Enabled image protocol support in tmux
2. **Apple Logo** - High-quality 512x512 PNG logo added
3. **Fastfetch Config** - Configured with chafa rendering
4. **Custom Script** - Created neofetch-apple.sh for perfect display
5. **Aliases** - Added convenient `fetch` and `neofetch` commands

### Usage

Simply run:
```bash
fetch
```

or

```bash
neofetch
```

This displays a beautiful Apple logo alongside your system info using chafa + fastfetch.

### Files Modified

- `config/tmux/tmux.conf` - Added passthrough settings
- `config/fastfetch/config.json` - Fastfetch configuration
- `config/fastfetch/logos/apple.png` - 512x512 Apple logo
- `util-scripts/neofetch-apple.sh` - Custom fetch script
- `config/shell/aliases.sh` - Added fetch aliases
- `installers/config-dirs.sh` - Auto-install fastfetch config

### How It Works

The solution combines:
1. **Chafa** - Renders PNG to Unicode blocks with true color
2. **Fastfetch** - Generates system info
3. **Bash `paste`** - Combines them side-by-side

Works perfectly in:
- ✅ Ghostty (native)
- ✅ Ghostty + tmux (with passthrough)
- ✅ Any terminal with true color support

### Testing

```bash
# Test the script directly
~/repos/dotfiles/util-scripts/neofetch-apple.sh

# After sourcing aliases (or in new shell)
fetch
```

### Customization

Edit the logo size in `util-scripts/neofetch-apple.sh`:
```bash
LOGO_WIDTH=18   # Adjust width
LOGO_HEIGHT=18  # Adjust height
```

Or use a different logo:
```bash
LOGO_FILE="$HOME/.config/fastfetch/logos/your-logo.png"
```

