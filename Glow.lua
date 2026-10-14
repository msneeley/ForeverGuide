-- Glow: points at what to click next without clicking it for you.
--  * Talent window: a pulsing gold border on the recommended talent (and on
--    its tree's tab if you're looking at another tree) while you have points.
--  * Class trainer reminder: a line in the guide window when you've gained
--    levels since your last trainer visit (new spell ranks).
-- Nothing here learns, buys or spends anything. Toggle: "Talent glow" in
-- /fg options or /fg glow.
local _, FG = ...

---------------------------------------------------------------------------
-- A reusable pulsing border
---------------------------------------------------------------------------
local glows = {}
function FG:ShowGlow(frame)
    if not frame then return end
    local g = glows[frame]
    if not g then
        g = frame:CreateTexture(nil, "OVERLAY")
        g:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        g:SetBlendMode("ADD")
        g:SetVertexColor(1, 0.85, 0.2)
        local w, h = frame:GetWidth(), frame:GetHeight()
        g:SetSize(w * 1.9, h * 1.9)
        g:SetPoint("CENTER", frame, "CENTER", 0, 0)
        if g.CreateAnimationGroup then
            local ag = g:CreateAnimationGroup()
            local a = ag:CreateAnimation("Alpha")
            a:SetFromAlpha(1); a:SetToAlpha(0.35); a:SetDuration(0.7)
            ag:SetLooping("BOUNCE")
            g.anim = ag
        end
        glows[frame] = g
    end
    g:Show()
    if g.anim and not g.anim:IsPlaying() then g.anim:Play() end
end

function FG:HideGlow(frame)
    local g = frame and glows[frame]
    if g then g:Hide(); if g.anim then g.anim:Stop() end end
end

---------------------------------------------------------------------------
-- Talent window
---------------------------------------------------------------------------
local PREFIXES = { "PlayerTalentFrame", "TalentFrame" }

local function talentFrame()
    for _, p in ipairs(PREFIXES) do
        local f = _G[p]
        if f and f.IsShown and f:IsShown() then return f, p end
    end
end

local function selectedTab(f)
    if PanelTemplates_GetSelectedTab then
        local t = PanelTemplates_GetSelectedTab(f)
        if t then return t end
    end
    return f.selectedTab or f.currentSelectedTab or 1
end

local function tabName(tab)
    local n = GetTalentTabInfo(tab)
    if type(n) == "number" then n = select(2, GetTalentTabInfo(tab)) end
    return n
end

function FG:UpdateTalentGlow()
    -- clear everything first
    for frame in pairs(glows) do
        local n = frame.GetName and frame:GetName()
        if n and (n:find("Talent") ) then self:HideGlow(frame) end
    end
    if ForeverGuideDB and ForeverGuideDB.glow == false then return end
    local f, prefix = talentFrame()
    if not f or self:UnspentTalentPoints() <= 0 then return end
    local name, nextRank, _, wantTab = self:NextTalent()
    if not (name and nextRank) then return end
    local cur = selectedTab(f)
    if tabName(cur) == wantTab then
        for i = 1, 40 do
            local b = _G[prefix .. "Talent" .. i]
            if not b then break end
            if b:IsShown() and b.GetID and GetTalentInfo(cur, b:GetID()) == name then self:ShowGlow(b) end
        end
    else
        for t = 1, (GetNumTalentTabs and GetNumTalentTabs() or 3) do
            if tabName(t) == wantTab then self:ShowGlow(_G[prefix .. "Tab" .. t]) end
        end
    end
end

local hooked = false
local function hookTalentUI()
    if hooked then return end
    for _, fn in ipairs({ "TalentFrame_Update", "PlayerTalentFrame_Update", "PlayerTalentFrame_UpdateTalents" }) do
        if _G[fn] then hooksecurefunc(fn, function() FG:UpdateTalentGlow() end); hooked = true end
    end
    for _, p in ipairs(PREFIXES) do
        local f = _G[p]
        if f and f.HookScript then
            f:HookScript("OnShow", function() C_Timer.After(0, function() FG:UpdateTalentGlow() end) end)
            hooked = true
        end
    end
end

---------------------------------------------------------------------------
-- Class trainer reminder
---------------------------------------------------------------------------
-- Line for the guide window, or nil
function FG:TrainerLine()
    local c = ForeverGuideCharDB
    if not c then return end
    local level = UnitLevel("player")
    local last = c.trainedLevel or 0
    if level < 4 or level < last + 2 then return end
    local since = last > 0 and (" (last trained at %d)"):format(last) or ""
    return "|cff66ccffNew spell ranks:|r visit your class trainer" .. since .. " - Orgrimmar or Thunder Bluff on this route"
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("TRAINER_SHOW")
ev:RegisterEvent("CHARACTER_POINTS_CHANGED")
ev:RegisterEvent("PLAYER_LEVEL_UP")
if C_EventUtils == nil or (C_EventUtils.IsEventValid and C_EventUtils.IsEventValid("PLAYER_TALENT_UPDATE")) then
    pcall(ev.RegisterEvent, ev, "PLAYER_TALENT_UPDATE")
end
ev:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" then
        if arg == "Blizzard_TalentUI" then hookTalentUI() end
        return
    end
    if event == "PLAYER_LOGIN" then
        if _G.TalentFrame or _G.PlayerTalentFrame then hookTalentUI() end
        return
    end
    if event == "TRAINER_SHOW" then
        -- profession trainers don't count
        if not (IsTradeskillTrainer and IsTradeskillTrainer()) then
            ForeverGuideCharDB.trainedLevel = UnitLevel("player")
            if FG.UpdateUI then FG:UpdateUI() end
        end
        return
    end
    FG:UpdateTalentGlow()
    if FG.UpdateUI then FG:UpdateUI() end
end)
