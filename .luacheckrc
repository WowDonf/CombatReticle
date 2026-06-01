-- Luacheck configuration for Combat Reticle.
-- Run from repo root: luacheck *.lua

std = "lua51"

-- WoW addon UI strings often need to fit a single readable line.
max_line_length = 200

-- Globals the addon defines, owns, or writes to.
globals = {
    -- Saved variables (managed by WoW from the TOC's SavedVariables field)
    "CombatReticleDB",
    -- Slash command registration
    "SLASH_COMBATRETICLE1",
    "SLASH_COMBATRETICLE2",
    -- Addon compartment hooks (must be globals; referenced from the TOC's
    -- AddonCompartmentFunc* fields)
    "CombatReticle_OnAddonCompartmentClick",
    "CombatReticle_OnAddonCompartmentEnter",
    "CombatReticle_OnAddonCompartmentLeave",
    -- Blizzard tables we mutate
    "SlashCmdList",         -- /cr handler registration
    "StaticPopupDialogs",   -- reload / reset popups
    -- Read/written for named frame child regions
    "_G",
}

-- Blizzard / WoW API globals the addon only reads from.
read_globals = {
    -- Frame + UI infrastructure
    "CreateFrame", "UIParent",
    "Minimap",
    "Settings", "SettingsPanel", "HideUIPanel",
    "GameTooltip",
    "ColorPickerFrame",
    "StaticPopup_Show",
    "UISpecialFrames",
    "SquareButton_SetIcon",   -- icon helper for UIPanelSquareButton
    -- Combat / protected-frame state
    "InCombatLockdown",
    -- Vehicle / mount state (combat-only visibility rules)
    "UnitInVehicle", "IsMounted",
    -- Timing
    "C_Timer",
    -- Tables / misc
    "wipe", "tinsert", "hooksecurefunc", "ReloadUI", "GetTime",
    -- Bundled libraries (LibStub and the LDB/LibDBIcon stack under Libs/)
    "LibStub",
    -- Optional globals probed before use (modern color picker; sometimes
    -- referenced bare after an `if OpenColorPicker then` guard)
    "OpenColorPicker",
}
