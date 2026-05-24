-- =============================================================================
-- CombatReticle - main module
--
-- Center-screen reticle for Midnight (12.0+). Picks one of 20 bundled textures
-- or any built-in WoW icon, sizes/colors/positions it, and controls when it's
-- visible (always / combat-only / hidden in vehicles).
--
-- This file owns the reticle frame, the saved-variables schema, the event
-- loop, the slash commands, and the static popups. The minimap launcher lives
-- in Minimap.lua, the options panel in Options.lua; both reach back here via
-- the shared `ns.API` table.
-- =============================================================================

local addonName, ns = ...
ns.API = ns.API or {}

-- ---------------------------------------------------------------------------
-- Reticle library (20 presets). New entries auto-appear in the options
-- dropdown - just add to the list.
-- ---------------------------------------------------------------------------
ns.RETICLES = {
    -- Standard size designs (1-10)
    { id = 1,  name = "Crosshair",      texture = "Interface\\AddOns\\CombatReticle\\Textures\\reticle_01_crosshair.tga" },
    { id = 2,  name = "Brackets",       texture = "Interface\\AddOns\\CombatReticle\\Textures\\reticle_02_brackets.tga" },
    { id = 3,  name = "Target Rings",   texture = "Interface\\AddOns\\CombatReticle\\Textures\\reticle_03_rings.tga" },
    { id = 4,  name = "Diamond",        texture = "Interface\\AddOns\\CombatReticle\\Textures\\reticle_04_diamond.tga" },
    { id = 5,  name = "Hexagon",        texture = "Interface\\AddOns\\CombatReticle\\Textures\\reticle_05_hexagon.tga" },
    { id = 6,  name = "Double Side Arrows", texture = "Interface\\AddOns\\CombatReticle\\Textures\\reticle_06_double_side.tga" },
    { id = 7,  name = "Star",           texture = "Interface\\AddOns\\CombatReticle\\Textures\\reticle_07_star.tga" },
    { id = 8,  name = "Triangle",       texture = "Interface\\AddOns\\CombatReticle\\Textures\\reticle_08_triangle.tga" },
    { id = 9,  name = "X",              texture = "Interface\\AddOns\\CombatReticle\\Textures\\reticle_09_x.tga" },
    { id = 10, name = "Quad Double Arrows", texture = "Interface\\AddOns\\CombatReticle\\Textures\\reticle_10_quad_double.tga" },
    -- Pointing-inward / small designs (11-20). Tip points toward the
    -- center so the character stays visible through the middle.
    { id = 11, name = "Arrows In",       texture = "Interface\\AddOns\\CombatReticle\\Textures\\reticle_11_arrows_in.tga" },
    { id = 12, name = "Top Chevron",     texture = "Interface\\AddOns\\CombatReticle\\Textures\\reticle_12_chevron_top.tga" },
    { id = 13, name = "Bottom Chevron",  texture = "Interface\\AddOns\\CombatReticle\\Textures\\reticle_13_chevron_bottom.tga" },
    { id = 14, name = "Gap Crosshair",   texture = "Interface\\AddOns\\CombatReticle\\Textures\\reticle_14_gap_cross.tga" },
    { id = 15, name = "Side Arrows",     texture = "Interface\\AddOns\\CombatReticle\\Textures\\reticle_15_side_arrows.tga" },
    { id = 16, name = "Small Square",    texture = "Interface\\AddOns\\CombatReticle\\Textures\\reticle_16_small_square.tga" },
    { id = 17, name = "Filled Dot",      texture = "Interface\\AddOns\\CombatReticle\\Textures\\reticle_17_filled_dot.tga" },
    { id = 18, name = "Vertical Arrows", texture = "Interface\\AddOns\\CombatReticle\\Textures\\reticle_18_vert_arrows.tga" },
    { id = 19, name = "Ring + Dot",      texture = "Interface\\AddOns\\CombatReticle\\Textures\\reticle_19_ring_dot.tga" },
    { id = 20, name = "Corner Arrows",   texture = "Interface\\AddOns\\CombatReticle\\Textures\\reticle_20_corner_arrows.tga" },
}

local function GetReticleById(id)
    for _, r in ipairs(ns.RETICLES) do
        if r.id == id then return r end
    end
    return ns.RETICLES[1]
end
ns.API.GetReticleById = GetReticleById

