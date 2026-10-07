-- overrides/caelestia/0xide-binds.lua and hypr-user.lua's keybind guard,
-- against a recording stand-in for Hyprland's hl table.
--
--   lua tests/binds_test.lua <overrides/caelestia>
--
-- Prints "ok <what>" or "FAIL <what>" per check.

local dir = assert(arg[1], "usage: binds_test.lua <overrides/caelestia>")
package.path = dir .. "/?.lua;" .. package.path

local function check(cond, what, detail)
    print((cond and "ok " or "FAIL ") .. what .. ((not cond and detail) and (": " .. tostring(detail)) or ""))
end

-- A stand-in hl: constructors return Dispatcher-like objects that remember
-- what built them, and bind records each call and returns something.
local function fake_hl()
    local h = { calls = {} }
    local function ctor(path)
        return function(...)
            return setmetatable({ path = path, args = table.pack(...) }, { __name = "HL.Dispatcher" })
        end
    end
    h.dsp = {
        global = ctor("global"), exec_cmd = ctor("exec_cmd"), focus = ctor("focus"), layout = ctor("layout"),
        submap = ctor("submap"),
        window = {
            move = ctor("window.move"), close = ctor("window.close"), pin = ctor("window.pin"),
            float = ctor("window.float"), center = ctor("window.center"), drag = ctor("window.drag"),
            resize = ctor("window.resize"), cycle_next = ctor("window.cycle_next"),
            fullscreen = ctor("window.fullscreen"),
        },
        group = { next = ctor("group.next"), prev = ctor("group.prev"), toggle = ctor("group.toggle"),
                  lock_active = ctor("group.lock_active") },
        workspace = {},
    }
    h.bind = function(key, action, flags, ...)
        h.calls[#h.calls + 1] = { key = key, action = action, flags = flags, extra = table.pack(...) }
        if key == "ERR" then error("bind refused " .. key, 0) end
        return "bound:" .. key, select("#", ...)
    end
    h.config = function() end
    h.on = function() end
    h.exec_cmd = function() end
    return h
end

-- Upstream's registration patterns: one flags table shared by many binds, a
-- flags function's result, plain Lua functions as actions, lists of keys.
local locked = { locked = true }
local function register()
    local d = hl.dsp
    local out = {}
    local function b(...) out[#out + 1] = table.pack(pcall(hl.bind, ...)) end
    b("SUPER + SUPER_L", d.global("caelestia:launcher"), { release = true })
    b("CTRL + ALT + C", d.global("caelestia:clearNotifs"), locked)
    b("XF86AudioPlay", d.global("caelestia:mediaToggle"), locked)
    b("SUPER + T", d.exec_cmd("foot"))
    b("SUPER + Q", d.window.close())
    b("SUPER + P", d.window.pin())
    b("SUPER + F", d.window.fullscreen({ mode = "fullscreen" }))
    b("SUPER + left", d.focus({ direction = "left" }))
    b("SUPER + SHIFT + left", d.window.move({ direction = "left" }))
    b("SUPER + mouse_down", d.focus({ workspace = "-1" }), { repeating = true })
    b("CTRL + SUPER + mouse_down", d.focus({ workspace = "+10" }))
    b("CTRL + SUPER + SHIFT + Down", d.window.move({ workspace = "e+0" }))
    b("SUPER + SHIFT + Comma", d.group.lock_active())
    b("SUPER + 1", function() return 1 end)
    b("SUPER + Z", d.window.drag(), { mouse = true })
    b("SUPER + ALT + Space", d.window.float({ action = "on", window = "address:0x1" }))
    b("SUPER + X", d.layout("togglesplit"), nil, "extra-argument")
    b("SUPER + D", d.exec_cmd("true"), { description = "Explicit — kept" })
    b("ERR", d.window.close())
    return out
end

local function run(wrapped)
    _G.hl = fake_hl()
    package.loaded["0xide-binds"] = nil
    local M = require("0xide-binds")
    if wrapped then M.install() end
    local results = register()
    if wrapped then M.restore() end
    return hl, results, M
end

local function same(a, b, depth)
    depth = depth or 0
    if type(a) ~= type(b) then return false end
    -- Closures are made afresh by each registration run.
    if type(a) == "function" then return true end
    if type(a) ~= "table" then return a == b end
    if depth > 4 then return true end
    for k, v in pairs(a) do if not same(v, b[k], depth + 1) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- Wrapped and unwrapped registration produce the same binds: same keys, same
-- actions, same flags but for the added description, same extra arguments,
-- same return values, same errors.
local plain, plain_results = run(false)
local wrapped, wrapped_results, M = run(true)
check(#plain.calls == #wrapped.calls, "wrapped registration makes as many hl.bind calls", #wrapped.calls)
local identical, described = true, 0
for i, a in ipairs(plain.calls) do
    local b = wrapped.calls[i]
    local fa, fb = a.flags, b.flags
    local stripped = nil
    if fb ~= nil then
        stripped = {}
        for k, v in pairs(fb) do stripped[k] = v end
        if not (fa and fa.description) and stripped.description then
            stripped.description = nil
            described = described + 1
            if next(stripped) == nil and fa == nil then stripped = nil end
        end
    end
    if a.key ~= b.key or not same(a.action, b.action) or not same(fa, stripped) or not same(a.extra, b.extra) then
        identical = false
        print("  differs: " .. a.key)
    end
end
check(identical, "wrapped and unwrapped registration bind the same keys, actions, flags and arguments")
check(same(plain_results, wrapped_results), "hl.bind returns and raises exactly as it does unwrapped")
check(wrapped_results[#wrapped_results][2] == "bind refused ERR", "an error from hl.bind reaches the caller unchanged",
    wrapped_results[#wrapped_results][2])
check(locked.description == nil, "a flags table shared between binds is never written to")
check(described >= 10, "upstream binds without a description get one", described)

local function desc(key)
    for _, c in ipairs(wrapped.calls) do
        if c.key == key then return c.flags and c.flags.description end
    end
end
local expect = {
    ["SUPER + SUPER_L"] = "global caelestia:launcher",
    ["CTRL + ALT + C"] = "global caelestia:clearNotifs",
    ["SUPER + T"] = "Run foot",
    ["SUPER + Q"] = "Close window",
    ["SUPER + P"] = "Toggle pinned",
    ["SUPER + F"] = "Toggle fullscreen",
    ["SUPER + left"] = "Focus window left",
    ["SUPER + SHIFT + left"] = "Move window left",
    ["SUPER + mouse_down"] = "Focus previous workspace",
    ["SUPER + Z"] = "Move window with the mouse",
    -- Not certain, so the dispatcher and its arguments as given.
    ["CTRL + SUPER + mouse_down"] = "focus workspace=+10",
    ["CTRL + SUPER + SHIFT + Down"] = "window.move workspace=e+0",
    ["SUPER + SHIFT + Comma"] = "group.lock_active",
    ["SUPER + ALT + Space"] = "window.float action=on window=address:0x1",
    ["SUPER + X"] = "layout togglesplit",
    ["SUPER + D"] = "Explicit — kept",
}
for key, want in pairs(expect) do
    check(desc(key) == want, ("%s is described as %q"):format(key, want), desc(key))
end
check(desc("SUPER + 1") == nil, "a Lua function action gets no description, not a guess")

-- Installing twice wraps once; restoring puts back the very same functions.
_G.hl = fake_hl()
local orig_bind, orig_close, orig_global = hl.bind, hl.dsp.window.close, hl.dsp.global
package.loaded["0xide-binds"] = nil
M = require("0xide-binds")
check(M.install() and M.install(), "install reports success both times")
local once = hl.bind
M.install()
check(rawequal(hl.bind, once) and not rawequal(once, orig_bind), "a second install does not wrap hl.bind again")
check(M.restore(), "restore reports that it restored")
check(rawequal(hl.bind, orig_bind) and rawequal(hl.dsp.window.close, orig_close) and rawequal(hl.dsp.global, orig_global),
    "restore puts back the original hl.bind and constructors")
check(not M.restore(), "a second restore does nothing")
check(M.install() and not rawequal(hl.bind, orig_bind), "it installs again after a restore, as on a reload")
M.restore()

-- The action hl.bind receives is the very object the caller built.
_G.hl = fake_hl()
package.loaded["0xide-binds"] = nil
M = require("0xide-binds")
M.install()
local made = hl.dsp.window.move({ workspace = "+1" })
local fn_action = function() end
hl.bind("SUPER + A", made)
hl.bind("SUPER + B", fn_action, locked)
check(rawequal(hl.calls[1].action, made) and rawequal(hl.calls[2].action, fn_action) and rawequal(hl.calls[2].flags, locked),
    "actions, and flags left undescribed, reach hl.bind as the same objects")
M.restore()

-- A failure while describing never stops the bind.
_G.hl = fake_hl()
package.loaded["0xide-binds"] = nil
M = require("0xide-binds")
M.install()
M.describe = function() error("broken describer") end
local ok, ret = pcall(hl.bind, "SUPER + Y", hl.dsp.window.close(), { locked = true })
check(ok and ret == "bound:SUPER + Y" and hl.calls[1].flags.locked == true and hl.calls[1].flags.description == nil,
    "a description that fails to build leaves the bind as it was")
M.restore()
check(type(hl.bind) == "function", "hl.bind survives a broken describer")

-- Not installed at all (no hl): nothing breaks.
_G.hl = nil
package.loaded["0xide-binds"] = nil
M = require("0xide-binds")
check(M.install() == false and M.restore() == false, "without Hyprland's hl it does nothing")

-- hypr-user.lua: its own binds, after upstream's, never shadow one.
local function user(vars, upstream_keys, broken)
    _G.hl = fake_hl()
    package.loaded["0xide-binds"] = nil
    package.loaded["hypr-user"] = nil
    package.loaded["variables"] = vars
    local B = require("0xide-binds")
    if broken then package.loaded["0xide-binds"] = "not a module" end
    B.install()
    for _, key in ipairs(upstream_keys) do hl.bind(key, hl.dsp.window.close()) end
    local printed = {}
    local real_print = print
    _G.print = function(s) printed[#printed + 1] = s end
    local ok_user, err = pcall(dofile, dir .. "/hypr-user.lua")
    _G.print = real_print
    if not ok_user then real_print("  hypr-user.lua failed: " .. tostring(err)) end
    local mine = {}
    for i = #upstream_keys + 1, #hl.calls do mine[hl.calls[i].key] = hl.calls[i].flags and hl.calls[i].flags.description end
    if broken then B.restore() end
    return mine, table.concat(printed, "\n"), ok_user
end

local base = {
    kbOcrScreenshot = "SUPER + SHIFT + T", kbRegionSearch = "SUPER + SHIFT + A",
    kbDictation = "SUPER + SHIFT + D", kbShowShortcuts = "SUPER + Slash",
    kbTerminal = "SUPER + T", kbNextWs = { "SUPER + mouse_down", "SUPER + Page_Down" },
}
local mine, printed, ran = user(base, { "SUPER + T", "SUPER + mouse_down", "SUPER + Page_Down" })
check(ran and mine["SUPER + Slash"] == "[0xIde] Show keyboard shortcuts", "the shortcuts key is bound, with its description", mine["SUPER + Slash"])
check(mine["SUPER + SHIFT + T"] == "[0xIde] Extract text from a screen region" and mine["SUPER + SHIFT + D"] ~= nil,
    "0xIde's binds carry their descriptions")
check(rawequal(hl.bind, (function() return hl.bind end)()) and not rawget(hl, "__0xide_binds"), "hypr-user.lua restores the originals")

local function with(over)
    local v = {}
    for k, x in pairs(base) do v[k] = x end
    for k, x in pairs(over) do v[k] = x end
    return v
end
mine, printed = user(with({ kbShowShortcuts = "SUPER + T" }), { "SUPER + T" })
check(mine["SUPER + T"] == nil and printed:find("kbShowShortcuts wants SUPER %+ T, already bound by"),
    "a shortcuts key upstream already uses is skipped, and says so")
mine, printed = user(with({ kbShowShortcuts = "SUPER + Page_Down" }), { "SUPER + Page_Down" })
check(mine["SUPER + Page_Down"] == nil, "a key from a list-valued kb* variable is not shadowed")
mine, printed = user(with({ kbShowShortcuts = "SUPER + Delete" }), { "Delete + SUPER" })
check(mine["SUPER + Delete"] == nil and printed:find("already bound by a Caelestia keybind"),
    "a key upstream bound outside any variable, in another order, is not shadowed")
mine = user(with({ kbShowShortcuts = "SHIFT + SUPER + T" }), {})
check(mine["SHIFT + SUPER + T"] == nil, "the same combination written in another order counts as taken")
mine = user(with({ kbOcrScreenshot = "SUPER + T" }), { "SUPER + T" })
check(mine["SUPER + T"] == nil, "a skipped 0xIde bind is not registered, so it cannot be listed")
mine, printed, ran = user(base, { "SUPER + T" }, true)
check(ran and mine["SUPER + Slash"] ~= nil, "without the module hypr-user.lua still binds, by the variables alone")
