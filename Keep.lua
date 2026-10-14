-- Keep: marks items worth hanging onto with a line in their tooltip
-- ("[Keep] First Aid: Wool Cloth"), so nobody vendors their food fish or
-- the cloth for their next bandages. Built from your class, professions and
-- current guide, and rebuilt when those change.
local _, FG = ...

local CLOTH = { [2589] = "Linen Cloth", [2592] = "Wool Cloth", [4306] = "Silk Cloth" }
local CAMP = { [4470] = "Simple Wood", [4471] = "Flint and Tinder" }
local HERBS = {
    [2447] = "Peacebloom", [765] = "Silverleaf", [2449] = "Earthroot", [785] = "Mageroyal",
    [2450] = "Briarthorn", [2452] = "Swiftthistle", [2453] = "Bruiseweed", [3355] = "Wild Steelbloom",
    [3356] = "Kingsblood", [3357] = "Liferoot", [3820] = "Stranglekelp", [3821] = "Goldthorn", [6522] = "Deviate Fish",
    [3371] = "Empty Vial", [3372] = "Leaded Vial",
}
local LEATHER = { [2934] = "Ruined Leather Scraps", [2318] = "Light Leather", [783] = "Light Hide",
                  [2319] = "Medium Leather", [4232] = "Medium Hide", [4234] = "Heavy Leather" }
local RECIPES = { [6328] = "Recipe: Longjaw Mud Snapper", [5488] = "Recipe: Crispy Lizard Tail",
                  [6325] = "Recipe: Brilliant Smallfish" }

-- Codes for sharing a keep list with the party: id:code
local CODE_NAMES = { F = "food", C = "First Aid cloth", W = "campfire", A = "Alchemy", L = "Leatherworking",
                     G = "a guide step", R = "a recipe", U = "crafting a party upgrade", B = "party bags (Tailoring alt)" }

function FG:BuildKeepList()
    local keep, codes = {}, {}
    local currentCode = "G"
    local function mark(id, reason)
        if id and not keep[id] then keep[id] = reason; codes[id] = currentCode end
    end

    -- Your own food: cooked, raw, and what goes with it
    currentCode = "F"
    local _, class = UnitClass("player")
    for _, f in ipairs(self.foodPlan and self.foodPlan[class] or {}) do
        mark(f[2], ("your food (%s, Well Fed +5%% XP)"):format(f[4]))
        if f[7] then mark(f[7], ("your food: cook into %s at Cooking %d"):format(f[3], f[5])) end
    end
    if class == "DRUID" then mark(2678, "your food: Mild Spices for Herb Baked Egg") end
    -- Forever's real ingredients for your food, once your Cooking window was opened
    for _, f in ipairs(self.foodPlan and self.foodPlan[class] or {}) do
        for _, g in ipairs(self.RecipeReagents and self:RecipeReagents(f[2]) or {}) do
            mark(g.id, ("your food: %s for %s"):format(g.name or "ingredient", f[3]))
        end
    end
    currentCode = "R"
    for id, name in pairs(RECIPES) do mark(id, "food recipe - learn it when your Cooking is high enough") end

    currentCode = "C"
    for id, name in pairs(CLOTH) do
        if self.ClothReason then
            local reason, forAlt = self:ClothReason(id)
            if forAlt then currentCode = "B" end
            mark(id, reason)
            currentCode = "C"
        else
            mark(id, "First Aid: " .. name .. " for bandages")
        end
    end
    currentCode = "W"
    for id, name in pairs(CAMP) do mark(id, "campfire: " .. name) end

    currentCode = "A"
    if self:SkillRank("Alchemy") then
        -- Forever's real reagents for the elixirs/potions in your plan, once your Alchemy window was opened
        for _, cat in ipairs(self.potionPlan or {}) do
            for _, p in ipairs(cat[2]) do
                for _, g in ipairs(self.RecipeReagents and self:RecipeReagents(p[3]) or {}) do
                    mark(g.id, "Alchemy: " .. (g.name or "reagent") .. " for " .. p[4] .. " (/fg pots)")
                end
            end
        end
        for id, name in pairs(HERBS) do mark(id, "Alchemy: " .. name .. " (/fg pots)") end
    end
    currentCode = "L"
    if self:SkillRank("Leatherworking") then
        for id, name in pairs(LEATHER) do mark(id, "Leatherworking: " .. name) end
    end

    -- Materials for crafts that would upgrade someone in the party (Craft.lua)
    currentCode = "U"
    if self.CraftKeepItems then
        for id, reason in pairs(self:CraftKeepItems()) do mark(id, reason) end
    end

    -- Items a later step of your current guide asks for
    currentCode = "G"
    local guide = self:GetGuide()
    for _, s in ipairs(guide and guide.steps or {}) do
        if s.item then mark(s.item, "needed for a guide step: " .. (s.itemName or "")) end
    end
    self.keepList, self.keepCodes = keep, codes
    if self.BroadcastNeeds then self:BroadcastNeeds() end
end

-- What party members need: [itemID] = { "Cairne (food)", ... }
FG.partyNeeds = {}

