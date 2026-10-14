-- Cloth: where cloth goes - your Tailoring (bank) alt for party bags, or
-- First Aid. Two tiers, and only what the alt's CHARACTER level can reach:
--   1. Red Linen Bag (8 slots, Tailoring ~70 - Apprentice, any level):
--      Linen goes to the alt until it can level there and make one for every
--      party bag slot under 8. Then Linen goes to First Aid.
--   2. Small Silk Pack (10 slots, Tailoring 150 - Journeyman, level 10+):
--      once the alt is level 10, Wool goes to it for Tailoring 75-150 and Silk
--      for the packs (one per slot under 10). Before that, nobody gathers for it.
-- The alt is the character you mark with /fg bagalt - opt-in, so only the
-- person who sets it up has a bag plan (a friend's tailor never competes). When it logs in,
-- its level, skill, cloth (bags + bank) and Tailoring recipes are saved
-- account-wide, so the materials come from Forever's real recipes. Party
-- members share bag sizes; the character that knows the alt shares the plan.
-- /fg cloth shows it; /fg cloth bags|firstaid|auto overrides tier 1.
local _, FG = ...

local LINEN, WOOL, SILK = 2589, 2592, 4306
local BOLT = { [2996] = { LINEN, 2 }, [2997] = { WOOL, 3 }, [4305] = { SILK, 4 } }   -- fallback if the bolt recipe isn't read
local RED_LINEN_BAG, LINEN_BAG, SMALL_SILK_PACK = 5762, 4238, 4245
local TIERS = {
    { key = "small", bag = RED_LINEN_BAG, size = 8,  skill = 70,  cloth = LINEN, perBag = { [LINEN] = 6 },
      levelCloth = LINEN, name = "Red Linen Bag" },
    { key = "big",   bag = SMALL_SILK_PACK, size = 10, skill = 150, cloth = SILK, perBag = { [SILK] = 12 },
      levelCloth = WOOL, name = "Small Silk Pack" },
}
-- Rough cloth to level when the alt's recipes haven't been read yet
local FALLBACK_LEVELING = { small = { { 0, 110 }, { 25, 85 }, { 45, 50 }, { 60, 20 }, { 70, 0 } },
                            big = { { 0, 180 }, { 75, 160 }, { 100, 110 }, { 125, 60 }, { 150, 0 } } }

local function count(id, bank)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id, bank) or 0 end
    return GetItemCount and (GetItemCount(id, bank) or 0) or 0
end

---------------------------------------------------------------------------
-- Bag sizes (shared with the party by Group.lua)
---------------------------------------------------------------------------
function FG:BagSizes()
    local sizes = {}
    local num = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    for bag = 1, 4 do sizes[bag] = num and (num(bag) or 0) or 0 end
    return sizes
end

FG.partyBags = {}   -- [name] = { size, size, size, size }

function FG:SetPartyBags(name, text)
    local sizes = {}
    for n in (text or ""):gmatch("(%d+)") do table.insert(sizes, tonumber(n)) end
    self.partyBags[name] = #sizes > 0 and sizes or nil
end

-- Party bag slots smaller than `size`: total, { name = n }
local function slotsUnder(size)
    local total, by = 0, {}
    local function add(name, sizes)
        local n = 0
        for i = 1, 4 do if (sizes[i] or 0) < size then n = n + 1 end end
        if n > 0 then by[name] = n; total = total + n end
    end
    add(UnitName("player"), FG:BagSizes())
    for name, sizes in pairs(FG.partyBags) do add(name, sizes) end
    return total, by
end

