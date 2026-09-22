-- AloiseAuras - Tracking module
-- On PLAYER_TARGET_CHANGED, if the player is a Hunter, out of combat, and
-- has the Improved Tracking talent, switch tracking to match the target's
-- creature type. Only casts when the corresponding Track spell is known.

local HA = AloiseAuras
local M = {}

M.defaults = {
    tracking = {
        enabled = true,
        -- Improved Tracking talent spell ID (Wowhead Classic/Forever). Set to 0
        -- to disable the talent gate entirely.
        improvedTrackingID = 24293,
    },
}

-- English creature-type -> Track X spell ID.
local TRACK_SPELL_BY_TYPE = {
    ["Beast"]     = 1494,
    ["Demon"]     = 19878,
    ["Dragonkin"] = 19879,
    ["Elemental"] = 19880,
    ["Giant"]     = 19882,
    ["Humanoid"]  = 19883,
    ["Undead"]    = 19884,
}

local db

local function GetTrackingAPI()
    local cm = _G.C_Minimap
    local getNum = (cm and cm.GetNumTrackingTypes) or _G.GetNumTrackingTypes
    local getInfo = function(i)
        if cm and cm.GetTrackingInfo then
            local info = cm.GetTrackingInfo(i)
            if info then return info.name, info.active end
        elseif _G.GetTrackingInfo then
            local n, _, active = _G.GetTrackingInfo(i)
            return n, active
        end
    end
    return getNum, getInfo
end

local function IsAlreadyTracking(spellName)
    local getNum, getInfo = GetTrackingAPI()
    if not getNum then return false end
    for i = 1, getNum() do
        local name, active = getInfo(i)
        if active and name == spellName then return true end
    end
    return false
end

local function TrySwap()
    local cfg = db.tracking
    if not cfg.enabled then return end
    if not HA:IsHunter() then return end

    if InCombatLockdown() or UnitAffectingCombat("player") then return end
    if ChannelInfo() or CastingInfo() then return end
    if GetCursorInfo() then return end

    if cfg.improvedTrackingID and cfg.improvedTrackingID > 0 then
        if not IsPlayerSpell(cfg.improvedTrackingID) then return end
    end

    if not UnitExists("target") or UnitIsDead("target") then return end
    if not UnitCanAttack("player", "target") then return end

    local creatureType = UnitCreatureType("target")
    if not creatureType then return end

    local spellID = TRACK_SPELL_BY_TYPE[creatureType]
    if not spellID or not IsSpellKnown(spellID) then return end

    local spellName = GetSpellInfo(spellID)
    if not spellName or IsAlreadyTracking(spellName) then return end

    CastSpellByName(spellName)
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:SetScript("OnEvent", function()
    TrySwap()
end)

--------------------------------------------------------------------------------
-- Module interface
--------------------------------------------------------------------------------
function M.OnInit(dbref)
    db = dbref
end

function M.OnNonHunter()
    ev:UnregisterAllEvents()
end

local trackCB

function M.BuildOptions(panel, anchor)
    local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -20)
    header:SetText("Tracking auto-swap")

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    sub:SetWidth(420)
    sub:SetJustifyH("LEFT")
    sub:SetText("When you target a Beast/Demon/Dragonkin/Elemental/Giant/Humanoid/Undead out of combat and have the Improved Tracking talent, automatically switch to the matching Track spell.")

    trackCB = CreateFrame("CheckButton", "AloiseAurasTrackCB", panel, "InterfaceOptionsCheckButtonTemplate")
    trackCB:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -8)
    trackCB.Text:SetText("Enable tracking auto-swap")
    trackCB:SetScript("OnClick", function(self)
        db.tracking.enabled = self:GetChecked() and true or false
    end)

    return trackCB
end

function M.RefreshOptions()
    if not trackCB then return end
    trackCB:SetChecked(db.tracking.enabled)
end

function M.HandleSlash(cmd, rest)
    if cmd == "track" then
        db.tracking.enabled = not db.tracking.enabled
        print("|cff33ff99AloiseAuras|r: tracking auto-swap " .. (db.tracking.enabled and "enabled" or "disabled") .. ".")
        return true
    elseif cmd == "itid" then
        local id = tonumber(rest and rest:match("^(%d+)$") or "")
        if id then
            db.tracking.improvedTrackingID = id
            print(("|cff33ff99AloiseAuras|r: Improved Tracking spell ID set to %d (0 disables the gate)."):format(id))
            return true
        end
    end
    return false
end

HA:RegisterModule("Tracking", M)
