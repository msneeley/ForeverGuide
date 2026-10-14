-- Options: /fg options opens a small panel to switch each part on or off.
-- The first time a character loads the addon it gets a welcome page first.
-- Everything is independent - e.g. group panel only, no guide or arrow.
local _, FG = ...

FG.optionList = {
    { "showGuide",  "Guide window",                      "The step-by-step guide window" },
    { "showArrow",  "Waypoint arrow",                    "The arrow pointing at the current step" },
    { "auto",       "Auto accept / turn in quests",      "Hold Shift at an NPC to do it by hand" },
    { "autoReward", "Auto pick quest rewards",           "Uses the guide's pick, or your class's best stats" },
    { "share",      "Auto share quests with the group",  "Shares guide quests you accept" },
    { "showGroup",  "Group panel",                       "Party levels, XP, professions, food, hearth, durability" },
    { "bagIcons",   "Bag dots",                          "Gold: you need. Blue: party needs. Green: party upgrade. Purple: your upgrade" },
    { "upgradeDots","Upgrade checks",                    "Green / purple dots and tooltip lines for gear upgrades" },
    { "talentGuide","Talent recommendations",            "Next-talent line in the guide window (/fg talents still lists the build)" },
    { "glow",       "Talent glow",                       "Glowing border on the talent to take next (never clicks for you)" },
    { "skipOutleveled","Skip quests you've outleveled",  "After playing off-script, the guide jumps ahead and skips grey quests (keeps chains you need)" },
    { "nearby",     "Nearby quests when off the route",  "Suggests quests around you for your level when you're away from the guide (/fg nearby)" },
    { "craftHelper","Crafting for the party",            "Leatherworking/Tailoring/Blacksmithing upgrades for the group (/fg craft)" },
    { "showBuffs",  "Buff bar",                          "Red when you're missing food, camp, class buffs or elixirs (/fg buffs)" },
}

function FG:OptionDefaults()
    local db = ForeverGuideDB
    if db.showGuide == nil then db.showGuide = not db.hidden end
    for _, o in ipairs(self.optionList) do
        if db[o[1]] == nil then db[o[1]] = true end
    end
end

function FG:ApplyOptions()
    if self.frame then
        if ForeverGuideDB.showGuide then self.frame:Show() else self.frame:Hide() end
        ForeverGuideDB.hidden = not ForeverGuideDB.showGuide
    end
    self:UpdateUI()
    if self.UpdateGroupPanel then self:UpdateGroupPanel() end
    if self.RefreshBagIcons then self:RefreshBagIcons() end
    if self.UpdateBuffBar then self:UpdateBuffBar() end
    if self.UpdateTalentGlow then self:UpdateTalentGlow() end
end

-- Builds the options window once. It doubles as the first-login welcome.
local function buildOptions()
    local f = CreateFrame("Frame", "ForeverGuideOptions", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    local n = #FG.optionList
    local top = 96   -- room for the intro and the guide line
    f:SetSize(440, top + n * 30 + 50)
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
        f:SetBackdropColor(0, 0, 0, 0.92)
    end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 12, -12)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    f.intro = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.intro:SetPoint("TOPLEFT", 12, -36)
    f.intro:SetWidth(416)
    f.intro:SetJustifyH("LEFT")
    f.guideLine = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.guideLine:SetPoint("TOPLEFT", 12, -74)
    f.guideLine:SetWidth(416)
    f.guideLine:SetJustifyH("LEFT")
    f.checks = {}
    for i, o in ipairs(FG.optionList) do
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 10, -top - (i - 1) * 30)
        local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", cb, "RIGHT", 2, 6)
        label:SetText(o[2])
        local note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        note:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -1)
        note:SetText(o[3])
        cb:SetScript("OnClick", function(self)
            ForeverGuideDB[o[1]] = self:GetChecked() and true or false
            FG:ApplyOptions()
        end)
        f.checks[o[1]] = cb
    end
    local buffs = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    buffs:SetSize(230, 24)
    buffs:SetPoint("BOTTOMLEFT", 12, 12)
    buffs:SetText("Buff checks, roles & blessing...")
    buffs:SetScript("OnClick", function() if FG.ToggleBuffOptions then FG:ToggleBuffOptions() end end)
    local done = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    done:SetSize(100, 24)
    done:SetPoint("BOTTOMRIGHT", -12, 12)
    done:SetText("Done")
    done:SetScript("OnClick", function() f:Hide() end)
    f:Hide()   -- before the OnHide hook, so building the window doesn't count as "seen"
    f:SetScript("OnHide", function() if ForeverGuideCharDB then ForeverGuideCharDB.welcomed = true end end)
    return f
