-- XPTrack: real XP rates, so you can compare routes with your own play.
-- A fresh character starts tracking at its first accepted quest, so setting up
-- the UI doesn't count. Per character (saved account-wide, so any character
-- can compare them all):
--  * every level: /played when you reached it, time in dungeons vs the open
--    world, XP from quests / dungeon quests / kills / dungeon kills, deaths
--  * every dungeon run: time inside, XP from its mobs, plus its quests when
--    you hand them in (matched by the guide's dungeon quest lists)
-- /fg xp            this character, level by level
-- /fg xp runs       your dungeon runs
-- /fg xp compare    every tracked character side by side
-- /fg xp verdict    each dungeon run vs your questing at the same level
-- /fg xp report     everything in a window you can copy or screenshot (ends with spreadsheet rows)
-- /fg xp export     just the spreadsheet rows
-- /fg xp run 2      which experiment run this character is (default 1)
-- /fg xp milestones 22 25   levels where that window pops up by itself (default 22 and 25)
-- /fg xp reset      clear this character's log
local _, FG = ...

local log            -- this character's record
local lastXP, lastMax, lastLevel
local sessionStart, inInstance, instanceName, runStart
local pendingQuestXP = 0
local lfgStart, pendingWait   -- time spent looking for a group before a dungeon
local dungeonOfQuest  -- [questID] = dungeon name

local function key() return (UnitName("player") or "Unknown") .. "-" .. (GetRealmName and GetRealmName() or "") end

local function level(l)
    log.levels[l] = log.levels[l] or { quest = 0, dquest = 0, kill = 0, dkill = 0, other = 0, tOpen = 0, tDungeon = 0, deaths = 0 }
    return log.levels[l]
end

local function buildDungeonQuests()
    dungeonOfQuest = {}
    for _, g in pairs(FG.guides or {}) do
        for _, s in ipairs(g.steps) do
            if s.dungeon then
                for _, q in ipairs(s.quests or {}) do dungeonOfQuest[q] = s.dungeon end
            end
        end
    end
end

-- Time since the last tick goes to the open world or the current dungeon
local function tick()
    if not log or not sessionStart then return end
    if not log.started then sessionStart = GetTime(); return end   -- waiting for the first quest
    local step = FG.currentStep
    if step and step.lfg and not lfgStart and not FG:FullGroup() then lfgStart = GetTime() end
    if lfgStart and step and not step.lfg and not step.dungeon and not FG:FullGroup() then lfgStart = nil end   -- skipped it
    local now = GetTime()
    local dt = now - sessionStart
    sessionStart = now
    if dt <= 0 or dt > 600 then return end   -- ignore gaps (loading, sleeping laptop)
    local lv = level(UnitLevel("player"))
    if inInstance then lv.tDungeon = lv.tDungeon + dt else lv.tOpen = lv.tOpen + dt end
end

-- Fresh characters start tracking at their first accepted quest (time to set up the UI)
local function startTracking(quiet)
    if log.started then return end
    log.started = true
    sessionStart = GetTime()
    if not quiet and FG.Print then FG:Print("XP tracking started (first quest accepted).") end
end

local function hasQuests()
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        local n = C_QuestLog.GetNumQuestLogEntries()
        return (n or 0) > 0
    end
    return GetNumQuestLogEntries and (GetNumQuestLogEntries() or 0) > 0
end

local function checkInstance()
    tick()
    local inside, kind = IsInInstance()
    local nowIn = inside and (kind == "party" or kind == "raid")
    if nowIn and not inInstance then
        if lfgStart then pendingWait = GetTime() - lfgStart; lfgStart = nil end   -- went in without a full 5
        instanceName = GetInstanceInfo and GetInstanceInfo() or GetRealZoneText()
        runStart = GetTime()
        table.insert(log.runs, { name = instanceName, level = UnitLevel("player"), time = 0, killXP = 0, questXP = 0,
                                 wait = pendingWait or 0, date = date and date("%m/%d %H:%M") or "" })
        pendingWait = nil
    elseif inInstance and not nowIn then
        local run = log.runs[#log.runs]
        if run and runStart then run.time = run.time + (GetTime() - runStart) end
        runStart = nil
        if run and FG.Print then   -- quick summary as you leave
            C_Timer.After(2, function()
                FG:Print(("Dungeon run logged: %s - %s inside%s, %d XP so far (its quests are added when you hand them in). /fg xp runs"):format(
                    run.name or "?", math.floor(run.time / 60) .. "m", (run.wait or 0) > 60 and (", " .. math.floor(run.wait / 60) .. "m finding a group") or "",
                    run.killXP + run.questXP))
            end)
        end
    end
    inInstance = nowIn
end

local function addXP(amount, atLevel)
    if amount <= 0 or not log.started then return end
    local lv = level(atLevel or lastLevel or UnitLevel("player"))
    if pendingQuestXP > 0 then
        local q = math.min(amount, pendingQuestXP)
        pendingQuestXP = pendingQuestXP - q
        amount = amount - q
        local dq = FG.lastTurnin and dungeonOfQuest and dungeonOfQuest[FG.lastTurnin]
        if dq then
            lv.dquest = lv.dquest + q
            -- credit the most recent run of that dungeon
            for i = #log.runs, 1, -1 do
                if log.runs[i].name and (log.runs[i].name:find(dq, 1, true) or dq:find(log.runs[i].name, 1, true)) then
                    log.runs[i].questXP = log.runs[i].questXP + q; break
                end
            end
        else
            lv.quest = lv.quest + q
        end
    end
    if amount > 0 then
        if inInstance then
            lv.dkill = lv.dkill + amount
            local run = log.runs[#log.runs]
            if run then run.killXP = run.killXP + amount end
        else
            lv.kill = lv.kill + amount   -- open-world kills (and exploration)
        end
    end
end

-- XP gains wait a moment so a quest turn-in event arriving just after can claim them
local buffered, bufferedLevel, flushing = 0, nil, false
local function onXP()
    local xp, max, lvl = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    if lastXP then
        local gained
        if lvl > lastLevel then gained = (lastMax - lastXP) + xp else gained = xp - lastXP end
        buffered = buffered + math.max(0, gained)
        bufferedLevel = bufferedLevel or lastLevel   -- XP that levels you up counts for the level you earned it in
        if not flushing then
            flushing = true
            C_Timer.After(0.3, function()
                flushing = false
                local g, l = buffered, bufferedLevel
                buffered, bufferedLevel = 0, nil
                addXP(g, l)
            end)
        end
    end
    lastXP, lastMax, lastLevel = xp, max, lvl
end

---------------------------------------------------------------------------
-- Reports
---------------------------------------------------------------------------
local function fmtTime(s)
    s = math.floor((s or 0) + 0.5)
    if s >= 3600 then return ("%dh%02dm"):format(math.floor(s / 3600), math.floor((s % 3600) / 60)) end
    return ("%dm"):format(math.floor(s / 60))
end

local function rate(xp, t) return t > 60 and ("%.1fk/h"):format(xp / (t / 3600) / 1000) or "-" end

function FG:PrintXPLog(which)
    tick()
    local c = ForeverGuideDB.xpLog and ForeverGuideDB.xpLog[which or key()]
    if not c then self:Print("No XP log yet for this character.") return end
    self:Print(("XP log for %s (open world vs dungeon time, XP by source):"):format(which or UnitName("player")))
    for l = 1, 60 do
        local v = c.levels[l]
        if v then
            local total = v.quest + v.dquest + v.kill + v.dkill
            local t = v.tOpen + v.tDungeon
            self:Print(("  L%d: %s%s  |  %s  |  quests %d, dungeon quests %d, kills %d, dungeon kills %d%s"):format(
                l, fmtTime(t), v.tDungeon > 60 and (" (" .. fmtTime(v.tDungeon) .. " in dungeons)") or "",
                rate(total, t), v.quest, v.dquest, v.kill, v.dkill, v.deaths > 0 and (", " .. v.deaths .. " deaths") or ""))
        end
    end
end

function FG:PrintRuns()
    checkInstance()
    if #log.runs == 0 then self:Print("No dungeon runs logged yet.") return end
    self:Print("Dungeon runs (kill XP inside + its quests when handed in):")
    for _, r in ipairs(log.runs) do
        local xp = r.killXP + r.questXP
        local w = r.wait or 0
        self:Print(("  %s %s (level %d): %s inside%s, %d XP (%d kills + %d quests) = %s%s"):format(r.date or "", r.name or "?", r.level or 0,
            fmtTime(r.time), w > 60 and (" + " .. fmtTime(w) .. " finding a group") or "", xp, r.killXP, r.questXP,
            rate(xp, r.time + w), w > 60 and " (incl. group-finding)" or ""))
    end
    self:Print("|cff888888Per hour counts time inside plus time finding a group (from the guide's Look for a group step). Travel to the door is in your open-world time.|r")
end

function FG:PrintXPCompare(fromL, toL)
    tick()
    fromL, toL = fromL or 20, toL or 30
    self:Print(("Characters compared, levels %d-%d:"):format(fromL, toL))
    for name, c in pairs(ForeverGuideDB.xpLog or {}) do
        local t, td, xp, dq, runs = 0, 0, 0, 0, 0
        for l = fromL, toL do
            local v = c.levels[l]
            if v then
                t = t + v.tOpen + v.tDungeon; td = td + v.tDungeon
                xp = xp + v.quest + v.dquest + v.kill + v.dkill; dq = dq + v.dquest
            end
        end
        for _, r in ipairs(c.runs or {}) do if (r.level or 0) >= fromL and (r.level or 0) <= toL then runs = runs + 1 end end
        local top = 0
        for l in pairs(c.levels) do if l > top then top = l end end
        if t > 0 then
            self:Print(("  %s: level %d now | %s played in %d-%d (%s in %d dungeon runs) | %d XP = %s | dungeon quests %d XP"):format(
                name:gsub("%-.*", ""), top, fmtTime(t), fromL, toL, fmtTime(td), runs, xp, rate(xp, t), dq))
        end
    end
end

-- The answer to "is the dungeon worth it at this level?": each run's XP per hour
-- (time inside + finding a group) against your open-world questing at the same
-- levels (the run's level +-1; questing XP = quests + kills outside dungeons,
-- not counting dungeon quests handed in).
function FG:PrintVerdict()
    tick()
    if #log.runs == 0 then self:Print("No dungeon runs yet - the verdict needs at least one.") return end
    self:Print("|cffffd100Dungeon vs questing at the same level:|r")
    local wins, losses = 0, 0
    for _, r in ipairs(log.runs) do
        local rt = r.time + (r.wait or 0)
        local rxp = r.killXP + r.questXP
        local qt, qxp = 0, 0
        for l = (r.level or 1) - 1, (r.level or 1) + 1 do
            local v = log.levels[l]
            if v then qt = qt + v.tOpen; qxp = qxp + v.quest + v.kill end
        end
        -- time spent looking for groups at these levels isn't questing
        for _, o in ipairs(log.runs) do
            if math.abs((o.level or 0) - (r.level or 0)) <= 1 then qt = qt - (o.wait or 0) end
        end
        if rt > 300 and qt > 600 then
            local d, q = rxp / (rt / 3600), qxp / (qt / 3600)
            local better = d >= q
            if better then wins = wins + 1 else losses = losses + 1 end
            self:Print(("  %s (level %d): dungeon %.1fk/h vs questing %.1fk/h at %d-%d -> %s"):format(r.name or "?", r.level or 0,
                d / 1000, q / 1000, (r.level or 1) - 1, (r.level or 1) + 1,
                better and ("|cff40c040dungeon %.1fx faster|r"):format(d / math.max(q, 1))
                       or ("|cffff6060questing %.1fx faster|r"):format(q / math.max(d, 1))))
            if r.questXP == 0 then self:Print("      |cff888888its quests aren't handed in yet - rerun this after turning them in|r") end
        else
            self:Print(("  %s (level %d): not enough questing time at %d-%d yet to compare"):format(r.name or "?", r.level or 0,
                (r.level or 1) - 1, (r.level or 1) + 1))
        end
    end
    if wins + losses > 0 then
        self:Print(("  So far: dungeons won %d, questing won %d. Gear from dungeons isn't counted here."):format(wins, losses))
    end
end

-- Spreadsheet rows (comma-separated, one per level and one per dungeon run) for
-- the group's XP tracker sheet. Columns match its Data tab:
-- Character, Class, Race, Run, Exported at, Type, Level, Dungeon, Minutes,
-- Dungeon min, LFG wait min, Quest XP, Dungeon quest XP, Kill XP, Dungeon kill XP, Deaths
function FG:XPExportRows()
    tick()
    local _, class = UnitClass("player")
    local _, race = UnitRace("player")
    local head = { UnitName("player") or "?", class or "?", race or "?", ForeverGuideCharDB.xpRun or "1", UnitLevel("player") }
    local rows = {}
    local function row(...)
        local r = {}
        for _, v in ipairs(head) do table.insert(r, tostring(v)) end
        for _, v in ipairs({ ... }) do
            if type(v) == "number" and v % 1 ~= 0 then v = ("%.1f"):format(v) end
            table.insert(r, (tostring(v):gsub(",", "")))
        end
        table.insert(rows, table.concat(r, ","))
    end
    for l = 1, 60 do
        local v = log.levels[l]
        if v then
            row("level", l, "", (v.tOpen + v.tDungeon) / 60, v.tDungeon / 60, "", v.quest, v.dquest, v.kill, v.dkill, v.deaths)
        end
    end
    for _, r in ipairs(log.runs) do
        row("dungeon", r.level or 0, r.name or "?", r.time / 60, r.time / 60, (r.wait or 0) / 60, 0, r.questXP, 0, r.killXP, 0)
    end
    return rows
end

-- Everything in one window you can copy from (Ctrl+A, Ctrl+C) or screenshot
function FG:ShowXPReport(title, rowsOnly)
    local lines = {}
    local realPrint = self.Print
    self.Print = function(_, m) table.insert(lines, (tostring(m):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))) end
    local ok = rowsOnly or pcall(function()
        self:PrintVerdict(); self:PrintXPLog(); self:PrintRuns()
        local top = UnitLevel("player")
        self:PrintXPCompare(math.max(1, top - 12), top)
    end)
    self.Print = realPrint
    for _, l in ipairs(lines) do self:Print(l) end
    -- the tracker sheet's rows go in the window only (too long for chat)
    local okRows, rows = pcall(self.XPExportRows, self)
    if okRows then
        table.insert(lines, "")
        table.insert(lines, ("--- Spreadsheet rows (run %s) - paste into the Data tab ---"):format(ForeverGuideCharDB.xpRun or "1"))
        for _, r in ipairs(rows) do table.insert(lines, r) end
    end
    if not self.xpFrame then
        local f = CreateFrame("Frame", "ForeverGuideXPReport", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetSize(620, 420)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
        if f.SetBackdrop then
            f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                            tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
        end
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOPLEFT", 22, -20)
        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("TOPLEFT", 22, -42)
        hint:SetText("Click the text, Ctrl+A then Ctrl+C to copy it - or take a screenshot.")
        local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 20, -60); sf:SetPoint("BOTTOMRIGHT", -40, 50)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true); eb:SetFontObject(ChatFontNormal); eb:SetWidth(540); eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function(e) e:ClearFocus() end)
        sf:SetScrollChild(eb)
        f.edit = eb
        local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        close:SetSize(100, 24); close:SetPoint("BOTTOMRIGHT", -22, 18); close:SetText("Close")
        close:SetScript("OnClick", function() f:Hide() end)
        self.xpFrame = f
    end
    self.xpFrame.title:SetText(title or "ForeverGuide XP report")
    self.xpFrame.edit:SetText(table.concat(lines, "\n"))
    self.xpFrame:Show()
    return lines
