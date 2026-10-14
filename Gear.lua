-- Gear: scores items for a class (leveling stat weights), knows what each
-- class can wear, and works out whether an item is an upgrade for someone
-- given what they have equipped. Used by the reward picker and the green
-- "upgrade for a party member" dot.
local _, FG = ...

FG.CLASS_WEIGHTS = {
    SHAMAN  = { STR = 2, AGI = 1, STA = 0.6, INT = 0.8, SPI = 0.2, DPS = 4 },
    DRUID   = { STR = 0.2, AGI = 0.2, STA = 0.8, INT = 1, SPI = 0.6, DPS = 0, SP = 3 },  -- Balance / Thorns
    ROGUE   = { STR = 1, AGI = 2.5, STA = 0.6, INT = 0, SPI = 0, DPS = 4 },
    WARRIOR = { STR = 2.5, AGI = 1.2, STA = 1, INT = 0, SPI = 0, DPS = 4 },
    PALADIN = { STR = 2.5, AGI = 0.8, STA = 0.8, INT = 0.6, SPI = 0.3, DPS = 4 },
    HUNTER  = { STR = 0.3, AGI = 2.5, STA = 0.7, INT = 0.5, SPI = 0.2, DPS = 2 },
    MAGE    = { STR = 0, AGI = 0, STA = 0.8, INT = 2, SPI = 1, DPS = 0, SP = 2 },
    WARLOCK = { STR = 0, AGI = 0, STA = 1.2, INT = 1.5, SPI = 0.8, DPS = 0, SP = 2 },
    PRIEST  = { STR = 0, AGI = 0, STA = 0.8, INT = 1.5, SPI = 1.5, DPS = 0, SP = 2 },
}
-- Armor subclass IDs each class can wear before level 40 (1 cloth, 2 leather, 3 mail, 6 shield)
local ARMOR = {
    SHAMAN = { [1] = true, [2] = true, [6] = true }, DRUID = { [1] = true, [2] = true },
    ROGUE = { [1] = true, [2] = true }, HUNTER = { [1] = true, [2] = true },
    WARRIOR = { [1] = true, [2] = true, [3] = true, [6] = true }, PALADIN = { [1] = true, [2] = true, [3] = true, [6] = true },
    MAGE = { [1] = true }, WARLOCK = { [1] = true }, PRIEST = { [1] = true },
}
-- Weapon subclass IDs (0/1 axe, 4/5 mace, 7/8 sword, 10 staff, 13 fist, 15 dagger, 6 polearm, 19 wand)
local WEAPON = {
    SHAMAN = { [0] = true, [1] = true, [4] = true, [5] = true, [10] = true, [13] = true, [15] = true },
    DRUID = { [4] = true, [5] = true, [10] = true, [13] = true, [15] = true },
    ROGUE = { [4] = true, [7] = true, [13] = true, [15] = true, [2] = true, [3] = true, [18] = true, [16] = true },
    WARRIOR = { [0] = true, [1] = true, [4] = true, [5] = true, [7] = true, [8] = true, [6] = true, [10] = true, [13] = true, [15] = true },
    PALADIN = { [0] = true, [1] = true, [4] = true, [5] = true, [7] = true, [8] = true, [6] = true },
    HUNTER = { [0] = true, [1] = true, [7] = true, [8] = true, [6] = true, [10] = true, [13] = true, [15] = true, [2] = true, [3] = true, [18] = true },
    MAGE = { [7] = true, [10] = true, [15] = true, [19] = true }, WARLOCK = { [7] = true, [10] = true, [15] = true, [19] = true },
    PRIEST = { [4] = true, [10] = true, [15] = true, [19] = true },
}
local STAT_KEYS = {
    STR = "ITEM_MOD_STRENGTH_SHORT", AGI = "ITEM_MOD_AGILITY_SHORT", STA = "ITEM_MOD_STAMINA_SHORT",
    INT = "ITEM_MOD_INTELLECT_SHORT", SPI = "ITEM_MOD_SPIRIT_SHORT", DPS = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT",
}
-- Equip location -> inventory slots it can go in
FG.EQUIP_SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

function FG:ItemInfo(item)
    if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(item) end
    return GetItemInfo(item)
end

