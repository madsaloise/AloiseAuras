-- AloiseAuras - Ammo restock module
-- On MERCHANT_SHOW, detects whether the equipped ranged weapon is a bow/
-- crossbow (needs arrows) or a gun (needs bullets), then scans the vendor for
-- the highest-tier projectile of that type the player meets the required
-- level for, and buys up to db.ammo.targetCount ammo.

local HA = AloiseAuras
local M = {}

M.defaults = {
    ammo = {
        enabled = true,
    },
}

local db

local RANGED_SLOT = 18
local COLOR = "|cff33ff99AloiseAuras|r"

-- Bag family bit flags: 0x1 = Quiver, 0x2 = Ammo Pouch.
local AMMO_BAG_MASK = 0x3

local band = (bit and bit.band) or function(a, b)
    -- Fallback for environments without bitlib: bag family flags fit in a
    -- byte, so a tiny mask loop is fine.
    local r, p = 0, 1
    while a > 0 and b > 0 do
        if (a % 2 == 1) and (b % 2 == 1) then r = r + p end
        a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
    end
    return r
end

local function GetContainerFreeSlots(bag)
    if C_Container and C_Container.GetContainerNumFreeSlots then
        return C_Container.GetContainerNumFreeSlots(bag)
    end
    return GetContainerNumFreeSlots(bag)
end

-- Finds the quiver / ammo pouch bag. Returns bagID, freeSlots or nil.
local function FindAmmoBag()
    for bag = 1, NUM_BAG_SLOTS or 4 do
        local free, family = GetContainerFreeSlots(bag)
        if family and family > 0 and band(family, AMMO_BAG_MASK) ~= 0 then
            return bag, free or 0
        end
    end
end

--------------------------------------------------------------------------------
-- Weapon / ammo type detection
--------------------------------------------------------------------------------
-- Returns "Arrow" or "Bullet" or nil.
local function GetRequiredAmmoType()
    local link = GetInventoryItemLink("player", RANGED_SLOT)
    if not link then return nil end
    local _, _, _, _, _, _, subType = GetItemInfo(link)
    if subType == "Bows" or subType == "Crossbows" then
        return "Arrow"
    elseif subType == "Guns" then
        return "Bullet"
    end
    return nil
end

--------------------------------------------------------------------------------
-- Merchant scan
--------------------------------------------------------------------------------
-- Returns index, link, stackSize, reqLevel of the best (highest req level)
-- projectile of the given ammo type the player can use, or nil if none found.
local function FindBestAmmoOnMerchant(ammoType)
    local n = GetMerchantNumItems() or 0
    local playerLevel = UnitLevel("player")
    local bestIndex, bestLink, bestStack, bestReq

    for i = 1, n do
        local link = GetMerchantItemLink(i)
        if link then
            local _, _, _, _, reqLevel, itemType, subType, stackCount = GetItemInfo(link)
            if itemType == "Projectile" and subType == ammoType then
                reqLevel = reqLevel or 0
                if reqLevel <= playerLevel then
                    if not bestReq or reqLevel > bestReq then
                        bestIndex, bestLink, bestStack, bestReq = i, link, stackCount or 200, reqLevel
                    end
                end
            end
        end
    end

    return bestIndex, bestLink, bestStack, bestReq
end

--------------------------------------------------------------------------------
-- Buying
--------------------------------------------------------------------------------
local function RestockAmmo()
    if not db.ammo.enabled then return end
    if not HA:IsHunter() then return end

    local ammoType = GetRequiredAmmoType()
    if not ammoType then return end

    local index, link, stackSize = FindBestAmmoOnMerchant(ammoType)
    if not index then return end

    local bag, freeSlots = FindAmmoBag()
    if not bag then
        print(COLOR .. ": no quiver or ammo pouch equipped.")
        return
    end
    if freeSlots <= 0 then return end

    local toBuy = freeSlots * stackSize

    -- Respect merchant-side limits (numAvailable == -1 means unlimited).
    local _, _, price, quantity, numAvailable = GetMerchantItemInfo(index)
    quantity = quantity or 1
    if numAvailable and numAvailable > 0 then
        toBuy = math.min(toBuy, numAvailable * quantity)
    end

    if price and quantity > 0 then
        local unitPrice = price / quantity
        if unitPrice * toBuy > GetMoney() then
            print(COLOR .. ": not enough coin to fully restock " .. link .. ".")
            return
        end
    end

    local _, _, _, lagHome = GetNetStats()
    local delayStep = math.max(0.05, (lagHome or 100) / 2000)
    local delay = 0
    local total = toBuy

    while toBuy > 0 do
        local chunk = math.min(toBuy, stackSize)
        C_Timer.After(delay, function()
            BuyMerchantItem(index, chunk)
        end)
        delay = delay + delayStep
        toBuy = toBuy - chunk
    end

    print(("%s: restocking %d %s."):format(COLOR, total, link))
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("MERCHANT_SHOW")
ev:SetScript("OnEvent", function()
    RestockAmmo()
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

local enableCB

function M.BuildOptions(panel, anchor)
    local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -20)
    header:SetText("Ammo restock")

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    sub:SetWidth(420)
    sub:SetJustifyH("LEFT")
    sub:SetText("When you open a vendor, fill your quiver or ammo pouch with the best arrows or bullets the vendor sells that match your equipped ranged weapon.")

    enableCB = CreateFrame("CheckButton", "AloiseAurasAmmoCB", panel, "InterfaceOptionsCheckButtonTemplate")
    enableCB:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -8)
    enableCB.Text:SetText("Enable ammo restock")
    enableCB:SetScript("OnClick", function(self)
        db.ammo.enabled = self:GetChecked() and true or false
    end)

    return enableCB
end

function M.RefreshOptions()
    if not enableCB then return end
    enableCB:SetChecked(db.ammo.enabled)
end

function M.HandleSlash(cmd)
    if cmd == "ammo" then
        db.ammo.enabled = not db.ammo.enabled
        if enableCB then enableCB:SetChecked(db.ammo.enabled) end
        print(COLOR .. ": ammo restock " .. (db.ammo.enabled and "enabled" or "disabled") .. ".")
        return true
    end
    return false
end

HA:RegisterModule("Ammo", M)