---------------------------------------------------------------------------
-- The tailoring alt (saved account-wide when it logs in)
---------------------------------------------------------------------------
local function recordAlt()
    local skill = FG:SkillRank("Tailoring")
    if not skill then return end
    local me = UnitName("player")
    local chosen = ForeverGuideDB.bagAltName
    if chosen == false then return end                       -- bag plan turned off
    if chosen and chosen ~= me then return end               -- another character is the bag alt
    if not chosen then return end   -- opt-in: no bag plan until /fg bagalt is run on the tailor
    local alt = {
        name = UnitName("player"), skill = skill, level = UnitLevel("player"),
        cloth = {}, bags = {},
        recipes = ForeverGuideCharDB.recipes and ForeverGuideCharDB.recipes["Tailoring"],
    }
    for _, id in ipairs({ LINEN, WOOL, SILK }) do alt.cloth[id] = count(id, true) end
    for bolt, b in pairs(BOLT) do alt.cloth[b[1]] = alt.cloth[b[1]] + b[2] * count(bolt, true) end
    for _, t in ipairs(TIERS) do alt.bags[t.key] = count(t.bag, true) + (t.key == "small" and count(LINEN_BAG, true) or 0) end
    ForeverGuideDB.bagAlt = alt
end
function FG:RecordBagAlt() recordAlt() end

-- Cloth in one bag of a tier: from the alt's real recipe if read, bolts expanded
local function clothPerBag(t, alt)
    local r = alt.recipes and alt.recipes[t.bag]
    if not r then return t.perBag[t.cloth] end
    local n = 0
    for _, g in ipairs(r.reagents) do
        if g.id == t.cloth then n = n + g.count
        else
            local sub = alt.recipes[g.id]
            local b = BOLT[g.id]
            if sub then
                for _, s in ipairs(sub.reagents) do if s.id == t.cloth then n = n + s.count * g.count end end
            elseif b and b[1] == t.cloth then n = n + b[2] * g.count end
        end
    end
    return n > 0 and n or t.perBag[t.cloth]
end

-- Cloth the alt needs to level to a tier's skill
local function clothToLevel(t, alt)
    if alt.skill >= t.skill then return 0, "done" end
    if alt.recipes and FG.LevelingAdvice then
        local a = FG:LevelingAdvice("Tailoring", t.skill, alt.recipes, alt.skill)
        if a and a.need and a.need[t.levelCloth] then return math.ceil(a.need[t.levelCloth].count), "recipes" end
    end
    local need = 0
    for _, s in ipairs(FALLBACK_LEVELING[t.key]) do if alt.skill >= s[1] then need = s[2] end end
    return need, "estimate"
end

