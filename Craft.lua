-- Craft: reads your recipes from the game (so they're always WoW Forever's,
-- for every profession), and works out what your Leatherworking / Tailoring /
-- Blacksmithing / Engineering can make that would upgrade someone in the party.
-- Alchemy, Cooking and First Aid reagents feed /fg pots, /fg food and [Keep].
--  * Open your profession window once and the recipes you know are saved.
--  * /fg craft lists the upgrades: who, how much, materials (have/need) and
--    whether it still gives skill. The guide window says when one is ready.
--  * Materials for those crafts get the gold "keep" dot in your bags, and
--    party members see the blue "party needs" dot on them.
--  * At a profession trainer, recipes that would make an upgrade glow.
-- Suggestions only: nothing is crafted, learned or bought for you.
local _, FG = ...

local GEAR_PROFESSIONS = { Leatherworking = true, Tailoring = true, Blacksmithing = true, Engineering = true }
local SKILL_COLOR = { optimal = "|cffff8040", medium = "|cffffff00", easy = "|cff40c040", trivial = "|cff808080" }
local SKILL_WORD = { optimal = "skill-up", medium = "skill-up", easy = "maybe a skill-up", trivial = "no skill-up" }
local MIN_GAIN = 2   -- ignore tiny upgrades (e.g. +1 because a slot is empty)

local function itemID(link) return link and tonumber(link:match("item:(%d+)")) end

---------------------------------------------------------------------------
-- Scan the open profession window
---------------------------------------------------------------------------
function FG:ScanTradeSkill()
    if not (GetTradeSkillLine and GetNumTradeSkills) then return end
    local prof = GetTradeSkillLine()
    if not prof or prof == "UNKNOWN" then return end   -- every profession: Forever's real recipes
    local c = ForeverGuideCharDB
    c.recipes = c.recipes or {}
    local list = {}
    for i = 1, GetNumTradeSkills() do
        local name, kind = GetTradeSkillInfo(i)
        if name and kind ~= "header" and kind ~= "subheader" then
            local id = itemID(GetTradeSkillItemLink(i))
            if id then
                local r = { name = name, diff = kind, reagents = {} }
                for j = 1, (GetTradeSkillNumReagents(i) or 0) do
                    local rname, _, count = GetTradeSkillReagentInfo(i, j)
                    local rid = itemID(GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(i, j))
                    if rid then table.insert(r.reagents, { id = rid, name = rname, count = count or 1 }) end
                end
                list[id] = r
            end
        end
    end
    if next(list) then
        c.recipes[prof] = list
        self.craftCache = nil
        self.keepList = nil
    end
end

---------------------------------------------------------------------------
-- Upgrades from known recipes
---------------------------------------------------------------------------
local function myGear()
    local gear = {}
    for slot = 1, 18 do gear[slot] = GetInventoryItemID and GetInventoryItemID("player", slot) end
    return gear
end

-- Everyone whose gear we know: you + party members sharing it
local function members()
    local out = {}
    local className, class = UnitClass("player")
    table.insert(out, { name = UnitName("player"), class = class, level = UnitLevel("player"), gear = myGear(),
                        className = className, raceName = (UnitRace("player")) })
    for name, d in pairs(FG.groupData or {}) do
        if d.gear and d.class then
            table.insert(out, { name = name, class = d.class, level = d.level, gear = d.gear,
                                className = d.className, raceName = d.raceName })
        end
    end
    return out
end

-- Other crafters' best offer per person and slot: [crafter] = { ["Name:slot"] = { id, delta, ready } }
FG.craftOffers = {}

local function slotOf(id)
    local equipLoc = select(9, FG:ItemInfo(id))
    local slots = equipLoc and FG.EQUIP_SLOTS[equipLoc]
    return slots and slots[1]
end

-- Is someone else's craft for this person/slot better than delta? returns crafter, offer
local function betterOffer(member, slot, delta)
    local bestBy, best
    for crafter, offers in pairs(FG.craftOffers) do
        if crafter ~= UnitName("player") then
            local o = offers[member .. ":" .. slot]
            if o and o.delta > delta and (not best or o.delta > best.delta) then bestBy, best = crafter, o end
        end
    end
    return bestBy, best
end