end

-- Levels that pop the report automatically (once each, per character)
local function checkMilestones(newLevel)
    local c = ForeverGuideCharDB
    if not c then return end
    c.xpMilestones = c.xpMilestones or { 22, 25 }
    c.xpMilestonesDone = c.xpMilestonesDone or {}
    for _, m in ipairs(c.xpMilestones) do
        if newLevel >= m and not c.xpMilestonesDone[m] then
            c.xpMilestonesDone[m] = true
            C_Timer.After(3, function()
                FG:ShowXPReport(("Experiment checkpoint - level %d"):format(m))
                FG:Print(("|cffffd100Level %d checkpoint:|r your XP report is open - send it over (copy or screenshot)."):format(m))
            end)
            break
        end
    end
end
FG.CheckXPMilestones = checkMilestones

function FG:XPCommand(rest)
    rest = (rest or ""):lower()
    if rest == "runs" then self:PrintRuns()
    elseif rest:match("^compare") then
        local a, b = rest:match("(%d+)%D+(%d+)")
        self:PrintXPCompare(tonumber(a), tonumber(b))
    elseif rest == "report" then self:ShowXPReport()
    elseif rest == "verdict" then self:PrintVerdict()
    elseif rest == "export" then self:ShowXPReport("ForeverGuide XP - spreadsheet rows", true)
    elseif rest:match("^run") then
        local r = rest:match("^run%s+(%S+)")
        if r then ForeverGuideCharDB.xpRun = r end
        self:Print(("This character is logged as run %s (/fg xp run 2 to change)."):format(ForeverGuideCharDB.xpRun or "1"))
    elseif rest:match("^milestones") then
        local list = {}
        for n in rest:gmatch("(%d+)") do table.insert(list, tonumber(n)) end
        if #list > 0 then
            ForeverGuideCharDB.xpMilestones = list
            ForeverGuideCharDB.xpMilestonesDone = {}
        end
        local shown = {}
        for _, n in ipairs(ForeverGuideCharDB.xpMilestones or { 22, 25 }) do table.insert(shown, n) end
        self:Print("XP report pops up at level(s): " .. table.concat(shown, ", "))
    elseif rest == "reset" then
        ForeverGuideDB.xpLog[key()] = { levels = {}, runs = {} }
        log = ForeverGuideDB.xpLog[key()]
        log.started = true
        sessionStart = GetTime()
        self:Print("XP log cleared for this character (tracking continues from now).")
    else self:PrintXPLog() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_XP_UPDATE", "QUEST_TURNED_IN", "QUEST_ACCEPTED", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE",
                     "ZONE_CHANGED_NEW_AREA", "PLAYER_DEAD", "PLAYER_LEVEL_UP", "PLAYER_LOGOUT" }) do
    ev:RegisterEvent(e)
