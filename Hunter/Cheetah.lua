-- AloiseAuras - Cheetah module
-- 1. Auto-casts Aspect of the Cheetah on PLAYER_REGEN_ENABLED.
-- 2. Shows a large moveable icon while Cheetah is up during combat.

local HA = AloiseAuras
local M = {}

local CHEETAH_SPELL_ID = 186257
local CHEETAH_NAME = GetSpellInfo(CHEETAH_SPELL_ID) or "Aspect of the Cheetah"

M.defaults = {
    autoCast = true,
    -- "solo" = only cast when not in any group.
    -- "party" = also cast in a party (but never in a raid).
    groupMode = "party",
    icon = {
        point = "CENTER",
        relPoint = "CENTER",
        x = 0,
        y = 150,
        size = 96,
    },
}

local db
local icon, configMode

--------------------------------------------------------------------------------
-- Auto-cast logic
--------------------------------------------------------------------------------
local function CastCheetah()
    if not db.autoCast then return end
    if not HA:IsHunter() then return end
    if not IsPlayerSpell(CHEETAH_SPELL_ID) then return end

    if InCombatLockdown() then return end
    if ChannelInfo() or CastingInfo() then return end
    if GetCursorInfo() then return end

    if IsInRaid() then return end
    if IsInGroup() and db.groupMode ~= "party" then return end

    local start, duration = GetSpellCooldown(CHEETAH_NAME)
    if start and duration and duration > 1.5 then return end

    if AuraUtil and AuraUtil.FindAuraByName then
        local name = AuraUtil.FindAuraByName(CHEETAH_NAME, "player", "HELPFUL")
        if name then return end
    end

    CastSpellByName(CHEETAH_NAME)
end

--------------------------------------------------------------------------------
-- Icon frame
--------------------------------------------------------------------------------
local function GetCheetahAura()
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        return C_UnitAuras.GetAuraDataBySpellName("player", CHEETAH_NAME, "HELPFUL")
    end
    if AuraUtil and AuraUtil.FindAuraByName then
        local name, _, count, _, duration, expiration = AuraUtil.FindAuraByName(CHEETAH_NAME, "player", "HELPFUL")
        if name then
            return { name = name, applications = count, duration = duration, expirationTime = expiration }
        end
    end
end

local function ApplyIconLayout()
    local cfg = db.icon
    icon:ClearAllPoints()
    icon:SetPoint(cfg.point, UIParent, cfg.relPoint, cfg.x, cfg.y)
    icon:SetSize(cfg.size, cfg.size)
end

local function UpdateIcon()
    if configMode then return end
    local aura = GetCheetahAura()
    local inCombat = InCombatLockdown() or UnitAffectingCombat("player")
    if aura and inCombat then
        if aura.duration and aura.duration > 0 and aura.expirationTime then
            icon.cd:SetCooldown(aura.expirationTime - aura.duration, aura.duration)
        else
            icon.cd:Clear()
        end
        icon:Show()
    else
        icon:Hide()
    end
end

local function SetConfigMode(on)
    configMode = on
    if on then
        icon:EnableMouse(true)
        icon.drag:EnableMouse(true)
        icon.label:Show()
        icon.tex:SetDesaturated(true)
        icon:Show()
    else
        icon:EnableMouse(false)
        icon.drag:EnableMouse(false)
        icon.label:Hide()
        icon.tex:SetDesaturated(false)
        UpdateIcon()
    end
end

local function BuildIcon()
    icon = CreateFrame("Frame", "AloiseAurasIcon", UIParent, "BackdropTemplate")
    icon:SetFrameStrata("MEDIUM")
    icon:EnableMouse(false)
    icon:SetMovable(true)
    icon:SetClampedToScreen(true)
    icon:Hide()

    icon.tex = icon:CreateTexture(nil, "ARTWORK")
    icon.tex:SetAllPoints()
    icon.tex:SetTexture(GetSpellTexture(CHEETAH_SPELL_ID))
    icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    icon.border = icon:CreateTexture(nil, "OVERLAY")
    icon.border:SetPoint("TOPLEFT", -2, 2)
    icon.border:SetPoint("BOTTOMRIGHT", 2, -2)
    icon.border:SetColorTexture(0, 0, 0, 1)
    icon.border:SetDrawLayer("BACKGROUND")

    icon.cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cd:SetAllPoints()
    icon.cd:SetDrawEdge(false)
    icon.cd:SetHideCountdownNumbers(false)

    icon.drag = CreateFrame("Frame", nil, icon)
    icon.drag:SetAllPoints()
    icon.drag:EnableMouse(false)
    icon.drag:RegisterForDrag("LeftButton")
    icon.drag:SetScript("OnDragStart", function() icon:StartMoving() end)
    icon.drag:SetScript("OnDragStop", function()
        icon:StopMovingOrSizing()
        local point, _, relPoint, x, y = icon:GetPoint(1)
        db.icon.point = point
        db.icon.relPoint = relPoint
        db.icon.x = x
        db.icon.y = y
    end)

    icon.label = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    icon.label:SetPoint("BOTTOM", icon, "TOP", 0, 4)
    icon.label:SetText("AloiseAuras (drag to move)")
    icon.label:Hide()
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterUnitEvent("UNIT_AURA", "player")
ev:SetScript("OnEvent", function(_, event)
    if not HA:IsHunter() then return end
    if event == "PLAYER_REGEN_ENABLED" then
        CastCheetah()
        UpdateIcon()
    elseif event == "PLAYER_REGEN_DISABLED" then
        UpdateIcon()
    elseif event == "UNIT_AURA" then
        UpdateIcon()
    end
end)

