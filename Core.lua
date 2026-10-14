-- Core: namespace, guide registration, quest + position helpers
local addonName, FG = ...
_G.ForeverGuide = FG   -- lets separate guide addons call ForeverGuide:RegisterGuide{...}

FG.guides = {}
FG.guideOrder = {}

function FG:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ForeverGuide|r: " .. tostring(msg))
end

---------------------------------------------------------------------------
-- Guide registration
--   name     (required) unique guide name
--   races    list of englishRace tokens: "Orc","Troll","Tauren","Scourge"
--   classes  list of class tokens: "SHAMAN","WARRIOR",... (nil = any class)
--   minLevel / maxLevel   used for auto-selection
--   map      default uiMapID for steps without their own map
--   next     name of the guide to load when this one is finished
--   steps    list of step tables (see README)
---------------------------------------------------------------------------
-- Elite / group quests: optional when you're solo (skip if you can't get help)
FG.groupQuests = { [883] = "Lakota'mani", [4021] = "Counterattack!" }

-- Before each dungeon: a "look for a group" step. In a group it's already done;
-- solo, Skip on it (or the dungeon, or its quests) skips that dungeon and its quests.
local function prepareGroupSteps(guide)
    local out = {}
    local tagOf = {}   -- questID -> solo tag
    for _, step in ipairs(guide.steps) do
        if step.dungeon then
            local tag = step.optional or ("Dungeon: " .. step.dungeon)
            for _, q in ipairs(step.quests or {}) do tagOf[q] = tag end
            for _, q in ipairs(step.followUps or {}) do tagOf[q] = tag end   -- chains that need the dungeon
        end
    end
    for q, name in pairs(FG.groupQuests) do tagOf[q] = tagOf[q] or ("Group quest: " .. name) end
    for _, step in ipairs(guide.steps) do
        local q = step.accept or step.complete or step.turnin
        if step.dungeon then
            local tag = step.optional or ("Dungeon: " .. step.dungeon)
            table.insert(out, { lfg = step.dungeon, soloOptional = tag, optional = step.optional, x = step.x, y = step.y, map = step.map,
                                classes = step.classes, races = step.races, quests = step.quests })
            if not step.optional then step.soloOptional = tag end
        elseif q and tagOf[q] and not step.optional then
            step.soloOptional = tagOf[q]
        end
        table.insert(out, step)
    end
    guide.steps = out
end

function FG:RegisterGuide(guide)
    assert(type(guide.name) == "string", "ForeverGuide: guide needs a name")
    guide.steps = guide.steps or {}
    prepareGroupSteps(guide)
    for i, step in ipairs(guide.steps) do
        step.index = i
        step.map = step.map or guide.map
    end
    if not self.guides[guide.name] then
        table.insert(self.guideOrder, guide.name)
    end
    self.guides[guide.name] = guide
end

---------------------------------------------------------------------------
-- Quest helpers
---------------------------------------------------------------------------
function FG:IsQuestTurnedIn(id)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        return C_QuestLog.IsQuestFlaggedCompleted(id) and true or false
    end
    if IsQuestFlaggedCompleted then
        return IsQuestFlaggedCompleted(id) and true or false
    end
    return false
end

-- FindQuestInLog lives in Compat.lua (it differs between Classic and Forever)

-- Objective lines ("Mottled Boar slain: 4/10") for a quest in the log
function FG:GetObjectiveLines(id)
    if not self:FindQuestInLog(id) then return nil end
    local lines = {}
    for _, o in ipairs(self:QuestObjectives(id)) do
        if o.text then
            table.insert(lines, (o.finished and "|cff00ff00" or "|cffbbbbbb") .. "   - " .. o.text .. "|r")
        end
    end
    return lines
end

-- A step's reward for this character's class. reward / rewardName can be a
-- plain value (same for everyone) or a table keyed by class token, with an
-- optional "default" entry: reward = { SHAMAN = 4964, WARRIOR = 4964, default = 4974 }
function FG:StepReward(step)
    local r, n = step.reward, step.rewardName
    if type(r) == "table" or type(n) == "table" then
        local _, class = UnitClass("player")
        if type(r) == "table" then r = r[class] or r.default end
        if type(n) == "table" then n = n[class] or n.default end
    end
    return r, n
end

-- Quest title from the log, or from the guide steps that mention it
function FG:QuestTitle(id)
    if self:FindQuestInLog(id) then
        local t = self:LogQuestTitle(id)
        if t then return t end
    end
    local guide = self.GetGuide and self:GetGuide()
    for _, s in ipairs(guide and guide.steps or {}) do
        if (s.accept == id or s.turnin == id or s.complete == id) and s.title then return s.title end
    end
    return "quest #" .. id
end

---------------------------------------------------------------------------
-- Position helpers (map coords are 0-100 like Wowhead / TomTom)
---------------------------------------------------------------------------
function FG:GetPlayerMapPos()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return end
    local x, y = pos:GetXY()
    if not x or (x == 0 and y == 0) then return end
    return mapID, x * 100, y * 100
