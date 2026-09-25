-- Hyprland configuration (Lua) — managed by ~/repos/dotfiles (config/hypr/).
-- Installed as a symlink to ~/.config/hypr by ./install.sh --hypr.
-- Refer to the wiki: https://wiki.hypr.land/Configuring/Start/

-- You can (and should!!) split this configuration into multiple files
-- Create your files separately and then require them like this:
-- require("myColors")


------------------
---- MONITORS ----
------------------

-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})


---------------------
---- MY PROGRAMS ----
---------------------

-- Set programs that you use
local terminal    = "kitty"
local fileManager = "dolphin"
local menu        = "wofi --show drun"
local browser     = "google-chrome-stable"


-------------------
---- AUTOSTART ----
-------------------

-- See https://wiki.hypr.land/Configuring/Basics/Autostart/

-- Autostart necessary processes (like notifications daemons, status bars, etc.)
-- Or execute your favorite apps at launch like this:
--
-- hl.on("hyprland.start", function ()
--   hl.exec_cmd(terminal)
--   hl.exec_cmd("nm-applet")
-- end)
-- Inside the start hook so config reloads don't spawn duplicate instances.
hl.on("hyprland.start", function ()
    hl.exec_cmd("wayle panel start") -- bare `wayle` only prints help
    hl.exec_cmd("hyprpaper")
end)


-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")


-----------------------
----- PERMISSIONS -----
-----------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Permissions/
-- Please note permission changes here require a Hyprland restart and are not applied on-the-fly
-- for security reasons

-- hl.config({
--   ecosystem = {
--     enforce_permissions = true,
--   },
-- })

-- hl.permission("/usr/(bin|local/bin)/grim", "screencopy", "allow")
-- hl.permission("/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland", "screencopy", "allow")
-- hl.permission("/usr/(bin|local/bin)/hyprpm", "plugin", "allow")


-----------------------
---- LOOK AND FEEL ----
-----------------------

-- Refer to https://wiki.hypr.land/Configuring/Basics/Variables/
hl.config({
    general = {
        gaps_in  = 5,
        gaps_out = 10,

        border_size = 2,

        col = {
            active_border   = { colors = {"rgba(33ccffee)", "rgba(00ff99ee)"}, angle = 45 },
            inactive_border = "rgba(595959aa)",
        },

        -- Set to true to enable resizing windows by clicking and dragging on borders and gaps
        resize_on_border = true,

        -- Please see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before you turn this on
        allow_tearing = false,

        layout = "dwindle",
    },

    decoration = {
        rounding       = 10,
        rounding_power = 2,

        -- Change transparency of focused and unfocused windows
        active_opacity   = 0.9,
        inactive_opacity = 0.7,

        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = 0xee1a1a1a,
        },

        blur = {
            enabled   = true,
            size      = 3,
            passes    = 1,
            vibrancy  = 0.1696,
        },
    },

    animations = {
        enabled = true,
    },

    plugin = {
      hyprexpo = {
        columns          = 3,
        rows             = 2,
        gaps_in          = 5,
        gaps_out         = 0,
        workspace_method = "center current",
        fill_gaps        = 0,
      },
    },
})

-- Default curves and animations, see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })

-- Default springs
hl.curve("easy",           { type = "spring", mass = 1, stiffness = 238.1191, dampening = 24.21279333 })

