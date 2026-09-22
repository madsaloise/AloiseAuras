-- AloiseAuras: main entry

local ADDON_NAME, wt = ...

wt.currentClass = select(2, UnitClass("player"))

AloiseAuras = AloiseAuras or {}
local AA = AloiseAuras
AA.ADDON_NAME = "AloiseAuras"
AA.private = wt
AA.modules = AA.modules or {}
AA.defaults = AA.defaults or {}

AloiseAurasDB = AloiseAurasDB or {}

local function DeepMergeDefaults(tbl, defs)
    for k, v in pairs(defs) do
        if type(v) == "table" then
            tbl[k] = tbl[k] or {}
            DeepMergeDefaults(tbl[k], v)
        elseif tbl[k] == nil then
            tbl[k] = v
        end
    end
end

function AA:RegisterModule(name, mod)
    self.modules[name] = mod
    if mod.defaults then
        DeepMergeDefaults(self.defaults, mod.defaults)
    end
end

function AA:IsHunter()
    return wt.currentClass == "HUNTER"
end

--------------------------------------------------------------------------------
-- Spell API compat shim
--   Wraps the C_Spell.* APIs preferred on Mainline 12.1+ with graceful
--   fallbacks to the older globals. Modules should call through AA.Spell.
--------------------------------------------------------------------------------
AA.Spell = {}

function AA.Spell.Name(id)
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(id)
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        return info and info.name
    end
    return GetSpellInfo(id)
end

function AA.Spell.Texture(id)
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(id)
    end
    return GetSpellTexture(id)
end

function AA.Spell.Cooldown(id)
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(id)
        if info then return info.startTime, info.duration end
        return 0, 0
    end
    return GetSpellCooldown(id)
end

function AA.Spell.Cast(id)
    if C_Spell and C_Spell.CastSpell then
        C_Spell.CastSpell(id)
        return
    end
    local name = AA.Spell.Name(id)
    if name then CastSpellByName(name) end
end

function AA.Spell.IsPlayerCasting()
    return UnitCastingInfo("player") ~= nil or UnitChannelInfo("player") ~= nil
end

--------------------------------------------------------------------------------
-- Options panel
--------------------------------------------------------------------------------
local optionsPanel

local function BuildOptionsPanel()
    local panel = CreateFrame("Frame", "AloiseAurasOptionsPanel", UIParent)
    panel.name = AA.ADDON_NAME

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("AloiseAuras")

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    sub:SetText("Utility modules. Toggle and configure each below.")

    local anchor = sub
    for _, mod in pairs(AA.modules) do
        if mod.BuildOptions then
            anchor = mod.BuildOptions(panel, anchor) or anchor
        end
    end

    panel.refresh = function()
        for _, mod in pairs(AA.modules) do
            if mod.RefreshOptions then mod.RefreshOptions() end
        end
    end

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, AA.ADDON_NAME)
        Settings.RegisterAddOnCategory(category)
        panel.category = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end

    return panel
end

function AA:OpenOptions()
    if not optionsPanel then return end
    if Settings and Settings.OpenToCategory and optionsPanel.category then
        Settings.OpenToCategory(optionsPanel.category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(optionsPanel)
        InterfaceOptionsFrame_OpenToCategory(optionsPanel)
    end
end

--------------------------------------------------------------------------------
-- Boot
--------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        DeepMergeDefaults(AloiseAurasDB, AA.defaults)
        AA.db = AloiseAurasDB
        for _, mod in pairs(AA.modules) do
            if mod.OnInit then mod.OnInit(AA.db) end
        end
        optionsPanel = BuildOptionsPanel()
        if optionsPanel.refresh then optionsPanel.refresh() end
    elseif event == "PLAYER_LOGIN" then
        wt.currentClass = select(2, UnitClass("player")) or wt.currentClass
        if not AA:IsHunter() then
            for _, mod in pairs(AA.modules) do
                if mod.OnNonHunter then mod.OnNonHunter() end
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- Slash dispatch
--------------------------------------------------------------------------------
SLASH_ALOISEAURAS1 = "/aloiseauras"
SLASH_ALOISEAURAS2 = "/aa"
SlashCmdList.ALOISEAURAS = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = cmd and cmd:lower() or ""

    for _, mod in pairs(AA.modules) do
        if mod.HandleSlash and mod.HandleSlash(cmd, rest) then
            return
        end
    end

    AA:OpenOptions()
end
