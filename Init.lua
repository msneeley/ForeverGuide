-- Init: saved variables, events, slash commands (loaded last)
local _, FG = ...

local function defaults()
    ForeverGuideDB = ForeverGuideDB or {}
    if ForeverGuideDB.auto == nil then ForeverGuideDB.auto = true end
    if ForeverGuideDB.share == nil then ForeverGuideDB.share = true end
    if ForeverGuideDB.autoReward == nil then ForeverGuideDB.autoReward = true end
    FG:OptionDefaults()

    ForeverGuideCharDB = ForeverGuideCharDB or {}
    local c = ForeverGuideCharDB
    c.skipped   = c.skipped   or {}
    c.skipStack = c.skipStack or {}
    c.reached   = c.reached   or {}
    c.recording = c.recording or { active = false, steps = {} }
    c.recording.steps = c.recording.steps or {}
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
local function onEvent(self, event, ...)
    if event == "PLAYER_LOGIN" then
        defaults()
        FG:CreateUI()
        FG:CreateArrow()

        local c = ForeverGuideCharDB
        if not (c.guide and FG.guides[c.guide]) then
            c.guide = FG:AutoPickGuide()
        end
        FG:BuildQuestLookup()
        FG:Resync(true)
        FG:CheckClothWarnings()
        -- First time this character loads the addon: welcome screen with every toggle
        if not c.welcomed then C_Timer.After(2, function() FG:ShowWelcome() end) end
        -- Hearth cooldown in the status line counts down
        C_Timer.NewTicker(1, function() if FG.frame and FG.frame:IsShown() then FG.frame.status:SetText(FG:StatusText()) end end)

        for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN",
                             "QUEST_REMOVED", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA",
                             "ZONE_CHANGED", "PLAYER_ALIVE", "PLAYER_UNGHOST", "SKILL_LINES_CHANGED",
                             "BAG_UPDATE_DELAYED", "TRAINER_CLOSED", "UNIT_AURA",
                             "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "TAXIMAP_OPENED" }) do
            self:RegisterEvent(e)
        end
    elseif event == "UNIT_AURA" and ... ~= "player" then
        return
    else
        -- Closing a trainer window finishes the current train step
        local step = FG.currentStep
        if event == "SKILL_LINES_CHANGED" or event == "PLAYER_LEVEL_UP" then FG.keepList = nil end
        if event == "PLAYER_LEVEL_UP" then C_Timer.After(1, function() FG:CheckClothWarnings() end) end
        if step and ((event == "TRAINER_CLOSED" and step.train) or (event == "TAXIMAP_OPENED" and step.fp)) then
            FG:MarkReached(step)
        end
        FG:QueueRecalc(event == "QUEST_TURNED_IN" and 0.5 or 0.2)
    end
end

-- Report our own errors in chat (once each) so a problem never just looks
-- like "the addon isn't showing"
local reported = {}
ev:SetScript("OnEvent", function(self, event, ...)
    local ok, err = pcall(onEvent, self, event, ...)
    if not ok and not reported[err] then
        reported[err] = true
        FG:Print("|cffff4040error|r (" .. event .. "): " .. tostring(err))
        if event == "PLAYER_LOGIN" then FG:Print("Type /reload to retry, and tell whoever maintains this guide.") end
    end
end)

---------------------------------------------------------------------------
-- /fg commands
---------------------------------------------------------------------------
local HELP = {
    "|cffffd100Guide|r  /fg (show/hide) · /fg list · /fg set <name> · /fg skip · /fg back · /fg reset · /fg sync (catch up after playing off-script) · /fg nearby",
    "|cffffd100XP tracking|r  /fg xp (this character by level) · /fg xp runs (dungeon runs) · /fg xp compare 20 30 (all your characters) · /fg xp verdict · /fg xp report · /fg xp export · /fg xp run 1|2",
    "|cffffd100Settings|r  /fg options (or the ? button): switch any part on/off · /fg welcome · /fg auto · /fg share · /fg reward · /fg group",
    "|cffffd100Buffs|r  /fg buffs: checks, which roles get each, roles, your blessing",
    "    /fg buffs blessing might|wisdom|kings|salvation|light · /fg buffs learn|forget|reset",
    "|cffffd100Roles|r  /fg role tank|healer|melee|caster [name] (shared with the party)",
    "|cffffd100Talents|r  /fg talents (the build) · /fg talents on|off (recommendation line) · /fg glow (talent glow on/off)",
    "|cffffd100Plans|r  /fg legacy · /fg camp · /fg prof · /fg food · /fg pots · /fg keep · /fg craft (party upgrades you can make) · /fg cloth (cloth: bags vs First Aid) · /fg craftguide (level your crafting)",
    "|cffffd100Recording|r  /fg rec start|stop|clear · /fg note <text> · /fg export",
    "Make it yours: untick what you don't use in /fg options and /fg buffs; drag any window to move it;",
    "    shaman totem keys are in Key Bindings > AddOns > ForeverGuide.",
}