function FG:SetPartyNeeds(sender, list)
    for id, who in pairs(self.partyNeeds) do
        who[sender] = nil
        if not next(who) then self.partyNeeds[id] = nil end
    end
    for id, code in pairs(list) do
        self.partyNeeds[id] = self.partyNeeds[id] or {}
        self.partyNeeds[id][sender] = CODE_NAMES[code] or "something"
    end
    self:RefreshBagIcons()
end

-- Encoded "id:code;id:code" chunks under the addon message size limit
function FG:EncodeNeeds()
    if not self.keepList then self:BuildKeepList() end
    local chunks, cur = {}, {}
    local len = 0
    for id, code in pairs(self.keepCodes or {}) do
        local item = id .. ":" .. code
        if len + #item + 1 > 220 then
            table.insert(chunks, table.concat(cur, ";")); cur, len = {}, 0
        end
        table.insert(cur, item); len = len + #item + 1
    end
    if #cur > 0 then table.insert(chunks, table.concat(cur, ";")) end
    return chunks
end

function FG:DecodeNeeds(text, into)
    for id, code in text:gmatch("(%d+):(%a)") do into[tonumber(id)] = code end
    return into
end

function FG:KeepReason(itemID)
    if not self.keepList then self:BuildKeepList() end
    return itemID and self.keepList[itemID]
end

-- Party members this item would be an upgrade for: { "Cairne (+14)", ... }
function FG:UpgradesFor(itemID)
    if not itemID or ForeverGuideDB.upgradeDots == false then return nil end
    local out
    for name, d in pairs(self.groupData or {}) do
        if d.gear and d.class then
            local delta = self:UpgradeDelta(itemID, d.class, d.level, d.gear, d.className, d.raceName)
            if delta then
                out = out or {}
                table.insert(out, ("%s (+%d)"):format(name, math.floor(delta + 0.5)))
            end
        end
    end
    if out then table.sort(out) end
    return out
end

-- The same colored dot as in the bags, as an inline tooltip icon
local function dot(r, g, b)
    return ("|TInterface\\COMMON\\Indicator-Gray:12:12:0:0:32:32:0:32:0:32:%d:%d:%d|t "):format(r, g, b)
end
local GOLD, BLUE, GREEN, PURPLE = dot(255, 209, 0), dot(77, 166, 255), dot(77, 255, 77), dot(190, 90, 255)

-- Upgrade for you, against what you're wearing: delta or nil
function FG:SelfUpgrade(itemID)
    if not itemID or ForeverGuideDB.upgradeDots == false then return nil end
    local gear = {}
    for slot = 1, 18 do gear[slot] = GetInventoryItemID and GetInventoryItemID("player", slot) end
    local className, class = UnitClass("player")
    return self:UpgradeDelta(itemID, class, UnitLevel("player"), gear, className, (UnitRace("player")))
end

local function addLine(tooltip, itemID)
    local reason = FG:KeepReason(itemID)
    if reason then
        tooltip:AddLine(GOLD .. "|cffffd100You need this:|r " .. reason, 1, 0.85, 0.4, true)
    end
    local who = itemID and FG.partyNeeds[itemID]
    if who then
        local parts = {}
        for name, why in pairs(who) do table.insert(parts, name .. " (" .. why .. ")") end
        table.sort(parts)
        tooltip:AddLine(BLUE .. "|cff4da6ffKeep for party:|r " .. table.concat(parts, ", "), 0.6, 0.8, 1, true)
    end
    local ups = FG:UpgradesFor(itemID)
    if ups then
        tooltip:AddLine(GREEN .. "|cff4dff4dUpgrade for party:|r " .. table.concat(ups, ", ") .. " |cff888888(if you can trade it)|r", 0.6, 1, 0.6, true)
    end
    local mine = FG:SelfUpgrade(itemID)
    if mine then
        tooltip:AddLine(PURPLE .. ("|cffbe5affUpgrade for you:|r +%d over what you're wearing"):format(math.floor(mine + 0.5)), 0.85, 0.6, 1, true)
    end
end

-- Newer clients pass tooltip data; older ones fire OnTooltipSetItem
if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
        addLine(tooltip, data and data.id)
    end)
else
    local function onSetItem(tooltip)
        local _, link = tooltip:GetItem()
        local id = link and tonumber(link:match("item:(%d+)"))
        addLine(tooltip, id)
    end
    GameTooltip:HookScript("OnTooltipSetItem", onSetItem)
    if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipSetItem", onSetItem) end
end

function FG:PrintKeepList()
    self:BuildKeepList()
    local count = 0
    for _ in pairs(self.keepList) do count = count + 1 end
    self:Print(("Marking %d item types as [Keep] in tooltips: your food and its ingredients, First Aid cloth, campfire wood, recipes%s, and items your guide still needs."):format(
        count, self:SkillRank("Alchemy") and ", Alchemy herbs and vials" or ""))
end

