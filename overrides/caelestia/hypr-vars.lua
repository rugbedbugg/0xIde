-- Caelestia's supported Hyprland variable override point.
-- Upstream merges this table over hypr/variables.lua, so nothing in
-- ~/.config/hypr needs editing for any value that lives here.
return {
    -- Apps
    browser = "microsoft-edge-dev",
    editor = "vim",

    -- Input
    touchpadScrollFactor = 0.6,

    -- Appearance
    blurSpecialWs = false,
    blurXray = true,
    -- Upstream ships this lowercase; the installed theme directory is capitalised,
    -- and hyprcursor does not fall back, so the wrong case leaves the default cursor.
    cursorTheme = "Sweet-cursors",

    -- Keybinds for the shell extensions, bound in hypr-user.lua.
    -- Web search has one key: rectangle or circle is chosen in the selector.
    kbOcrScreenshot = "SUPER + SHIFT + T",
    kbRegionSearch = "SUPER + SHIFT + A",
}