SLASH_FOREVERGUIDE1 = "/fg"
SLASH_FOREVERGUIDE2 = "/foreverguide"
SlashCmdList.FOREVERGUIDE = function(msg)
    local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()

    if cmd == "" then FG:ToggleUI()
    elseif cmd == "options" or cmd == "config" then FG:ToggleOptions()
    elseif cmd == "welcome" then FG:ShowWelcome()
    elseif cmd == "group" then
        ForeverGuideDB.showGroup = not ForeverGuideDB.showGroup
        FG:ApplyOptions()
    elseif cmd == "help" then for _, l in ipairs(HELP) do FG:Print(l) end
    elseif cmd == "list" then
        for _, n in ipairs(FG.guideOrder) do FG:Print(" - " .. n) end
    elseif cmd == "set" then FG:SetGuide(rest)
    elseif cmd == "skip" then FG:SkipStep()
    elseif cmd == "back" then FG:Back()
    elseif cmd == "reset" then FG:ResetGuide()
    elseif cmd == "auto" then
        ForeverGuideDB.auto = not ForeverGuideDB.auto
        FG:Print("Auto accept/turn-in " .. (ForeverGuideDB.auto and "ON" or "OFF"))
    elseif cmd == "reward" then
        ForeverGuideDB.autoReward = not ForeverGuideDB.autoReward
        FG:Print("Stat-based reward picks " .. (ForeverGuideDB.autoReward and "ON" or "OFF"))
    elseif cmd == "share" then
        ForeverGuideDB.share = not ForeverGuideDB.share
        FG:Print("Auto-share quests with group " .. (ForeverGuideDB.share and "ON" or "OFF"))
    elseif cmd == "rec" then
        rest = rest:lower()
        if rest == "start" then FG:RecStart()
        elseif rest == "stop" then FG:RecStop()
        elseif rest == "clear" then FG:RecClear()
        else FG:Print("/fg rec start | stop | clear") end
    elseif cmd == "note" then FG:RecNote(rest)
    elseif cmd == "export" then FG:RecExport()
    elseif cmd == "talents" then
        rest = (rest or ""):lower()
        if rest == "on" or rest == "off" then
            ForeverGuideDB.talentGuide = (rest == "on")
            FG:Print("Talent recommendations " .. rest:upper())
            FG:ApplyOptions()
        else FG:PrintTalentPlan() end
    elseif cmd == "glow" then
        ForeverGuideDB.glow = not (ForeverGuideDB.glow ~= false)
        FG:Print("Talent glow " .. (ForeverGuideDB.glow and "ON" or "OFF"))
        if FG.UpdateTalentGlow then FG:UpdateTalentGlow() end
    elseif cmd == "legacy" then FG:PrintLegacyPlan()
    elseif cmd == "camp" then FG:PrintCampPlan()
    elseif cmd == "buffs" then FG:BuffCommand(rest)
    elseif cmd == "role" then FG:RoleCommand(rest)
    elseif cmd == "prof" then FG:PrintSecondaryPlan()
    elseif cmd == "food" then FG:PrintFoodPlan()
    elseif cmd == "pots" then FG:PrintPotionPlan()
    elseif cmd == "craft" then FG:PrintCraftPlan()
    elseif cmd == "cloth" then FG:ClothCommand(rest)
    elseif cmd == "bagalt" then FG:BagAltCommand(rest)
    elseif cmd == "craftguide" then FG:PrintCraftGuide()
    elseif cmd == "sync" then FG:Resync()
    elseif cmd == "nearby" then FG:PrintNearby()
    elseif cmd == "xp" then FG:XPCommand(rest)
    elseif cmd == "keep" then FG:PrintKeepList()
    else for _, l in ipairs(HELP) do FG:Print(l) end
    end
end
