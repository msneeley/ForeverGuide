-- Buffs: a Pally Power-style bar. Top row: one icon per buff you should
-- have right now (Well Fed, camp, buffs from the classes in your party, your
-- own self-buffs and weapon imbue, elixirs, potions in your bags). Green
-- edge = you have it, yellow = running out, red = missing. Click a missing
-- one of your own (food, elixir, shield, imbue) to use it.
-- Below that, one row per buff YOU give, with a button per party member:
-- red = they're missing it. Click to cast it on them (spells) or to open a
-- trade with them (elixirs; on yourself it drinks one).
-- Buffs only appear when someone in the party can give them.
-- Roles (tank/healer/melee/caster) decide who each buff is checked for.
-- /fg buffs toggles each check and its roles, sets roles, and picks the
-- paladin blessing you want;
-- /fg buffs learn records camp buff names.
local _, FG = ...

local MANA = { DRUID = true, PALADIN = true, SHAMAN = true, MAGE = true, PRIEST = true, WARLOCK = true, HUNTER = true }
-- Which potionPlan category is each class's "battle" elixir
local BATTLE = { SHAMAN = "Strength", WARRIOR = "Strength", PALADIN = "Strength", ROGUE = "Agility (rogue)",
                 HUNTER = "Agility (rogue)", DRUID = "Mana", MAGE = "Mana", PRIEST = "Mana", WARLOCK = "Mana" }
-- The campfire buff (camp objects' bonuses are part of it). Matched by these
-- words, plus whatever name /fg buffs learn records if Forever calls it something else.
local CAMP_WORDS = { "Campfire", "Cozy Fire", "Camp" }
local LOW = 120   -- seconds left that counts as "running out"

local function spellKnown(name)
    if C_Spell and C_Spell.GetSpellInfo then return C_Spell.GetSpellInfo(name) ~= nil end
    return GetSpellInfo ~= nil and GetSpellInfo(name) ~= nil
end

local function firstKnown(list)
    for _, s in ipairs(list or {}) do if spellKnown(s) then return s end end
end

local function spellIcon(name)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(name) end
    return GetSpellTexture and GetSpellTexture(name)
end

local function itemIcon(id)
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
    return GetItemIcon and GetItemIcon(id)
end

-- The buff an item gives (name, spellID), cached once the item data loads
local itemSpells = {}
local function itemSpell(id)
    local c = itemSpells[id]
    if c then return c[1], c[2] end
    local get = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    local name, sid = get and get(id)
    if name then itemSpells[id] = { name, sid }
    elseif C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    return name, sid
end

-- Helpful auras on a unit: [name] = { name, spellId, expirationTime, duration, icon }
local function auraSet(unit)
    local set = {}
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local a = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
            if not a then break end
            if a.name then set[a.name] = a end
        end
    elseif UnitBuff then
        for i = 1, 40 do
            local name, icon, _, _, duration, expirationTime, _, _, _, spellId = UnitBuff(unit, i)
            if not name then break end
            set[name] = { name = name, icon = icon, duration = duration, expirationTime = expirationTime, spellId = spellId }
        end
    end
    return set
end

local function timeLeft(a)
    if not a or not a.expirationTime or a.expirationTime == 0 then return nil end
    return a.expirationTime - GetTime()
end

-- Elixirs in one potionPlan category (skips potions: they aren't buffs)
local function planItems(category, elixirsOnly)
    for _, cat in ipairs(FG.potionPlan or {}) do
        if cat[1] == category then
            local out = {}
            for _, p in ipairs(cat[2]) do
                if not elixirsOnly or not p[4]:find("Potion") then table.insert(out, p) end
            end
            return out
        end
    end
    return {}
end

local function elixirList(kind, class)
    if kind == "battle" then return planItems(BATTLE[class] or "Strength", true) end
    local out = planItems("Defense", true)
    for _, p in ipairs(planItems("Health", true)) do table.insert(out, p) end
    return out
end

-- Aura from this list of elixirs, if the unit has one
local function findElixir(set, list)
    for _, p in ipairs(list) do
        local name, sid = itemSpell(p[3])
        if name and set[name] then return set[name], p end
        if sid then
            for _, a in pairs(set) do if a.spellId == sid then return a, p end end
        end
    end
end

-- Best elixir in your bags for someone of this level (highest tier you carry)
local function bestInBags(list, level)
    local best
    for _, p in ipairs(list) do
        if (level or 0) >= p[2] and FG:ItemCount(p[3]) > 0 then best = p end
    end
    return best
end

-- Best tier the group's alchemist can make for this level (skill if it's you)
local function bestTier(list, level, skill)
    local best
    for _, p in ipairs(list) do
        if (level or 0) >= p[2] and (not skill or skill >= p[1]) then best = p end
    end
    return best
end

-- The tier to recommend: battle = class elixir; guard = best Defense, else Health
local function recommend(kind, class, level, skill)
    if kind == "guard" then
        return bestTier(planItems("Defense", true), level, skill) or bestTier(planItems("Health", true), level, skill)
    end
    return bestTier(planItems(BATTLE[class] or "Strength", true), level, skill)
end

local function isCampAura(name)
    if ForeverGuideDB.campAuras and ForeverGuideDB.campAuras[name] then return true end
    for _, w in ipairs(CAMP_WORDS) do
        if name:find(w, 1, true) then return true end
    end
    return false
end

-- Roles: Tank / Healer / Melee / Caster. Anyone can set anyone's role (/fg buffs
-- or /fg role); it's shared with the party ("O" message) so every bar agrees.
-- Each buff check has the roles it goes to (Thorns: tanks only by default).
FG.ROLES = { "TANK", "HEALER", "MELEE", "CASTER" }
FG.ROLE_NAMES = { TANK = "Tank", HEALER = "Healer", MELEE = "Melee", CASTER = "Caster" }
local DEFAULT_ROLE = { WARRIOR = "TANK", PALADIN = "MELEE", SHAMAN = "MELEE", ROGUE = "MELEE", HUNTER = "MELEE",
                       DRUID = "CASTER", MAGE = "CASTER", WARLOCK = "CASTER", PRIEST = "HEALER" }