-- { { id, name, prof, diff, who = { {name, delta, note} }, best, reagents, ready } } sorted by best upgrade.
-- If another party crafter can make something better for that person and slot and has the
-- materials, it's left off; if they don't have the materials yet, it stays as a stopgap.
function FG:CraftUpgrades()
    if ForeverGuideDB.craftHelper == false then return {} end
    if self.craftCache and GetTime() - self.craftCache.t < 10 then return self.craftCache.list end
    local out = {}
    local people = members()
    for prof, list in pairs(ForeverGuideCharDB.recipes or {}) do
        if GEAR_PROFESSIONS[prof] and self:SkillRank(prof) then
            for id, r in pairs(list) do
                local who, best = {}, 0
                for _, m in ipairs(people) do
                    local delta = self:UpgradeDelta(id, m.class, m.level, m.gear, m.className, m.raceName)
                    if delta and delta >= MIN_GAIN then
                        local slot = slotOf(id)
                        local by, offer = nil, nil
                        if slot then by, offer = betterOffer(m.name, slot, delta) end
                        if offer and offer.ready then
                            -- someone else can make a better one right now: skip
                        else
                            local note = offer and ("stopgap: %s's craft is better once they have materials"):format(by)
                            table.insert(who, { m.name, delta, note })
                            if delta > best then best = delta end
                        end
                    elseif C_Item and C_Item.RequestLoadItemDataByID and not self:ItemInfo(id) then
                        C_Item.RequestLoadItemDataByID(id)
                    end
                end
                if #who > 0 then
                    table.sort(who, function(a, b) return a[2] > b[2] end)
                    local ready = true
                    for _, g in ipairs(r.reagents) do
                        if self:ItemCount(g.id) < g.count then ready = false end
                    end
                    table.insert(out, { id = id, name = r.name, prof = prof, diff = r.diff, who = who, best = best,
                                        reagents = r.reagents, ready = ready })
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.best > b.best end)
    self.craftCache = { t = GetTime(), list = out }
    local sig = {}
    for _, u in ipairs(out) do table.insert(sig, u.id .. (u.ready and "r" or "")) end
    sig = table.concat(sig, ",")
    if sig ~= self.craftSig then
        self.craftSig = sig; self.keepList = nil
        if self.BroadcastCraftOffers then C_Timer.After(1, function() self:BroadcastCraftOffers() end) end
    end
    return out
end

-- Our best offer per person and slot, for the party: "Name:slot:itemID:delta:ready"
function FG:CraftOfferEntries()
    local best = {}
    for _, u in ipairs(self:CraftUpgrades()) do
        local slot = slotOf(u.id)
        if slot then
            for _, w in ipairs(u.who) do
                local k = w[1] .. ":" .. slot
                if not best[k] or w[2] > best[k].delta then best[k] = { id = u.id, delta = w[2], ready = u.ready } end
            end
        end
    end
    local out = {}
    for k, o in pairs(best) do
        table.insert(out, ("%s:%d:%d:%d"):format(k, o.id, math.floor(o.delta + 0.5), o.ready and 1 or 0))
    end
    return out
end

function FG:SetCraftOffers(crafter, text)
    local offers = {}
    for name, slot, id, delta, ready in (text or ""):gmatch("([^:;]+):(%d+):(%d+):(%d+):(%d)") do
        offers[name .. ":" .. slot] = { id = tonumber(id), delta = tonumber(delta), ready = ready == "1" }
    end
    self.craftOffers[crafter] = next(offers) and offers or nil
    self.craftCache = nil
end

---------------------------------------------------------------------------
-- Crafting guide: the cheapest recipe that still gives skill, from your own
-- (Forever) recipes, and roughly how much material it takes to reach a goal.
---------------------------------------------------------------------------
local POINTS = { optimal = 1, medium = 0.6, easy = 0.25 }
local DIFF_WORD = { optimal = "orange", medium = "yellow", easy = "green" }

-- Base materials for one craft, expanding intermediates you also make (e.g. bolts -> cloth)
local function baseMats(recipes, r, mult, into, depth)
    for _, g in ipairs(r.reagents) do
        local sub = recipes[g.id]
        if sub and depth < 2 and #sub.reagents > 0 then
            baseMats(recipes, sub, mult * g.count, into, depth + 1)
        else
            local m = into[g.id] or { id = g.id, name = g.name, count = 0 }
            m.count = m.count + g.count * mult
            into[g.id] = m
        end
    end
    return into
