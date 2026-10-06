-- Describes Caelestia's keybinds to Hyprland, so `hyprctl binds` and the
-- keyboard shortcuts overlay can say what each one does.
--
-- With a Lua config every bind's dispatcher is reported as "__lua" and an
-- action is an opaque HL.Dispatcher, so the running compositor cannot say what
-- a bind does unless the bind carries a description. Upstream's binds carry
-- none, and its keybinds.lua is not ours to edit. So, for the duration of
-- upstream's registration only, the hl.dsp constructors note what each action
-- they build is, and hl.bind gives a bind that has no description one derived
-- from that note. Everything else is passed through untouched.
--
-- hypr-vars.lua installs this, and Caelestia's hyprland.lua requires
-- hypr-vars before hyprland.keybinds; hypr-user.lua, required after it,
-- restores the originals. A reload starts a fresh Lua state, so each load
-- installs and restores once; installing twice in one state does nothing.

local M = {}

local KEY = "__0xide_binds"

-- Every key combination bound while installed, as given to hl.bind.
local observed = {}

-- Arguments, as "k=v" in key order. Nested tables are shown, not guessed at.
local function show(value, depth)
    depth = depth or 0
    if type(value) == "string" then return value end
    if type(value) ~= "table" then return tostring(value) end
    if depth > 2 then return "{…}" end
    local keys = {}
    for k in pairs(value) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do
        local v = show(value[k], depth + 1)
        parts[#parts + 1] = type(k) == "number" and v or (tostring(k) .. "=" .. v)
    end
    return table.concat(parts, " ")
end

local function only(args, ...)
    if type(args) ~= "table" then return false end
    local allowed = {}
    for _, k in ipairs({ ... }) do allowed[k] = true end
    for k in pairs(args) do
        if not allowed[k] then return false end
    end
    return true
end

local function workspace_target(ws)
    if ws == "+1" then return "next workspace" end
    if ws == "-1" then return "previous workspace" end
    if type(ws) == "number" or (type(ws) == "string" and ws:match("^%d+$")) then return "workspace " .. ws end
    return nil
end

local directions = { left = true, right = true, up = true, down = true }

-- What a dispatcher does, from its constructor's path and arguments, or the
-- path and arguments themselves when that is not certain. Global shortcuts
-- are named, not described: the shell that registers them owns the wording.
function M.describe(path, args)
    local a = args[1]
    local n = args.n or #args
    if path == "global" and n == 1 and type(a) == "string" then return "global " .. a end
    if path == "exec_cmd" and n == 1 and type(a) == "string" then return "Run " .. a end

    if path == "focus" and n == 1 then
        if only(a, "workspace") and workspace_target(a.workspace) then return "Focus " .. workspace_target(a.workspace) end
        if only(a, "direction") and directions[a.direction] then return "Focus window " .. a.direction end
    end
    if path == "window.move" and n == 1 then
        if only(a, "workspace") and workspace_target(a.workspace) then return "Move window to " .. workspace_target(a.workspace) end
        if only(a, "direction") and directions[a.direction] then return "Move window " .. a.direction end
        if only(a, "out_of_group") and a.out_of_group == true then return "Move window out of its group" end
    end

    local plain = {
        ["window.close"] = "Close window",
        ["window.pin"] = "Toggle pinned",
        ["window.float"] = "Toggle floating",
        ["window.center"] = "Centre window",
        ["window.drag"] = "Move window with the mouse",
        ["window.resize"] = "Resize window with the mouse",
        ["window.cycle_next"] = "Focus next window",
        ["group.next"] = "Next window in group",
        ["group.prev"] = "Previous window in group",
        ["group.toggle"] = "Toggle window group",
    }
    if plain[path] and n == 0 then return plain[path] end
    if path == "window.cycle_next" and n == 1 and only(a, "next") and a.next == false then return "Focus previous window" end
    if path == "window.fullscreen" and n == 1 and only(a, "mode") then
        if a.mode == "fullscreen" then return "Toggle fullscreen" end
        if a.mode == "maximized" then return "Toggle maximised" end
    end

    -- Not certain: the dispatcher and its arguments, as they were given.
    local shown = {}
    for i = 1, n do shown[#shown + 1] = show(args[i]) end
    return #shown > 0 and (path .. " " .. table.concat(shown, " ")) or path
end

-- hl.dsp.window.move and the rest, each with its dotted path.
local function constructors(tbl, prefix, out, seen)
    out = out or {}
    seen = seen or {}
    if seen[tbl] then return out end
    seen[tbl] = true
    for name, value in pairs(tbl) do
        local path = prefix and (prefix .. "." .. name) or name
        if type(value) == "function" then
            out[#out + 1] = { tbl = tbl, name = name, path = path, fn = value }
        elseif type(value) == "table" then
            constructors(value, path, out, seen)
        end
    end
    return out
end

function M.install()
    if type(hl) ~= "table" or type(hl.bind) ~= "function" or type(hl.dsp) ~= "table" then return false end
    if rawget(hl, KEY) then return true end

    local state = { bind = hl.bind, constructors = constructors(hl.dsp), notes = setmetatable({}, { __mode = "k" }) }
    if package.loaded["hyprland.keybinds"] then
        print("0xide-binds: installed after Caelestia's keybinds; they will not be described")
    end

    for _, c in ipairs(state.constructors) do
        local fn, path = c.fn, c.path
        c.tbl[c.name] = function(...)
            local action = fn(...)
            local args = table.pack(...)
            pcall(function()
                if type(action) == "userdata" or type(action) == "table" then
                    state.notes[action] = M.describe(path, args)
                end
            end)
            return action
        end
    end

    local bind = state.bind
    hl.bind = function(key, action, flags, ...)
        pcall(function()
            if type(key) == "string" then observed[#observed + 1] = key end
        end)
        local ok, described = pcall(function()
            if flags ~= nil and type(flags) ~= "table" then return nil end
            if flags and flags.description ~= nil then return nil end
            local text = state.notes[action]
            if type(text) ~= "string" or text == "" then return nil end
            -- A copy: upstream shares one flags table across many binds.
            local copy = {}
            for k, v in pairs(flags or {}) do copy[k] = v end
            copy.description = text
            return copy
        end)
        if ok and described then flags = described end
        return bind(key, action, flags, ...)
    end

    rawset(hl, KEY, state)
    return true
end

-- Puts the originals back. Binds made through the wrappers keep their
-- descriptions; binds made after this get none unless they bring their own.
function M.restore()
    local state = type(hl) == "table" and rawget(hl, KEY)
    if not state then return false end
    for _, c in ipairs(state.constructors) do
        c.tbl[c.name] = c.fn
    end
    hl.bind = state.bind
    rawset(hl, KEY, nil)
    return true
end

-- The key combinations upstream bound, so hypr-user.lua binds none of them
-- again: the keys a bind actually used, not the variables that may have
-- named them.
function M.bound()
    local copy = {}
    for i, key in ipairs(observed) do copy[i] = key end
    return copy
end

return M
