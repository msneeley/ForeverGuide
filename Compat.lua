-- Compat: one place for API calls that differ between Classic Era and WoW
-- Forever. Forever has the newer C_QuestLog / C_Item functions and lacks
-- GetQuestLogTitle, so prefer the C_ versions whenever they exist (the same
-- check RXPGuides uses) and fall back to the old globals otherwise.
local _, FG = ...

local QL = C_QuestLog
local modernLog = QL and QL.GetInfo ~= nil

-- Quest log entries as { index, questID, title, isHeader, isComplete }
function FG:QuestLogEntries()
    local list = {}
    if modernLog then
        for i = 1, QL.GetNumQuestLogEntries() do
            local info = QL.GetInfo(i)
            if info then
                local complete = false
                if not info.isHeader and info.questID and info.questID > 0 then
                    complete = (QL.IsComplete and QL.IsComplete(info.questID)) and true or false
                end
                table.insert(list, { index = i, questID = info.questID, title = info.title,
                                     isHeader = info.isHeader, isComplete = complete })
            end
        end
    else
        for i = 1, GetNumQuestLogEntries() do
            local title, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
            table.insert(list, { index = i, questID = questID, title = title, isHeader = isHeader,
                                 isComplete = (isComplete == 1 or isComplete == true) })
        end
    end
    return list
end

-- logIndex, isComplete for a quest in the log, or nil
function FG:FindQuestInLog(id)
    if modernLog and QL.GetLogIndexForQuestID then
        local idx = QL.GetLogIndexForQuestID(id)
        if not idx or idx == 0 then return nil end
        return idx, (QL.IsComplete and QL.IsComplete(id)) and true or false
    end
    for _, e in ipairs(self:QuestLogEntries()) do
        if not e.isHeader and e.questID == id then return e.index, e.isComplete end
    end
end

-- Title of a quest in the log
function FG:LogQuestTitle(id)
    if QL and QL.GetTitleForQuestID then
        local t = QL.GetTitleForQuestID(id)
        if t then return t end
    end
    for _, e in ipairs(self:QuestLogEntries()) do
        if e.questID == id then return e.title end
    end
end

-- Objective lines for a quest in the log: { { text, finished }, ... }
function FG:QuestObjectives(id)
    if QL and QL.GetQuestObjectives then
        local out = {}
        for _, o in ipairs(QL.GetQuestObjectives(id) or {}) do
            table.insert(out, { text = o.text, finished = o.finished })
        end
        return out
    end
    local idx = self:FindQuestInLog(id)
    if not idx or not GetNumQuestLeaderBoards then return {} end
    local out = {}
    for i = 1, GetNumQuestLeaderBoards(idx) do
        local text, _, finished = GetQuestLogLeaderBoard(i, idx)
        table.insert(out, { text = text, finished = finished })
    end
    return out
end

function FG:ItemCount(item)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(item) or 0 end
    return GetItemCount(item) or 0
end

-- Share a quest from the log with the party, if the game allows it
function FG:PushQuest(id)
    if QL and QL.IsPushableQuest and not QL.IsPushableQuest(id) then return end
    if QL and QL.SetSelectedQuest then
        QL.SetSelectedQuest(id)
    else
        local idx = self:FindQuestInLog(id)
        if not idx then return end
        SelectQuestLogEntry(idx)
        if GetQuestLogPushable and not GetQuestLogPushable() then return end
    end
    QuestLogPushQuest()
end
