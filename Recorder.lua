-- Recorder: play normally with /fg rec start and it writes guide steps
-- (quest IDs, NPC names, coordinates) from what you actually do.
-- /fg export shows the result as Lua you can paste into a guide file.
local _, FG = ...

local lastNPC, lastTitle
local wasComplete = {}

local function rec() return ForeverGuideCharDB.recording end

local function npcName()
    return UnitName("npc") or UnitName("target")
end

local function addStep(step)
    local mapID, x, y = FG:GetPlayerMapPos()
    if mapID then
        step.map = mapID
        step.x = math.floor(x * 10 + 0.5) / 10
        step.y = math.floor(y * 10 + 0.5) / 10
    end
    table.insert(rec().steps, step)
    FG:Print(("rec #%d: %s"):format(#rec().steps,
        step.title or step.text or "waypoint"))
end

local function snapshotLog()
    wipe(wasComplete)
    for _, e in ipairs(FG:QuestLogEntries()) do
        if not e.isHeader and e.questID then wasComplete[e.questID] = e.isComplete end
    end
end

function FG:RecStart()
    rec().active = true
    snapshotLog()
    self:Print("Recording ON. Play normally. /fg note <text> adds a waypoint here.")
    self:UpdateUI()
end

function FG:RecStop()
    rec().active = false
    self:Print(("Recording OFF (%d steps). /fg export to copy."):format(#rec().steps))
    self:UpdateUI()
end

function FG:RecClear()
    wipe(rec().steps)
    self:Print("Recording cleared.")
end

function FG:RecNote(text)
    if text == "" then text = nil end
    addStep({ travel = true, text = text })
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("QUEST_DETAIL")
ev:RegisterEvent("QUEST_COMPLETE")
ev:RegisterEvent("QUEST_ACCEPTED")
ev:RegisterEvent("QUEST_TURNED_IN")
ev:RegisterEvent("QUEST_LOG_UPDATE")

ev:SetScript("OnEvent", function(_, event, a, b)
    if not (ForeverGuideCharDB and rec().active) then return end

    if event == "QUEST_DETAIL" or event == "QUEST_COMPLETE" then
        lastNPC, lastTitle = npcName(), GetTitleText()

    elseif event == "QUEST_ACCEPTED" then
        -- Classic passes (logIndex, questID); Forever passes (questID)
        local questID = b or a
        local title = questID and FG:LogQuestTitle(questID)
        if questID then
            addStep({ accept = questID, title = title, npc = lastNPC })
            wasComplete[questID] = false
        end

    elseif event == "QUEST_TURNED_IN" then
        addStep({ turnin = a, title = lastTitle, npc = lastNPC })
        wasComplete[a] = nil

    elseif event == "QUEST_LOG_UPDATE" then
        -- objectives just finished: record where (last kill / pickup spot)
        for _, e in ipairs(FG:QuestLogEntries()) do
            local id = e.questID
            if not e.isHeader and id and e.isComplete and wasComplete[id] == false then
                wasComplete[id] = true
                addStep({ complete = id, title = e.title })
            end
        end
    end
end)

---------------------------------------------------------------------------
-- Export window
---------------------------------------------------------------------------
local function fmt(step)
    local parts = {}
    for _, k in ipairs({ "accept", "complete", "turnin", "travel" }) do
        if step[k] ~= nil then table.insert(parts, k .. "=" .. tostring(step[k])) end
    end
    for _, k in ipairs({ "title", "npc", "text" }) do
        if step[k] then table.insert(parts, ("%s=%q"):format(k, step[k])) end
    end
    if step.map then
        table.insert(parts, ("map=%d, x=%.1f, y=%.1f"):format(step.map, step.x, step.y))
    end
    return "        { " .. table.concat(parts, ", ") .. " },"
end

function FG:RecExport()
    local lines = { "    steps = {" }
    for _, s in ipairs(rec().steps) do table.insert(lines, fmt(s)) end
    table.insert(lines, "    },")
    local text = table.concat(lines, "\n")

    if not self.exportFrame then
        local f = CreateFrame("Frame", "ForeverGuideExport", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetSize(600, 400)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)

        local sf = CreateFrame("ScrollFrame", "ForeverGuideExportScroll", f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 20, -30)
        sf:SetPoint("BOTTOMRIGHT", -40, 20)

        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(530)
        eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        sf:SetScrollChild(eb)
        f.edit = eb
        self.exportFrame = f
    end
    self.exportFrame.edit:SetText(text)
    self.exportFrame:Show()
    self.exportFrame.edit:SetFocus()
    self.exportFrame.edit:HighlightText()
    self:Print("Ctrl+C to copy. Also saved in WTF\\...\\SavedVariables\\ForeverGuide.lua")
end