-- ---------------------------------------------------------------------------
-- Defaults (and saved-variable migration)
-- ---------------------------------------------------------------------------
ns.DEFAULTS = {
    reticleId          = 1,
    -- Empty string (not nil) so settings APIs can read it without nil traps.
    customIconPath     = "",
    size               = 48,
    xOffset            = 0,
    yOffset            = 0,
    alpha              = 1.0,
    colorR             = 1,
    colorG             = 1,
    colorB             = 1,
    -- Off by default: people want to see the reticle right after install,
    -- not be told "go enter combat first to see what you bought".
    combatOnly         = false,
    hideOnVehicle      = true,
    -- LibDBIcon persists its angle and hide flag here.
    minimap            = { hide = false, minimapPos = 220 },
    -- Floating options window position; restored on each open. Defaults to
    -- top-left so the reticle (screen center) is never obscured.
    optionsWindow      = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 100, y = -100 },
}

-- Recursively fill any missing default keys without clobbering existing values.
local function MergeDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            MergeDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

-- Placeholder for future schema migrations. Each future version that
-- changes the saved-variable shape should add a guarded one-shot cleanup
-- block here. Nothing to do today since 1.0.0 is the first public schema.
local function MigrateLegacy(db)
    -- customIconPath must be a string (empty = no override) - kept here
    -- because MergeDefaults won't replace nil-but-present-in-defaults
    -- values, and downstream code expects this to be a string.
    if db.customIconPath == nil then db.customIconPath = "" end
end

-- ---------------------------------------------------------------------------
-- Active texture resolution
-- ---------------------------------------------------------------------------
local function GetActiveTexture()
    local db = CombatReticleDB
    if db.customIconPath and db.customIconPath ~= "" then
        return db.customIconPath
    end
    return GetReticleById(db.reticleId).texture
end
ns.API.GetActiveTexture = GetActiveTexture

-- ---------------------------------------------------------------------------
-- Frame
-- ---------------------------------------------------------------------------
local reticle
local inCombat  = false
local onVehicle = false

local function EnsureFrame()
    if reticle then return reticle end
    reticle = CreateFrame("Frame", "CombatReticleFrame", UIParent)
    -- MEDIUM keeps the reticle above world geometry but below any UI panel
    -- (Settings, character pane, world map, etc., all of which sit on HIGH+).
    reticle:SetFrameStrata("MEDIUM")
    reticle:SetFrameLevel(10)
    reticle:EnableMouse(false)
    reticle:SetMouseClickEnabled(false)
    local tex = reticle:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints(reticle)
    reticle.texture = tex
    reticle:Hide()
    return reticle
end

local function ApplyVisuals()
    local f = EnsureFrame()
    local db = CombatReticleDB
    -- Clamp to the same range the slider exposes. Defends against
    -- hand-edited SavedVariables files or future schema drift.
    local size = math.max(16, math.min(256, tonumber(db.size) or 48))
    f:SetSize(size, size)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", db.xOffset or 0, db.yOffset or 0)
    f.texture:SetTexture(GetActiveTexture())
    f.texture:SetAlpha(math.max(0, math.min(1, tonumber(db.alpha) or 1)))
    f.texture:SetVertexColor(db.colorR or 1, db.colorG or 1, db.colorB or 1)
end
ns.API.ApplyVisuals = ApplyVisuals

-- Preview window: any settings change extends this so the user sees the
-- reticle even when combat-only/vehicle rules would normally hide it.
local previewUntil = 0

local function PreviewActive()
    return GetTime() < previewUntil
end

local function PreviewReticle(duration)
    duration = duration or 4
    previewUntil = GetTime() + duration
    ns.API.Refresh()
    C_Timer.After(duration + 0.05, function() ns.API.Refresh() end)
end
ns.API.PreviewReticle = PreviewReticle

-- Options window open/closed state, set by Options.lua. While the options
-- window is up, combat-only and vehicle rules are bypassed so the user can
-- actually see what they're configuring.
local optionsOpen = false
ns.API.SetOptionsOpen = function(isOpen)
    optionsOpen = isOpen and true or false
    if ns.API.Refresh then ns.API.Refresh() end
end

local function ShouldShow()
    local db = CombatReticleDB
    if PreviewActive() then return true end
    if optionsOpen then return true end
    if onVehicle and db.hideOnVehicle then return false end
    if db.combatOnly and not inCombat then return false end
    return true
end