function FG:RoleOf(name, class)
    local r = ForeverGuideDB.roles and name and ForeverGuideDB.roles[name]
    return r or DEFAULT_ROLE[class] or "MELEE"
end

function FG:SetRole(name, role, fromParty)
    role = role and role:upper()
    if not (name and self.ROLE_NAMES[role]) then return end
    ForeverGuideDB.roles = ForeverGuideDB.roles or {}
    if ForeverGuideDB.roles[name] == role then return end
    ForeverGuideDB.roles[name] = role
    if not fromParty then
        self:Print(("%s is now %s"):format(name, self.ROLE_NAMES[role]))
        if self.SendRole then self:SendRole(name, role) end
    end
    if self.buffOptions and self.buffOptions:IsShown() and self.RefreshRoleButtons then self:RefreshRoleButtons() end
    self:UpdateBuffBar()
end

-- Does this check go to this role? (per check, set in /fg buffs)
local DEFAULT_CHECK_ROLES = { thorns = { TANK = true } }
function FG:CheckForRole(key, role)
    local t = ForeverGuideDB.buffRoles and ForeverGuideDB.buffRoles[key]
    if t and t[role] ~= nil then return t[role] end
    local d = DEFAULT_CHECK_ROLES[key]
    if d then return d[role] == true end
    return true
end

function FG:SetCheckForRole(key, role, on)
    ForeverGuideDB.buffRoles = ForeverGuideDB.buffRoles or {}
    ForeverGuideDB.buffRoles[key] = ForeverGuideDB.buffRoles[key] or {}
    ForeverGuideDB.buffRoles[key][role] = on and true or false
    self:UpdateBuffBar()
end

-- Which blessing each person wants: yours is picked in /fg buffs and shared
-- with the party ("B" message), so a paladin's row casts what you asked for.
FG.BLESSINGS = { "Might", "Wisdom", "Kings", "Salvation", "Light" }
local BLESSING_ICONS = { Might = "Spell_Holy_FistOfJustice", Wisdom = "Spell_Holy_SealOfWisdom",
                         Kings = "Spell_Magic_MageArmor", Salvation = "Spell_Holy_SealOfSalvation", Light = "Spell_Holy_PrayerOfHealing02" }

function FG:WantedBlessing(m)
    if not m or m.unit == "player" then
        local w = ForeverGuideCharDB and ForeverGuideCharDB.blessing
        if w then return w end
        local _, class = UnitClass("player")
        local role = self:RoleOf(UnitName("player"), class)
        return (role == "CASTER" or role == "HEALER") and "Wisdom" or "Might"
    end
    local d = self.groupData and self.groupData[m.name]
    if d and d.blessing and d.blessing ~= "" then return d.blessing end
    local role = self:RoleOf(m.name, m.class)
    return (role == "CASTER" or role == "HEALER") and "Wisdom" or "Might"
end

function FG:SetWantedBlessing(name)
    for _, b in ipairs(self.BLESSINGS) do
        if b:lower() == (name or ""):lower() then
            ForeverGuideCharDB.blessing = b
            self:Print("Wanted paladin blessing: Blessing of " .. b)
            if self.BroadcastGroupInfo then self:BroadcastGroupInfo(true) end
            self:UpdateBuffBar()
            return
        end
    end
    self:Print("/fg buffs blessing " .. table.concat(self.BLESSINGS, " | "):lower())
end

