-- AloiseAuras - Trainer auto-buy module
-- When a class/profession trainer opens, automatically buy every available
-- service whose base name matches an entry in the user's whitelist.
--
-- WoW Forever = Classic content on the retail interface, so the Classic
-- trainer API (GetNumTrainerServices / GetTrainerServiceInfo /
-- BuyTrainerService) is what we target here.

local HA = AloiseAuras
local wt = HA.private
local M = {}

M.defaults = {
    trainer = {
        enabled = true,
        -- Array of lowercase spell names to auto-buy. Stored lowercase so
        -- lookups are O(1)-ish and case-insensitive against trainer names.
        spells = {},
        -- Set to true after the initial default whitelist has been seeded, so
        -- we don't repopulate it if the user intentionally clears the list.
        seeded = false,
    },
}

local db

--------------------------------------------------------------------------------
-- Whitelist helpers
--------------------------------------------------------------------------------
local function NormalizeName(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return nil end
    return s:lower()
end

-- Accepts a spell name OR a numeric spell ID. Returns the resolved base name
-- (lowercased) or nil if it can't be resolved.
local function ResolveEntry(input)
    local id = tonumber(input)
    if id then
        local name = HA.Spell.Name(id)
        return NormalizeName(name)
    end
    return NormalizeName(input)
end

local function Contains(name)
    if not name then return false end
    for _, v in ipairs(db.trainer.spells) do
        if v == name then return true end
    end
    return false
end

local function AddEntry(input)
    local name = ResolveEntry(input)
    if not name then return false, "could not resolve" end
    if Contains(name) then return false, "already in list" end
    table.insert(db.trainer.spells, name)
    return true, name
end

local function RemoveEntry(input)
    local name = ResolveEntry(input)
    if not name then return false, "could not resolve" end
    for i, v in ipairs(db.trainer.spells) do
        if v == name then
            table.remove(db.trainer.spells, i)
            return true, name
        end
    end
    return false, "not in list"
end

--------------------------------------------------------------------------------
-- Trainer scan + buy
--------------------------------------------------------------------------------
-- Names already bought this trainer visit, cleared on TRAINER_SHOW.
local attemptedThisVisit = {}

local function EnsureAvailableFilter()
    -- Some clients hide "unavailable" / "used" by default; make sure available
    -- services are shown so GetNumTrainerServices returns them.
    if SetTrainerServiceTypeFilter then
        pcall(SetTrainerServiceTypeFilter, "available", 1)
    end
end

local function BuyMatchingServices()
    if not db.trainer.enabled then return end
    if #db.trainer.spells == 0 then return end
    if not GetNumTrainerServices or not GetTrainerServiceInfo or not BuyTrainerService then return end

    EnsureAvailableFilter()

    -- Single forward pass. The service list only refreshes on TRAINER_UPDATE,
    -- not synchronously after a buy, so a restart loop would re-buy the same
    -- index forever (this crashed the client). attemptedThisVisit stops us from
    -- re-buying across the TRAINER_UPDATE events that each purchase triggers.
    local bought = 0
    local n = GetNumTrainerServices() or 0
    for i = 1, n do
        -- This build returns name, category, icon (category is the 2nd value).
        local name, category = GetTrainerServiceInfo(i)
        if name and category == "available" then
            local norm = NormalizeName(name)
            if norm and Contains(norm) and not attemptedThisVisit[norm] then
                attemptedThisVisit[norm] = true
                if pcall(BuyTrainerService, i) then
                    bought = bought + 1
                    print(("|cff33ff99AloiseAuras|r: trained %s."):format(name))
                end
            end
        end
    end

    if bought > 0 then
        print(("|cff33ff99AloiseAuras|r: bought %d trainer service(s)."):format(bought))
    end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("TRAINER_SHOW")
ev:RegisterEvent("TRAINER_UPDATE")
ev:SetScript("OnEvent", function(_, event)
    if event == "TRAINER_SHOW" then
        wipe(attemptedThisVisit)
    end
    BuyMatchingServices()
end)

--------------------------------------------------------------------------------
-- Module interface
--------------------------------------------------------------------------------
function M.OnInit(dbref)
    db = dbref
    if not db.trainer.seeded then
        if wt and wt.SpellsByLevel then
            for _, entries in pairs(wt.SpellsByLevel) do
                for _, entry in ipairs(entries) do
                    if entry.train then
                        local norm = NormalizeName(HA.Spell.Name(entry.id))
                        if norm and not Contains(norm) then
                            table.insert(db.trainer.spells, norm)
                        end
                    end
                end
            end
        end
        db.trainer.seeded = true
    end
end

local enableCB, listFS, spellCheckboxes

local function RefreshList()
    if listFS then
        if #db.trainer.spells == 0 then
            listFS:SetText("|cff888888(none)|r")
        else
            listFS:SetText(table.concat(db.trainer.spells, ", "))
        end
    end
    if spellCheckboxes then
        for _, cb in ipairs(spellCheckboxes) do
            cb:SetChecked(Contains(cb.norm))
        end
    end
end

local spellListPopup

local function BuildSpellListPopup()
    if spellListPopup then return spellListPopup end
    if not (wt and wt.SpellsByLevel) then return nil end

    local f = CreateFrame("Frame", "AloiseAurasTrainerSpellPopup", UIParent, "BackdropTemplate")
    f:SetSize(460, 420)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
    end
    f:Hide()

    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOP", 0, -14)
    title:SetText("Class spell list (check to auto-buy)")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    local scroll = CreateFrame("ScrollFrame", "AloiseAurasTrainerScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -40)
    scroll:SetPoint("BOTTOMRIGHT", -34, 16)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(400, 1)
    scroll:SetScrollChild(child)

    spellCheckboxes = {}
    local y = 4

    local levels = {}
    for lvl in pairs(wt.SpellsByLevel) do levels[#levels + 1] = lvl end
    table.sort(levels)

    for _, lvl in ipairs(levels) do
        local lvlFS = child:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        lvlFS:SetPoint("TOPLEFT", 0, -y)
        lvlFS:SetText(("|cffffd100Level %d|r"):format(lvl))
        y = y + 20

        for _, entry in ipairs(wt.SpellsByLevel[lvl]) do
            local name = HA.Spell.Name(entry.id)
            local icon = HA.Spell.Texture(entry.id)
            if name then
                local cb = CreateFrame("CheckButton", nil, child, "InterfaceOptionsCheckButtonTemplate")
                cb:SetPoint("TOPLEFT", 12, -y)
                local iconStr = icon and ("|T" .. icon .. ":16:16:0:0|t ") or ""
                cb.Text:SetText(iconStr .. name .. ("  |cff888888(%d)|r"):format(entry.id))
                cb.norm = name:lower()
                cb:SetScript("OnClick", function(self)
                    if self:GetChecked() then
                        if not Contains(cb.norm) then
                            table.insert(db.trainer.spells, cb.norm)
                        end
                    else
                        for i, v in ipairs(db.trainer.spells) do
                            if v == cb.norm then table.remove(db.trainer.spells, i) break end
                        end
                    end
                    RefreshList()
                end)
                spellCheckboxes[#spellCheckboxes + 1] = cb
                y = y + 22
            end
        end
        y = y + 6
    end

    child:SetHeight(math.max(y, 1))
    RefreshList()

    spellListPopup = f
    return f
end

function M.BuildOptions(panel, anchor)
    local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -20)
    header:SetText("Trainer auto-buy")

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    sub:SetWidth(420)
    sub:SetJustifyH("LEFT")
    sub:SetText("When you open a trainer, automatically buy any available service whose name matches your whitelist. Check spells below, or add extras (e.g. professions) by name/ID.")

    enableCB = CreateFrame("CheckButton", "AloiseAurasTrainerCB", panel, "InterfaceOptionsCheckButtonTemplate")
    enableCB:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -8)
    enableCB.Text:SetText("Enable trainer auto-buy")
    enableCB:SetScript("OnClick", function(self)
        db.trainer.enabled = self:GetChecked() and true or false
    end)

    local listLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    listLabel:SetPoint("TOPLEFT", enableCB, "BOTTOMLEFT", 0, -16)
    listLabel:SetText("Current whitelist:")

    listFS = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    listFS:SetPoint("TOPLEFT", listLabel, "BOTTOMLEFT", 0, -4)
    listFS:SetWidth(420)
    listFS:SetJustifyH("LEFT")
    listFS:SetJustifyV("TOP")
    listFS:SetHeight(40)

    local listBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    listBtn:SetSize(200, 24)
    listBtn:SetPoint("TOPLEFT", listFS, "BOTTOMLEFT", 0, -8)
    listBtn:SetText("Class spell list...")
    listBtn:SetScript("OnClick", function()
        local p = BuildSpellListPopup()
        if p then
            if p:IsShown() then p:Hide() else p:Show() end
        end
    end)

    return listBtn
end

function M.RefreshOptions()
    if not enableCB then return end
    enableCB:SetChecked(db.trainer.enabled)
    RefreshList()
end

--------------------------------------------------------------------------------
-- Slash: /aa train [add|remove|list|clear|on|off] [arg]
--------------------------------------------------------------------------------
function M.HandleSlash(cmd, rest)
    if cmd ~= "train" then return false end

    local sub, arg = rest:match("^(%S+)%s*(.-)$")
    sub = sub and sub:lower() or ""

    if sub == "add" and arg ~= "" then
        local ok, msg = AddEntry(arg)
        if ok then
            print(("|cff33ff99AloiseAuras|r: added \"%s\" to trainer whitelist."):format(msg))
            RefreshList()
        else
            print("|cff33ff99AloiseAuras|r: " .. msg)
        end
    elseif sub == "remove" and arg ~= "" then
        local ok, msg = RemoveEntry(arg)
        if ok then
            print(("|cff33ff99AloiseAuras|r: removed \"%s\" from trainer whitelist."):format(msg))
            RefreshList()
        else
            print("|cff33ff99AloiseAuras|r: " .. msg)
        end
    elseif sub == "list" or sub == "" then
        if #db.trainer.spells == 0 then
            print("|cff33ff99AloiseAuras|r: trainer whitelist is empty.")
        else
            print("|cff33ff99AloiseAuras|r: trainer whitelist: " .. table.concat(db.trainer.spells, ", "))
        end
    elseif sub == "clear" then
        wipe(db.trainer.spells)
        RefreshList()
        print("|cff33ff99AloiseAuras|r: trainer whitelist cleared.")
    elseif sub == "on" then
        db.trainer.enabled = true
        if enableCB then enableCB:SetChecked(true) end
        print("|cff33ff99AloiseAuras|r: trainer auto-buy enabled.")
    elseif sub == "off" then
        db.trainer.enabled = false
        if enableCB then enableCB:SetChecked(false) end
        print("|cff33ff99AloiseAuras|r: trainer auto-buy disabled.")
    else
        print("|cff33ff99AloiseAuras|r: usage: /aa train add|remove|list|clear|on|off [name-or-id]")
    end
    return true
end

HA:RegisterModule("Trainer", M)
