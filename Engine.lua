-- Engine: works out the current step from live game state.
-- The current step is simply the first step that isn't done, so anything
-- already completed (or done out of order) is skipped automatically.
local _, FG = ...

-- Steps finished by doing something the game can't be asked about later
-- (arriving somewhere, closing a trainer, opening a flight map). Saved per
-- character so a /reload doesn't send you back to them.
function FG:MarkReached(step)
    local _, g = self:GetGuide()
    if not g then return end
    local r = ForeverGuideCharDB.reached
    r[g] = r[g] or {}
    if not r[g][step.index] then
        r[g][step.index] = true
        self:Recalculate()
    end
end

function FG:IsReached(step, guideName)
    local r = ForeverGuideCharDB.reached[guideName]
    return r and r[step.index] or false
end

function FG:GetGuide()
    local name = ForeverGuideCharDB and ForeverGuideCharDB.guide
    return name and self.guides[name], name
end

---------------------------------------------------------------------------
-- Catching up after going off-script: quests you've outleveled are skipped,
-- unless a quest you still want needs them (chains), or it's a class quest.
---------------------------------------------------------------------------
-- How many levels below you a quest can be before it's grey (the game's rule if available)
local function greenRange(level)
    if GetQuestGreenRange then
        local ok, r = pcall(GetQuestGreenRange, "player")
        if ok and r then return r end
    end
    return 5 + math.floor(level / 10)
end

-- Have you outleveled this quest? Yes once it gives reduced XP (6+ levels below
-- you) or is grey. Quests with no known level fall back to how far you are past
-- the section they're in.
function FG:QuestGray(q, guide)
    local level = UnitLevel("player")
    local d = self.questData and self.questData[q]
    if d and d[1] then return level - d[1] >= 6 or level - d[1] > greenRange(level) end
    return guide ~= nil and guide.maxLevel ~= nil and level - guide.maxLevel >= 4
end

-- A whole section you're well past (its travel / flight path / session steps get skipped)
function FG:SectionOutleveled(guide)
    return guide and guide.maxLevel and UnitLevel("player") > guide.maxLevel + 2
end

-- Quests to keep even if grey: prerequisites of quests you still want, from
-- this section on (rebuilt on level up and /fg sync)
function FG:BuildNeededQuests()
    local needed, live = {}, {}
    local _, name = self:GetGuide()
    local seen = {}
    while name and self.guides[name] and not seen[name] do
        seen[name] = true
        local g = self.guides[name]
        for _, s in ipairs(g.steps) do
            local q = s.accept or s.complete or s.turnin
            -- worth unlocking: class quests, or quests still a good level for you (not near grey)
            local d = self.questData and self.questData[q]
            local good = d and d[1] and (UnitLevel("player") - d[1] <= 3)
            if q and not self:IsQuestTurnedIn(q) and (s.classes or good) then live[q] = true end
        end
        name = g.next
    end
    local function walk(q, depth)
        local d = self.questData and self.questData[q]
        if not d or not d[2] or depth >= 4 then return end   -- short chains only
        for _, p in ipairs(d[2]) do
            if not needed[p] then needed[p] = true; walk(p, depth + 1) end
        end
    end
    for q in pairs(live) do walk(q, 0) end
    self.neededQuests, self.neededLevel = needed, UnitLevel("player")
    return needed
end

-- True if this step should be skipped because you've outleveled it
function FG:Outleveled(step, guideName)
    if ForeverGuideDB.skipOutleveled == false or step.classes then return false end
    local guide = self.guides[guideName]
    if not self.neededQuests or self.neededLevel ~= UnitLevel("player") then self:BuildNeededQuests() end
    local q = step.accept or step.complete or step.turnin
    if q then
        if self.neededQuests[q] or not self:QuestGray(q, guide) then return false end
        local idx, complete = self:FindQuestInLog(q)
        if idx and step.turnin and complete then return false end   -- finished already: still hand it in
        return true
    end
    if step.dungeon or step.lfg then
        -- a dungeon (or its look-for-group step) whose quests are all grey for you
        for _, dq in ipairs(step.quests or {}) do
            if self.neededQuests[dq] or not self:QuestGray(dq, guide) then return false end
        end
        return #(step.quests or {}) > 0 or self:SectionOutleveled(guide)
    end
    -- travel, flight paths, hearth, sessions, items, look-for-group: only when the section is behind you
    if step.level then return false end
    return self:SectionOutleveled(guide) and true or false
end

