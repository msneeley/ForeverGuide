-- Secondary professions (First Aid, Cooking, Fishing): level them as you go
-- so you never have to come back. The window shows where each one should
-- be for your level, chat warns when the next cloth tier starts dropping,
-- and you're told when to train the next rank (and where, on this route).
-- Nothing here ever stops the guide.
local _, FG = ...

-- { by level, skill target, why } - targets are where you want to be at that
-- level so the materials dropping around you still give skill-ups.
FG.secondaryPlan = {
    ["First Aid"] = {
        { 6,  40,  "Linen Bandages" },
        { 12, 80,  "Heavy Linen up to 80 before wool shows up" },
        { 18, 115, "Wool Bandages while wool drops" },
        { 24, 150, "Heavy Wool to 150 before silk shows up" },
        { 30, 180, "Silk Bandages (needs Expert First Aid)" },
        { 35, 210, "Heavy Silk Bandages - Expert First Aid book: Balai Lok'Wein, Brackenwall Village (Dustwallow)" },
    },
    ["Cooking"] = {
        { 8,  25,  "Charred / Spiced Wolf Meat" },
        { 14, 60,  "Barrens meats: plainstrider, zhevra, raptor, lion" },
        { 22, 90,  "90 = Journeyman Campfire Kit (5 camp objects)" },
        { 30, 125, "Expert Cookbook (Desolace) needed past 150" },
        { 35, 150, "150 cap until the Expert Cookbook (Wulan, Shadowprey Village, Desolace)" },
    },
    ["Fishing"] = {
        { 12, 50,  "Fish whenever the group waits on respawns" },
        { 20, 100, "Barrens oases, Thunder Bluff and Orgrimmar water" },
        { 30, 150, "Expert Fishing is a book in Booty Bay (needs 125)" },
        { 35, 200, "Buy Expert Fishing - The Bass and You from Old Man Heming in Booty Bay (route passes at ~31)" },
    },
}

-- Cloth tiers and the First Aid skill you want before each starts dropping
FG.clothWarnings = {
    { level = 15, text = "Wool Cloth starts dropping from humanoids now. First Aid should be 80+ (Wool Bandage) so you don't stockpile it." },
    { level = 23, text = "Silk Cloth starts dropping soon. First Aid should be close to 150 (Heavy Wool) - you'll need Expert First Aid for silk." },
}

-- Rank trainers on this route
local TRAINERS = {
    ["First Aid"] = "Vira Younghoof (Bloodhoof), Arnok (Orgrimmar, Valley of Spirits), Pand Stonebinder (Thunder Bluff)",
    ["Cooking"]   = "Pyall Silentstride (Bloodhoof), Duhng (Crossroads), Zamja (Orgrimmar), Aska Mistrunner (Thunder Bluff)",
    ["Fishing"]   = "Uthan Stillwater (Bloodhoof), Lumak (Orgrimmar, Valley of Honor), Kah Mistrunner (Thunder Bluff)",
}

-- rank, maxRank for a skill line, or nil if not learned
function FG:SkillInfo(name)
    if GetNumSkillLines then
        for i = 1, GetNumSkillLines() do
            local skillName, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
            if not isHeader and skillName == name then return rank, maxRank end
        end
    end
    local rank = self:SkillRank(name)
    if rank then return rank, nil end
end