local function Refresh()
    ApplyVisuals()
    local f = EnsureFrame()
    -- Re-assert frame invariants that camera transitions / scale changes /
    -- cinematics have been observed to perturb.
    f:SetParent(UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(10)
    if ShouldShow() then f:Show() else f:Hide() end
end
ns.API.Refresh = Refresh

-- Safety ticker. Every second, re-poll the combat / vehicle state in case
-- we missed a UNIT_ENTERED_VEHICLE, UNIT_EXITED_VEHICLE, PLAYER_REGEN_*,
-- or similar event during a loading screen or camera transition. If the
-- reticle's actual shown state disagrees with what ShouldShow() says it
-- should be, force-correct it. Cheap (~1Hz, no allocations) and exactly
-- what catches the "camera snaps and the icon vanishes" symptom.
local function SafetyTick()
    if not reticle then return end
    local newInCombat  = InCombatLockdown() or false
    local newOnVehicle = UnitInVehicle("player") or false
    if newInCombat ~= inCombat or newOnVehicle ~= onVehicle then
        inCombat, onVehicle = newInCombat, newOnVehicle
        Refresh()
        return
    end
    -- State agrees but the frame's shown flag drifted (e.g. some other addon
    -- or a Blizzard transition silently hid it).
    local should = ShouldShow()
    if should and not reticle:IsShown() then
        ApplyVisuals()
        reticle:SetParent(UIParent)
        reticle:SetFrameStrata("MEDIUM")
        reticle:Show()
    elseif (not should) and reticle:IsShown() then
        reticle:Hide()
    end
end
C_Timer.NewTicker(1, SafetyTick)

-- ---------------------------------------------------------------------------
-- Custom icon support
-- ---------------------------------------------------------------------------
local function SetCustomIcon(input)
    input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if input == "" then
        CombatReticleDB.customIconPath = ""
    elseif input:lower():match("^interface\\") then
        CombatReticleDB.customIconPath = input
    else
        CombatReticleDB.customIconPath = "Interface\\Icons\\" .. input
    end
    Refresh()
    if ns.API.RefreshOptions then ns.API.RefreshOptions() end
end
ns.API.SetCustomIcon = SetCustomIcon

local function ClearCustomIcon()
    CombatReticleDB.customIconPath = ""
    Refresh()
    if ns.API.RefreshOptions then ns.API.RefreshOptions() end
end
ns.API.ClearCustomIcon = ClearCustomIcon

local function HasCustomIcon()
    local p = CombatReticleDB.customIconPath
    return p ~= nil and p ~= ""
end
ns.API.HasCustomIcon = HasCustomIcon

-- Midnight refactored static popups onto a new GameDialog backend, so the
-- legacy `self.editBox` field is no longer reliably present on the OnShow
-- callback's `self`. Walk through every reasonable accessor and fall back
-- to scanning children for an EditBox object.
local function GetPopupEditBox(self)
    if not self then return nil end
    if self.editBox then return self.editBox end           -- legacy field
    if self.EditBox then return self.EditBox end           -- some templates use PascalCase
    if type(self.GetEditBox) == "function" then            -- modern GameDialog method
        local ok, eb = pcall(self.GetEditBox, self)
        if ok and eb then return eb end
    end
    if self.GetChildren then                                -- last resort: walk children
        for _, child in ipairs({ self:GetChildren() }) do
            if child.IsObjectType and child:IsObjectType("EditBox") then
                return child
            end
        end
    end
    return nil
end