end

-- Advice for a profession up to a goal skill:
-- { rank, goal, recipe, diff, perCraft = { mats }, need = { mats for the whole climb } } or { learn = true }
function FG:LevelingAdvice(prof, goal, recipes, rank)
    recipes = recipes or (ForeverGuideCharDB.recipes and ForeverGuideCharDB.recipes[prof])
    rank = rank or self:SkillRank(prof)
    if not (recipes and rank) or rank >= goal then return nil end
    local best, bestCost
    for id, r in pairs(recipes) do
        local pts = POINTS[r.diff]
        if pts then
            local mats = baseMats(recipes, r, 1, {}, 0)
            local cost = 0
            for _, m in pairs(mats) do cost = cost + m.count end
            cost = cost / pts
            if not bestCost or cost < bestCost or (cost == bestCost and r.diff == "optimal") then
                best, bestCost = { id = id, recipe = r.name, diff = r.diff, perCraft = mats, pts = pts }, cost
            end
        end
    end
    if not best then return { rank = rank, goal = goal, learn = true } end
    local crafts = math.ceil((goal - rank) / best.pts)
    local need = {}
    for id, m in pairs(best.perCraft) do need[id] = { id = id, name = m.name, count = m.count * crafts } end
    best.rank, best.goal, best.need, best.crafts = rank, goal, need, crafts
    return best
end

local function matsText(mats)
    local t = {}
    for _, m in pairs(mats) do table.insert(t, ("%d %s"):format(math.ceil(m.count), m.name or ("item " .. m.id))) end
    table.sort(t)
    return table.concat(t, ", ")
end
FG.MatsText = matsText

-- Training cap from character level (Apprentice / Journeyman / Expert / Artisan)
function FG:SkillCapForLevel(level)
    if (level or 1) >= 35 then return 300 elseif level >= 20 then return 225 elseif level >= 10 then return 150 end
    return 75
end

-- Goal for a crafting profession on this character: the bag plan for the
-- tailoring alt, otherwise the most this character can train right now
function FG:CraftGoal(prof)
    if prof == "Tailoring" and self.BagAltGoal then
        local g = self:BagAltGoal()
        if g then return g end
    end
    local rank, maxRank = self:SkillInfo(prof)
    if not rank then return nil end
    return math.min(maxRank or 75, self:SkillCapForLevel(UnitLevel("player")))
end

function FG:CraftGuideLine()
    if ForeverGuideDB.craftHelper == false then return nil end
    for prof in pairs(ForeverGuideCharDB.recipes or {}) do
        if GEAR_PROFESSIONS[prof] then
            local goal = self:CraftGoal(prof)
            local a = goal and self:LevelingAdvice(prof, goal)
            if a and a.learn then
                return ("|cff66ccff%s %d/%d:|r nothing gives skill - learn new recipes at your trainer"):format(prof, a.rank, a.goal)
            elseif a then
                return ("|cff66ccff%s %d/%d:|r make %s (%s) - about %s to %d |cff888888(/fg craftguide)|r"):format(
                    prof, a.rank, a.goal, a.recipe, DIFF_WORD[a.diff] or a.diff, matsText(a.need), a.goal)
            end
        end
    end
end

function FG:PrintCraftGuide()
    local any = false
    for prof, recipes in pairs(ForeverGuideCharDB.recipes or {}) do
        if GEAR_PROFESSIONS[prof] then
            local goal = self:CraftGoal(prof)
            local a = goal and self:LevelingAdvice(prof, goal)
            if a then
                any = true
                if a.learn then
                    self:Print(("%s %d/%d: nothing you know gives skill - visit your trainer for new recipes."):format(prof, a.rank, a.goal))
                else
                    self:Print(("%s %d -> %d: make |cffffffff%s|r (%s), about %d crafts"):format(prof, a.rank, a.goal, a.recipe, DIFF_WORD[a.diff], a.crafts))
                    self:Print("   each: " .. matsText(a.perCraft) .. "   total: " .. matsText(a.need))
                    self:Print("   |cff888888Recipe colors change as you level - reopen the window to refresh. Estimates assume you keep crafting the cheapest skill-up.|r")
                end
            end
        end
    end
    if not any then self:Print("No crafting profession to level here (or open its window once so I can read your recipes).") end
