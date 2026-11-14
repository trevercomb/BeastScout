local _, ns = ...

-- Food on item tooltips: will your summoned pet eat this? Forever's client
-- has its own check (C_PetInfo.CanPetEatItem, found with /beastscout probe),
-- the same one Feed Pet uses. Its exact signature isn't documented, so every
-- call is guarded and tries an item ID first, then the item link.

local unpack = unpack or table.unpack
local GREEN = "|cff40ff40"
local GREY = "|cff9d9d9d"

local function Call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

-- true, false, or nil when the client can't tell us.
function ns.PetCanEat(itemID, link)
    if not UnitExists("pet") or not C_PetInfo then return nil end
    local fn = C_PetInfo.CanPetEatItem
    for _, arg in ipairs({ itemID or false, link or false }) do
        if arg then
            local ok, answer = Call(fn, arg)
            if ok and type(answer) == "boolean" and not ns.IsSecret(answer) then return answer end
        end
    end
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
    local itemID, link = ItemOf(tooltip, data)
    if not itemID and not link then return end
    local eats = ns.PetCanEat(itemID, link)
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

-- /beastscout food [itemID]: raw answers from the client, to confirm the
-- signatures above. Without an ID it uses the item under the mouse.
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
    if not itemID and not link then
        say("hover an item and type /beastscout food again, or /beastscout food <itemID>.")
        return
    end
    for _, a in ipairs({ itemID or false, link or false }) do
        if a then
            local r = { pcall(C_PetInfo and C_PetInfo.CanPetEatItem or error, a) }
            local out = {}
            for i = 2, #r do out[#out + 1] = tostring(r[i]) end
            say("CanPetEatItem(" .. tostring(a) .. ") " .. (r[1] and "-> " or "error: ") .. table.concat(out, ", "))
        end
    end
end
