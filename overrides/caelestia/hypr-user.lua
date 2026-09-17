-- Caelestia's supported Hyprland user config point. Upstream requires this file
-- for its side effects only and discards whatever it returns, so everything here
-- has to call hl directly rather than return a table. Variable overrides belong
-- in hypr-vars.lua, which upstream does merge.
--
-- This runs after every hypr/hyprland/*.lua module, so hl.config calls here win.
local vars = require("variables")

hl.config({
    cursor = {
        no_hardware_cursors = false,
        enable_hyprcursor = true,
    },
})

-- Screen region -> OCR. The shell listens for this global.
-- create_bind in hypr/hyprland/keybinds.lua is a private helper; hl.bind is
-- what it calls, so binding directly here needs no change to that file.
if type(vars.kbOcrScreenshot) == "string" and vars.kbOcrScreenshot:match("%S") then
    hl.bind(vars.kbOcrScreenshot, hl.dsp.global("caelestia:screenshotOcr"))
end
