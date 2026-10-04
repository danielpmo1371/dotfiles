-- Local template (not from Omarchy), rendered by omarchy-theme-set-templates
-- next to Omarchy's hyprland.lua. config/hypr/hyprland.lua reads the values it
-- returns for the floating-window border, which Omarchy's template doesn't
-- theme. A theme sets hyprland_float_border in colors.toml to pick its own;
-- magenta is the default because accent is usually blue, so floats stand out.
return {
  floatBorderActive = "{{ gradient_start hyprland_float_border magenta }}",
  floatBorderInactive = "{{ gradient_start hyprland_float_border_inactive selection }}",
}
