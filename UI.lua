-- UI: draggable step window
local _, FG = ...

local WIDTH = 300

function FG:CreateUI()
    local f = CreateFrame("Frame", "ForeverGuideFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetWidth(WIDTH)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    -- Always anchored by its top-left corner, so the window only grows and
    -- shrinks at the bottom and the buttons (top-right) never move
    local function pinTopLeft()
        local left, top = f:GetLeft(), f:GetTop()
        if not left or not top then return end
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        ForeverGuideDB.framePos = { "TOPLEFT", "BOTTOMLEFT", left, top }
    end
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        pinTopLeft()
    end)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.75)
    f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

    f:SetHeight(100)
    local pos = ForeverGuideDB.framePos
    if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -60, -220) end
    pinTopLeft()   -- also converts positions saved by older versions

    local function button(label, onClick)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(52, 18)
        b:SetText(label)
        b:SetScript("OnClick", onClick)
        return b
    end
    -- Fixed in the top-right corner: same spot on every step
    f.skip = button("Skip", function() FG:SkipStep() end)
    f.skip:SetPoint("TOPRIGHT", -6, -6)
    f.back = button("Back", function() FG:Back() end)
    f.back:SetPoint("RIGHT", f.skip, "LEFT", -2, 0)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 10, -8)
    f.title:SetPoint("TOPRIGHT", f.back, "TOPLEFT", -6, -2)
    f.title:SetJustifyH("LEFT")

    f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.body:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
    f.body:SetWidth(WIDTH - 20)
    f.body:SetJustifyH("LEFT")

    f.nextText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.nextText:SetPoint("TOPLEFT", f.body, "BOTTOMLEFT", 0, -8)
    f.nextText:SetWidth(WIDTH - 20)
    f.nextText:SetJustifyH("LEFT")

    -- Status: talent point to spend, hearth cooldown, Well Fed
    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetPoint("TOPLEFT", f.nextText, "BOTTOMLEFT", 0, -6)
    f.status:SetWidth(WIDTH - 20)
    f.status:SetJustifyH("LEFT")

    f.rec = f:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
    f.rec:SetPoint("BOTTOMLEFT", 10, 9)

    -- Options button next to Back/Skip
    f.opt = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.opt:SetSize(20, 18)
    f.opt:SetText("?")
    f.opt:SetPoint("RIGHT", f.back, "LEFT", -2, 0)
    f.opt:SetScript("OnClick", function() FG:ToggleOptions() end)
    f.title:SetPoint("TOPRIGHT", f.opt, "TOPLEFT", -6, -2)

    self.frame = f
    if ForeverGuideDB.showGuide == false then f:Hide() end
end

function FG:UpdateUI()
    local f = self.frame
    if not f then return end
    local guide, name = self:GetGuide()
    local step = self.currentStep

    if not guide then
        f.title:SetText("ForeverGuide")
        f.body:SetText("No guide loaded.\nType |cffffffff/fg list|r")
        f.nextText:SetText("")
    else
        f.title:SetText(("%s  |cffaaaaaa%d/%d|r"):format(name, step and step.index or #guide.steps, #guide.steps))
        if step then
            f.body:SetText(self:StepText(step))
            local nxt = guide.steps[step.index + 1]
            f.nextText:SetText(nxt and ("Next: " .. self:StepText(nxt):gsub("\n.*", "")) or "")
        else
            f.body:SetText("|cff00ff00Guide complete!|r")
            f.nextText:SetText("")
        end
    end

    f.status:SetText(self:StatusText())
    f.rec:SetText(ForeverGuideCharDB.recording.active and "REC" or "")
    f:SetHeight(math.max(f.title:GetStringHeight(), 18) + f.body:GetStringHeight() + f.nextText:GetStringHeight()
        + f.status:GetStringHeight() + 40)

    if self.arrow then
        if step and step.x and step.map and ForeverGuideDB.showArrow ~= false then self.arrow:Show() else self.arrow:Hide() end
    end
end

function FG:StatusText()
    local lines = {}
    local talent = self:TalentLine()
    if talent then table.insert(lines, talent) end
    local trainer = self.TrainerLine and self:TrainerLine()
    if trainer then table.insert(lines, trainer) end
    local craft = self.CraftLine and self:CraftLine()
    if craft then table.insert(lines, craft) end
    local cloth = self.ClothLine and self:ClothLine()
    if cloth then table.insert(lines, cloth) end
    local cguide = self.CraftGuideLine and self:CraftGuideLine()
    if cguide then table.insert(lines, cguide) end
    local nearby = self.NearbyLine and self:NearbyLine()
    if nearby then table.insert(lines, nearby) end
    local cd = self:HearthCooldown()
    local hearth = cd > 0 and ("|cffff4040%d:%02d|r"):format(cd / 60, cd % 60) or "|cff00ff00ready|r"
    local fed = self:HasBuff("Well Fed") and "|cff00ff00Well Fed|r" or "|cffff8040not Well Fed|r"
    table.insert(lines, ("Hearth (%s): %s    %s"):format(GetBindLocation() or "?", hearth, fed))
    local food = self:FoodLine()
    if food then table.insert(lines, food) end
    local stock = self:FoodStockLine()
    if stock then table.insert(lines, stock) end
    for _, l in ipairs(self:SecondaryLines()) do table.insert(lines, l) end
    return table.concat(lines, "\n")
end

function FG:ToggleUI()
    ForeverGuideDB.showGuide = not ForeverGuideDB.showGuide
    self:ApplyOptions()
end
