local _, ns = ...

-- Food on item tooltips: will your summoned pet eat this? Forever's client
-- has its own check, the same one Feed Pet uses. Confirmed in game
-- 2026-11-14: C_PetInfo.CanPetEatItem(itemID) -> true/false (an item link is
-- rejected), and C_PetInfo.GetPetFoodTypes() -> { "Meat", "Fish" }.

local unpack = unpack or table.unpack
local GREEN = "|cff40ff40"
local GREY = "|cff9d9d9d"

local function Call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

-- true, false, or nil when the client can't tell us.
function ns.PetCanEat(itemID)
    if not itemID or not UnitExists("pet") or not C_PetInfo then return nil end
    local ok, answer = Call(C_PetInfo.CanPetEatItem, itemID)
    if ok and type(answer) == "boolean" and not ns.IsSecret(answer) then return answer end
    return nil
end

-- The summoned pet's food types as the client names them, e.g. { "Meat", "Fish" }.
function ns.PetFoodTypes()
    if not UnitExists("pet") then return {} end
    local fn = (C_PetInfo and C_PetInfo.GetPetFoodTypes) or GetPetFoodTypes
    local results = { Call(fn) }
    if not results[1] then return {} end
    local list = type(results[2]) == "table" and results[2] or { unpack(results, 2) }
    local names = {}
    for _, v in pairs(list) do
        if type(v) == "string" and not ns.IsSecret(v) then names[#names + 1] = v end
    end
    table.sort(names)
    return names
end

-- Food and drink only, so we don't say "won't eat" on every sword.
local function IsConsumable(itemID)
    local info = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not info or not itemID then return false end
    local ok, _, _, _, _, _, classID = Call(info, itemID)
    return ok and classID == 0
end

local function ItemOf(tooltip, data)
    local itemID = data and type(data.id) == "number" and data.id or nil
    local link
    if tooltip.GetItem then
        local ok, _, l, id = Call(tooltip.GetItem, tooltip)
        if ok then link, itemID = l, itemID or id end
    end
    if not itemID and type(link) == "string" then itemID = tonumber(link:match("item:(%d+)")) end
    return itemID, link
end

function ns.AddFoodLine(tooltip, data)
    if tooltip ~= GameTooltip or not UnitExists("pet") then return end
    local itemID = ItemOf(tooltip, data)
    local eats = ns.PetCanEat(itemID)
    local name = UnitName("pet")
    if ns.IsSecret(name) or type(name) ~= "string" then name = "Your pet" end
    if eats then
        tooltip:AddLine(GREEN .. name .. " will eat this|r")
    elseif eats == false and IsConsumable(itemID) then
        tooltip:AddLine(GREY .. name .. " won't eat this|r")
    else
        return
    end
    tooltip:Show()
end

function ns.HookFoodTooltip()
    if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ns.AddFoodLine)
    elseif GameTooltip.HookScript then
        pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", function(tooltip) ns.AddFoodLine(tooltip) end)
    end
end

-- Food vendors ----------------------------------------------------------------
-- Opening a vendor's window remembers the food and drink it sells, and where
-- you stood: BeastScoutDB.vendors[npcId] = { name, spot = { zone, x, y },
-- items = { { itemID, name } } }. find food then asks the client which of
-- those your summoned pet eats (CanPetEatItem works on any item ID, not just
-- ones in your bags), so one visit covers every pet you'll ever have.

local function MerchantItem(i)
    local id = GetMerchantItemID and GetMerchantItemID(i)
    local name
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local ok, info = pcall(C_MerchantFrame.GetItemInfo, i)
        if ok and type(info) == "table" then name = info.name end
    end
    if not name and GetMerchantItemInfo then name = GetMerchantItemInfo(i) end
    if not id and GetMerchantItemLink then
        local link = GetMerchantItemLink(i)
        id = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
    end
    if ns.IsSecret(id) or ns.IsSecret(name) then return nil end
    return id, name
end

function ns.ReadMerchant()
    local npcId = ns.NpcIdFromGUID(UnitGUID("npc"))
    local count = GetMerchantNumItems and GetMerchantNumItems() or 0
    if not npcId or ns.IsSecret(count) or count == 0 then return end
    local items = {}
    for i = 1, count do
        local id, name = MerchantItem(i)
        if id and IsConsumable(id) then items[#items + 1] = { id, name } end
    end
    BeastScoutDB.vendors = BeastScoutDB.vendors or {}
    if #items == 0 then
        BeastScoutDB.vendors[npcId] = nil -- sells no food (any more)
        return
    end
    local old = BeastScoutDB.vendors[npcId]
    local vendorName = UnitName("npc")
    BeastScoutDB.vendors[npcId] = {
        name = (not ns.IsSecret(vendorName) and vendorName) or (old and old.name) or "?",
        spot = ns.CurrentSpot and ns.CurrentSpot() or (old and old.spot),
        items = items,
    }
end

-- Your pet's food from one vendor: { "Tough Jerky", ... }, or {} (nil when
-- the client can't tell).
function ns.VendorFoodForPet(vendor)
    local out = {}
    for _, item in ipairs(vendor.items or {}) do
        local eats = ns.PetCanEat(item[1])
        if eats == nil then return nil end
        if eats then out[#out + 1] = item[2] or ("item " .. item[1]) end
    end
    return out
end

-- /beastscout food [itemID]: raw answers from the client, for troubleshooting. Without an ID it uses the item under the mouse.
function ns.ProbeFood(arg)
    local say = function(text) print("|cffabd473BeastScout|r food probe: " .. text) end
    if not UnitExists("pet") then say("summon your pet first.") return end
    local raw = { Call((C_PetInfo and C_PetInfo.GetPetFoodTypes) or GetPetFoodTypes) }
    local shown = {}
    for i = 2, #raw do
        local v = raw[i]
        if type(v) == "table" then
            local parts = {}
            for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(x) end
            shown[#shown + 1] = "{" .. table.concat(parts, ", ") .. "}"
        else
            shown[#shown + 1] = tostring(v)
        end
    end
    say("GetPetFoodTypes " .. (raw[1] and ("-> " .. (#shown > 0 and table.concat(shown, ", ") or "(nothing)")) or "failed"))

    local itemID, link = tonumber(arg or "")
    if not itemID and GameTooltip:IsShown() then itemID, link = ItemOf(GameTooltip) end
    if not itemID then
        say("hover an item and type /beastscout food again, or /beastscout food <itemID>.")
        return
    end
    local r = { pcall(C_PetInfo and C_PetInfo.CanPetEatItem or error, itemID) }
    local out = {}
    for i = 2, #r do out[#out + 1] = tostring(r[i]) end
    say("CanPetEatItem(" .. itemID .. ")" .. (link and (" " .. link) or "") .. (r[1] and " -> " or " error: ")
        .. table.concat(out, ", "))
end
