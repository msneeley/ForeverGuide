-- Automation: auto-accept / auto-turn-in quests that are part of the
-- current guide. Hold SHIFT while talking to an NPC to do it manually.
-- Picks a reward only when the guide step names one (reward = itemID).
local _, FG = ...

local function enabled()
    return ForeverGuideDB.auto and not IsShiftKeyDown()
end

local function wanted(questID, title)
    return (questID and FG.guideQuestIDs and FG.guideQuestIDs[questID])
        or (title and FG.guideTitles and FG.guideTitles[title])
end

-- Choice index of the guide's preferred reward, if it is offered
local function rewardIndex(questID, title)
    local want = FG.guideRewards and (FG.guideRewards[questID] or FG.guideRewards[title])
    if not want then return end
    for i = 1, GetNumQuestChoices() do
        local link = GetQuestItemLink("choice", i)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id == want then return i end
    end
end

-- If the current step is "accept X from this NPC" and the NPC doesn't offer X
-- (breadcrumb you skipped, class/race locked, already done), skip the step
-- instead of leaving the guide stuck on it.
local function checkNotOffered(availableIDs, availableTitles)
    local step = FG.currentStep
    if not (step and step.accept and step.npc) then return end
    if UnitName("npc") ~= step.npc then return end
    if availableIDs[step.accept] or (step.title and availableTitles[step.title]) then return end
    if FG:FindQuestInLog(step.accept) or FG:IsQuestTurnedIn(step.accept) then return end
    FG:Print(("%s doesn't offer %s - skipped (/fg back to undo)"):format(step.npc, step.title or step.accept))
    FG:SkipStep()
end

-- In a group, share each guide quest you accept so everyone stays in sync
local function shareAccepted(questID)
    if not (ForeverGuideDB.share and IsInGroup and IsInGroup()) then return end
    if not (FG.guideQuestIDs and FG.guideQuestIDs[questID]) then return end
    if not FG:FindQuestInLog(questID) then return end
    FG:PushQuest(questID)
end

---------------------------------------------------------------------------
-- Fallback reward pick when the guide doesn't name one: score each choice
-- for this class (Gear.lua), skipping armor/weapons the class can't use.
-- With nothing usable, take the one that sells for the most.
---------------------------------------------------------------------------
-- Best choice index for this class, or nil if item data isn't loaded yet
local function bestRewardByStats()
    local _, class = UnitClass("player")
    local bestUsable, bestUsableScore, bestSell, bestSellPrice
    for i = 1, GetNumQuestChoices() do
        local link = GetQuestItemLink("choice", i)
        if not link then return end
        local sellPrice = select(11, FG:ItemInfo(link))
        if sellPrice == nil then return end
        if not bestSell or sellPrice > bestSellPrice then bestSell, bestSellPrice = i, sellPrice end
        local score = FG:ScoreItem(link, class)
        if score == nil then return end
        if score and (not bestUsable or score > bestUsableScore) then bestUsable, bestUsableScore = i, score end
    end
    if bestUsable and bestUsableScore > 0 then return bestUsable end
    return bestSell
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("QUEST_DETAIL")
ev:RegisterEvent("QUEST_PROGRESS")
ev:RegisterEvent("QUEST_COMPLETE")
ev:RegisterEvent("QUEST_GREETING")
ev:RegisterEvent("GOSSIP_SHOW")
ev:RegisterEvent("QUEST_ACCEPTED")

ev:SetScript("OnEvent", function(_, event, ...)
    if event == "QUEST_ACCEPTED" then
        -- Classic passes (logIndex, questID); newer clients pass (questID)
        local a, b = ...
        local questID = b or a
        C_Timer.After(0.5, function() shareAccepted(questID) end)
        return
    end
    if not enabled() then return end

    if event == "QUEST_DETAIL" then
        if wanted(GetQuestID(), GetTitleText()) then AcceptQuest() end

    elseif event == "QUEST_PROGRESS" then
        if IsQuestCompletable() and wanted(GetQuestID(), GetTitleText()) then CompleteQuest() end

    elseif event == "QUEST_COMPLETE" then
        local id, title = GetQuestID(), GetTitleText()
        if not wanted(id, title) then return end
        local choices = GetNumQuestChoices()
        if choices <= 1 then
            GetQuestReward(choices)
        elseif ForeverGuideDB.autoReward ~= false then
            local pick = rewardIndex(id, title)
            if not pick and ForeverGuideDB.autoReward then
                pick = bestRewardByStats()
                if pick then FG:Print("Picked " .. (GetQuestItemLink("choice", pick) or "a reward") .. " for your class (/fg reward to turn this off)") end
            end
            if pick then GetQuestReward(pick) end
        end

    elseif event == "QUEST_GREETING" then
        local titles = {}
        for i = 1, GetNumAvailableQuests() do titles[GetAvailableTitle(i) or ""] = true end
        checkNotOffered({}, titles)
        -- Old-style quest NPCs: no quest IDs available, match by title
        for i = 1, GetNumActiveQuests() do
            local title, isComplete = GetActiveTitle(i)
            if isComplete and wanted(nil, title) then SelectActiveQuest(i) return end
        end
        for i = 1, GetNumAvailableQuests() do
            if wanted(nil, GetAvailableTitle(i)) then SelectAvailableQuest(i) return end
        end

    elseif event == "GOSSIP_SHOW" and C_GossipInfo then
        local ids, titles = {}, {}
        for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
            if q.questID then ids[q.questID] = true end
            if q.title then titles[q.title] = true end
        end
        checkNotOffered(ids, titles)
        for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
            if q.isComplete and wanted(q.questID, q.title) then
                C_GossipInfo.SelectActiveQuest(q.questID) return
            end
        end
        for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
            if wanted(q.questID, q.title) then
                C_GossipInfo.SelectAvailableQuest(q.questID) return
            end
        end
    end
end)