--------------------------------------------------------------------------------
-- Module interface
--------------------------------------------------------------------------------
function M.OnInit(dbref)
    db = dbref
    BuildIcon()
    ApplyIconLayout()
    UpdateIcon()
end

function M.OnNonHunter()
    ev:UnregisterAllEvents()
    if icon then icon:Hide() end
end

local moveBtn, resetBtn, autoCB, groupDD, sizeSlider

function M.BuildOptions(panel, anchor)
    local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)
    header:SetText("Aspect of the Cheetah")

    autoCB = CreateFrame("CheckButton", "AloiseAurasAutoCastCB", panel, "InterfaceOptionsCheckButtonTemplate")
    autoCB:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    autoCB.Text:SetText("Auto-cast Cheetah on leaving combat")
    autoCB:SetScript("OnClick", function(self)
        db.autoCast = self:GetChecked() and true or false
    end)

    local groupLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    groupLabel:SetPoint("TOPLEFT", autoCB, "BOTTOMLEFT", 4, -12)
    groupLabel:SetText("Auto-cast group context:")

    groupDD = CreateFrame("Frame", "AloiseAurasGroupDD", panel, "UIDropDownMenuTemplate")
    groupDD:SetPoint("TOPLEFT", groupLabel, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(groupDD, 180)

    local groupOptions = {
        { value = "solo",  text = "Solo only" },
        { value = "party", text = "Solo or party (not raid)" },
    }

    local function SetGroupText()
        for _, opt in ipairs(groupOptions) do
            if opt.value == db.groupMode then
                UIDropDownMenu_SetText(groupDD, opt.text)
                return
            end
        end
    end

    UIDropDownMenu_Initialize(groupDD, function(_, level)
        for _, opt in ipairs(groupOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.text
            info.value = opt.value
            info.checked = (db.groupMode == opt.value)
            info.func = function()
                db.groupMode = opt.value
                SetGroupText()
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    groupDD.SetGroupText = SetGroupText

    sizeSlider = CreateFrame("Slider", "AloiseAurasSizeSlider", panel, "OptionsSliderTemplate")
    sizeSlider:SetPoint("TOPLEFT", groupDD, "BOTTOMLEFT", 16, -24)
    sizeSlider:SetMinMaxValues(32, 256)
    sizeSlider:SetValueStep(1)
    sizeSlider:SetObeyStepOnDrag(true)
    sizeSlider:SetWidth(240)
    _G[sizeSlider:GetName() .. "Low"]:SetText("32")
    _G[sizeSlider:GetName() .. "High"]:SetText("256")
    _G[sizeSlider:GetName() .. "Text"]:SetText("Icon size")
    sizeSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        db.icon.size = value
        if icon then icon:SetSize(value, value) end
        _G[self:GetName() .. "Text"]:SetText("Icon size: " .. value)
    end)

    moveBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    moveBtn:SetSize(200, 24)
    moveBtn:SetPoint("TOPLEFT", sizeSlider, "BOTTOMLEFT", 0, -32)
    moveBtn:SetText("Unlock icon (drag to move)")
    moveBtn:SetScript("OnClick", function(self)
        if not configMode then
            SetConfigMode(true)
            self:SetText("Lock icon")
        else
            SetConfigMode(false)
            self:SetText("Unlock icon (drag to move)")
        end
    end)

    resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetSize(200, 24)
    resetBtn:SetPoint("TOPLEFT", moveBtn, "BOTTOMLEFT", 0, -8)
    resetBtn:SetText("Reset position")
    resetBtn:SetScript("OnClick", function()
        db.icon.point = M.defaults.icon.point
        db.icon.relPoint = M.defaults.icon.relPoint
        db.icon.x = M.defaults.icon.x
        db.icon.y = M.defaults.icon.y
        db.icon.size = M.defaults.icon.size
        ApplyIconLayout()
        sizeSlider:SetValue(db.icon.size)
    end)

    return resetBtn
end

function M.RefreshOptions()
    if not autoCB then return end
    autoCB:SetChecked(db.autoCast)
    if groupDD and groupDD.SetGroupText then groupDD.SetGroupText() end
    sizeSlider:SetValue(db.icon.size)
    _G[sizeSlider:GetName() .. "Text"]:SetText("Icon size: " .. db.icon.size)
end

function M.HandleSlash(cmd)
    if cmd == "unlock" then
        SetConfigMode(true)
        print("|cff33ff99AloiseAuras|r: icon unlocked. Drag to move.")
        return true
    elseif cmd == "lock" then
        SetConfigMode(false)
        print("|cff33ff99AloiseAuras|r: icon locked.")
        return true
    end
    return false
end

HA:RegisterModule("Cheetah", M)