StaticPopupDialogs["COMBATRETICLE_CUSTOM_ICON"] = {
    text = "Built-in icon name (e.g. |cffffff00Ability_Mount_RidingHorse|r)\n|cffaaaaaaLeave blank and confirm to revert to preset.|r",
    button1 = "Set",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 192,
    OnShow = function(self)
        local eb = GetPopupEditBox(self)
        if not eb then return end
        local current = CombatReticleDB.customIconPath or ""
        current = current:gsub("^Interface\\Icons\\", "")
        eb:SetText(current)
        eb:HighlightText()
        eb:SetFocus()
    end,
    OnAccept = function(self)
        local eb = GetPopupEditBox(self)
        if eb then SetCustomIcon(eb:GetText()) end
    end,
    EditBoxOnEnterPressed = function(self)
        -- self here is the EditBox itself (not the popup); GetParent() climbs
        -- to the popup frame so we can hide it.
        SetCustomIcon(self:GetText())
        local parent = self:GetParent()
        if parent and parent.Hide then parent:Hide() end
    end,
    EditBoxOnEscapePressed = function(self)
        local parent = self:GetParent()
        if parent and parent.Hide then parent:Hide() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

ns.API.ShowCustomIconPopup = function() StaticPopup_Show("COMBATRETICLE_CUSTOM_ICON") end

-- ---------------------------------------------------------------------------
-- Color picker (Blizzard's standard ColorPickerFrame)
-- ---------------------------------------------------------------------------
local function ShowColorPicker()
    local prevR, prevG, prevB = CombatReticleDB.colorR or 1, CombatReticleDB.colorG or 1, CombatReticleDB.colorB or 1
    local prevA = CombatReticleDB.alpha or 1

    local function ReadColor()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        local a = 1
        if ColorPickerFrame.GetColorAlpha then
            a = ColorPickerFrame:GetColorAlpha() or 1
        end
        return r, g, b, a
    end
    local function OnSwatch()
        local r, g, b = ReadColor()
        CombatReticleDB.colorR, CombatReticleDB.colorG, CombatReticleDB.colorB = r, g, b
        PreviewReticle(4)
        if ns.API.RefreshOptions then ns.API.RefreshOptions() end
    end
    local function OnOpacity()
        local _, _, _, a = ReadColor()
        CombatReticleDB.alpha = a
        PreviewReticle(4)
        if ns.API.RefreshOptions then ns.API.RefreshOptions() end
    end
    local function OnCancel()
        CombatReticleDB.colorR, CombatReticleDB.colorG, CombatReticleDB.colorB = prevR, prevG, prevB
        CombatReticleDB.alpha = prevA
        PreviewReticle(2)
        if ns.API.RefreshOptions then ns.API.RefreshOptions() end
    end

    local info = {
        swatchFunc = OnSwatch, opacityFunc = OnOpacity, cancelFunc = OnCancel,
        hasOpacity = true, opacity = prevA,
        r = prevR, g = prevG, b = prevB,
    }

    if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow(info)
    elseif OpenColorPicker then
        OpenColorPicker(info)
    else
        print("|cffff5555CombatReticle:|r color picker API not available on this client.")
    end
end
ns.API.ShowColorPicker = ShowColorPicker

-- ---------------------------------------------------------------------------
-- Reset to defaults
-- ---------------------------------------------------------------------------
local function ResetAllSettings()
    -- Preserve the minimap subtable's reference so LibDBIcon (which
    -- captured it on PLAYER_LOGIN) keeps writing position updates into the
    -- same Lua object. Wiping CombatReticleDB and letting MergeDefaults
    -- create a fresh minimap = {...} would orphan LibDBIcon's reference
    -- and silently break minimap-position persistence until /reload.
    local mm = CombatReticleDB.minimap
    wipe(CombatReticleDB)
    if mm then
        wipe(mm)
        mm.hide       = false
        mm.minimapPos = 220
        CombatReticleDB.minimap = mm
    end
    MergeDefaults(CombatReticleDB, ns.DEFAULTS)
    Refresh()
    if ns.API.RefreshOptions then ns.API.RefreshOptions() end
    print("|cff7ec8ffCombatReticle|r: settings reset to defaults.")
end
ns.API.ResetAllSettings = ResetAllSettings

StaticPopupDialogs["COMBATRETICLE_RESET_CONFIRM"] = {
    text = "Reset every CombatReticle setting to defaults?\n|cffaaaaaaThis cannot be undone.|r",
    button1 = "Reset", button2 = "Cancel",
    OnAccept = ResetAllSettings,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

ns.API.ShowResetConfirm = function() StaticPopup_Show("COMBATRETICLE_RESET_CONFIRM") end

-- ---------------------------------------------------------------------------
-- Convenience helpers used by slash commands and the minimap launcher
-- ---------------------------------------------------------------------------
ns.API.GetDB = function() return CombatReticleDB end

ns.API.ToggleCombatOnly = function()
    CombatReticleDB.combatOnly = not CombatReticleDB.combatOnly
    Refresh()
    if ns.API.RefreshOptions then ns.API.RefreshOptions() end
    return CombatReticleDB.combatOnly
end

ns.API.OpenOptions = function()
    -- Real implementation is installed by Options.lua after the canvas is
    -- registered. This stub is just here so something callable exists.
    print("|cffff5555CombatReticle:|r options panel not yet initialized.")
end

local function Msg(s) print("|cff7ec8ffCombatReticle|r: " .. s) end
ns.Print = Msg

-- ---------------------------------------------------------------------------
-- Event loop
-- ---------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("UNIT_ENTERED_VEHICLE")
f:RegisterEvent("UNIT_EXITED_VEHICLE")
-- These don't always fire but when they do, we want to re-apply visuals
-- because they can leave the reticle stranded mid-transition.
f:RegisterEvent("UI_SCALE_CHANGED")
f:RegisterEvent("DISPLAY_SIZE_CHANGED")
f:RegisterEvent("LOADING_SCREEN_DISABLED")
f:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")

f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            CombatReticleDB = CombatReticleDB or {}
            MigrateLegacy(CombatReticleDB)
            MergeDefaults(CombatReticleDB, ns.DEFAULTS)
            ApplyVisuals()
        end

    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        inCombat  = InCombatLockdown() or false
        onVehicle = UnitInVehicle("player") or false
        Refresh()

    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true; Refresh()
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false; Refresh()
    elseif event == "UNIT_ENTERED_VEHICLE" then
        if arg1 == "player" then onVehicle = true; Refresh() end
    elseif event == "UNIT_EXITED_VEHICLE" then
        if arg1 == "player" then onVehicle = false; Refresh() end

    elseif event == "UI_SCALE_CHANGED"
        or event == "DISPLAY_SIZE_CHANGED"
        or event == "LOADING_SCREEN_DISABLED"
        or event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        -- Re-poll volatile state along with the refresh, in case the event
        -- fired while we were in a transition that also moved us in/out of
        -- combat or a vehicle (loading screens are notorious for this).
        inCombat  = InCombatLockdown() or false
        onVehicle = UnitInVehicle("player") or false
        Refresh()
    end
end)

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------
SLASH_COMBATRETICLE1 = "/combatreticle"
SLASH_COMBATRETICLE2 = "/cr"
SlashCmdList.COMBATRETICLE = function(input)
    input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = input:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "options" or cmd == "config" then
        ns.API.OpenOptions(); return
    end

    if cmd == "help" then
        Msg("commands:")
        print("  |cffffff00/cr|r                open options")
        print("  |cffffff00/cr reticle <1-20>|r choose a preset")
        print("  |cffffff00/cr icon <name>|r    use a built-in WoW icon (Interface\\Icons\\<name>)")
        print("  |cffffff00/cr icon clear|r     revert to preset")
        print("  |cffffff00/cr size <n>|r       size in pixels (16-256)")
        print("  |cffffff00/cr combat on|off|r  show only in combat")
        print("  |cffffff00/cr minimap on|off|r show minimap icon")
        print("  |cffffff00/cr list|r           list all reticle presets")
        print("  |cffffff00/cr color|r          open color picker")
        print("  |cffffff00/cr reset|r          restore defaults")
        return
    end

    if cmd == "list" then
        Msg("available reticles:")
        for _, r in ipairs(ns.RETICLES) do
            print(string.format("  %2d. %s", r.id, r.name))
        end
        return

    elseif cmd == "reticle" then
        local n = tonumber(rest)
        if not n or not GetReticleById(n) then
            Msg("usage: /cr reticle <1-" .. #ns.RETICLES .. ">"); return
        end
        CombatReticleDB.reticleId = n
        CombatReticleDB.customIconPath = ""

    elseif cmd == "icon" or cmd == "customicon" then
        if rest == "" then
            ns.API.ShowCustomIconPopup(); return
        elseif rest:lower() == "clear" or rest:lower() == "none" or rest:lower() == "off" then
            ClearCustomIcon(); Msg("custom icon cleared."); return
        else
            SetCustomIcon(rest); Msg("custom icon set to " .. rest); return
        end

    elseif cmd == "size" then
        local n = tonumber(rest)
        if not n then Msg("usage: /cr size <n>"); return end
        CombatReticleDB.size = math.max(16, math.min(256, n))

    elseif cmd == "combat" then
        CombatReticleDB.combatOnly = (rest == "on" or rest == "1" or rest == "true")

    elseif cmd == "minimap" then
        if ns.API.SetMinimapButtonShown then
            ns.API.SetMinimapButtonShown(rest == "on" or rest == "1" or rest == "true" or rest == "")
        end
        return

    elseif cmd == "color" then
        ShowColorPicker(); return

    elseif cmd == "reset" then
        ns.API.ShowResetConfirm(); return

    else
        Msg("unknown command. Type /cr help.")
        return
    end

    Refresh()
    if ns.API.RefreshOptions then ns.API.RefreshOptions() end
end