end

local function fillOptions(f, welcome)
    if welcome then
        f.title:SetText("Choose your settings")
        f.intro:SetText("Turn off anything you don't want - everything is independent. Set up the buff bar, your role and the paladin blessing you want with the button below. You can change all of this later with /fg options or the ? button.")
    else
        f.title:SetText("ForeverGuide options")
        f.intro:SetText("Everything is independent: turn off whatever you don't use. /fg help lists every command.")
    end
    local _, g = FG:GetGuide()
    f.guideLine:SetText("Guide: |cffffffff" .. (g or "none picked yet") .. "|r  |cff888888(/fg list, /fg set <name> to change)|r")
    for key, cb in pairs(f.checks) do cb:SetChecked(ForeverGuideDB[key] ~= false) end
end

function FG:ToggleOptions()
    self.optionsFrame = self.optionsFrame or buildOptions()
    local f = self.optionsFrame
    if f:IsShown() then f:Hide() return end
    fillOptions(f, false)
    f:Show()
end

-- First login on this character: a welcome page, then the settings
local function buildWelcome()
    local f = CreateFrame("Frame", "ForeverGuideWelcome", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(460, 380)
    f:SetPoint("CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                        tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    end
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(48, 48)
    icon:SetPoint("TOPLEFT", 22, -22)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -2)
    title:SetText("ForeverGuide")
    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetText("Group leveling guide for WoW Forever, 1-35")
    local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", 26, -90)
    body:SetWidth(408)
    body:SetJustifyH("LEFT")
    body:SetSpacing(3)
    body:SetText(table.concat({
        "|cffffd100Welcome!|r Here's what ForeverGuide does for your group:",
        "",
        "|cff66ccff-|r Step-by-step route with an arrow, solo to 12, then all five together",
        "|cff66ccff-|r Auto accept, turn in and share quests (hold Shift to do it by hand)",
        "|cff66ccff-|r Party panel, buff bar with roles, and bag dots for what to keep or trade",
        "|cff66ccff-|r Talent, trainer, profession, food and potion recommendations",
        "",
        "|cff888888It never spends talents, Legacy points or gold for you - it only points the way.|r",
    }, "\n"))
    f.guideLine = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.guideLine:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -14)
    f.guideLine:SetWidth(408)
    f.guideLine:SetJustifyH("LEFT")
    local setup = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    setup:SetSize(190, 28)
    setup:SetPoint("BOTTOMLEFT", 26, 22)
    setup:SetText("Choose my settings")
    setup:SetScript("OnClick", function()
        f.toSettings = true
        f:Hide()
        FG.optionsFrame = FG.optionsFrame or buildOptions()
        fillOptions(FG.optionsFrame, true)
        FG.optionsFrame:Show()
    end)
    local defaults = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    defaults:SetSize(190, 28)
    defaults:SetPoint("BOTTOMRIGHT", -26, 22)
    defaults:SetText("Start with everything on")
    defaults:SetScript("OnClick", function() f:Hide() end)
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", 0, 56)
    hint:SetText("Settings later: /fg options or the ? button.  Commands: /fg help")
    f:Hide()
    f:SetScript("OnHide", function()
        if ForeverGuideCharDB then ForeverGuideCharDB.welcomed = true end
    end)
    return f
end

function FG:ShowWelcome()
    self.welcomeFrame = self.welcomeFrame or buildWelcome()
    local _, g = self:GetGuide()
    self.welcomeFrame.guideLine:SetText("Your guide: |cffffffff" .. (g or "picked when you reach a starting zone") ..
        "|r\n|cff888888Change it any time with /fg list and /fg set <name>.|r")
    self.welcomeFrame:Show()
end
