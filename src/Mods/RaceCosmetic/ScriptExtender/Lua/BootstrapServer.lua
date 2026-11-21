---@diagnostic disable: undefined-global

-- Marker: proves that Script Extender actually loaded this mod's Lua.
pcall(function()
    Ext.IO.SaveFile("RaceCosmetic_bootstrap.txt", "bootstrap loaded at " .. tostring(os.time()))
end)

Ext.Require("RaceCosmetic/Core.lua")