hl.animation({ leaf = "global",        enabled = true,  speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true,  speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true,  speed = 4.79, spring = "easy" })
hl.animation({ leaf = "windowsIn",     enabled = true,  speed = 4.1,  spring = "easy",         style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true,  speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true,  speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true,  speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true,  speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true,  speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true,  speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true,  speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true,  speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true,  speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true,  speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true,  speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true,  speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor",    enabled = true,  speed = 7,    bezier = "quick" })

-- Ref https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
-- "Smart gaps" / "No gaps when only"
-- uncomment all if you wish to use that.
-- hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
-- hl.workspace_rule({ workspace = "f[1]",   gaps_out = 0, gaps_in = 0 })
-- hl.window_rule({
--     name  = "no-gaps-wtv1",
--     match = { float = false, workspace = "w[tv1]" },
--     border_size = 0,
--     rounding    = 0,
-- })
-- hl.window_rule({
--     name  = "no-gaps-f1",
--     match = { float = false, workspace = "f[1]" },
--     border_size = 0,
--     rounding    = 0,
-- })

-- See https://wiki.hypr.land/Configuring/Layouts/Dwindle-Layout/ for more
hl.config({
    dwindle = {
        preserve_split = true, -- You probably want this
    },
})

-- See https://wiki.hypr.land/Configuring/Layouts/Master-Layout/ for more
hl.config({
    master = {
        new_status = "master",
    },
})

-- See https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/ for more
hl.config({
    scrolling = {
        fullscreen_on_one_column = true,
    },
})

----------------
----  MISC  ----
----------------

hl.config({
    misc = {
        force_default_wallpaper = -1,    -- Set to 0 or 1 to disable the anime mascot wallpapers
        disable_hyprland_logo   = false, -- If true disables the random hyprland logo / anime girl background. :(
    },
})


---------------
---- INPUT ----
---------------

hl.config({
    input = {
        kb_layout  = "us",
        kb_variant = "",
        kb_model   = "",
        -- Swap Left Ctrl <-> Left Alt: puts Ctrl on the thumb key (macOS cmd
        -- position), so tmux/zsh Ctrl bindings match mac muscle memory.
        -- This is the Linux analogue of the ghostty super+key forwarding table
        -- (config/ghostty/config) — deliberate, do not "fix".
        kb_options = "ctrl:swap_lalt_lctl",
        kb_rules   = "",

        follow_mouse = 1,

        sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.

        touchpad = {
            natural_scroll = true,
        },
    },
})

hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace"
})

-- Example per-device config
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Devices/ for more
hl.device({
    name        = "epic-mouse-v1",
    sensitivity = -0.5,
})


---------------------
---- KEYBINDINGS ----
---------------------

local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- Example binds, see https://wiki.hypr.land/Configuring/Basics/Binds/ for more
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal))
local closeWindowBind = hl.bind(mainMod .. " + C", hl.dsp.window.close())
-- closeWindowBind:set_enabled(false)
hl.bind(mainMod .. " + M", hl.dsp.exit())
hl.bind(mainMod .. " + F", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("zen-browser"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + space", function()
    hl.plugin.hyprexpo.expo("toggle")
end)
-- hyprexpo enters the `hyprexpo` submap itself while the overview is open and
-- resets it on close; see docs/configuration/keyboard.md in sandwichfarm/hyprexpo.
-- Raw digits are handled by the plugin (number_key_mode = "workspace").
hl.define_submap("hyprexpo", function()
    for _, nav in ipairs({
        { key = "h", dir = "left" },  { key = "left",  dir = "left" },
        { key = "l", dir = "right" }, { key = "right", dir = "right" },
        { key = "k", dir = "up" },    { key = "up",    dir = "up" },
        { key = "j", dir = "down" },  { key = "down",  dir = "down" },
    }) do
        hl.bind(nav.key, function() hl.plugin.hyprexpo.kb_focus(nav.dir) end)
    end
    hl.bind("return", function() hl.plugin.hyprexpo.kb_confirm() end)
    hl.bind("escape", function() hl.plugin.hyprexpo.expo("cancel") end)
end)
-- hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
-- hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))    -- dwindle only

-- Floating windows take 85% of the monitor's usable area, centred.
local floatRatio = 0.95

-- monitor.width/height are physical pixels, but windows are sized in logical
-- ones and monitor.reserved is already logical -- so scale before subtracting.
local function usableSize(monitor)
    local w, h = monitor.width / monitor.scale, monitor.height / monitor.scale
    if monitor.transform % 2 == 1 then -- 90/270 rotation swaps the axes
        w, h = h, w
    end
    local r = monitor.reserved
    return w - r.left - r.right, h - r.top - r.bottom
end

hl.bind(mainMod .. " + V", function()
    local win = hl.get_active_window()
    if not win then return end

    local wasFloating = win.floating
    hl.dispatch(hl.dsp.window.float({ action = wasFloating and "disable" or "enable" }))

    -- Only size on the way *into* float: resizing a tiled window would skew the
    -- dwindle split, and both resize and center reject fullscreen windows.
    if wasFloating or win.fullscreen ~= 0 then return end

    local monitor = win.monitor or hl.get_active_monitor()
    if not monitor then return end

    local w, h = usableSize(monitor)
    hl.dispatch(hl.dsp.window.resize({ x = math.floor(w * floatRatio), y = math.floor(h * floatRatio) }))
    hl.dispatch(hl.dsp.window.center()) -- after resize: it centres the goal size
end)


-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + h",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + l", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + k",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))
hl.bind(mainMod .. " + j",  hl.dsp.focus({ direction = "down" }))

-- Physical Alt+Tab cycles the windows of the active workspace (SHIFT reverses).
-- The ctrl:swap_lalt_lctl kb_option above makes the key labelled Alt emit
-- CTRL, so the bind is CTRL + Tab. Trade-off, accepted: apps no longer see
-- CTRL + Tab from that key for their own tab switching.
local function cycleWindows(forward)
    return function()
        hl.dispatch(hl.dsp.window.cycle_next({ next = forward }))
        -- cycle_next only focuses; floating windows stay buried without this.
        hl.dispatch(hl.dsp.window.bring_to_top())
    end
