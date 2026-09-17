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

    -- Keybinds consumed by overrides/caelestia/hypr-user.lua
    kbOcrScreenshot = "SUPER + SHIFT + T",

    -- Default OCR language for the shell's capture path
    ocrLanguages = "eng",
}
