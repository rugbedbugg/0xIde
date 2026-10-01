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

-- Desktop profiles. 0xIde writes the committed profile's window-management
-- policy to $XDG_STATE_HOME/0xide/wm-policy (see orchestration/lib/wm-policy.sh).
-- A window that policy floats is floated here as it opens, and recorded in
-- wm-floated, so that returning to a tiling profile tiles it again. No policy
-- file, or one this does not understand, means tiling: nothing is changed.
-- Windows on special workspaces, pinned and fullscreen ones are left alone.
local state_home = os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")
local profile_state = state_home .. "/0xide"

local function read_wm_policy()
    local policy = { name = "tiling", all = false, classes = {}, tags = {} }
    local file = io.open(profile_state .. "/wm-policy", "r")
    if not file then return policy end
    for line in file:lines() do
        local key, value = line:match("^(%S+)%s*(%S*)%s*$")
        if key == "policy" then policy.name = value
        elseif key == "float_all" then policy.all = true
        elseif key == "float_class" then policy.classes[value] = true
        elseif key == "float_tag" then policy.tags[value] = true
        end
    end
    file:close()
    return policy
end

local function wm_policy_floats(policy, win)
    if policy.name == "stacking" then return policy.all end
    if policy.name ~= "hybrid" then return false end
    if type(win.class) == "string" and policy.classes[win.class] then return true end
    if type(win.tags) ~= "table" then return false end
    for _, tag in ipairs(win.tags) do
        -- Hyprland marks tags a rule set dynamically with a trailing "*".
        if type(tag) == "string" and policy.tags[(tag:gsub("%*$", ""))] then return true end
    end
    return false
end

hl.on("window.open", function(win)
    if not win or win.floating ~= false or win.pinned or (win.fullscreen or 0) ~= 0 then return end
    local workspace = win.workspace and win.workspace.id
    if type(workspace) ~= "number" or workspace <= 0 then return end
    if type(win.address) ~= "string" then return end
    if not wm_policy_floats(read_wm_policy(), win) then return end
    hl.dispatch(hl.dsp.window.float({ action = "on", window = win }))
    -- Recorded with its stable id, which Hyprland never reuses, as
    -- orchestration/lib/wm-policy.sh expects; without one it is never re-tiled.
    local id = type(win.stable_id) == "number" and string.format("%x", win.stable_id) or "-"
    local ledger = io.open(profile_state .. "/wm-floated", "a")
    if ledger then
        ledger:write(win.address .. "\t" .. id .. "\n")
        ledger:close()
    end
end)

-- At login, the committed profile's policy is written afresh, so a damaged
-- state file falls back to Caelestia's tiling rather than a stale policy.
-- ./install writes this checkout's path here.
hl.on("hyprland.start", function()
    hl.exec_cmd("'@OX_ROOT@/0xide' profile resume")
end)
