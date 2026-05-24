-- =============================================================================
-- CombatReticle - Minimap.lua
--
-- Registers a LibDataBroker launcher and a LibDBIcon minimap button, plus the
-- AddonCompartment entries (the icon in the minimap addon list).
--
-- LibDBIcon handles all of the orbiting/dragging/persisting; we only supply
-- icon, OnClick, OnTooltipShow.
-- =============================================================================

local _, ns = ...
local LAUNCHER_NAME = "CombatReticle"

-- ---------------------------------------------------------------------------
-- LibDataBroker launcher
-- ---------------------------------------------------------------------------
local LDB     = LibStub and LibStub("LibDataBroker-1.1", true)
local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)

if not LDB or not LDBIcon then
    -- Libs missing - addon still works, you just don't get a minimap button.
    return
end

-- Shared tooltip builder used by both the LDB tooltip and the addon
-- compartment hover. Keeps both tooltips identical.
local function FillTooltip(tt)
    tt:AddLine("|cff7ec8ffCombatReticle|r")
    local db = ns.API.GetDB and ns.API.GetDB()
    if db then
        tt:AddLine(db.combatOnly
            and "|cff40ff40Combat-only|r"
            or  "|cffaaaaaaAlways on|r")
        if db.customIconPath and db.customIconPath ~= "" then
            local short = db.customIconPath:gsub("^Interface\\Icons\\", "")
            tt:AddLine("Custom icon: |cffffffff" .. short .. "|r", 0.7, 0.9, 1)
        elseif ns.API.GetReticleById then
            local r = ns.API.GetReticleById(db.reticleId)
            if r then
                tt:AddLine("Reticle: |cffffffff" .. r.name .. "|r", 0.7, 0.9, 1)
            end
        end
    end
    tt:AddLine(" ")
    tt:AddLine("|cffffff00Left-click|r: open options",            0.7, 0.7, 0.7)
    tt:AddLine("|cffffff00Right-click|r: toggle combat-only",     0.7, 0.7, 0.7)
    tt:AddLine("|cffffff00Drag|r: move around the minimap",       0.7, 0.7, 0.7)
end

local launcher = LDB:NewDataObject(LAUNCHER_NAME, {
    type = "launcher",
    text = "CombatReticle",
    icon = "Interface\\AddOns\\CombatReticle\\Icon.png",
    OnClick = function(_, button)
        if button == "RightButton" then
            local on = ns.API.ToggleCombatOnly and ns.API.ToggleCombatOnly()
            if ns.Print then
                ns.Print(on and "Combat-only |cff40ff40ON|r"
                            or "Combat-only |cffff8844OFF|r")
            end
        else
            if ns.API.OpenOptions then ns.API.OpenOptions() end
        end
    end,
    OnTooltipShow = FillTooltip,
})

-- ---------------------------------------------------------------------------
-- Register with LibDBIcon on PLAYER_LOGIN.
--
-- LibDBIcon stores minimapPos and hide inside the db table we hand it - we
-- keep that table at OutOfRange-style `CombatReticleDB.minimap` so the angle
-- and hide flag survive reloads.
-- ---------------------------------------------------------------------------
local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function()
    CombatReticleDB = CombatReticleDB or {}
    CombatReticleDB.minimap = CombatReticleDB.minimap or { hide = false, minimapPos = 220 }
    LDBIcon:Register(LAUNCHER_NAME, launcher, CombatReticleDB.minimap)

    -- If user previously hid the button via slash command, honor it.
    if CombatReticleDB.minimap.hide then
        LDBIcon:Hide(LAUNCHER_NAME)
    end
end)

-- ---------------------------------------------------------------------------
-- Public API: show/hide the minimap button + retexture it when the user
-- picks a different reticle.
-- ---------------------------------------------------------------------------
ns.API.SetMinimapButtonShown = function(shown)
    if not CombatReticleDB or not CombatReticleDB.minimap then return end
    CombatReticleDB.minimap.hide = not shown
    if shown then LDBIcon:Show(LAUNCHER_NAME) else LDBIcon:Hide(LAUNCHER_NAME) end
end

ns.API.IsMinimapButtonShown = function()
    return CombatReticleDB and CombatReticleDB.minimap
        and not CombatReticleDB.minimap.hide
end

-- ---------------------------------------------------------------------------
-- AddonCompartment glue (the icon in the modern minimap addon list).
-- These must be globals so the TOC can reference them by name.
-- ---------------------------------------------------------------------------
function _G.CombatReticle_OnAddonCompartmentClick(_, button)
    if button == "RightButton" then
        local on = ns.API.ToggleCombatOnly and ns.API.ToggleCombatOnly()
        if ns.Print then
            ns.Print(on and "Combat-only |cff40ff40ON|r"
                        or "Combat-only |cffff8844OFF|r")
        end
    else
        if ns.API.OpenOptions then ns.API.OpenOptions() end
    end
end

function _G.CombatReticle_OnAddonCompartmentEnter(_, frame)
    if not frame then return end
    GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
    FillTooltip(GameTooltip)
    GameTooltip:Show()
end

function _G.CombatReticle_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