-- /fg sync: re-check everything against your level and finished quests
function FG:Resync(quiet)
    self:BuildNeededQuests()
    local before = ForeverGuideCharDB.guide
    self:Recalculate()
    if not quiet then
        local _, name = self:GetGuide()
        local step = self.currentStep
        self:Print(("Synced to level %d: |cffffffff%s|r, step %s%s"):format(UnitLevel("player"), name or "?",
            step and step.index or "-", before ~= name and (" (moved on from " .. tostring(before) .. ")") or ""))
    end
end

function FG:IsStepDone(step, guideName)
    local skipped = ForeverGuideCharDB.skipped[guideName]
    if skipped and skipped[step.index] then return true end
    -- classes / races on a step: only for those characters (class quests, racial breadcrumbs)
    if step.classes and not self:ListHas(step.classes, select(2, UnitClass("player"))) then return true end
    if step.races and not self:ListHas(step.races, select(2, UnitRace("player"))) then return true end
    -- maxLevel: the step stops being worth it above this level (death skips, low XP quests)
    if step.maxLevel and UnitLevel("player") > step.maxLevel then return true end
    -- went off-script and outleveled it (keeps chains you still need)
    if self:Outleveled(step, guideName) then return true end

    -- Turn-in / complete steps for a quest you don't have and never finished
    -- don't apply to you (a breadcrumb only your race gets, a quest that
    -- dropped for someone else, an accept the NPC didn't offer). Accept steps
    -- always come first in a guide, so this never skips ahead of them.
    if step.turnin then
        if self:IsQuestTurnedIn(step.turnin) then return true end
        return self:FindQuestInLog(step.turnin) == nil
    end
    if step.complete then
        if self:IsQuestTurnedIn(step.complete) then return true end
        local idx, isComplete = self:FindQuestInLog(step.complete)
        if not idx then return true end
        return isComplete and true or false
    end
    if step.accept then
        -- alt = other IDs for the same quest (e.g. Horde/Alliance versions)
        for _, id in ipairs({ step.accept, unpack(step.alt or {}) }) do
            if self:IsQuestTurnedIn(id) or self:FindQuestInLog(id) ~= nil then return true end
        end
        return false
    end
    if step.level then
        return UnitLevel("player") >= step.level
    end
    -- Steps whose condition can stop being true later (you rebind, turn in
    -- or use the items, a buff runs out, you walk away) are remembered once met.
    local function sticky(met)
        if met then
            local r = ForeverGuideCharDB.reached
            r[guideName] = r[guideName] or {}
            r[guideName][step.index] = true
        end
        return met or self:IsReached(step, guideName)
    end
    if step.bind then
        return sticky(GetBindLocation() == step.bind)
    end
    if step.hearth or step.deathskip then
        local dest = step.hearth or step.area
        return sticky(dest ~= nil and GetSubZoneText() == dest)
    end
    if step.lfg then
        -- 5 in the group, or you went in short-handed; remembered, so leaving later doesn't send you back
        local inside, kind = IsInInstance()
        return sticky(FG:FullGroup() or (inside and kind == "party"))
    end
    if step.travel or step.train or step.fp then
        return self:IsReached(step, guideName)
    end
    if step.skill then
        return (self:SkillRank(step.skill[1]) or -1) >= step.skill[2]
    end
    if step.item then
        return sticky(self:ItemCount(step.item) >= (step.count or 1))
    end
    if step.secondary then
        -- Group profession session: done once each listed skill you have is at
        -- its target (skills you haven't learned don't hold you up)
        local ok = true
        for name, target in pairs(step.secondary) do
            local rank = self:SkillRank(name)
            if rank and rank < target then ok = false end
        end
        return sticky(ok)
    end
    if step.buff then
        return sticky(self:HasBuff(step.buff))
    end
    if step.dungeon then
        -- Done when every dungeon quest you picked up is complete or turned in.
        -- Quests you never picked up are ignored; with none at all, click Skip.
        local have = false
        for _, id in ipairs(step.quests or {}) do
            if self:IsQuestTurnedIn(id) then
                have = true
            else
                local idx, complete = self:FindQuestInLog(id)
                if idx then
                    have = true
                    if not complete then return false end
                end
            end
        end
        return have
    end
    return false   -- text-only steps advance with Skip
end

function FG:Recalculate()
    local guide, name = self:GetGuide()
    self.currentStep = nil
    if guide then
        for _, step in ipairs(guide.steps) do
            if not self:IsStepDone(step, name) then
                self.currentStep = step
                break
            end
        end
        if not self.currentStep and guide.next and self.guides[guide.next] then
            self:Print("Finished " .. name .. " - loading " .. guide.next)
            self:SetGuide(guide.next)
            return
        end
    end
    self:UpdateUI()
