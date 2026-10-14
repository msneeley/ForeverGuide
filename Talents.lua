-- Talents + Legacy: tells you where the next talent point goes (and Glow.lua
-- highlights it in the talent window - nothing is ever spent for you), and a
-- Legacy perk spending plan for leveling. Talents are matched by name, so
-- the build keeps working if Forever moves talents around in the trees.
local _, FG = ...

-- One entry per talent in the order points go in: { name, target rank }.
-- WoW Forever trees (not Classic): Forever tiers open every 5 levels, and
-- several Classic talents are gone or baseline (Improved Thorns and Omen of
-- Clarity are free for druids; Natural Weapons became Naturalist).
-- 10-30 follows the Forever beta guides (Icy Veins, Wowvendor, Mobalytics,
-- wow4evernews, wowclassicforever, Oct 2026). 31-35 uses only talents those
-- guides show in Forever's trees - no Forever data past 30 yet, so provisional.
-- A talent the game doesn't have is skipped and the next one is recommended.
FG.talentBuilds = {
    SHAMAN = {
        name = "Enhancement leveling (Forever)",
        { "Thundering Strikes", 5 },   -- 10-14  crit on everything
        { "Mental Dexterity", 3 },     -- 15-17  attack power from Intellect
        { "Improved Ghost Wolf", 2 },  -- 18-19  faster Ghost Wolf
        { "Shamanistic Focus", 1 },    -- 20     cheaper shocks
        { "Elemental Weapons", 3 },    -- 21-23  stronger weapon imbues
        { "Ancestral Knowledge", 1 },  -- 24     more mana
        { "Stormstrike", 1 },          -- 25     the 16-point talent in Forever
        { "Flurry", 4 },               -- 26-29  attack speed after crits
        { "Improved Stormstrike", 1 }, -- 30
        { "Improved Stormstrike", 2 }, -- 31     (provisional past 30)
        { "Flurry", 5 },               -- 32     (provisional)
        { "Ancestral Knowledge", 4 },  -- 33-35  (provisional)
    },
    -- Balance, healing when needed. Pure Balance so Moonkin Form lands at 40
    -- (it needs 31 points in the tree). Thorns and Omen of Clarity are free.
    DRUID = {
        name = "Balance leveling (Forever)",
        { "Improved Wrath", 5 },             -- 10-14  cheaper, faster Wrath
        { "Moonglow", 3 },                   -- 15-17  cheaper damage spells
        { "Nature's Majesty", 2 },           -- 18-19  more crit
        { "Improved Moonfire", 2 },          -- 20-21
        { "Improved Entangling Roots", 3 },  -- 22-24  stronger roots for kiting
        { "Insect Swarm", 1 },               -- 25
        { "Vengeance", 5 },                  -- 26-30  bigger crits
        { "Eclipse", 3 },                    -- 31-33  Wrath speeds up Starfire (tier opens at 30)
        { "Nature's Reach", 2 },             -- 34-35  range (provisional)
    },
    -- Combat 0/21/0 (wow4evernews / Wowvendor order)
    ROGUE = {
        name = "Combat leveling (Forever)",
        { "Improved Sinister Strike", 2 },   -- 10-11
        { "Improved Eviscerate", 3 },        -- 12-14
        { "Precision", 2 },                  -- 15-16
        { "Deflection", 3 },                 -- 17-19
        { "Riposte", 1 },                    -- 20
        { "Precision", 3 },                  -- 21
        { "Endurance", 2 },                  -- 22-23
        { "Lightning Reflexes", 1 },         -- 24
        { "Flawless Execution", 1 },         -- 25     new in Forever
        { "Dual Wield Specialization", 4 },  -- 26-29
        { "Blade Flurry", 1 },               -- 30
        { "Dual Wield Specialization", 5 },  -- 31     (provisional past 30)
        { "Lightning Reflexes", 5 },         -- 32-35  (provisional)
    },
}

function FG:UnspentTalentPoints()
    if GetUnspentTalentPoints then return GetUnspentTalentPoints() or 0 end
    if UnitCharacterPoints then return (UnitCharacterPoints("player")) or 0 end
    return 0
end

-- name -> { rank, maxRank, tabName } for every talent the client knows
local function scanTalents()
    local known = {}
    if not GetNumTalentTabs then return known end
    for tab = 1, GetNumTalentTabs() do
        local tabName = GetTalentTabInfo(tab)
        if type(tabName) == "number" then tabName = select(2, GetTalentTabInfo(tab)) end
        for i = 1, GetNumTalents(tab) do
            local name, _, _, _, rank, maxRank = GetTalentInfo(tab, i)
            if name then known[name] = { rank = rank or 0, maxRank = maxRank, tab = tabName } end
        end
    end
    return known
end

-- Returns name, nextRank, targetRank, tabName for the next point, or nil
function FG:NextTalent()
    local _, class = UnitClass("player")
    local build = self.talentBuilds[class]
    if not build then return end
    local known = scanTalents()
    if not next(known) then return end
    for _, entry in ipairs(build) do
        local name, target = entry[1], entry[2]
        local t = known[name]
        -- a talent this client doesn't have is skipped (shown red in /fg talents)
        if t and t.rank < target then
            return name, t.rank + 1, target, t.tab
        end
    end