end
local handle
ev:SetScript("OnEvent", function(_, event, a, b)
    -- tracking must never break the rest of the addon
    local ok, err = pcall(handle, event, a, b)
    if not ok and FG.Print then FG:Print("XP tracker error: " .. tostring(err)) end
end)
handle = function(event, a, b)
    if event == "PLAYER_LOGIN" then
        ForeverGuideDB = ForeverGuideDB or {}   -- may run before Init.lua on a brand-new install
        ForeverGuideDB.xpLog = ForeverGuideDB.xpLog or {}
        ForeverGuideDB.xpLog[key()] = ForeverGuideDB.xpLog[key()] or { levels = {}, runs = {} }
        log = ForeverGuideDB.xpLog[key()]
        lastXP, lastMax, lastLevel = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
        sessionStart = GetTime()
        -- existing characters (past level 1, or with quests) track right away
        if not log.started and (UnitLevel("player") > 1 or UnitXP("player") > 0 or next(log.levels) or hasQuests()) then
            startTracking(true)
        end
        if not log.started then
            C_Timer.After(5, function() FG:Print("XP tracking starts with your first quest - set up your UI first.") end)
        end
        buildDungeonQuests()
        checkInstance()
        C_Timer.NewTicker(30, tick)
        return
    end
    if not log then return end
    if event == "QUEST_ACCEPTED" then
        startTracking()
        return
    end
    if not log.started then return end
    if event == "QUEST_TURNED_IN" then
        -- Classic passes (questID, xpReward, money); the XP update follows
        FG.lastTurnin = a
        pendingQuestXP = pendingQuestXP + (tonumber(b) or 0)
    elseif event == "PLAYER_XP_UPDATE" then
        onXP()
    elseif event == "PLAYER_DEAD" then
        local lv = level(UnitLevel("player")); lv.deaths = lv.deaths + 1
    elseif event == "PLAYER_LEVEL_UP" then
        tick()
        local lv = level(tonumber(a) or UnitLevel("player"))
        lv.reachedAt = time and time() or 0
        checkMilestones(tonumber(a) or UnitLevel("player"))
    elseif event == "GROUP_ROSTER_UPDATE" then
        if lfgStart and FG:FullGroup() then
            pendingWait = GetTime() - lfgStart
            lfgStart = nil
        end
    elseif event == "PLAYER_LOGOUT" then
        checkInstance(); tick()
    else
        checkInstance()
    end
end