end

-- Forever's reagents for something you can make (from your profession window), or nil
function FG:RecipeReagents(id)
    for _, list in pairs(ForeverGuideCharDB and ForeverGuideCharDB.recipes or {}) do
        if list[id] then return list[id].reagents end
    end
end

function FG:ReagentText(reagents)
    local t = {}
    for _, g in ipairs(reagents) do table.insert(t, (g.count > 1 and (g.count .. "x ") or "") .. (g.name or ("item " .. g.id))) end
    return table.concat(t, ", ")
end

-- Materials to keep for upgrade crafts: [itemID] = reason
function FG:CraftKeepItems()
    local keep = {}
    for _, u in ipairs(self:CraftUpgrades()) do
        for _, g in ipairs(u.reagents) do
            keep[g.id] = keep[g.id] or ("craft %s for %s"):format(u.name, u.who[1][1])
        end
    end
    return keep
end

-- What party members carry of the materials crafters want: [member] = { [itemID] = count }
FG.partyHave = {}

local function partyHolding(id)
    local total, who = 0, {}
    for name, have in pairs(FG.partyHave) do
        local n = have[id] or 0
        if n > 0 then total = total + n; table.insert(who, { name, n }) end
    end
    return total, who
end

-- Materials still missing for upgrades you can't make yet (after what the party already carries):
-- { { id, name, need, have, crafts = n, best = { who, delta } } } sorted by best upgrade
function FG:CraftShopping()
    local want = {}
    for _, u in ipairs(self:CraftUpgrades()) do
        if not u.ready then
            for _, g in ipairs(u.reagents) do
                local w = want[g.id] or { id = g.id, name = g.name, need = 0, crafts = 0 }
                w.need = w.need + g.count
                w.crafts = w.crafts + 1
                if not w.best or u.who[1][2] > w.best[2] then w.best = { u.who[1][1], u.who[1][2], u.name } end
                want[g.id] = w
            end
        end
    end
    local out = {}
    for id, w in pairs(want) do
        w.own = self:ItemCount(id)
        w.party, w.holders = partyHolding(id)
        w.have = w.own + w.party
        if w.own < w.need then table.insert(out, w) end
    end
    table.sort(out, function(a, b) return a.best[2] > b.best[2] end)
    return out
end

-- Who can gather an item: "skin" / "herb" / "mine", or nil (drops, cloth, vendors)
-- Trade Goods subclasses: 5 cloth, 6 leather, 7 metal & stone, 9 herb
local GATHER = { [6] = { "Skinning", "skin" }, [7] = { "Mining", "mine" }, [9] = { "Herbalism", "pick" } }
function FG:GatherSkillFor(id)
    local classID, subclassID = select(12, self:ItemInfo(id))
    if classID == 7 and GATHER[subclassID] then return GATHER[subclassID][1], GATHER[subclassID][2] end
end

-- Guide window line
function FG:CraftLine()
    local lines = {}
    local ups = self:CraftUpgrades()
    local ready = 0
    for _, u in ipairs(ups) do if u.ready then ready = ready + 1 end end
    if ready > 0 then
        table.insert(lines, ("|cff66ccffCraft:|r %d party upgrade(s) ready to make - |cffffffff/fg craft|r"):format(ready))
    end
    -- what you still need to gather for the rest
    local shop = self:CraftShopping()
    if #shop > 0 then
        local t, held = {}, {}
        for _, w in ipairs(shop) do
            if w.have < w.need and #t < 3 then table.insert(t, ("%d %s"):format(w.need - w.have, w.name or "?")) end
            for _, h in ipairs(w.holders) do
                if #held < 3 then table.insert(held, ("%s %d %s"):format(h[1], math.min(h[2], w.need - w.own), w.name or "?")) end
            end
        end
        if #t > 0 then
            table.insert(lines, ("|cff66ccffGather for upgrades:|r %s |cff888888(/fg craft)|r"):format(table.concat(t, ", ")))
        end
        if #held > 0 then
            table.insert(lines, ("|cff66ccffParty has:|r %s |cff888888- ask for a trade|r"):format(table.concat(held, ", ")))
        end
    end
    -- what party crafters are waiting on that you could gather
    for crafter, list in pairs(self.partyGather or {}) do
        for _, g in ipairs(list) do
            local skill, verb = self:GatherSkillFor(g.id)
            local mine = skill and self:SkillRank(skill)
            local name = (self:ItemInfo(g.id)) or ("item " .. g.id)
            local carrying = self:ItemCount(g.id)
            if carrying > 0 then
                table.insert(lines, ("|cff4da6ffTrade to %s:|r you have %d %s -> %s +%d"):format(crafter, carrying, name, g.who, g.delta))
            end
            if g.count > 0 and (not skill or mine) then
                table.insert(lines, ("|cff4da6ffGather for %s:|r %d %s%s -> %s +%d"):format(crafter, g.count, name,
                    mine and (" (you can " .. verb .. " it)") or "", g.who, g.delta))
            end
            if #lines >= 6 then break end
        end
    end
    if #lines == 0 then return nil end
    return table.concat(lines, "\n")