local function itemStats(link)
    if C_Item and C_Item.GetItemStats then return C_Item.GetItemStats(link) end
    return GetItemStats and GetItemStats(link)
end

-- Spell power: Forever reports "+X spell damage and healing" as ITEM_MOD_SPELL_POWER
-- (or ITEM_MOD_SPELL_DAMAGE_DONE), one lower than the tooltip; Nature-only damage
-- (what Thorns uses) is only in the tooltip text.
local function spellPower(link, stats)
    local sp = math.max(stats.ITEM_MOD_SPELL_POWER or -1, stats.ITEM_MOD_SPELL_DAMAGE_DONE or -1) + 1
    if sp <= 0 then sp = (stats.ITEM_MOD_SPELL_HEALING_DONE or 0) * 0.3 end
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local data = C_TooltipInfo.GetHyperlink(link)
        for _, line in ipairs(data and data.lines or {}) do
            local n = line.leftText and line.leftText:match("Nature spells and effects by up to (%d+)")
            if n then sp = sp + tonumber(n) end
        end
    end
    return sp
end

-- Can this class wear/wield it? (cloaks, rings, necks, trinkets: everyone)
function FG:CanWear(class, classID, subclassID, equipLoc)
    if classID == 4 and subclassID and subclassID > 0 and equipLoc ~= "INVTYPE_CLOAK" then
        return ARMOR[class] and ARMOR[class][subclassID] or false
    elseif classID == 2 then
        return WEAPON[class] and WEAPON[class][subclassID] or false
    end
    return true
end

-- "Classes: Shaman" / "Races: Tauren" lines on an item's tooltip. Names are the
-- localized ones the game shows (shared by each party member's addon).
function FG:RestrictionsOK(link, className, raceName)
    if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return true end
    local data = C_TooltipInfo.GetHyperlink(link)
    for _, line in ipairs(data and data.lines or {}) do
        local t = line.leftText
        if t then
            local classes = t:match("^Classes: (.+)$")
            if classes and className and not (", " .. classes .. ","):find(", " .. className .. ",", 1, true) then return false end
            local races = t:match("^Races: (.+)$")
            if races and raceName and not (", " .. races .. ","):find(", " .. raceName .. ",", 1, true) then return false end
        end
    end
    return true
end

-- Score for a class: number, false if they can't use it, nil if item data isn't loaded yet
function FG:ScoreItem(item, class)
    local _, link, _, _, _, _, _, _, equipLoc, _, _, classID, subclassID = self:ItemInfo(item)
    if not link then return nil end
    if not self:CanWear(class, classID, subclassID, equipLoc) then return false end
    local w = self.CLASS_WEIGHTS[class]
    if not w then return 0 end
    local stats, score = itemStats(link) or {}, 0
    for k, key in pairs(STAT_KEYS) do score = score + (stats[key] or 0) * (w[k] or 0) end
    if w.SP then score = score + spellPower(link, stats) * w.SP end
    score = score + (stats.RESISTANCE0_NAME or 0) * 0.02
    return score
end

-- How much better `item` is for someone with this class, level and gear
-- ({ [slot] = itemID }), or nil if it isn't an upgrade (or isn't known yet).
function FG:UpgradeDelta(item, class, level, gear, className, raceName)
    local _, link, _, _, minLevel, _, _, _, equipLoc = self:ItemInfo(item)
    local slots = link and self.EQUIP_SLOTS[equipLoc]
    if not slots or (minLevel or 0) > (level or 0) then return nil end
    if not self:RestrictionsOK(link, className, raceName) then return nil end
    local new = self:ScoreItem(item, class)
    if not new or new <= 0 then return nil end
    local function scoreAt(slot)
        local id = gear and gear[slot]
        if not id or id == 0 then return 0 end
        local s = self:ScoreItem(id, class)
        if s == nil and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        return s or 0
    end
    local current
    if equipLoc == "INVTYPE_2HWEAPON" then
        current = scoreAt(16) + scoreAt(17)        -- a two-hander replaces both hands
    else
        for _, slot in ipairs(slots) do         -- rings, trinkets, one-handers: beat the weaker one
            local s = scoreAt(slot)
            if not current or s < current then current = s end
        end
    end
    local delta = new - (current or 0)
    if delta > 0.5 then return delta end
end