---------------------------------------------------------------------------
-- The checks. from = class that casts it (needs one in the party, at
-- minLevel); self = your class only; give = you can cast it on others.
---------------------------------------------------------------------------
FG.buffChecks = {
    { key = "food", label = "Well Fed", names = { "Well Fed" }, icon = "Interface\\Icons\\INV_Misc_Food_15" },
    { key = "camp", label = "Campfire", camp = true, icon = "Interface\\Icons\\Spell_Fire_Fire" },
    { key = "motw", label = "Mark of the Wild", from = "DRUID", minLevel = 1, give = "Mark of the Wild",
      names = { "Mark of the Wild", "Gift of the Wild" }, icon = "Interface\\Icons\\Spell_Nature_Regeneration" },
    { key = "thorns", label = "Thorns", from = "DRUID", minLevel = 6, give = "Thorns",
      names = { "Thorns" }, icon = "Interface\\Icons\\Spell_Nature_Thorns" },
    { key = "blessing", label = "Paladin blessing", from = "PALADIN", minLevel = 4, blessing = true,
      give = function(m) return "Blessing of " .. FG:WantedBlessing(m) end,
      icon = "Interface\\Icons\\Spell_Holy_FistOfJustice" },
    { key = "palaura", label = "Paladin aura", from = "PALADIN", minLevel = 1, suffix = " Aura",
      icon = "Interface\\Icons\\Spell_Holy_DevotionAura" },
    { key = "fort", label = "Power Word: Fortitude", from = "PRIEST", minLevel = 1, give = "Power Word: Fortitude",
      names = { "Power Word: Fortitude", "Prayer of Fortitude" }, icon = "Interface\\Icons\\Spell_Holy_WordFortitude" },
    { key = "int", label = "Arcane Intellect", from = "MAGE", minLevel = 1, give = "Arcane Intellect", manaOnly = true,
      names = { "Arcane Intellect", "Arcane Brilliance" }, icon = "Interface\\Icons\\Spell_Holy_MagicalSentry" },
    { key = "shout", label = "Battle Shout", from = "WARRIOR", minLevel = 1, defaultOff = true,
      names = { "Battle Shout" }, icon = "Interface\\Icons\\Ability_Warrior_BattleShout" },
    { key = "totem", label = "Shaman totem", from = "SHAMAN", minLevel = 4, defaultOff = true,
      names = { "Strength of Earth", "Stoneskin", "Grace of Air", "Mana Spring", "Windfury Totem", "Healing Stream" },
      icon = "Interface\\Icons\\Spell_Nature_EarthBindTotem" },
    { key = "shield", label = "Lightning Shield", self = "SHAMAN", minLevel = 8, cast = "Lightning Shield",
      names = { "Lightning Shield" }, icon = "Interface\\Icons\\Spell_Nature_LightningShield" },
    { key = "omen", label = "Omen of Clarity", self = "DRUID", cast = "Omen of Clarity", needSpell = true,
      names = { "Omen of Clarity" }, icon = "Interface\\Icons\\Spell_Nature_CrystalBall" },
    -- Shaman stat totems: only red in combat. Earth = Strength of Earth; air =
    -- Windfury once you have it, else Grace of Air. Highest rank is cast.
    { key = "earthTotem", label = "Strength of Earth Totem", totem = 2, spells = { "Strength of Earth Totem" },
      icon = "Interface\\Icons\\Spell_Nature_EarthBindTotem", button = "ForeverGuideTotemEarth" },
    { key = "airTotem", label = "Air totem (Windfury/Grace)", totem = 4, spells = { "Windfury Totem", "Grace of Air Totem" },
      icon = "Interface\\Icons\\Spell_Nature_Windfury", button = "ForeverGuideTotemAir" },
    { key = "imbue", label = "Weapon imbue / poison", weapon = { SHAMAN = 1, ROGUE = 20 },
      icon = "Interface\\Icons\\Spell_Nature_RockBiter" },
    { key = "elixir", label = "Battle elixir", elixir = "battle", icon = "Interface\\Icons\\INV_Potion_61" },
    { key = "guard", label = "Defensive elixir", elixir = "guard", icon = "Interface\\Icons\\INV_Potion_66" },
    { key = "potions", label = "Mana potions in bags", potions = true, manaOnly = true,
      icon = "Interface\\Icons\\INV_Potion_76" },
}

local function checkOn(c)
    local v = ForeverGuideDB.buffChecks and ForeverGuideDB.buffChecks[c.key]
    if v == nil then return not c.defaultOff end
    return v
end

-- Who's in the group, who can cast what, who has Alchemy
local function context()
    local ctx = { members = {}, providers = {}, alchemists = {} }
    local units = { "player" }
    for i = 1, 4 do if UnitExists("party" .. i) then table.insert(units, "party" .. i) end end
    for _, u in ipairs(units) do
        local _, class = UnitClass(u)
        local m = { unit = u, name = UnitName(u), class = class, level = UnitLevel(u) }
        table.insert(ctx.members, m)
        if class then ctx.providers[class] = math.max(ctx.providers[class] or 0, m.level or 0) end
    end
    ctx.me = ctx.members[1]
    ctx.alchemy = FG:SkillRank("Alchemy")
    ctx.alchemySkill = ctx.alchemy
    if ctx.alchemy then table.insert(ctx.alchemists, "you") end
    for name, d in pairs(FG.groupData or {}) do
        for _, p in ipairs(d.profs or {}) do
            if p[1] == "Alchemy" then
                table.insert(ctx.alchemists, name)
                ctx.alchemySkill = math.max(ctx.alchemySkill or 0, p[2] or 0)
            end
        end
    end
    return ctx
end

-- Does check c apply to member m?
local function applies(c, m, ctx)
    if not checkOn(c) or not m.class then return false end
    if not FG:CheckForRole(c.key, FG:RoleOf(m.name, m.class)) then return false end
    if c.manaOnly and not MANA[m.class] then return false end
    if c.from then return (ctx.providers[c.from] or 0) >= c.minLevel end
    if c.self then
        if m.unit ~= "player" or m.class ~= c.self or (m.level or 0) < (c.minLevel or 1) then return false end
        return spellKnown(c.cast)
    end
    if c.totem then return m.unit == "player" and m.class == "SHAMAN" and firstKnown(c.spells) ~= nil end
    if c.weapon then
        if m.unit ~= "player" or not c.weapon[m.class] or m.level < c.weapon[m.class] then return false end
        return m.class ~= "SHAMAN" or spellKnown("Rockbiter Weapon") or spellKnown("Flametongue Weapon") or spellKnown("Windfury Weapon")
    end
    if c.elixir then return #ctx.alchemists > 0 and bestTier(elixirList(c.elixir, m.class), m.level) ~= nil end
    if c.potions then return m.unit == "player" and #ctx.alchemists > 0 and m.level >= 5 end
    if c.camp then return (m.level or 0) >= 5 end
    return true
end

-- Status of check c on member m: "ok" / "low" / "missing" / "unknown", plus details
-- Forever: GetWeaponEnchantInfo() returns nil even with Rockbiter on, but the weapon's
-- tooltip has the green line "Rockbiter 1 (58 min)". Read that (main hand, then off hand).
local UNIT_SECONDS = { sec = 1, secs = 1, min = 60, mins = 60, hr = 3600, hrs = 3600, hour = 3600, hours = 3600 }
local tipCache, tipCacheAt = nil, -10
local function tooltipImbue()
    if GetTime() - tipCacheAt < 2 then return tipCache end
    tipCacheAt, tipCache = GetTime(), false
    if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then return false end
    for _, slot in ipairs({ 16, 17 }) do
        local info = C_TooltipInfo.GetInventoryItem("player", slot)
        for _, line in ipairs(info and info.lines or {}) do
            local name, n, unit = (line.leftText or ""):match("^(.-%S) %((%d+) (%a+)%)$")
            if name and UNIT_SECONDS[unit:lower()] then
                tipCache = { name = name, t = tonumber(n) * UNIT_SECONDS[unit:lower()] }
                return tipCache
            end
        end
    end
    return tipCache