-- Full plan: { alt, tiers = { { t, reachable, levelNeed, bags, perBag, need = { [cloth] = n }, by } } }
function FG:ClothPlan()
    local alt = ForeverGuideDB.bagAltName ~= false and ForeverGuideDB.bagAlt
    if not alt then return nil end
    local plan = { alt = alt, tiers = {} }
    local cap = self:SkillCapForLevel(alt.level or 1)
    local prevCovered = true
    for _, t in ipairs(TIERS) do
        local e = { t = t, reachable = cap >= t.skill, need = {} }
        local slots, by = slotsUnder(t.size)
        e.by = by
        e.bags = math.max(0, slots - (alt.bags and alt.bags[t.key] or 0))
        e.perBag = clothPerBag(t, alt)
        e.levelNeed, e.source = clothToLevel(t, alt)
        if e.reachable and prevCovered then
            local function add(id, n) if n > 0 then e.need[id] = (e.need[id] or 0) + n end end
            add(t.levelCloth, e.levelNeed)
            add(t.cloth, e.bags * e.perBag)
            for id, n in pairs(e.need) do e.need[id] = math.max(0, n - (alt.cloth[id] or 0)) end
            for id, n in pairs(e.need) do if n == 0 then e.need[id] = nil end end
            e.active = next(e.need) ~= nil
        end
        -- tier 2 only starts once tier 1 is covered (or doesn't apply)
        prevCovered = prevCovered and not e.active
        table.insert(plan.tiers, e)
    end
    -- manual override for Linen (tier 1)
    local o = ForeverGuideDB.clothPhase
    if o == "firstaid" then plan.tiers[1].active = false; plan.tiers[1].need = {} end
    if o == "bags" and not plan.tiers[1].active then
        plan.tiers[1].active = true; plan.tiers[1].need[LINEN] = plan.tiers[1].need[LINEN] or 0
    end
    return plan
end

-- Tailoring goal for the alt itself (used by the crafting guide on the alt)
function FG:BagAltGoal()
    local alt = ForeverGuideDB.bagAlt
    if not (alt and alt.name == UnitName("player")) then return nil end
    local cap = self:SkillCapForLevel(UnitLevel("player"))
    local goal
    for _, t in ipairs(TIERS) do if cap >= t.skill then goal = t.skill end end
    return goal
end

-- { [clothID] = { need, tierName } } for what the alt still wants
local function wanted(plan)
    local w = {}
    for _, e in ipairs(plan.tiers) do
        if e.active then
            for id, n in pairs(e.need) do w[id] = { n, e.t.name, e.t.levelCloth == id and e.levelNeed > 0 } end
        end
    end
    return w
end

-- Shared plan from the party member who knows the alt: { alt, [cloth] = { need, tier } }
FG.sharedCloth = nil
function FG:SetSharedCloth(sender, alt, text)
    local s = { from = sender, alt = alt }
    for id, n, tier in (text or ""):gmatch("(%d+):(%d+):([^;]+)") do s[tonumber(id)] = { tonumber(n), tier } end
    self.sharedCloth = s
    self.keepList = nil
end

-- "L" message: alt, "clothID:need:tier;..."
function FG:ClothEncode()
    local plan = self:ClothPlan()
    if not plan then return nil end
    local parts = {}
    for id, w in pairs(wanted(plan)) do table.insert(parts, ("%d:%d:%s"):format(id, w[1], w[2])) end
    table.sort(parts)
    return plan.alt.name, table.concat(parts, ";")
end

-- Where a cloth goes: reason string and whether it's for the alt
function FG:ClothReason(id)
    local alt, want
    local plan = ForeverGuideDB.bagAlt and self:ClothPlan()
    if plan then
        alt = plan.alt.name
        local w = wanted(plan)[id]
        if w then want = { w[1], w[2] } end
    elseif self.sharedCloth then
        alt = self.sharedCloth.alt
        want = self.sharedCloth[id]
    end
    local name = ({ [LINEN] = "Linen Cloth", [WOOL] = "Wool Cloth", [SILK] = "Silk Cloth" })[id] or "cloth"
    if want then
        return ("Tailoring: send to %s for %ss (%d more %s needed)"):format(alt or "the bag alt", want[2], want[1], name), true
    end
    return "First Aid: " .. name .. " for bandages", false
end
function FG:LinenReason() return (self:ClothReason(LINEN)) end

---------------------------------------------------------------------------
-- /fg cloth and the guide window line
---------------------------------------------------------------------------
local CLOTH_NAME = { [LINEN] = "Linen", [WOOL] = "Wool", [SILK] = "Silk" }

-- /fg bagalt [none]: choose which character is the tailoring bag alt
function FG:BagAltCommand(rest)
    rest = (rest or ""):lower()
    if rest == "none" or rest == "off" then
        ForeverGuideDB.bagAltName = false
        ForeverGuideDB.bagAlt = nil
        self.keepList = nil
        self:Print("Bag plan turned off - all cloth goes to First Aid. /fg bagalt on your tailor turns it back on.")
    else
        if not self:SkillRank("Tailoring") then
            self:Print("This character doesn't have Tailoring - run /fg bagalt on your tailoring alt.")
            return
        end
        ForeverGuideDB.bagAltName = UnitName("player")
        ForeverGuideDB.bagAlt = nil
        recordAlt()
        self.keepList = nil
        self:Print(UnitName("player") .. " is now your bag alt. Only this character updates the bag plan.")
    end
    if self.BroadcastGroupInfo then self:BroadcastGroupInfo(true) end
end

function FG:ClothCommand(rest)
    rest = (rest or ""):lower()
    if rest == "bags" or rest == "firstaid" or rest == "auto" then
        ForeverGuideDB.clothPhase = rest
        self:Print("Linen phase: " .. rest)
        self.keepList = nil
        if self.BroadcastGroupInfo then self:BroadcastGroupInfo(true) end
        return
    end
    local plan = self:ClothPlan()
    if not plan then
        local s = self.sharedCloth
        if s then
            for _, id in ipairs({ LINEN, WOOL, SILK }) do
                if s[id] then self:Print(("%s: send to %s for %ss - %d more needed (plan from %s)"):format(CLOTH_NAME[id], s.alt, s[id][2], s[id][1], s.from)) end
            end
            self:Print("Any cloth not listed goes to First Aid.")
        else
            self:Print("No tailoring alt seen yet. Log in on your Tailoring alt once (with this addon) so I can track the bag plan.")
        end
        return
    end
    local alt = plan.alt
    self:Print(("Bag alt: %s, level %d, Tailoring %d (can train up to %d at this level)"):format(alt.name, alt.level or 1, alt.skill, self:SkillCapForLevel(alt.level or 1)))
    self:Print(("  Has: %d Linen, %d Wool, %d Silk (bags + bank, bolts counted as cloth)"):format(alt.cloth[LINEN] or 0, alt.cloth[WOOL] or 0, alt.cloth[SILK] or 0))
    for i, e in ipairs(plan.tiers) do
        local t = e.t
        local head = ("%d. %s (%d slots, Tailoring %d):"):format(i, t.name, t.size, t.skill)
        if not e.reachable then
            self:Print(head .. (" |cffff8040waits until %s is level %d|r - no gathering for it yet"):format(alt.name, t.skill <= 150 and 10 or 20))
        elseif e.active then
            local parts = {}
            for id, n in pairs(e.need) do table.insert(parts, n .. " " .. CLOTH_NAME[id]) end
            self:Print(head .. " |cffffffff" .. table.concat(parts, ", ") .. " more|r")
            local who = {}
            for name, n in pairs(e.by) do table.insert(who, name .. " " .. n) end
            self:Print(("     leveling: %s (%s)  |  %d bags x %d %s  |  slots under %d: %s"):format(
                e.levelNeed > 0 and (e.levelNeed .. " " .. CLOTH_NAME[t.levelCloth]) or "done",
                e.source == "recipes" and "from the alt's recipes" or "estimate", e.bags, e.perBag, CLOTH_NAME[t.cloth], t.size,
                #who > 0 and table.concat(who, ", ") or "none"))
        elseif i > 1 and plan.tiers[i - 1].active then
            self:Print(head .. " after tier " .. (i - 1))
        else
            self:Print(head .. " |cff40c040covered|r")
        end
    end
    self:Print("Cloth not needed above goes to First Aid." .. (ForeverGuideDB.clothPhase and ForeverGuideDB.clothPhase ~= "auto"
        and " (Linen set by hand - /fg cloth auto to undo)" or ""))
    if not alt.recipes then self:Print("|cff888888Open the Tailoring window on the alt once to use Forever's real recipes.|r") end
end

function FG:ClothLine()
    local lines = {}
    for _, id in ipairs({ LINEN, WOOL, SILK }) do
        local reason, forAlt = self:ClothReason(id)
        if forAlt then table.insert(lines, "|cffd0a060" .. CLOTH_NAME[id] .. ":|r " .. reason:gsub("^Tailoring: ", "") .. " |cff888888(/fg cloth)|r") end
    end
    return #lines > 0 and table.concat(lines, "\n") or nil
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("BANKFRAME_OPENED")
ev:RegisterEvent("SKILL_LINES_CHANGED")
ev:RegisterEvent("TRADE_SKILL_UPDATE")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(3, recordAlt)
    elseif FG.SkillRank and FG:SkillRank("Tailoring") then
        C_Timer.After(0.5, recordAlt)
    end
end)
