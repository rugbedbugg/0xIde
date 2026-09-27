-- Caelestia's supported Hyprland user config point. Upstream requires this file
-- for its side effects only and discards whatever it returns, so everything here
-- has to call hl directly rather than return a table. Variable overrides belong
-- in hypr-vars.lua, which upstream does merge.
--
-- This runs after every hypr/hyprland/*.lua module, so hl.config calls here win
-- and hl.bind calls here are added on top of upstream's.
local vars = require("variables")

hl.config({
    cursor = {
        no_hardware_cursors = false,
        enable_hyprcursor = true,
    },
})

local function normalise(key)
    return type(key) == "string" and key:gsub("%s+", ""):lower() or nil
end

-- Keys upstream already bound, so a binding added here can never shadow one.
-- hypr/hyprland/keybinds.lua binds every vars.kb* value it knows about; these
-- are ours and are bound nowhere else.
local ours = {
    kbOcrScreenshot = true,
    kbRegionSearch = true,
    kbDictation = true,
}

local taken = {}
for name, value in pairs(vars) do
    local key = not ours[name] and name:match("^kb") and normalise(value)
    if key then taken[key] = name end
end

-- create_bind in hypr/hyprland/keybinds.lua is a private helper; hl.bind is
-- what it calls, so binding directly here needs no change to that file.
local function bind_to(name, dispatcher)
    local key = normalise(vars[name])
    if not key or key == "" then return end
    if taken[key] then
        print(("hypr-user: %s wants %s, already bound by %s; skipping")
            :format(name, vars[name], taken[key]))
        return
    end
    taken[key] = name
    hl.bind(vars[name], dispatcher)
end

local function bind(name, action)
    bind_to(name, hl.dsp.global("caelestia:" .. action))
end

bind("kbOcrScreenshot", "screenshotOcr")
bind("kbRegionSearch", "regionSearch")

-- Dictation is a script, not a shell shortcut: it records and types from
-- outside the shell, so it keeps working while the shell restarts.
local config_home = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
bind_to("kbDictation", hl.dsp.exec_cmd("bash " .. config_home .. "/quickshell/caelestia/assets/dictation/dictate.sh"))
