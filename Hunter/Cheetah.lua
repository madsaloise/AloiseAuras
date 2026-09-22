-- AloiseAuras - Cheetah module
-- Reminder aura icon for Aspect of the Cheetah:
--   out of combat, not up  -> desaturated icon + glow (cast reminder)
--   out of combat, up      -> normal icon
--   in combat, up          -> normal icon + glow
--   in combat, not up      -> hidden

local HA = AloiseAuras
local M = {}

local CHEETAH_SPELL_ID = 5118

M.defaults = {
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
-- 12.1 AuraContainer: the engine shows/hides the real aura icon itself, working
-- in combat where aura reads and UNIT_AURA are blocked. nil on older clients.
local container
-- Fallback-only cached state, used when the AuraContainer system is unavailable.
local cheetahUp = false
local inCombat = false

--------------------------------------------------------------------------------
-- Icon frame
--------------------------------------------------------------------------------
local function GetCheetahAura()
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        return C_UnitAuras.GetPlayerAuraBySpellID(CHEETAH_SPELL_ID)
    end
end

local function ApplyIconLayout()
    local cfg = db.icon
    icon:ClearAllPoints()
    icon:SetPoint(cfg.point, UIParent, cfg.relPoint, cfg.x, cfg.y)
    icon:SetSize(cfg.size, cfg.size)

    local g = cfg.size * 0.4
    icon.glow:ClearAllPoints()
    icon.glow:SetPoint("TOPLEFT", icon, "TOPLEFT", -g, g)
    icon.glow:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", g, -g)

    if container then
        container:ClearAllPoints()
        container:SetSize(cfg.size, cfg.size)
        container:SetPoint("CENTER", icon, "CENTER")
        if container:HasAuraGroup("cheetah") then
            container:SetAuraGroupLayout("cheetah", {
                elementWidth = cfg.size,
                elementHeight = cfg.size,
                elementSpacing = 0,
                lineSpacing = 0,
                layoutIndex = 1,
            })
        end
    end
end

local function SetGlow(on)
    if on then
        icon.glow:Show()
        if not icon.glowAnim:IsPlaying() then icon.glowAnim:Play() end
    else
        icon.glowAnim:Stop()
        icon.glow:Hide()
    end
end

local function UpdateIcon()
    if configMode then return end

    local known = IsPlayerSpell(CHEETAH_SPELL_ID)

    if container then
        -- The engine draws the real aura icon whenever Cheetah is up, in combat
        -- too. Out of combat, where aura reads work, also show a desaturated
        -- glowing reminder while it is down. In combat the buff state is secret,
        -- so no reminder is possible there.
        if inCombat then container:Show() else container:Hide() end

        if known and not inCombat and GetCheetahAura() == nil then
            icon.tex:Show()
            icon.tex:SetDesaturated(true)
            SetGlow(true)
            icon:Show()
        else
            icon.tex:Hide()
            SetGlow(false)
            icon:Hide()
        end
        return
    end

    -- Fallback for clients without the AuraContainer system: cached state that
    -- cannot see aura changes during combat.
    if not known then
        SetGlow(false)
        icon:Hide()
        return
    end

    local hasAura = cheetahUp

    if not hasAura and inCombat then
        SetGlow(false)
        icon:Hide()
        return
    end

    icon.tex:Show()
    icon:Show()
    if hasAura then
        icon.tex:SetDesaturated(false)
        SetGlow(inCombat)
    else
        icon.tex:SetDesaturated(true)
        SetGlow(true)
    end
end

local function SetConfigMode(on)
    configMode = on
    if on then
        if container then container:Hide() end
        icon:EnableMouse(true)
        icon.drag:EnableMouse(true)
        icon.label:Show()
        icon.tex:Show()
        icon.tex:SetDesaturated(true)
        SetGlow(true)
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
    icon.tex:SetTexture(HA.Spell.Texture(CHEETAH_SPELL_ID))
    icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    icon.border = icon:CreateTexture(nil, "OVERLAY")
    icon.border:SetPoint("TOPLEFT", -2, 2)
    icon.border:SetPoint("BOTTOMRIGHT", 2, -2)
    icon.border:SetColorTexture(0, 0, 0, 1)
    icon.border:SetDrawLayer("BACKGROUND")

    icon.glow = icon:CreateTexture(nil, "OVERLAY")
    icon.glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
    icon.glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
    icon.glow:SetBlendMode("ADD")
    icon.glow:Hide()

    local ag = icon.glow:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local pulseOut = ag:CreateAnimation("Alpha")
    pulseOut:SetFromAlpha(1.0)
    pulseOut:SetToAlpha(0.35)
    pulseOut:SetDuration(0.6)
    pulseOut:SetOrder(1)
    local pulseIn = ag:CreateAnimation("Alpha")
    pulseIn:SetFromAlpha(0.35)
    pulseIn:SetToAlpha(1.0)
    pulseIn:SetDuration(0.6)
    pulseIn:SetOrder(2)
    icon.glowAnim = ag

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
        ApplyIconLayout()
    end)

    icon.label = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    icon.label:SetPoint("BOTTOM", icon, "TOP", 0, 4)
    icon.label:SetText("AloiseAuras (drag to move)")
    icon.label:Hide()