end

-- Shared with the party: "itemID:count:who:delta;..." (biggest upgrades first)
function FG:CraftGatherEntries()
    local out = {}
    for i, w in ipairs(self:CraftShopping()) do
        if i > 8 then break end
        table.insert(out, ("%d:%d:%s:%d"):format(w.id, math.max(0, w.need - w.have), w.best[1], math.floor(w.best[2] + 0.5)))
    end
    return out
end

-- Items any party crafter is asking for
local function wantedIDs()
    local ids = {}
    for _, list in pairs(FG.partyGather or {}) do
        for _, g in ipairs(list) do ids[g.id] = true end
    end
    return ids
end

-- What we carry of those: "itemID:count;..." (sent by Group.lua as "H")
function FG:HaveEntries()
    local out = {}
    for id in pairs(wantedIDs()) do table.insert(out, ("%d:%d"):format(id, self:ItemCount(id))) end
    table.sort(out)
    return out
end

function FG:SetPartyHave(member, text)
    local have = {}
    for id, n in (text or ""):gmatch("(%d+):(%d+)") do have[tonumber(id)] = tonumber(n) end
    self.partyHave[member] = next(have) and have or nil
    self.craftCache = nil
    -- re-share what's still missing so everyone's counts update
    if self.BroadcastCraftOffers and not self.gatherPending then
        self.gatherPending = true
        C_Timer.After(2, function() self.gatherPending = false; self:BroadcastCraftOffers() end)
    end
    if self.UpdateUI then self:UpdateUI() end
end

function FG:SetPartyGather(crafter, text)
    local list = {}
    for id, count, who, delta in (text or ""):gmatch("(%d+):(%d+):([^:;]+):(%d+)") do
        table.insert(list, { id = tonumber(id), count = tonumber(count), who = who, delta = tonumber(delta) })
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(tonumber(id)) end
    end
    self.partyGather = self.partyGather or {}
    self.partyGather[crafter] = #list > 0 and list or nil
    if self.SendHave then self:SendHave() end   -- tell the crafter what we already carry
    if self.UpdateUI then self:UpdateUI() end
end

local function printShopping(self)
    local shop = self:CraftShopping()
    if #shop == 0 then return end
    self:Print("To gather (for the upgrades you can't make yet):")
    for _, w in ipairs(shop) do
        local _, verb = self:GatherSkillFor(w.id)
        self:Print(("  |cffffffff%d %s|r (have %d of %d)%s - best: %s for %s +%d"):format(w.need - w.have, w.name or "?", w.have, w.need,
            verb and (" |cff888888[" .. verb .. "]|r") or "", w.best[3], w.best[1], math.floor(w.best[2] + 0.5)))
    end
end

