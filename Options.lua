-- =============================================================================
-- CombatReticle - options panel
--
-- A floating, movable, ESC-closable window (rather than a Blizzard Settings
-- canvas) so it doesn't sit on top of the reticle while you're configuring
-- it. Same helper-widget pattern as OutOfRange: AddHeader, AddSlider,
-- AddCheckbox, AddButton, AddGap, AddDescription, etc., laid out vertically
-- off a running `y` cursor.
--
-- The Blizzard Settings window still has a CombatReticle entry, but it's a
-- thin stub - a single "Open CombatReticle options" button - because the
-- real controls live in the floating window.
-- =============================================================================

local _, ns = ...

-- Forward declarations
local RefreshAll, reticleGrid, currentLabel, ShowOptionsWindow, optionsFrame

-- ---------------------------------------------------------------------------
-- The movable window itself
-- ---------------------------------------------------------------------------
local FRAME_W, FRAME_H = 500, 620

optionsFrame = CreateFrame("Frame", "CombatReticleOptionsFrame", UIParent,
    "BasicFrameTemplateWithInset")
optionsFrame:SetSize(FRAME_W, FRAME_H)
optionsFrame:SetFrameStrata("DIALOG")
optionsFrame:SetToplevel(true)
optionsFrame:SetClampedToScreen(true)
optionsFrame:SetMovable(true)
optionsFrame:EnableMouse(true)
optionsFrame:RegisterForDrag("LeftButton")
optionsFrame:SetScript("OnDragStart", optionsFrame.StartMoving)
optionsFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    CombatReticleDB.optionsWindow = {
        point = point, relPoint = relPoint, x = x, y = y,
    }
end)
optionsFrame:Hide()

-- Title bar text
if optionsFrame.TitleText then
    optionsFrame.TitleText:SetText("CombatReticle")
elseif _G["CombatReticleOptionsFrameTitleText"] then
    _G["CombatReticleOptionsFrameTitleText"]:SetText("CombatReticle")
end

-- ESC closes the window (UISpecialFrames is honored by the keyboard handler)
tinsert(UISpecialFrames, "CombatReticleOptionsFrame")

-- ---------------------------------------------------------------------------
-- Scroll container that holds all of the widgets
-- ---------------------------------------------------------------------------
local scroll = CreateFrame("ScrollFrame", "CombatReticleOptionsScroll",
    optionsFrame, "UIPanelScrollFrameTemplate")
-- Leave room for title bar (top) and the inset border (sides/bottom)
scroll:SetPoint("TOPLEFT", 10, -30)
scroll:SetPoint("BOTTOMRIGHT", -30, 10)

local content = CreateFrame("Frame", nil, scroll)
content:SetSize(440, 100)
scroll:SetScrollChild(content)
scroll:SetScript("OnSizeChanged", function(_, w)
    if w and w > 0 then content:SetWidth(w) end
end)

-- ---------------------------------------------------------------------------
-- Layout helpers
-- ---------------------------------------------------------------------------
local LEFT    = 14
local y       = -10
local widgets = {}

local function HideTooltip() GameTooltip:Hide() end

local function AddHeader(text)
    y = y - 6
    local fs = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", LEFT, y)
    fs:SetText(text)
    fs:SetTextColor(1, 0.82, 0)
    y = y - 20
    local line = content:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.12)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", LEFT, y)
    line:SetPoint("TOPRIGHT", -10, y)
    y = y - 10
end

local function AddDescription(text)
    local fs = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    fs:SetPoint("TOPLEFT", LEFT, y)
    fs:SetWidth(420)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    y = y - (fs:GetStringHeight() + 8)
end

