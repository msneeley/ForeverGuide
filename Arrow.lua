-- Arrow: points at the current step's coordinates
local _, FG = ...

function FG:CreateArrow()
    local f = CreateFrame("Frame", "ForeverGuideArrow", UIParent)
    f:SetSize(54, 68)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        ForeverGuideDB.arrowPos = { p, rp, x, y }
    end)

    local pos = ForeverGuideDB.arrowPos
    if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else f:SetPoint("TOP", UIParent, "TOP", 0, -120) end

    -- Minimal look: white arrow with a soft dark shadow so it reads on any
    -- background, green on arrival, small distance text underneath
    f.shadow = f:CreateTexture(nil, "BACKGROUND")
    f.shadow:SetTexture("Interface\\Minimap\\MinimapArrow")
    f.shadow:SetSize(60, 60)
    f.shadow:SetPoint("TOP", 0, 4)
    f.shadow:SetDesaturated(true)
    f.shadow:SetVertexColor(0, 0, 0, 0.6)

    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetTexture("Interface\\Minimap\\MinimapArrow")
    f.tex:SetSize(50, 50)
    f.tex:SetPoint("TOP", 0, -1)
    f.tex:SetDesaturated(true)   -- greyscale, so the tint below is the colour you see

    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text:SetPoint("TOP", f.tex, "BOTTOM", 0, 4)
    f.text:SetShadowOffset(1, -1)

    f.elapsed = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed < 0.05 then return end
        self.elapsed = 0

        local step = FG.currentStep
        if not step or not step.x or not step.map then return end

        local dist, bearing = FG:GetVectorTo(step.map, step.x, step.y)
        if not dist then
            self.tex:SetVertexColor(1, 1, 1, 0.35)
            self.text:SetText("other zone")
            return
        end

        local facing = GetPlayerFacing()
        if facing then
            self.tex:SetRotation(bearing - facing)
            self.shadow:SetRotation(bearing - facing)
        end

        local radius = step.radius or 8
        if dist <= radius then
            self.tex:SetVertexColor(0.3, 1, 0.3, 0.9)
        else
            self.tex:SetVertexColor(1, 1, 1, 1)
        end
        self.text:SetFormattedText("%dy", dist)

        if (step.travel or step.hearth or step.deathskip) and dist <= radius then
            FG:MarkReached(step)
        end
    end)

    f:Hide()
    self.arrow = f
end