end

function FG:TalentLine()
    if ForeverGuideDB and ForeverGuideDB.talentGuide == false then return nil end
    local points = self:UnspentTalentPoints()
    if points <= 0 then return nil end
    local name, nextRank, target, tab = self:NextTalent()
    if not name then return ("|cff00ff00%d talent point(s)|r - build finished"):format(points) end
    return ("|cff00ff00Talent:|r %s %d/%d |cff888888(%s)|r"):format(name, nextRank, target, tab or "?")
end

function FG:PrintTalentPlan()
    local _, class = UnitClass("player")
    local build = self.talentBuilds[class]
    if not build then self:Print("No talent build for this class yet.") return end
    local known = scanTalents()
    self:Print(build.name .. " (points at level 10+):")
    local level, planned = 10, {}
    for _, entry in ipairs(build) do
        local t = known[entry[1]]
        local have = t and t.rank or 0
        local pts = entry[2] - (planned[entry[1]] or 0)   -- a talent can come back for more ranks later
        planned[entry[1]] = entry[2]
        local color = (have >= entry[2]) and "|cff00ff00" or (t and "|cffffffff" or "|cffff4040")
        local lv = pts > 1 and ("%d-%d"):format(level, level + pts - 1) or tostring(level)
        self:Print(("  %s  %s%s|r %d/%d"):format(lv, color, entry[1], have, entry[2]))
        level = level + pts
    end
end

---------------------------------------------------------------------------
-- Legacy perks: account-wide points (one per Legacy Challenge), max 16
-- spent per character. The first point usually comes at level 25 on your
-- first character, so this is for alts and later. Spend in this order.
---------------------------------------------------------------------------
FG.legacyPlan = {
    { "Well Rested", 5, "Adventure", "Rested XP builds up to 20% faster with a higher cap" },
    { "Thrill of Adventure", 5, "Adventure", "Killing blows restore up to 5% HP/mana: less drinking between pulls" },
    { "Gourmand", 3, "Resourcefulness", "Well Fed (+5% kill XP) lasts up to 100% longer" },
    { "The Quick and the Dead", 2, "Resourcefulness", "Faster ghost runs, free spells after res: better death skips" },
    { "Talented", 1, "Adventure", "First talent point at level 9 (needs 5 points in Adventure)" },
}

function FG:PrintLegacyPlan()
    self:Print("Legacy plan for leveling speed (16 points per character):")
    local total = 0
    for _, p in ipairs(self.legacyPlan) do
        total = total + p[2]
        self:Print(("  %2d  %s x%d |cff888888(%s)|r - %s"):format(total, p[1], p[2], p[3], p[4]))
    end
    self:Print("Skip Reinforce, For Great Honor and Diplomat while leveling.")
end

---------------------------------------------------------------------------
-- Group camp plan: one camp object per player (each player can add one).
-- Basic Campfire Kit (Cooking 1) holds 3 objects. Journeyman Campfire Kit
-- holds 5: learned at Cooking 90 but placeable only at 140 in the beta.
-- Buffs from different professions stack; sit ~1 minute for 1 hour of all
-- of them. Each camp buff is skipped if its matching class buff is up.
---------------------------------------------------------------------------
FG.campPlan = {   -- group: Druid, Shaman, Rogue, Paladin, Warrior (no Priest/Mage)
    { "Skyborne Rogue", "Leatherworking + Skinning", "Camp Tent: rested XP up to 5% of a level",
      "Slot 1. The only buff that adds XP directly." },
    { "Warrior", "Fishing 20 (secondary)", "Fish Bowl: +8% all stats",
      "Slot 2. Everyone. Only a Paladin's Blessing of Kings (Protection talent) would overlap it." },
    { "Tauren Druid", "Skinning + (his pick)", "Camp Chair: +2% crit",
      "Slot 3. Everyone." },
    { "Paladin", "First Aid 20 (secondary)", "First Aid Kit: +Stamina",
      "Slot 4 (Journeyman fire). Everyone - no Priest, so no Fortitude to overlap." },
    { "You (Tauren Shaman)", "Herbalism + Alchemy", "Mana Well: mana regeneration",
      "Slot 5 (Journeyman fire). Helps you and the Paladin (the druid gets Blessing of Wisdom, which overlaps it). Camping 101: Kray (Thunder Bluff) or Whuut (Orgrimmar) at Alchemy 20." },
}

function FG:PrintCampPlan()
    self:Print("Camp plan - Basic Campfire Kit (Cooking 1): first 3 objects; Journeyman Campfire Kit (learn at Cooking 90, place at 140): all 5")
    for i, p in ipairs(self.campPlan) do
        self:Print(("  %d. |cffffffff%s|r - %s -> |cff00ff00%s|r"):format(i, p[1], p[2], p[3]))
        self:Print("       " .. p[4])
    end
    self:Print("Skip: Lodestone (= Blessing of Might on the melee), Enchanted Lute (= Mark of the Wild), Sharpening Wheel (= Strength of Earth).")
    self:Print("Everyone: level First Aid, Cooking and Fishing (/fg prof) and cook your own food (/fg food).")
end