end

local function status(c, m, set)
    if m.unit ~= "player" and not UnitIsVisible(m.unit) then return "unknown" end
    if UnitIsDeadOrGhost(m.unit) then return "unknown" end
    local found
    if c.names then
        for _, n in ipairs(c.names) do if set[n] then found = set[n] break end end
    elseif c.blessing then
        local want, other = FG:WantedBlessing(m), nil
        for n, a in pairs(set) do
            local b = n:match("^Blessing of (.+)$") or n:match("^Greater Blessing of (.+)$")
            if b == want then found = a break elseif b then other = n end
        end
        if not found then return "missing", other end
    elseif c.suffix then
        for n, a in pairs(set) do
            if n:sub(-#c.suffix) == c.suffix then found = a break end
        end
    elseif c.camp then
        for n, a in pairs(set) do
            if isCampAura(n) then found = a break end
        end
    elseif c.totem then
        local want = firstKnown(c.spells)
        local have, name, start, duration
        if GetTotemInfo then have, name, start, duration = GetTotemInfo(c.totem) end
        if have and name and want and name:find(want, 1, true) then
            local t = duration and duration > 0 and (start + duration - GetTime()) or nil
            return (t and t < 10) and "low" or "ok", name, t
        end
        -- only matters in combat; otherwise grey
        if not (UnitAffectingCombat and UnitAffectingCombat("player")) then return "idle", want end
        return "missing", want
    elseif c.weapon then
        local has, ms = GetWeaponEnchantInfo()
        if not has then
            local tip = tooltipImbue()
            if not tip then return "missing" end
            return tip.t < LOW and "low" or "ok", tip.name, tip.t
        end
        local t = ms and ms / 1000
        return (t and t < LOW) and "low" or "ok", nil, t
    elseif c.elixir then
        local a, p = findElixir(set, elixirList(c.elixir, m.class))
        if not a then return "missing" end
        local t = timeLeft(a)
        return (t and t < LOW) and "low" or "ok", p[4], t
    elseif c.potions then
        local n = 0
        for _, p in ipairs(planItems("Mana")) do
            if p[4]:find("Potion") then n = n + FG:ItemCount(p[3]) end
        end
        return n == 0 and "missing" or (n < 3 and "low" or "ok"), n
    end
    if not found then return "missing" end
    local t = timeLeft(found)
    return (t and t < LOW) and "low" or "ok", found.name, t
end

---------------------------------------------------------------------------
-- What clicking does (set only out of combat): your own missing buffs
---------------------------------------------------------------------------
local function selfAction(c, m)
    if c.key == "food" then
        local f = FG:BestFood()
        if f and FG:ItemCount(f[2]) > 0 then return "item", "item:" .. f[2] end
    elseif c.elixir then
        local p = bestInBags(elixirList(c.elixir, m.class), m.level)
        if p then return "item", "item:" .. p[3] end
    elseif c.cast then
        if spellKnown(c.cast) then return "spell", c.cast end
    elseif c.totem then
        local s = firstKnown(c.spells)
        if s then return "spell", s end
    elseif c.weapon and m.class == "SHAMAN" then
        for _, s in ipairs({ "Windfury Weapon", "Rockbiter Weapon", "Flametongue Weapon" }) do
            if spellKnown(s) then return "spell", s end
        end
    elseif c.give then
        local spell = type(c.give) == "function" and c.give(m) or c.give
        if c.from == m.class and spellKnown(spell) then return "spell", spell end
    end
end

-- Tooltip text for a missing / present check on you
local function selfTip(c, m, ctx, st, detail, t)
    local lines = {}
    if c.totem then
        local want = firstKnown(c.spells)
        if st == "ok" or st == "low" then
            table.insert(lines, "|cff4dff4dDown|r: " .. (detail or "") .. (t and (" (%ds left)"):format(math.floor(t)) or ""))
        elseif st == "idle" then
            table.insert(lines, "Turns red in combat when it isn't down")
        else
            table.insert(lines, "|cffff4040Not down|r")
        end
        table.insert(lines, ("Click to drop %s (or bind a key: Key Bindings > AddOns > ForeverGuide)"):format(want or "it"))
        return lines
    end
    if st == "ok" or st == "low" then
        if c.potions then
            table.insert(lines, ("%d mana potions in your bags"):format(detail or 0))
        else
            table.insert(lines, "|cff4dff4dActive|r" .. (detail and type(detail) == "string" and (": " .. detail) or ""))
        if c.blessing then table.insert(lines, "|cff888888Wanted blessing set in /fg buffs|r") end
        end
        if t then table.insert(lines, ("%d min left"):format(math.floor(t / 60 + 0.5))) end
        return lines
    end
    table.insert(lines, "|cffff4040Missing|r")
    if c.key == "food" then
        table.insert(lines, FG:FoodLine() or "Eat cooked food (/fg food)")
    elseif c.camp then
        table.insert(lines, "Sit at the group's campfire for 1 minute (lasts 1 hour)")
        table.insert(lines, "|cff888888Has the buff but still red? Sit at camp, then /fg buffs learn|r")
    elseif c.suffix and m.class == c.from then
        table.insert(lines, "Turn on one of your auras")
    elseif c.blessing then
        local who = {}
        for _, mm in ipairs(ctx.members) do if mm.class == "PALADIN" and mm.unit ~= "player" then table.insert(who, mm.name) end end
        table.insert(lines, ("Want: Blessing of %s - ask %s"):format(FG:WantedBlessing(m), #who > 0 and table.concat(who, " / ") or "your paladin"))
        if detail then table.insert(lines, "You have " .. detail .. " instead") end
        table.insert(lines, "|cff888888Change it in /fg buffs|r")
    elseif c.from then
        local who = {}
        for _, mm in ipairs(ctx.members) do if mm.class == c.from and mm.unit ~= "player" then table.insert(who, mm.name) end end
        table.insert(lines, ("Ask %s"):format(#who > 0 and table.concat(who, " / ") or "your " .. c.from:lower()))
    elseif c.elixir then
        local list = elixirList(c.elixir, m.class)
        local have = bestInBags(list, m.level)
        local tier = recommend(c.elixir, m.class, m.level, ctx.alchemySkill)
        if have then table.insert(lines, ("Click to drink %s (%d in bags)"):format(have[4], FG:ItemCount(have[3])))
        elseif ctx.alchemy and tier then
            table.insert(lines, ("Make %s (%s)"):format(tier[4], tier[5]))
            if tier[7] then table.insert(lines, "Herbs: " .. tier[7]) end
        else
            local others = {}
            for _, n in ipairs(ctx.alchemists) do if n ~= "you" then table.insert(others, n) end end
            table.insert(lines, ("Ask %s for %s"):format(#others > 0 and table.concat(others, " / ") or "your alchemist",
                tier and tier[4] or "an elixir"))
        end
    elseif c.potions then
        local others = {}
        for _, n in ipairs(ctx.alchemists) do if n ~= "you" then table.insert(others, n) end end
        table.insert(lines, ctx.alchemy and "Make mana potions (/fg pots)"
            or ("Ask %s for mana potions"):format(#others > 0 and table.concat(others, " / ") or "your alchemist"))
    elseif c.weapon then
        table.insert(lines, m.class == "ROGUE" and "Apply a poison to your weapons" or "Click to imbue your weapon")
    elseif c.cast then
        table.insert(lines, "Click to cast " .. c.cast)
    end
    return lines
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
local SIZE, PAD = 24, 3
local COLORS = { ok = { 0.2, 0.9, 0.2 }, low = { 1, 0.85, 0.1 }, missing = { 1, 0.15, 0.15 }, unknown = { 0.4, 0.4, 0.4 }, idle = { 0.4, 0.4, 0.4 } }
local bar
local selfButtons, giveRows = {}, {}
local layout = { self = {}, give = {} }   -- what's shown, rebuilt out of combat
local needLayout = true

local function makeSecure(parent, w, h, name)
    local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
    b:SetSize(w, h)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b.edge = b:CreateTexture(nil, "BACKGROUND")
    b.edge:SetAllPoints()
    b.edge:SetColorTexture(1, 1, 1)
    return b
end

local namedButtons = {}
local function selfButton(i, name)
    local b
    if name then b = namedButtons[name] else b = selfButtons[i] end
    if b then return b end
    b = makeSecure(bar, SIZE, SIZE, name)   -- named ones can be key-bound (Bindings.xml)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.text = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.text:SetPoint("BOTTOMRIGHT", -1, 1)
    b:SetScript("OnEnter", function(self)
        if not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(self.tipTitle)
        for _, l in ipairs(self.tip) do GameTooltip:AddLine(l, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if name then namedButtons[name] = b else selfButtons[i] = b end
    return b
end

local function memberButton(row, i)
    local b = row.members[i]
    if b then return b end
    b = makeSecure(row, 52, 18)
    b.bg = b:CreateTexture(nil, "BORDER")
    b.bg:SetPoint("TOPLEFT", 1, -1)
    b.bg:SetPoint("BOTTOMRIGHT", -1, 1)
    b.bg:SetColorTexture(0, 0, 0, 0.75)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("CENTER")
    b:HookScript("OnClick", function(self, _, down)
        -- Elixirs for someone else: open a trade so you can hand them over
        if down or not self.tradeUnit or InCombatLockdown() then return end
        if CheckInteractDistance(self.tradeUnit, 2) then InitiateTrade(self.tradeUnit)
        else FG:Print(UnitName(self.tradeUnit) .. " is too far away to trade") end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(self.tipTitle or "")
        if self.tipText then GameTooltip:AddLine(self.tipText, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.members[i] = b
    return b
end

local function giveRow(i)
    local r = giveRows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, bar)
    r:SetSize(SIZE, SIZE)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(SIZE - 4, SIZE - 4)
    r.icon:SetPoint("LEFT", 2, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.members = {}
    giveRows[i] = r
    return r
end

local function createBar()
    bar = CreateFrame("Frame", "ForeverGuideBuffBar", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    bar:SetSize(200, SIZE + 8)
    local p = ForeverGuideDB.buffPos
    if p then bar:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else bar:SetPoint("TOP", UIParent, "TOP", 0, -120) end
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local a, _, rel, x, y = self:GetPoint()
        ForeverGuideDB.buffPos = { a, rel, x, y }
    end)
    if bar.SetBackdrop then
        bar:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                          tile = true, tileSize = 16, edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
        bar:SetBackdropColor(0, 0, 0, 0.6)
    end
    bar.title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.title:SetPoint("TOPLEFT", 6, -6)
    bar.title:SetText("Buffs")
end

-- Rebuild which buttons exist and what they do. Only out of combat.
local function doLayout(ctx)
    if InCombatLockdown() then needLayout = true return end
    needLayout = false
    local me = ctx.me
    local x, width = 40, 40
    layout.self = {}
    for _, c in ipairs(FG.buffChecks) do
        if applies(c, me, ctx) then table.insert(layout.self, c) end
    end
    layout.selfBtns = {}
    local used, n = {}, 0
    for i, c in ipairs(layout.self) do
        local b
        if c.button then b = selfButton(nil, c.button) else n = n + 1; b = selfButton(n) end
        layout.selfBtns[i] = b
        used[b] = true
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", x, -4)
        x = x + SIZE + PAD
        local kind, value = selfAction(c, me)
        b:SetAttribute("type", kind)
        b:SetAttribute(kind or "spell", value)
        b:SetAttribute("unit", "player")
        b.check = c
        b:Show()
    end
    for _, b in ipairs(selfButtons) do if not used[b] then b:Hide() end end
    for _, b in pairs(namedButtons) do if not used[b] then b:Hide() end end
    width = math.max(width, x)

    -- Rows for buffs you give: your class's spells, and elixirs if you have Alchemy
    layout.give = {}
    if ForeverGuideDB.buffGive ~= false then
        for _, c in ipairs(FG.buffChecks) do
            if checkOn(c) then
                local spell = c.give and c.from == me.class and (type(c.give) == "function" and c.give(me) or c.give)
                if c.blessing and spell then spell = "Blessing of Might" end
                if spell and spellKnown(spell) then table.insert(layout.give, c)
                elseif c.elixir and ctx.alchemy then table.insert(layout.give, c) end
            end
        end
    end
    local y = -4 - SIZE - PAD
    for i, c in ipairs(layout.give) do
        local r = giveRow(i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 14, y)
        r.check = c
        r.icon:SetTexture(c.give and spellIcon(type(c.give) == "function" and c.give(me) or c.give) or c.icon)
        local rx = SIZE + 2
        local shown = 0
        for _, m in ipairs(ctx.members) do
            if applies(c, m, ctx) then
                shown = shown + 1
                local b = memberButton(r, shown)
                b:ClearAllPoints()
                b:SetPoint("LEFT", r, "LEFT", rx, 0)
                rx = rx + 54
                b.member = m
                b.label:SetText((m.name or "?"):sub(1, 6) .. " |cff888888" .. FG:RoleOf(m.name, m.class):sub(1, 1) .. "|r")
                b.tradeUnit = nil
                if c.give then
                    b:SetAttribute("type", "spell")
                    b:SetAttribute("spell", type(c.give) == "function" and c.give(m) or c.give)
                    b:SetAttribute("unit", m.unit)
                elseif m.unit == "player" then
                    local p = bestInBags(elixirList(c.elixir, m.class), m.level)
                    b:SetAttribute("type", p and "item" or nil)
                    b:SetAttribute("item", p and ("item:" .. p[3]) or nil)
                else
                    b:SetAttribute("type", nil)
                    b.tradeUnit = m.unit
                end
                b:Show()
            end
        end
        for j = shown + 1, #r.members do r.members[j]:Hide() end
        r.count = shown
        r:SetWidth(rx)
        r:Show()
        width = math.max(width, rx + 14)
        y = y - SIZE
    end
    for i = #layout.give + 1, #giveRows do giveRows[i]:Hide() end
    bar:SetSize(width + 4, -y + 4)
end

local function colorEdge(tex, st)
    local c = COLORS[st] or COLORS.unknown
    tex:SetColorTexture(c[1], c[2], c[3], 1)
end

local lastKey
function FG:UpdateBuffBar()
    if not ForeverGuideDB or ForeverGuideDB.showBuffs == false then
        if bar and not InCombatLockdown() then bar:Hide() end
        return
    end
    if not bar then createBar() end
    local ctx = context()
    -- Re-layout when the group, levels, Alchemy, spells or bag contents change
    local key = {}
    for _, m in ipairs(ctx.members) do
        table.insert(key, (m.name or "?") .. (m.level or 0) .. (m.class or "") .. FG:WantedBlessing(m) .. FG:RoleOf(m.name, m.class))
    end
    for k, t in pairs(ForeverGuideDB.buffRoles or {}) do
        for r, v in pairs(t) do table.insert(key, k .. r .. tostring(v)) end
    end
    table.insert(key, tostring(ctx.alchemy) .. #ctx.alchemists)
    for _, c in ipairs(self.buffChecks) do
        local kind, value = selfAction(c, ctx.me)
        table.insert(key, tostring(value) .. tostring(checkOn(c)))
    end
    key = table.concat(key, ",") .. tostring(ForeverGuideDB.buffGive)
    if key ~= lastKey or needLayout then
        if not InCombatLockdown() then lastKey = key end
        doLayout(ctx)
    end
    if not InCombatLockdown() then bar:Show() end

    local mySet = auraSet("player")
    local missing = 0
    for i, c in ipairs(layout.self) do
        local b = layout.selfBtns[i]
        local st, detail, t = status(c, ctx.me, mySet)
        colorEdge(b.edge, st)
        local a = c.names and mySet[c.names[1]]
        local icon = c.blessing and ("Interface\\Icons\\" .. (BLESSING_ICONS[FG:WantedBlessing()] or "Spell_Holy_FistOfJustice"))
        if c.totem then icon = spellIcon(firstKnown(c.spells) or "") end
        b.icon:SetTexture((a and a.icon) or icon or (c.cast and spellIcon(c.cast)) or c.icon)
        b.icon:SetDesaturated(st == "missing")
        if st == "missing" then b.icon:SetVertexColor(1, 0.4, 0.4) missing = missing + 1 else b.icon:SetVertexColor(1, 1, 1) end
        b.text:SetText(c.potions and tostring(detail or 0) or (c.totem and t and tostring(math.floor(t)))
            or (t and t < 600 and (math.floor(t / 60) .. "m")) or "")
        b.tipTitle = c.label
        b.tip = selfTip(c, ctx.me, ctx, st, detail, t)
    end
    bar.title:SetText(missing > 0 and ("|cffff4040Buffs|r\n|cffff4040" .. missing .. "|r") or "|cff4dff4dBuffs|r")

    local sets = { player = mySet }
    for _, r in ipairs(giveRows) do
        if r:IsShown() and r.check then
            local c = r.check
            for j = 1, r.count or 0 do
                local b = r.members[j]
                local m = b.member
                sets[m.unit] = sets[m.unit] or auraSet(m.unit)
                local st, detail, t = status(c, m, sets[m.unit])
                colorEdge(b.edge, st)
                b.tipTitle = ("%s on %s"):format(c.label, m.name or "?")
                if st == "missing" then
                    if c.blessing then
                        b.tipText = ("Wants Blessing of %s - click to cast%s"):format(FG:WantedBlessing(m), detail and (" (has " .. detail .. ")") or "")
                    elseif c.give then b.tipText = "Missing - click to cast"
                    elseif m.unit == "player" then b.tipText = "Missing - click to drink one"
                    else
                        local p = bestInBags(elixirList(c.elixir, m.class), m.level)
                        b.tipText = p and ("Missing - click to trade them %s (%d in bags)"):format(p[4], FG:ItemCount(p[3]))
                            or ("Missing - make %s"):format((recommend(c.elixir, m.class, m.level, ctx.alchemySkill) or { [4] = "an elixir" })[4])
                    end
                elseif st == "unknown" then b.tipText = "Out of range or dead"
                else b.tipText = (detail and type(detail) == "string" and detail .. " - " or "") .. (t and ("%d min left"):format(math.floor(t / 60 + 0.5)) or "active") end
            end
        end
    end
end

-- /fg buffs learn: if the campfire buff has a name we don't match, remember
-- whichever buff you have that no other check explains (sit at camp first)
function FG:LearnCampBuffs()
    local set = auraSet("player")
    ForeverGuideDB.campAuras = ForeverGuideDB.campAuras or {}
    local learned = {}
    for name in pairs(set) do
        local claimed = false
        for _, c in ipairs(self.buffChecks) do
            if not c.camp then
                local st = status(c, { unit = "player", class = select(2, UnitClass("player")), level = UnitLevel("player") }, { [name] = set[name] })
                if st == "ok" or st == "low" then claimed = true break end
            end
        end
        if not claimed and not isCampAura(name) then
            ForeverGuideDB.campAuras[name] = true
            table.insert(learned, name)
        end
    end
    if #learned > 0 then self:Print("Campfire buff learned: " .. table.concat(learned, ", ") .. " (/fg buffs forget to clear)")
    else self:Print("Nothing new to learn - sit at the campfire until its buff appears, then try again.") end
    self:UpdateBuffBar()
end

---------------------------------------------------------------------------
-- /fg buffs: per check, on/off and which roles get it (T H M C); on the
-- right, the party's roles and the blessing you want
---------------------------------------------------------------------------
local ROLE_COLORS = { TANK = "|cff6699ff", HEALER = "|cff66ff66", MELEE = "|cffff9933", CASTER = "|cffcc66ff" }

local function cycleRole(role)
    for i, r in ipairs(FG.ROLES) do if r == role then return FG.ROLES[i % #FG.ROLES + 1] end end
    return FG.ROLES[1]
end

function FG:RefreshRoleButtons()
    local f = self.buffOptions
    if not f then return end
    local units = { "player" }
    for i = 1, 4 do if UnitExists("party" .. i) then table.insert(units, "party" .. i) end end
    for i, b in ipairs(f.roleButtons) do
        local u = units[i]
        if u then
            local name = UnitName(u)
            local _, cls = UnitClass(u)
            b.name, b.class = name, cls
            local role = self:RoleOf(name, cls)
            b:SetText(("%s: %s%s|r"):format(name or "?", ROLE_COLORS[role], self.ROLE_NAMES[role]))
            b:Show()
        else
            b:Hide()
        end
    end
    f.blessingButton:SetText("Blessing I want: " .. self:WantedBlessing())
end

function FG:ToggleBuffOptions()
    if not self.buffOptions then
        local list = self.buffChecks
        local f = CreateFrame("Frame", "ForeverGuideBuffOptions", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetSize(560, 80 + (#list + 1) * 22)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        if f.SetBackdrop then
            f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                            tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
            f:SetBackdropColor(0, 0, 0, 0.9)
        end
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 12, -10)
        title:SetText("ForeverGuide buff checks")
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 0, 0)

        -- Column headers for the role toggles
        local head = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        head:SetPoint("TOPLEFT", 200, -30)
        head:SetText(ROLE_COLORS.TANK .. "T|r    " .. ROLE_COLORS.HEALER .. "H|r    " .. ROLE_COLORS.MELEE .. "M|r    " .. ROLE_COLORS.CASTER .. "C|r")

        f.checks, f.roleChecks = {}, {}
        local entries = {}
        for _, c in ipairs(list) do table.insert(entries, { key = c.key, label = c.label, c = c }) end
        table.insert(entries, { key = "_give", label = "Rows for buffs you give" })
        for i, e in ipairs(entries) do
            local y = -44 - (i - 1) * 22
            local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
            cb:SetSize(22, 22)
            cb:SetPoint("TOPLEFT", 10, y)
            local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
            label:SetWidth(156)   -- stop before the T/H/M/C boxes
            label:SetJustifyH("LEFT")
            if label.SetWordWrap then label:SetWordWrap(false) end
            label:SetText(e.label)
            cb:SetScript("OnClick", function(self)
                if e.key == "_give" then
                    ForeverGuideDB.buffGive = self:GetChecked() and true or false
                else
                    ForeverGuideDB.buffChecks = ForeverGuideDB.buffChecks or {}
                    ForeverGuideDB.buffChecks[e.key] = self:GetChecked() and true or false
                end
                FG:UpdateBuffBar()
            end)
            cb.entry = e
            table.insert(f.checks, cb)
            if e.c then
                for j, role in ipairs(FG.ROLES) do
                    local rc = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
                    rc:SetSize(20, 20)
                    rc:SetPoint("TOPLEFT", 194 + (j - 1) * 24, y - 1)
                    rc:SetScript("OnClick", function(self) FG:SetCheckForRole(e.key, role, self:GetChecked()) end)
                    rc.key, rc.role = e.key, role
                    table.insert(f.roleChecks, rc)
                end
            end
        end

        -- Right side: party roles (click to change) and your blessing
        local rt = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        rt:SetPoint("TOPLEFT", 320, -30)
        rt:SetText("Roles (click to change)")
        f.roleButtons = {}
        for i = 1, 5 do
            local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
            b:SetSize(220, 22)
            b:SetPoint("TOPLEFT", 320, -48 - (i - 1) * 24)
            b:SetScript("OnClick", function(self)
                if self.name then FG:SetRole(self.name, cycleRole(FG:RoleOf(self.name, self.class))) end
                FG:RefreshRoleButtons()
            end)
            f.roleButtons[i] = b
        end
        local bl = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        bl:SetSize(220, 22)
        bl:SetPoint("TOPLEFT", 320, -48 - 5 * 24 - 12)
        bl:SetScript("OnClick", function()
            local cur, blist = FG:WantedBlessing(), FG.BLESSINGS
            for i, b in ipairs(blist) do
                if b == cur then FG:SetWantedBlessing(blist[i % #blist + 1]) break end
            end
            FG:RefreshRoleButtons()
        end)
        f.blessingButton = bl
        local note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        note:SetPoint("TOPLEFT", bl, "BOTTOMLEFT", 0, -6)
        note:SetWidth(220)
        note:SetJustifyH("LEFT")
        note:SetText("Roles and your blessing are shared with the party. T/H/M/C: which roles each buff is checked for.")
        self.buffOptions = f
        f:Hide()
    end
    local f = self.buffOptions
    if f:IsShown() then f:Hide() return end
    for _, cb in ipairs(f.checks) do
        if cb.entry.key == "_give" then cb:SetChecked(ForeverGuideDB.buffGive ~= false)
        else cb:SetChecked(checkOn(cb.entry.c)) end
    end
    for _, rc in ipairs(f.roleChecks) do rc:SetChecked(self:CheckForRole(rc.key, rc.role)) end
    self:RefreshRoleButtons()
    f:Show()
end

-- /fg role tank            - your own role
-- /fg role tank Grommash   - someone else's
function FG:RoleCommand(rest)
    local role, name = (rest or ""):match("^(%S*)%s*(.-)$")
    if name == "" then name = UnitName("player") end
    -- party names are matched case-insensitively
    for i = 1, 4 do
        local n = UnitName("party" .. i)
        if n and n:lower() == name:lower() then name = n end
    end
    if not self.ROLE_NAMES[(role or ""):upper()] then
        self:Print("/fg role tank|healer|melee|caster [name]")
        return
    end
    self:SetRole(name, role)
end

function FG:BuffCommand(rest)
    rest = (rest or ""):lower()
    local cmd, arg = rest:match("^(%S*)%s*(.-)$")
    if cmd == "blessing" then self:SetWantedBlessing(arg)
    elseif cmd == "role" then self:RoleCommand(arg)
    elseif rest == "learn" then self:LearnCampBuffs()
    elseif rest == "forget" then ForeverGuideDB.campAuras = {} self:Print("Forgot learned camp buffs.") self:UpdateBuffBar()
    elseif rest == "reset" then ForeverGuideDB.buffPos = nil
        if bar and not InCombatLockdown() then bar:ClearAllPoints() bar:SetPoint("TOP", UIParent, "TOP", 0, -120) end
    else self:ToggleBuffOptions() end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "UNIT_AURA", "GROUP_ROSTER_UPDATE", "PLAYER_LEVEL_UP", "BAG_UPDATE_DELAYED",
                     "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_TOTEM_UPDATE", "SPELLS_CHANGED", "UNIT_INVENTORY_CHANGED", "SKILL_LINES_CHANGED" }) do
    ev:RegisterEvent(e)
end
local pending = false
local function queue()
    if pending then return end
    pending = true
    C_Timer.After(0.3, function()
        pending = false
        local ok, err = pcall(FG.UpdateBuffBar, FG)
        if not ok then FG:Print("Buff bar error: " .. tostring(err)) end
    end)
end
ev:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" and unit and unit ~= "player" and not unit:find("^party%d$") then return end
    if event == "PLAYER_LOGIN" then
        -- after Init.lua sets up saved variables; then a slow tick for timers / weapon imbues
        C_Timer.After(1, function()
            queue()
            C_Timer.NewTicker(5, queue)
        end)
        return
    end
    queue()
end)

-- Key Bindings > AddOns > ForeverGuide (Bindings.xml)
BINDING_HEADER_FOREVERGUIDE = "ForeverGuide"
_G["BINDING_NAME_CLICK ForeverGuideTotemEarth:LeftButton"] = "Drop Strength of Earth Totem"
_G["BINDING_NAME_CLICK ForeverGuideTotemAir:LeftButton"] = "Drop air totem (Windfury / Grace of Air)"