-- Target for a skill at the player's level, rising smoothly between
-- milestones (from 0 at level 1), plus the reason for the next milestone
local function targetFor(plan, level)
    local prevLevel, prevTarget = 1, 0
    for _, m in ipairs(plan) do
        if level <= m[1] then
            local t = prevTarget + (m[2] - prevTarget) * (level - prevLevel) / math.max(1, m[1] - prevLevel)
            return math.floor(t + 0.5), m[3]
        end
        prevLevel, prevTarget = m[1], m[2]
    end
    local last = plan[#plan]
    return last[2], last[3]
end

-- Where the next rank comes from (Journeyman is a trainer for all three)
local EXPERT = {
    ["First Aid"] = "Expert First Aid",
    ["Cooking"] = "Expert Cookbook (Wulan, Desolace)",
    ["Fishing"] = "Expert Fishing book (Old Man Heming, Booty Bay)",
}

-- One status line per learned secondary skill
function FG:SecondaryLines()
    local level, lines = UnitLevel("player"), {}
    for _, name in ipairs({ "First Aid", "Cooking", "Fishing", "Alchemy" }) do
        local rank, maxRank = self:SkillInfo(name)
        if rank then
            local target, why = targetFor(self.secondaryPlan[name], level)
            local color = rank >= target and "|cff00ff00" or (target - rank <= 15 and "|cffff8040" or "|cffff4040")
            local line = ("%s%s %d/%d|r |cff888888%s|r"):format(color, name, rank, target, why)
            if maxRank == 75 and rank >= 45 then
                line = line .. (rank >= 50 and "\n   |cffffff00Train Journeyman now|r (trainer)" or "\n   |cffffff00Journeyman at 50|r (trainer)")
            elseif maxRank == 150 and rank >= 120 then
                line = line .. ("\n   |cffffff00%s %s|r"):format(rank >= 125 and "Get now:" or "At 125:", EXPERT[name])
            end
            if name == "First Aid" and rank < 80 and self.ClothLine and self:ClothLine() then
                line = line .. "\n   |cff888888Linen goes to party bags first - bandage with what's left (/fg cloth)|r"
            end
            table.insert(lines, line)
        elseif name == "First Aid" and level >= 5 then
            table.insert(lines, "|cffff4040First Aid not learned|r |cff888888- any First Aid trainer|r")
        end
    end
    return lines
end

-- Chat heads-up once per character when a new cloth tier starts dropping
function FG:CheckClothWarnings()
    local c = ForeverGuideCharDB
    c.clothWarned = c.clothWarned or {}
    local level = UnitLevel("player")
    for _, w in ipairs(self.clothWarnings) do
        if level >= w.level and not c.clothWarned[w.level] then
            c.clothWarned[w.level] = true
            self:Print(w.text)
        end
    end
end

function FG:PrintSecondaryPlan()
    self:Print("Secondary professions - targets by level (level them as you go, never come back):")
    for _, name in ipairs({ "First Aid", "Cooking", "Fishing" }) do
        local rank = self:SkillInfo(name)
        self:Print(("  |cffffffff%s|r %s"):format(name, rank and ("(now " .. rank .. ")") or "(not learned)"))
        for _, m in ipairs(self.secondaryPlan[name]) do
            self:Print(("     by %d: %d - %s"):format(m[1], m[2], m[3]))
        end
        self:Print("     Trainers: " .. TRAINERS[name])
    end
end

---------------------------------------------------------------------------
-- Food: everyone cooks their own. Best Well Fed food per class by level
-- (all of them also give +5% XP from kills; only one food buff at a time).
-- { from level, item ID, name, buff, Cooking needed, where the recipe is }
---------------------------------------------------------------------------
-- { from level, cooked item, name, buff, Cooking needed, recipe source, raw item, raw name, how to get raw }
local MELEE = {
    { 1,  6290, "Brilliant Smallfish", "+2 attack power", 1, "Harn Longcast (Bloodhoof) / Naal Mistrunner (Thunder Bluff)",
      6291, "Raw Brilliant Smallfish", "fish any Mulgore lake" },
    { 8,  4592, "Longjaw Mud Snapper", "+10 attack power", 50, "Harn Longcast (Bloodhoof) / Naal Mistrunner (Thunder Bluff)",
      6289, "Raw Longjaw Mud Snapper", "fish Stonebull Lake, the Thunder Bluff pond, Barrens oases" },
}
FG.foodPlan = {
    SHAMAN = MELEE, ROGUE = MELEE, WARRIOR = MELEE, PALADIN = MELEE,
    DRUID = {
        { 1,  6888, "Herb Baked Egg", "+1 Stamina", 1, "Cooking trainer",
          6889, "Small Egg", "plainstriders and birds (plus Mild Spices from cooking vendors)" },
        { 12, 5479, "Crispy Lizard Tail", "+3 Stamina", 50, "Tari'qa (Crossroads)",
          5470, "Thunder Lizard Tail", "Stormsnouts and Thunderheads in the Barrens" },
    },
}
FG.FOOD_STOCK = 10   -- keep at least this many meals (cooked + raw) on you

-- Best food for this character's class and level
function FG:BestFood()
    local _, class = UnitClass("player")
    local plan, best = self.foodPlan[class], nil
    for _, f in ipairs(plan or {}) do
        if UnitLevel("player") >= f[1] then best = f end
    end
    return best
end

-- Status line when you're not Well Fed: what to eat, or how to get it
function FG:FoodLine()
    if self:HasBuff("Well Fed") then return nil end
    local f = self:BestFood()
    if not f then return nil end
    local have = self:ItemCount(f[2])
    if have > 0 then
        return ("|cffff8040Not Well Fed:|r eat |cffffffff%s|r (%s, %d in bags) - sit 10+ sec"):format(f[3], f[4], have)
    end
    local cooking = self:SkillRank("Cooking") or 0
    if cooking >= f[5] then
        return ("|cffff8040Not Well Fed:|r cook |cffffffff%s|r (%s)"):format(f[3], f[4])
    end
    return ("|cffff8040Not Well Fed:|r eat any cooked food; at Cooking %d make |cffffffff%s|r (%s)"):format(f[5], f[3], f[4])
end

-- "Food: 6 Longjaw Mud Snapper + 9 raw" - always shown during sessions,
-- otherwise only when you're running low
function FG:FoodStockLine(always)
    local f = self:BestFood()
    if not f then return nil end
    local cooked, raw = self:ItemCount(f[2]), f[7] and self:ItemCount(f[7]) or 0
    local low = cooked + raw < self.FOOD_STOCK
    if not always and not low then return nil end
    local color = low and "|cffff8040" or "|cff00ff00"
    local line = ("%sFood: %d %s + %d %s|r"):format(color, cooked, f[3], raw, f[8] or "raw")
    if low then line = line .. (" |cff888888- stock up: %s|r"):format(f[9] or "") end
    return line
end

function FG:PrintFoodPlan()
    local _, class = UnitClass("player")
    self:Print("Your food plan (any cooked food = +5% kill XP; these add the best stats for your class):")
    for _, f in ipairs(self.foodPlan[class] or {}) do
        self:Print(("  from %d: |cffffffff%s|r %s (Cooking %d) - recipe: %s"):format(f[1], f[3], f[4], f[5], f[6]))
        local r = self.RecipeReagents and self:RecipeReagents(f[2])
        if r then
            self:Print("      |cff88ff88Forever recipe:|r " .. self:ReagentText(r))
        else
            self:Print(("      carry: %s - %s |cff888888(open your Cooking window to confirm Forever's recipe)|r"):format(f[8], f[9]))
        end
    end
end

---------------------------------------------------------------------------
-- Alchemy: best elixir / potion per category for your level and skill.
-- { Alchemy skill, character level to drink, item ID, name, effect, recipe, herbs }
-- Herbs are the Classic recipes - only a fallback: once you open your Alchemy
-- window, /fg pots and [Keep] use Forever's real reagents read from the game.
-- Forever beta data (Wowhead + seemeta). Healing potions are First Aid now.
-- Expert (150+) is trained in the Undercity (Doctor Herbert Halsey, level 20).
---------------------------------------------------------------------------
FG.potionPlan = {
    { "Strength", {
        { 55,  1,  2454, "Elixir of Minor Strength", "+4 Strength", "trainer", "Earthroot, Silverleaf" },
        { 90,  8,  6662, "Elixir of Giant Growth", "+8 Strength", "recipe drop - AH; needs Deviate Fish (fish near Wailing Caverns)", "Deviate Fish, Earthroot" },
        { 150, 20, 3391, "Elixir of Ogre Strength", "+8 Strength", "trainer or AH", "Kingsblood, Earthroot" },
    } },
    { "Agility (rogue)", {
        { 50,  2,  2457, "Elixir of Minor Agility", "+4 Agility", "trainer or AH", "Swiftthistle, Silverleaf" },
        { 140, 18, 3390, "Elixir of Lesser Agility", "+8 Agility", "trainer or AH", "Swiftthistle, Briarthorn" },
        { 185, 27, 8949, "Elixir of Agility", "+15 Agility", "trainer or AH", "Stranglekelp, Goldthorn" },
    } },
    { "Defense", {
        { 55,  1,  5997, "Elixir of Minor Defense", "+50 armor", "trainer", "Silverleaf x2" },
        { 155, 16, 3389, "Elixir of Lesser Defense", "+150 armor", "trainer", "Wild Steelbloom, Stranglekelp" },
        { 195, 29, 8951, "Elixir of Defense", "+250 armor", "trainer or AH", "Wild Steelbloom, Goldthorn" },
    } },
    { "Health", {
        { 50,  2,  2458, "Elixir of Minor Fortitude", "+27 max health", "trainer", "Earthroot x2, Peacebloom" },
        { 60,  1,  3382, "Minor Troll's Blood Elixir", "+2 health / 5 sec", "trainer", "Peacebloom, Earthroot" },
        { 150, 15, 3388, "Lesser Troll's Blood Elixir", "+6 health / 5 sec", "trainer", "Bruiseweed, Liferoot" },
        { 175, 25, 3825, "Elixir of Lesser Fortitude", "+120 max health", "trainer or AH", "Wild Steelbloom, Goldthorn" },
    } },
    { "Mana", {
        { 65,  5,  2455, "Minor Mana Potion", "140-180 mana", "trainer", "Mageroyal, Silverleaf" },
        { 120, 10, 3383, "Elixir of Wisdom", "+6 Intellect", "trainer", "Mageroyal, Briarthorn" },
        { 145, 14, 3385, "Lesser Mana Potion", "280-360 mana", "trainer", "Mageroyal, Stranglekelp" },
        { 180, 22, 3827, "Mana Potion", "455-585 mana", "trainer (Expert)", "Kingsblood, Stranglekelp" },
    } },
}

-- Alchemy pacing so the next tier unlocks as you reach its drink level
FG.secondaryPlan["Alchemy"] = {
    { 10, 55,  "Minor Strength / Defense, then Journeyman (level 10)" },
    { 16, 120, "Elixir of Wisdom, mana potions" },
    { 20, 150, "Ogre Strength at 150; Expert Alchemy in the Undercity (level 20)" },
    { 25, 180, "Lesser Defense, Mana Potions" },
    { 30, 200, "Elixir of Defense / Agility" },
    { 35, 225, "Artisan Alchemy needs level 35 (Undercity, end of the route)" },
}

-- Best you can make now, and what's next, per category
function FG:PrintPotionPlan()
    local skill = self:SkillRank("Alchemy")
    local level = UnitLevel("player")
    if not skill then
        self:Print("You don't have Alchemy. Group potions come from the Shaman (/fg camp).")
        return
    end
    self:Print(("Best potions for level %d, Alchemy %d (healing potions are First Aid):"):format(level, skill))
    local scanned = ForeverGuideCharDB.recipes and ForeverGuideCharDB.recipes["Alchemy"]
    if not scanned then self:Print("  |cff888888Open your Alchemy window once to show Forever's real reagents (grey = Classic data).|r") end
    for _, cat in ipairs(self.potionPlan) do
        local best, nextUp
        for _, p in ipairs(cat[2]) do
            if skill >= p[1] and level >= p[2] then best = p
            elseif not nextUp then nextUp = p end
        end
        local line = ("  |cffffffff%s|r: "):format(cat[1])
        local function mats(p)
            local r = self.RecipeReagents and self:RecipeReagents(p[3])
            if r then return "|cff88ff88[" .. self:ReagentText(r) .. "]|r" end
            return "|cff888888[Classic: " .. (p[7] or "?") .. "]|r"
        end
        line = line .. (best and ("%s (%s) %s"):format(best[4], best[5], mats(best)) or "nothing yet")
        if nextUp then
            line = line .. ("  |cff888888next: %s (%s) at Alchemy %d, level %d - %s|r %s"):format(nextUp[4], nextUp[5], nextUp[1], nextUp[2], nextUp[6], mats(nextUp))
        end
        self:Print(line)
    end
end