end

--------------------------------------------------------------------------------
-- AuraContainer (12.1 engine-driven display)
--------------------------------------------------------------------------------
-- Styles each engine-created AuraButton. This is the only place button regions
-- may be touched while auras are secret, so all setup happens here.
local function InitCheetahButton(button)
    button:SetFlattensRenderLayers(true)
    -- Native size calls are permitted on aura buttons during load; the layout
    -- should size it, but set it explicitly in case the layout is not applied.
    pcall(button.SetSize, button, db.icon.size, db.icon.size)

    local tex = button:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(button)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button:SetIcon(tex)

    -- Match the out-of-combat reminder look: black border + pulsing glow, but
    -- kept in full colour (not desaturated).
    local border = button:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
    border:SetColorTexture(0, 0, 0, 1)

    local g = db.icon.size * 0.4
    local glow = button:CreateTexture(nil, "OVERLAY")
    glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
    glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
    glow:SetBlendMode("ADD")
    glow:SetPoint("TOPLEFT", button, "TOPLEFT", -g, g)
    glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", g, -g)

    local ag = glow:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local pulseOut = ag:CreateAnimation("Alpha")
    pulseOut:SetFromAlpha(1.0)
    pulseOut:SetToAlpha(0.35)
    pulseOut:SetDuration(0.6)
    pulseOut:SetOrder(1)
    local pulseIn = ag:CreateAnimation("Alpha")
    pulseIn:SetFromAlpha(0.35)
    pulseIn:SetToAlpha(1.0)
    pulseIn:SetDuration(0.6)
    pulseIn:SetOrder(2)
    ag:Play()
end

local function BuildContainer()
    local ok, frame = pcall(CreateFrame, "AuraContainer", "AloiseAurasCheetahContainer",
        UIParent, "CustomAuraContainerTemplate")
    if not ok or not frame then return end

    container = frame
    -- Respect UIParent scale so the button matches the manual reminder icon size.
    container:SetIgnoreParentScale(false)
    container:SetFrameStrata("MEDIUM")
    container:SetSize(db.icon.size, db.icon.size)
    container:Hide()
    container:SetUnit("player")

    -- Configure the flow layout before declaring the group; MiniAuras does this
    -- in New() and the container will not lay out its buttons without it.
    local flowOk, flowErr = pcall(function()
        container:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
        container:SetFlowLayoutAnchorPoint("TOPLEFT")
        container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
    end)
    if not flowOk then
        print("|cff33ff99AloiseAuras|r: flow layout setup failed: " .. tostring(flowErr))
    end

    container:AddAuraGroup("cheetah", "HELPFUL", {
        maxFrameCount = 1,
        candidateFilters = { includeSpellIDs = { [CHEETAH_SPELL_ID] = true } },
        sortMethod = AuraContainerSortMethod and AuraContainerSortMethod.AuraInstanceIDOnly or nil,
        sortDirection = AuraContainerSortDirection and AuraContainerSortDirection.Normal or nil,
        initializeFrame = InitCheetahButton,
        layout = {
            elementWidth = db.icon.size,
            elementHeight = db.icon.size,
            elementSpacing = 0,
            lineSpacing = 0,
            layoutIndex = 1,
        },
    })

    -- A container tracks nothing until enabled; this registers its aura events.
    container:SetEnabled(true)
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

    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    end

    -- Aura reads return nil in combat under 12.1 secure-aura rules, so only
    -- refresh the cached state out of combat and hold it for the whole fight.
    if not inCombat then
        cheetahUp = GetCheetahAura() ~= nil
    end
    UpdateIcon()
end)

--------------------------------------------------------------------------------
-- Module interface
--------------------------------------------------------------------------------
function M.OnInit(dbref)
    db = dbref
    BuildIcon()
    BuildContainer()
    ApplyIconLayout()
    cheetahUp = GetCheetahAura() ~= nil
    UpdateIcon()
end

function M.OnNonHunter()
    ev:UnregisterAllEvents()
    if icon then icon:Hide() end
    if container then container:Hide() end
end

local sizeSlider

function M.BuildOptions(panel, anchor)
    local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)
    header:SetText("Aspect of the Cheetah")

    sizeSlider = CreateFrame("Slider", "AloiseAurasSizeSlider", panel, "OptionsSliderTemplate")
    sizeSlider:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 4, -24)
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
        if icon then ApplyIconLayout() end
        _G[self:GetName() .. "Text"]:SetText("Icon size: " .. value)
    end)

    return sizeSlider
end

function M.RefreshOptions()
    if not sizeSlider then return end
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