end

hl.bind("CTRL + Tab",         cycleWindows(true))
hl.bind("CTRL + SHIFT + Tab", cycleWindows(false))

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,             hl.dsp.focus({ workspace = i}))
    hl.bind(mainMod .. " + SHIFT + " .. key,     hl.dsp.window.move({ workspace = i }))
end

-- Toggle back and forth between the current and the last-focused workspace
-- (cmd-tab feel). "previous" is global; "previous_per_monitor" would scope it
-- to the active monitor. SUPER is untouched by the ctrl:swap_lalt_lctl option
-- above, and Tab is otherwise only bound with CTRL (window cycling).
hl.bind(mainMod .. " + Tab", hl.dsp.focus({ workspace = "previous" }))

-- Show the current workspace number (no status bar is running).
-- hyprctl notify args: <icon> <duration_ms> <color> <message>; -1 = no icon, 0 = default color.
local notifyNoIcon, notifyDefaultColor, notifyDurationMs = -1, 0, 2000
hl.bind(mainMod .. " + I", hl.dsp.exec_cmd(
    [[sh -c 'hyprctl notify ]] .. notifyNoIcon .. " " .. notifyDurationMs .. " " .. notifyDefaultColor
        .. [[ "workspace $(hyprctl activeworkspace -j | jq -r .id)"']]
))

-- Example special workspace (scratchpad)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Scroll through existing workspaces with mainMod + scroll (and SHIFT + h/l)
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + SHIFT + l", hl.dsp.focus({ workspace = "+1" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.focus({ workspace = "+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + SHIFT + left",   hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + SHIFT + h",   hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Resize current window: enter the `resize` submap with mainMod + SHIFT + R
-- (mainMod + R is the app launcher)
hl.bind(mainMod .. " + R", hl.dsp.submap("resize"))

-- Start the `resize` submap
hl.define_submap("resize", function()
    -- Set repeating binds using Vim keys to resize the active window
    hl.bind("l", hl.dsp.window.resize({ x = 20, y = 0, relative = true }), { repeating = true })
    hl.bind("h", hl.dsp.window.resize({ x = -20, y = 0, relative = true }), { repeating = true })
    hl.bind("k", hl.dsp.window.resize({ x = 0, y = -20, relative = true }), { repeating = true })
    hl.bind("j", hl.dsp.window.resize({ x = 0, y = 20, relative = true }), { repeating = true })

    -- Return to the global submap with Escape
    hl.bind("escape", hl.dsp.submap("reset"))
end)

-- Screenshots (grim + slurp): copied to clipboard and saved under ~/Pictures/Screenshots
local screenshotDir = "$HOME/Pictures/Screenshots"
hl.bind("Print", hl.dsp.exec_cmd(
    [[sh -c 'd="]] .. screenshotDir .. [["; f="$d/$(date +%F_%H-%M-%S).png"; mkdir -p "$d"; grim "$f" && wl-copy < "$f"']]
))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd(
    [[sh -c 'd="]] .. screenshotDir .. [["; f="$d/$(date +%F_%H-%M-%S).png"; mkdir -p "$d"; grim -g "$(slurp)" "$f" && wl-copy < "$f"']]
))

-- Laptop multimedia keys for volume and LCD brightness
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { locked = true, repeating = true })

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })


--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- and https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

-- Example window rules that are useful

local suppressMaximizeRule = hl.window_rule({
    -- Ignore maximize requests from all apps. You'll probably like this.
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})
-- suppressMaximizeRule:set_enabled(false)

hl.window_rule({
    -- Fix some dragging issues with XWayland
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})

-- Layer rules also return a handle.
-- local overlayLayerRule = hl.layer_rule({
--     name  = "no-anim-overlay",
--     match = { namespace = "^my-overlay$" },
--     no_anim = true,
-- })
-- overlayLayerRule:set_enabled(false)

-- Hyprland-run windowrule
hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },

    move  = "20 monitor_h-120",
    float = true,
})

-- Floating windows get a thicker, contrasting border so they read as distinct
-- from the tiled cyan/green gradient set in `general.col` above. `border_size`
-- and `border_color` are *dynamic* effects: Hyprland re-evaluates them when a
-- window's float state changes, so the SUPER+V toggle applies and reverts this
-- live. The two-colour string is `<active> <inactive>` -- a gradient table
-- ({ colors = ..., angle = ... }) would only set the active colour.
local floatBorderSize     = 3
local floatBorderActive   = "rgb(FF8800)"
local floatBorderInactive = "rgb(553300)"

hl.window_rule({
    name  = "floating-accent-border",
    match = { float = true },

    border_size  = floatBorderSize,
    border_color = floatBorderActive .. " " .. floatBorderInactive,
})
