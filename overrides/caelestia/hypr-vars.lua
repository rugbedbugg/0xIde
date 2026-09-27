-- Caelestia's supported Hyprland variable override point.
-- Upstream merges this table over hypr/variables.lua, so nothing in
-- ~/.config/hypr needs editing for any value that lives here.

-- Upstream names its cursor "sweet-cursors", but the Sweet package installs
-- "Sweet-cursors" and theme names are case sensitive, so upstream always gets
-- the default cursor. The cursor adapter rebuilds Sweet in the scheme's
-- colours as 0xide-sweet; until it has run, plain Sweet under its real name.
local function cursor_theme()
    local data = os.getenv("XDG_DATA_HOME") or (os.getenv("HOME") .. "/.local/share")
    local f = io.open(data .. "/icons/0xide-sweet/index.theme")
    if f then
        f:close()
        return "0xide-sweet"
    end
    return "Sweet-cursors"
end

return {
    -- Apps
    browser = "microsoft-edge-dev",
    editor = "vim",

    -- Input
    touchpadScrollFactor = 0.6,

    -- Appearance
    blurSpecialWs = false,
    blurXray = true,
    cursorTheme = cursor_theme(),

    -- Keybinds for the shell extensions, bound in hypr-user.lua.
    -- Web search has one key: rectangle or circle is chosen in the selector.
    kbOcrScreenshot = "SUPER + SHIFT + T",
    kbRegionSearch = "SUPER + SHIFT + A",
    -- Press to start dictating, press again to type what was said.
    kbDictation = "SUPER + SHIFT + D",
}