---------------------------------------------------------------------------
-- Bag dots, top-left of each slot: gold = you need it, blue = a party member
-- needs it, green = an upgrade for a party member, purple = an upgrade for
-- you. Soulbound items only ever get purple. Built-in bags, combined or
-- separate; tooltips explain each dot.
---------------------------------------------------------------------------
local function itemIDAt(bag, slot)
    if C_Container and C_Container.GetContainerItemID then return C_Container.GetContainerItemID(bag, slot) end
    if GetContainerItemID then return GetContainerItemID(bag, slot) end
end

local DOT_COLORS = {
    { 1, 0.82, 0 },     -- gold: you need it
    { 0.3, 0.65, 1 },   -- blue: a party member needs it
    { 0.3, 1, 0.3 },    -- green: an upgrade for a party member
    { 0.75, 0.35, 1 },  -- purple: an upgrade for you
}

local function isBound(bag, slot)
    if C_Item and C_Item.IsBound and ItemLocation and ItemLocation.CreateFromBagAndSlot then
        local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
        return loc and loc:IsValid() and C_Item.IsBound(loc)
    end
    return false
end

local function markButton(button, bag, slot)
    local id = itemIDAt(bag, slot)
    local show = {}
    if id and ForeverGuideDB.bagIcons ~= false then
        -- Soulbound items only get the purple "upgrade for you" dot
        local bound = isBound(bag, slot)
        if not bound then
            show[1] = FG:KeepReason(id) and true
            show[2] = FG.partyNeeds[id] and true
            show[3] = FG:UpgradesFor(id) and true
        end
        show[4] = FG:SelfUpgrade(id) and true
    end
    button.fgDots = button.fgDots or {}
    local x = 1
    for i = 1, 4 do
        local dot = button.fgDots[i]
        if show[i] then
            if not dot then
                dot = button:CreateTexture(nil, "OVERLAY", nil, 7)
                dot:SetTexture("Interface\\COMMON\\Indicator-Gray")
                dot:SetSize(12, 12)
                button.fgDots[i] = dot
            end
            dot:SetVertexColor(DOT_COLORS[i][1], DOT_COLORS[i][2], DOT_COLORS[i][3])
            dot:ClearAllPoints()
            dot:SetPoint("TOPLEFT", (x - 1) * 9 - 1, 1)
            dot:Show()
            x = x + 1
        elseif dot then
            dot:Hide()
        end
    end
end

-- Every open bag frame: the newer UI's combined bag and per-bag frames
-- (which list their slots with EnumerateValidItems), or the older Classic
-- ContainerFrameN with ContainerFrameNItemM buttons.
local function bagFrames()
    local list = {}
    if ContainerFrameCombinedBags then table.insert(list, ContainerFrameCombinedBags) end
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local f = _G["ContainerFrame" .. i]
        if f then table.insert(list, f) end
    end
    return list
end

function FG:RefreshBagIcons()
    for _, frame in ipairs(bagFrames()) do
        if frame:IsShown() then
            if frame.EnumerateValidItems then
                for _, button in frame:EnumerateValidItems() do
                    local bag = button.GetBagID and button:GetBagID()
                    local slot = button.GetID and button:GetID()
                    if bag and slot and slot > 0 then markButton(button, bag, slot) end
                end
            else
                local bag = frame.GetBagID and frame:GetBagID() or frame:GetID()
                local size = (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag))
                    or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
                for j = 1, size do
                    local button = _G[frame:GetName() .. "Item" .. j]
                    if button then
                        local slot = button.GetID and button:GetID()
                        if slot and slot > 0 then markButton(button, bag, slot) end
                    end
                end
            end
        end
    end
end

local bagEvents = CreateFrame("Frame")
bagEvents:RegisterEvent("BAG_UPDATE_DELAYED")
bagEvents:RegisterEvent("GET_ITEM_INFO_RECEIVED")
bagEvents:RegisterEvent("PLAYER_LOGIN")
bagEvents:SetScript("OnEvent", function() C_Timer.After(0.1, function() FG:RefreshBagIcons() end) end)
-- Refresh whenever a bag window shows or redraws its slots (both UIs)
local hooked = {}
local function hookFrames()
    for _, frame in ipairs(bagFrames()) do
        if not hooked[frame] then
            hooked[frame] = true
            frame:HookScript("OnShow", function() C_Timer.After(0, function() FG:RefreshBagIcons() end) end)
            if frame.UpdateItems then hooksecurefunc(frame, "UpdateItems", function() FG:RefreshBagIcons() end) end
        end
    end
end
if hooksecurefunc then
    if ContainerFrame_Update then hooksecurefunc("ContainerFrame_Update", function() FG:RefreshBagIcons() end) end
    if ToggleBag then hooksecurefunc("ToggleBag", function() C_Timer.After(0, function() FG:RefreshBagIcons() end) end) end
    if OpenAllBags then hooksecurefunc("OpenAllBags", function() C_Timer.After(0, function() FG:RefreshBagIcons() end) end) end
    if ToggleAllBags then hooksecurefunc("ToggleAllBags", function() C_Timer.After(0, function() FG:RefreshBagIcons() end) end) end
end
local hookEvents = CreateFrame("Frame")
hookEvents:RegisterEvent("PLAYER_LOGIN")
hookEvents:SetScript("OnEvent", hookFrames)