end

local function toWorld(mapID, x, y)
    local continent, world = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x / 100, y / 100))
    if not continent or not world then return end
    local wx, wy = world:GetXY()
    return continent, wx, wy
end

-- Distance (yards) and bearing (radians, counter-clockwise from north,
-- same convention as GetPlayerFacing) from the player to a map point.
-- World X points north, world Y points west.
function FG:GetVectorTo(mapID, x, y)
    local pMap, px, py = self:GetPlayerMapPos()
    if not pMap then return end
    local c1, ax, ay = toWorld(pMap, px, py)
    local c2, bx, by = toWorld(mapID, x, y)
    if not c1 or not c2 or c1 ~= c2 then return end
    local dNorth, dWest = bx - ax, by - ay
    return math.sqrt(dNorth * dNorth + dWest * dWest), math.atan2(dWest, dNorth)
end

---------------------------------------------------------------------------
-- Step text
---------------------------------------------------------------------------
local function qname(step, id)
    return "|cffffffff" .. (step.title or ("quest #" .. id)) .. "|r"
end

function FG:InGroup() return IsInGroup and IsInGroup() or false end
-- Dungeons need 5: a smaller party (e.g. 3 questing together) still looks for the rest
function FG:FullGroup()
    return self:InGroup() and (GetNumGroupMembers and GetNumGroupMembers() or 5) >= 5
end
-- The solo tag that applies right now: dungeons (and their quests) until the group
-- is full, group quests only when you're alone
function FG:SoloOptionalOn(step)
    local tag = step.soloOptional
    if not tag then return nil end
    if tag:match("^Group quest") then return not self:InGroup() and tag or nil end
    return not self:FullGroup() and tag or nil
end

-- Group wording reworded for solo players
local SOLO_WORDS = {
    { "Meet the group at the Crossroads%. Invite everyone%.", "Head to the Crossroads." },
    { "when the group flies to Thunder Bluff", "on your Thunder Bluff trip" },
    { "Group session", "Profession session" },
    { "The group can kill", "Kill" },
    { "Group kills them with you%.", "" },
    { "catch up with the group in the south", "carry on south" },
    { "the group goes near there", "the route goes near there" },
    { "Everyone tops up their own food%.", "Top up your food." },
    { "[Vv]ery easy with five%.", "A group makes this easy - skip it if it's too hard solo." },
    { "[Ee]asy with five%.?", "A group makes this easy - skip it if it's too hard solo." },
    { "start when everyone is ready", "start when you're ready" },
    { "have everyone ready", "be ready" },
    { "five people share few rocks, so split up or skip", "loot the rocks on the ground" },
}
local function soloText(s)
    for _, w in ipairs(SOLO_WORDS) do s = s:gsub(w[1], w[2]) end
    return s
end