local function AddCheckbox(label, tooltip, getter, setter)
    local cb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", LEFT, y)
    cb:SetSize(26, 26)
    local fs = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    fs:SetText(label)
    cb:SetScript("OnClick", function(self)
        setter(self:GetChecked() and true or false)
    end)
    if tooltip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", HideTooltip)
    end
    cb.Refresh = function() cb:SetChecked(getter() and true or false) end
    widgets[#widgets + 1] = cb
    y = y - 28
    return cb
end

local function AddSlider(label, minV, maxV, step, getter, setter, fmt)
    fmt = fmt or "%.2f"
    y = y - 2
    local title = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    title:SetPoint("TOPLEFT", LEFT, y)
    title:SetText(label)
    local valFS = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    y = y - 16

    -- Left stepper button (decrement by step)
    local leftBtn = CreateFrame("Button", nil, content, "UIPanelSquareButton")
    leftBtn:SetSize(20, 20)
    leftBtn:SetPoint("TOPLEFT", LEFT + 4, y - 1)
    if SquareButton_SetIcon then SquareButton_SetIcon(leftBtn, "LEFT") end

    -- Slider track
    local s = CreateFrame("Slider", nil, content)
    s:SetPoint("LEFT", leftBtn, "RIGHT", 4, 0)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(260, 18)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local thumb = s:GetThumbTexture()
    if thumb then thumb:SetSize(20, 20) end
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(0, 0, 0, 0.45)
    track:SetHeight(6)
    track:SetPoint("LEFT", 4, 0)
    track:SetPoint("RIGHT", -4, 0)

    -- Right stepper button (increment by step)
    local rightBtn = CreateFrame("Button", nil, content, "UIPanelSquareButton")
    rightBtn:SetSize(20, 20)
    rightBtn:SetPoint("LEFT", s, "RIGHT", 4, 0)
    if SquareButton_SetIcon then SquareButton_SetIcon(rightBtn, "RIGHT") end

    valFS:SetPoint("LEFT", rightBtn, "RIGHT", 8, 0)

    s:SetScript("OnValueChanged", function(_, v)
        valFS:SetText(fmt:format(v))
        setter(v)
    end)

    -- Step on click, with hold-to-repeat after a brief delay so a held mouse
    -- button keeps nudging instead of just firing once.
    local function MakeStepper(btn, delta)
        local ticker
        local fire = function()
            local cur = s:GetValue()
            local nxt = cur + delta
            if nxt < minV then nxt = minV end
            if nxt > maxV then nxt = maxV end
            if nxt ~= cur then s:SetValue(nxt) end
        end
        btn:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
        btn:SetScript("OnMouseDown", function()
            fire()
            -- Short pause, then start repeating
            local startAt = GetTime() + 0.35
            ticker = C_Timer.NewTicker(0.06, function()
                if GetTime() >= startAt then fire() end
            end)
        end)
        local stop = function()
            if ticker then ticker:Cancel(); ticker = nil end
        end
        btn:SetScript("OnMouseUp",   stop)
        btn:SetScript("OnLeave",     stop)
        btn:SetScript("OnHide",      stop)
    end
    MakeStepper(leftBtn,  -step)
    MakeStepper(rightBtn,  step)

    s.Refresh = function()
        local v = getter() or minV
        s:SetValue(v)
        valFS:SetText(fmt:format(v))
    end
    widgets[#widgets + 1] = s
    y = y - 28
    return s
end

local function AddButton(label, onClick, width, tooltip)
    local b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT", LEFT + 6, y)
    b:SetSize(width or 160, 24)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    if tooltip then
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", HideTooltip)
    end
    y = y - 30
    return b
end

local function AddButtonAfter(prev, label, onClick, width, tooltip)
    local b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    b:SetPoint("LEFT", prev, "RIGHT", 8, 0)
    b:SetSize(width or 130, 24)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    if tooltip then
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", HideTooltip)
    end
    return b
end

local function AddGap(px) y = y - (px or 8) end

-- ---------------------------------------------------------------------------
-- DB shorthand
-- ---------------------------------------------------------------------------
local function db() return CombatReticleDB or {} end

local function MarkChanged()
    if ns.API.Refresh then ns.API.Refresh() end
    if ns.API.PreviewReticle then ns.API.PreviewReticle(4) end
end

-- ---------------------------------------------------------------------------
-- Reticle icon grid - 30 buttons in a 6x5 layout. Tooltip on hover, yellow
-- border highlight on the currently selected one.
-- ---------------------------------------------------------------------------
local function AddIconGrid()
    local COLS    = 6
    local ICON    = 48
    local PAD     = 4
    local rows    = math.ceil(#ns.RETICLES / COLS)
    local totalW  = COLS * ICON + (COLS - 1) * PAD
    local totalH  = rows * ICON + (rows - 1) * PAD

    y = y - 4
    local grid = CreateFrame("Frame", nil, content)
    grid:SetPoint("TOPLEFT", LEFT + 6, y)
    grid:SetSize(totalW, totalH)

    local buttons = {}
    for i, r in ipairs(ns.RETICLES) do
        local row = math.floor((i - 1) / COLS)
        local col = (i - 1) % COLS
        local btn = CreateFrame("Button", nil, grid, "BackdropTemplate")
        btn:SetSize(ICON, ICON)
        btn:SetPoint("TOPLEFT", col * (ICON + PAD), -row * (ICON + PAD))
        btn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        -- Inactive look
        btn:SetBackdropColor(0.08, 0.10, 0.12, 0.95)
        btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 4, -4)
        icon:SetPoint("BOTTOMRIGHT", -4, 4)
        icon:SetTexture(r.texture)
        btn.icon = icon

        -- Built-in hover overlay
        btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

        local id, name = r.id, r.name
        btn:SetScript("OnClick", function()
            CombatReticleDB.reticleId      = id
            CombatReticleDB.customIconPath = ""
            MarkChanged()
            if ns.API.RefreshOptions then ns.API.RefreshOptions() end
        end)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(name, 1, 1, 1)
            GameTooltip:AddLine("Preset #" .. id, 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", HideTooltip)

        buttons[id] = btn
    end

    grid.buttons = buttons
    grid.Refresh = function()
        local cur       = (CombatReticleDB or {}).reticleId
        local custom    = (CombatReticleDB or {}).customIconPath
        local hasCustom = custom and custom ~= ""
        for id, btn in pairs(buttons) do
            if id == cur and not hasCustom then
                btn:SetBackdropBorderColor(1, 0.82, 0, 1)   -- gold
                btn:SetBackdropColor(0.18, 0.14, 0.04, 0.95)
            else
                btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                btn:SetBackdropColor(0.08, 0.10, 0.12, 0.95)
            end
        end
    end
    widgets[#widgets + 1] = grid

    y = y - (totalH + 6)
    return grid
end

-- ===========================================================================
-- Reticle section
-- ===========================================================================
AddHeader("Reticle")

AddDescription("Click a reticle below to select it. The highlighted icon is "
    .. "the current selection. Or use a built-in WoW icon with the button "
    .. "below the grid.")

reticleGrid = AddIconGrid()

-- "Current: <name>" status line under the grid - updated on every Refresh.
do
    local fs = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", LEFT, y)
    fs:SetText("Current: ...")
    currentLabel = fs
    currentLabel.Refresh = function()
        local d = CombatReticleDB or {}
        if d.customIconPath and d.customIconPath ~= "" then
            local short = d.customIconPath:gsub("^Interface\\Icons\\", "")
            fs:SetText("Current: |cffd0e8ffcustom icon|r (" .. short .. ")")
        else
            local r = ns.API.GetReticleById and ns.API.GetReticleById(d.reticleId)
            fs:SetText("Current: |cffffe070" .. (r and r.name or "?") .. "|r")
        end
    end
    widgets[#widgets + 1] = currentLabel
    y = y - 24
end

local customIconBtn = AddButton("Use a built-in WoW icon...",
    function() if ns.API.ShowCustomIconPopup then ns.API.ShowCustomIconPopup() end end,
    200,
    "Override the selected preset with any Interface\\Icons texture. Type "
    .. "the name (e.g. Ability_Mount_RidingHorse) when prompted.")
AddButtonAfter(customIconBtn, "Clear custom icon",
    function()
        if ns.API.ClearCustomIcon then ns.API.ClearCustomIcon() end
        MarkChanged()
    end, 140,
    "Revert back to whichever reticle is highlighted in the grid above.")

-- ===========================================================================
-- Appearance section
-- ===========================================================================
AddHeader("Appearance")

AddSlider("Size", 16, 256, 1,
    function() return db().size end,
    function(v) CombatReticleDB.size = v; MarkChanged() end,
    "%d px")

AddSlider("Opacity", 0, 1, 0.01,
    function() return db().alpha end,
    function(v) CombatReticleDB.alpha = v; MarkChanged() end,
    "%.2f")

local colorBtn = AddButton("Pick color...",
    function() if ns.API.ShowColorPicker then ns.API.ShowColorPicker() end end,
    160,
    "Opens the Blizzard color picker (wheel + RGB + hex). Tints the reticle "
    .. "without changing its texture.")

local colorSwatch = content:CreateTexture(nil, "OVERLAY")
colorSwatch:SetSize(24, 24)
colorSwatch:SetPoint("LEFT", colorBtn, "RIGHT", 12, 0)
colorSwatch:SetColorTexture(1, 1, 1, 1)
colorSwatch.Refresh = function()
    colorSwatch:SetColorTexture(db().colorR or 1, db().colorG or 1, db().colorB or 1, 1)
end
widgets[#widgets + 1] = colorSwatch

local resetColorBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
resetColorBtn:SetPoint("LEFT", colorSwatch, "RIGHT", 12, 0)
resetColorBtn:SetSize(130, 24)
resetColorBtn:SetText("Reset to white")
resetColorBtn:SetScript("OnClick", function()
    if ns.API.ResetColor then ns.API.ResetColor() end
    if ns.API.PreviewReticle then ns.API.PreviewReticle(4) end
end)
resetColorBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Reset to white", 1, 1, 1)
    GameTooltip:AddLine("Sets tint back to pure white (RGB 255,255,255) and opacity to 1.0.",
        0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
resetColorBtn:SetScript("OnLeave", HideTooltip)

-- ===========================================================================
-- Position section
-- ===========================================================================
AddHeader("Position")

AddSlider("X offset (from screen center)", -500, 500, 1,
    function() return db().xOffset end,
    function(v) CombatReticleDB.xOffset = v; MarkChanged() end,
    "%d px")

AddSlider("Y offset (positive = up)", -500, 500, 1,
    function() return db().yOffset end,
    function(v) CombatReticleDB.yOffset = v; MarkChanged() end,
    "%d px")

AddButton("Reset position",
    function()
        CombatReticleDB.xOffset = 0
        CombatReticleDB.yOffset = 0
        MarkChanged(); RefreshAll()
    end, 160,
    "Snap the reticle back to the exact center of the screen.")

-- ===========================================================================
-- Behavior section
-- ===========================================================================
AddHeader("Behavior")

AddCheckbox("Show only in combat",
    "If checked, the reticle is hidden when you are out of combat.",
    function() return db().combatOnly end,
    function(v) CombatReticleDB.combatOnly = v; MarkChanged() end)

AddCheckbox("Hide on vehicle / taxi",
    "Hide the reticle while riding a taxi, on a vehicle, or in a quest puppet.",
    function() return db().hideOnVehicle end,
    function(v) CombatReticleDB.hideOnVehicle = v; MarkChanged() end)

-- ===========================================================================
-- Minimap section
-- ===========================================================================
AddHeader("Minimap")

AddCheckbox("Show minimap button",
    "Draggable button on the minimap edge. Left-click opens this window, "
    .. "right-click toggles combat-only.",
    function() return ns.API.IsMinimapButtonShown and ns.API.IsMinimapButtonShown() end,
    function(v) if ns.API.SetMinimapButtonShown then ns.API.SetMinimapButtonShown(v) end end)

-- ===========================================================================
-- Tools section
-- ===========================================================================
AddHeader("Tools")

AddButton("Reset to defaults",
    function() if ns.API.ShowResetConfirm then ns.API.ShowResetConfirm() end end,
    200,
    "Restore every CombatReticle setting to its default value. A confirmation "
    .. "prompt appears before anything is touched.")

AddGap(16)

-- Lock in the scroll height now that every widget has been placed.
content:SetHeight(-y + 20)

-- ---------------------------------------------------------------------------
-- Show / hide / refresh
-- ---------------------------------------------------------------------------
function RefreshAll()
    if not CombatReticleDB then return end
    for _, w in ipairs(widgets) do
        if w.Refresh then w.Refresh() end
    end
end

function ShowOptionsWindow()
    -- Restore saved position, or fall back to a sensible off-center default
    optionsFrame:ClearAllPoints()
    local saved = CombatReticleDB and CombatReticleDB.optionsWindow
    if saved and saved.point and saved.x and saved.y then
        optionsFrame:SetPoint(saved.point, UIParent,
            saved.relPoint or saved.point, saved.x, saved.y)
    else
        -- Top-left corner area; well out of the way of the screen center
        optionsFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -100)
    end
    optionsFrame:Show()
    RefreshAll()
    if ns.API.PreviewReticle then ns.API.PreviewReticle(4) end
end

local function ToggleOptionsWindow()
    if optionsFrame:IsShown() then
        optionsFrame:Hide()
        if ns.API.PreviewReticle then ns.API.PreviewReticle(4) end
    else
        ShowOptionsWindow()
    end
end

-- While the window is up, reticle is force-shown regardless of combat-only
-- so the user can actually see what they're configuring. The preview pulse
-- on close gives a final pulse before normal rules resume.
optionsFrame:HookScript("OnShow", function()
    if ns.API.SetOptionsOpen then ns.API.SetOptionsOpen(true) end
end)
optionsFrame:HookScript("OnHide", function()
    if ns.API.SetOptionsOpen then ns.API.SetOptionsOpen(false) end
    if ns.API.PreviewReticle then ns.API.PreviewReticle(4) end
end)

-- Called by CombatReticle.lua after reset / slash command / minimap toggle.
ns.API.RefreshOptions = function()
    if optionsFrame:IsShown() then RefreshAll() end
end

-- This is what the slash command, minimap button, and addon compartment all
-- call. Toggle so a second click closes it.
ns.API.OpenOptions = ToggleOptionsWindow

-- ---------------------------------------------------------------------------
-- Blizzard Settings stub
--
-- Even though the real options live in the floating window, register a thin
-- entry in the Blizzard Settings window so people poking around there find
-- the addon. It's a single "Open CombatReticle options" button.
-- ---------------------------------------------------------------------------
if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local stub = CreateFrame("Frame", "CombatReticleSettingsStub")
    stub.name = "CombatReticle"

    local header = stub:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    header:SetPoint("TOPLEFT", 16, -16)
    header:SetText("CombatReticle")

    local body = stub:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -14)
    body:SetWidth(520)
    body:SetJustifyH("LEFT")
    body:SetText("CombatReticle uses a separate, movable options window so it "
        .. "doesn't sit on top of the reticle while you're configuring it. "
        .. "Click the button below to open it.")

    local btn = CreateFrame("Button", nil, stub, "UIPanelButtonTemplate")
    btn:SetSize(240, 28)
    btn:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -18)
    btn:SetText("Open CombatReticle options")
    btn:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then
            HideUIPanel(SettingsPanel)
        end
        ShowOptionsWindow()
    end)

    local hint = stub:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -16)
    hint:SetWidth(520)
    hint:SetJustifyH("LEFT")
    hint:SetText("Also: |cffffd200/cr|r opens the window, the minimap "
        .. "button opens it, and the addon compartment icon opens it.")

    local category = Settings.RegisterCanvasLayoutCategory(stub, "CombatReticle")
    Settings.RegisterAddOnCategory(category)
end