end

function FG:QueueRecalc(delay)
    if self.recalcPending then return end
    self.recalcPending = true
    C_Timer.After(delay or 0.2, function()
        FG.recalcPending = false
        FG:Recalculate()
    end)
end

function FG:SetGuide(name)
    if not self.guides[name] then
        self:Print("No guide named " .. tostring(name))
        return
    end
    ForeverGuideCharDB.guide = name
    self.keepList = nil
    self:BuildQuestLookup()
    self:Recalculate()
end

-- Quest IDs / titles the current guide cares about (used by Automation),
-- and the reward to pick for each quest that offers a choice
function FG:BuildQuestLookup()
    self.guideQuestIDs, self.guideTitles, self.guideRewards = {}, {}, {}
    local guide = self:GetGuide()
    if not guide then return end
    for _, s in ipairs(guide.steps) do
        for _, key in ipairs({ "accept", "turnin", "complete" }) do
            if s[key] then self.guideQuestIDs[s[key]] = true end
        end
        for _, id in ipairs(s.alt or {}) do self.guideQuestIDs[id] = true end
        if s.title then self.guideTitles[s.title] = true end
        local reward = s.turnin and self:StepReward(s)
        if reward then
            self.guideRewards[s.turnin] = reward
            if s.title then self.guideRewards[s.title] = reward end
        end
    end
end

function FG:ListHas(list, value)
    if not list then return true end
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end
local function listHas(list, value) return FG:ListHas(list, value) end

-- Picks the guide for this character: a guide for the map you're standing
-- on (startMaps) wins, then one written for your class, then any guide for
-- your race / faction at your level.
function FG:AutoPickGuide()
    local _, race = UnitRace("player")
    local _, class = UnitClass("player")
    local faction = UnitFactionGroup("player")
    local level = UnitLevel("player")
    local mapID = C_Map.GetBestMapForUnit("player")
    local byClass, generic
    for _, name in ipairs(self.guideOrder) do
        local g = self.guides[name]
        local levelOK = (g.minLevel or 1) <= level and level <= (g.maxLevel or 60)
        local factionOK = not g.faction or g.faction == faction
        if levelOK and factionOK and listHas(g.classes, class) then
            if g.startMaps and listHas(g.startMaps, mapID) then return name end
            if not g.startMaps and listHas(g.races, race) then
                if g.classes then byClass = byClass or name else generic = generic or name end
            end
        end
    end
    return byClass or generic
end

function FG:SkipStep()
    local step = self.currentStep
    if not step then return end
    local _, g = self:GetGuide()
    local c = ForeverGuideCharDB
    c.skipped[g] = c.skipped[g] or {}
    -- An optional detour (step.optional = "name") is skipped as a whole
    local indices = { step.index }
    -- an optional detour is skipped as a whole; solo, so is a dungeon with its quests
    local tag = step.optional or self:SoloOptionalOn(step)
    if tag then
        indices = {}
        local guide = self.guides[g]
        for i, s in ipairs(guide and guide.steps or {}) do
            if (s.optional == tag or s.soloOptional == tag) and not c.skipped[g][i] then table.insert(indices, i) end
        end
        self:Print(("Skipped %s (%d steps, /fg back to undo)"):format(tag, #indices))
    end
    for _, i in ipairs(indices) do c.skipped[g][i] = true end
    table.insert(c.skipStack, { g, #indices == 1 and indices[1] or indices })
    self:Recalculate()
end

function FG:Back()
    local c = ForeverGuideCharDB
    local last = table.remove(c.skipStack)
    if not last then
        self:Print("Nothing to go back to (only skipped steps can be undone).")
        return
    end
    local g = last[1]
    local indices = type(last[2]) == "table" and last[2] or { last[2] }
    for _, index in ipairs(indices) do
        if c.skipped[g] then c.skipped[g][index] = nil end
        local r = c.reached[g]
        if r then r[index] = nil end
    end
    if g ~= c.guide then self:SetGuide(g) else self:Recalculate() end
end

function FG:ResetGuide()
    local _, g = self:GetGuide()
    if not g then return end
    ForeverGuideCharDB.skipped[g] = nil
    ForeverGuideCharDB.reached[g] = nil
    self:Recalculate()
    self:Print("Cleared skips for " .. g)
end