function FG:StepText(step)
    local lines = {}
    local function add(s) table.insert(lines, s) end
    if step.lfg then
        local n = self:InGroup() and (GetNumGroupMembers and GetNumGroupMembers() or 0) or 0
        add("|cffff9900[Optional" .. (n > 0 and "" or " solo") .. "]|r |cffffcc80" .. (step.optional or step.lfg) .. "|r")
        if n > 0 then
            add(("|cff66ccffFind %d more|r for |cffffffff%s|r"):format(math.max(1, 5 - n), step.lfg))
            add("Dungeon Finder, /lfg or trade chat - this step finishes when the group has 5 (or you enter the dungeon).")
        else
            add("|cff66ccffLook for a group|r for |cffffffff" .. step.lfg .. "|r")
            add("Dungeon Finder, /lfg or trade chat - this step finishes when the group has 5 (or you enter the dungeon).")
        end
        add("|cff888888Can't find one? Skip skips the dungeon and its quests (/fg back to undo).|r")
        return table.concat(lines, "\n")
    end

    -- Optional steps say so up front
    if step.optional then
        add("|cffff9900[Optional]|r |cffffcc80" .. step.optional .. "|r")
    elseif self:SoloOptionalOn(step) then
        add("|cffff9900[Optional" .. (self:InGroup() and "" or " solo") .. "]|r |cffffcc80" .. step.soloOptional .. "|r")
    end
    if step.accept   then add("|cffffff00Accept|r "  .. qname(step, step.accept)) end
    if step.complete then
        add("|cffff8040Complete|r " .. qname(step, step.complete))
        local obj = self:GetObjectiveLines(step.complete)
        if obj then for _, l in ipairs(obj) do add(l) end end
    end
    if step.turnin   then add("|cff00ff00Turn in|r " .. qname(step, step.turnin)) end
    if step.level    then add(("Reach level |cffffffff%d|r"):format(step.level)) end
    if step.bind     then add("|cff66ccffSet hearthstone|r at |cffffffff" .. step.bind .. "|r") end
    if step.hearth   then
        local cd = self:HearthCooldown()
        add("|cff66ccffHearth|r to |cffffffff" .. step.hearth .. "|r"
            .. (cd > 0 and ("  |cffff4040(cooldown %d:%02d - run instead)|r"):format(cd / 60, cd % 60) or ""))
    end
    if step.deathskip then
        add("|cffcc66ffDeath skip|r: die, release, take the Spirit Healer res at |cffffffff"
            .. step.deathskip .. "|r (no res sickness at level 10 or below)")
    end
    if step.train    then add("|cff66ccffTrain|r at |cffffffff" .. step.train .. "|r") end
    if step.fp       then add("|cff66ccffGet the flight path|r at |cffffffff" .. step.fp .. "|r") end
    if step.skill    then
        add(("|cff66ccffProfession|r: %s |cffffffff%d|r  |cff888888(now %d)|r"):format(
            step.skill[1], step.skill[2], self:SkillRank(step.skill[1]) or 0))
    end
    if step.item     then
        add(("|cff66ccffCollect|r %s  |cffffffff%d/%d|r"):format(
            step.itemName or ("item #" .. step.item), self:ItemCount(step.item), step.count or 1))
    end
    if step.buff     then add("|cff66ccffGet buff|r |cffffffff" .. step.buff .. "|r") end
    if step.secondary then
        add("|cff66ccffGroup profession session|r - craft, cook and fish together")
        for _, name in ipairs({ "First Aid", "Cooking", "Fishing" }) do
            local target = step.secondary[name]
            if target then
                local rank = self:SkillRank(name)
                local color = (rank or 0) >= target and "|cff00ff00" or "|cffff8040"
                add(("   %s%s %s/%d|r"):format(color, name, rank and tostring(rank) or "-", target))
            end
        end
        local stock = self.FoodStockLine and self:FoodStockLine(true)
        if stock then add("   " .. stock) end
    end
    if step.dungeon  then
        add("|cffff66ccDungeon|r |cffffffff" .. step.dungeon .. "|r")
        for _, id in ipairs(step.quests or {}) do
            local state
            if self:IsQuestTurnedIn(id) then state = "|cff00ff00turned in|r"
            else
                local idx, complete = self:FindQuestInLog(id)
                state = not idx and "|cff888888not picked up|r"
                    or (complete and "|cff00ff00done|r" or "|cffff8040to do|r")
            end
            add(("   - %s: %s"):format(self:QuestTitle(id), state))
        end
    end
    local reward, rewardName = self:StepReward(step)
    if reward then add("|cff888888Reward: " .. (rewardName or ("item #" .. reward)) .. " (auto-picked)|r") end
    if step.npc      then add("NPC: |cffffffff" .. step.npc .. "|r") end
    if step.travel   then add("Go to the waypoint") end
    if step.x and step.y then add(("|cff888888(%.1f, %.1f)|r"):format(step.x, step.y)) end
    if step.text     then add(self:InGroup() and step.text or soloText(step.text)) end
    if step.optional then add("|cff888888Optional: " .. step.optional .. " - Skip skips the whole detour|r")
    elseif self:SoloOptionalOn(step) then
        add("|cff888888" .. (self:InGroup() and "Until the group has 5" or "Solo") .. ": optional - Skip skips " .. step.soloOptional:gsub("^%a+ ?%a*: ", "") .. " and its quests|r")
    end

    local manual = not (step.accept or step.complete or step.turnin or step.level or step.travel
        or step.bind or step.hearth or step.deathskip or step.skill or step.item or step.buff or step.train
        or step.dungeon or step.fp or step.secondary)
    if manual then add("|cff888888Click Skip when done|r") end
    return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Player state helpers for the extra step types
---------------------------------------------------------------------------
local HEARTHSTONE = 6948

-- Seconds left on the hearthstone cooldown (0 = ready)
function FG:HearthCooldown()
    local getCD = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if not getCD then return 0 end
    local start, duration = getCD(HEARTHSTONE)
    if not start or start == 0 or not duration then return 0 end
    return math.max(0, math.floor(start + duration - GetTime()))
end

-- Current rank of a profession / skill line by name, or nil if not learned
function FG:SkillRank(name)
    if GetNumSkillLines then
        for i = 1, GetNumSkillLines() do
            local skillName, isHeader, _, rank = GetSkillLineInfo(i)
            if not isHeader and skillName == name then return rank end
        end
    end
    if GetProfessions and GetProfessionInfo then
        for _, idx in pairs({ GetProfessions() }) do
            local skillName, _, rank = GetProfessionInfo(idx)
            if skillName == name then return rank end
        end
    end
end

function FG:HasBuff(name)
    if AuraUtil and AuraUtil.FindAuraByName then
        return AuraUtil.FindAuraByName(name, "player", "HELPFUL") ~= nil
    end
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not aura then return false end
            if aura.name == name then return true end
        end
        return false
    end
    if not UnitBuff then return false end
    for i = 1, 40 do
        local n = UnitBuff("player", i)
        if not n then return false end
        if n == name then return true end
    end
    return false
end