function FG:PrintCraftPlan()
    local known = ForeverGuideCharDB.recipes or {}
    if not next(known) then
        self:Print("Open your Leatherworking / Tailoring / Blacksmithing / Engineering window once so I can read your recipes.")
        return
    end
    local ups = self:CraftUpgrades()
    if #ups == 0 then
        self:Print("Nothing you can make right now is an upgrade for the party. (Party gear comes from members running ForeverGuide.)")
        return
    end
    self:Print("Crafts that would upgrade someone (best first):")
    for i, u in ipairs(ups) do
        if i > 12 then self:Print(("  ...and %d more"):format(#ups - 12)) break end
        local who = {}
        local notes = {}
        for _, w in ipairs(u.who) do
            table.insert(who, ("%s +%d"):format(w[1], math.floor(w[2] + 0.5)))
            if w[3] then table.insert(notes, w[1] .. ": " .. w[3]) end
        end
        local mats = {}
        for _, g in ipairs(u.reagents) do
            local have = self:ItemCount(g.id)
            local col = have >= g.count and "|cff40c040" or "|cffff6060"
            table.insert(mats, ("%s%d/%d|r %s"):format(col, math.min(have, g.count), g.count, g.name or ("item " .. g.id)))
        end
        self:Print(("  %s%s|r -> %s  |cff888888[%s]|r"):format(SKILL_COLOR[u.diff] or "|cffffffff", u.name,
            table.concat(who, ", "), SKILL_WORD[u.diff] or u.diff or "?"))
        self:Print("      " .. table.concat(mats, ", ") .. (u.ready and "  |cff40c040ready|r" or ""))
        for _, n in ipairs(notes) do self:Print("      |cff888888" .. n .. "|r") end
    end
    printShopping(self)
end

---------------------------------------------------------------------------
-- Profession trainer: glow recipes that make a party upgrade
---------------------------------------------------------------------------
local function trainerUpgrade(index)
    local link = GetTrainerServiceItemLink and GetTrainerServiceItemLink(index)
    local id = itemID(link)
    if not id then return nil end
    local bestName, best
    for _, m in ipairs(members()) do
        local delta = FG:UpgradeDelta(id, m.class, m.level, m.gear, m.className, m.raceName)
        if delta and delta >= MIN_GAIN and (not best or delta > best) then bestName, best = m.name, delta end
    end
    return bestName, best
end

function FG:UpdateTrainerGlow()
    for i = 1, 30 do
        local b = _G["ClassTrainerSkill" .. i]
        if not b then break end
        self:HideGlow(b)
        if ForeverGuideDB.craftHelper ~= false and ForeverGuideDB.glow ~= false and b:IsShown()
           and IsTradeskillTrainer and IsTradeskillTrainer() then
            local index = b.GetID and b:GetID()
            if index and index > 0 and trainerUpgrade(index) then self:ShowGlow(b) end
        end
    end
end

local announceTrainer
function FG:AnnounceTrainerUpgrades() return announceTrainer() end
announceTrainer = function()
    if ForeverGuideDB.craftHelper == false or not (IsTradeskillTrainer and IsTradeskillTrainer()) then return end
    if not GetNumTrainerServices then return end
    for i = 1, GetNumTrainerServices() do
        local name, _, kind = GetTrainerServiceInfo(i)
        if kind == "available" then
            local who, delta = trainerUpgrade(i)
            if who then FG:Print(("Trainer: |cffffffff%s|r makes an upgrade for %s (+%d)"):format(name, who, math.floor(delta + 0.5))) end
        end
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local hooked = false
local ev = CreateFrame("Frame")
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRAINER_SHOW", "ADDON_LOADED",
                     "GET_ITEM_INFO_RECEIVED", "BAG_UPDATE_DELAYED", "UNIT_INVENTORY_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, arg)
    if event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" then
        FG:ScanTradeSkill()
    elseif event == "TRAINER_SHOW" then
        C_Timer.After(0.2, function() announceTrainer(); FG:UpdateTrainerGlow() end)
    elseif event == "ADDON_LOADED" then
        if (arg == "Blizzard_TrainerUI" or _G.ClassTrainerFrame) and not hooked and _G.ClassTrainerFrame_Update then
            hooksecurefunc("ClassTrainerFrame_Update", function() FG:UpdateTrainerGlow() end)
            hooked = true
        end
        return
    else
        FG.craftCache = nil
        -- loot changes what's still missing: refresh the party's gather list (throttled)
        if event == "BAG_UPDATE_DELAYED" then
            if not FG.havePending and FG.SendHave then
                FG.havePending = true
                C_Timer.After(2, function() FG.havePending = false; FG:SendHave() end)
            end
            if not FG.gatherPending and FG.BroadcastCraftOffers then
                FG.gatherPending = true
                C_Timer.After(3, function() FG.gatherPending = false; FG:BroadcastCraftOffers() end)
            end
        end
    end
end)
