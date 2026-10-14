-- Nearby: when you're off the route, quests around you that suit your level
-- (from NearbyData.lua - quests NOT already in the guide). Shown in the guide
-- window as a one-line addendum and listed by /fg nearby. Prerequisites you
-- haven't done and quests you've finished or outleveled are left out.
local _, FG = ...

local function playerPos()
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not map then return end
    local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return map end
    local x, y = pos.x or (pos.GetXY and select(1, pos:GetXY())), pos.y or (pos.GetXY and select(2, pos:GetXY()))
    return map, x and x * 100, y and y * 100
end

-- { { id, title, level, giver, x, y, dist } } best first
function FG:NearbyList(max)
    local map, px, py = playerPos()
    if not map or not self.nearbyQuests then return {} end
    local level = UnitLevel("player")
    local out = {}
    for _, q in ipairs(self.nearbyQuests) do
        local qmap, id, qlvl, minl, x, y, giver, title, pre = q[1], q[2], q[3], q[4], q[5], q[6], q[7], q[8], q[9]
        if qmap == map and minl <= level and qlvl >= level - 2 and qlvl <= level + 3
           and not self:IsQuestTurnedIn(id) and not self:FindQuestInLog(id) then
            local ok = true
            for _, p in ipairs(pre or {}) do if not self:IsQuestTurnedIn(p) then ok = false break end end
            if ok then
                local dist = (px and py) and math.sqrt((x - px) ^ 2 + (y - py) ^ 2) or 0
                table.insert(out, { id = id, title = title, level = qlvl, giver = giver, x = x, y = y, dist = dist,
                                    score = qlvl * 3 - dist / 4 })
            end
        end
    end
    table.sort(out, function(a, b) return a.score > b.score end)
    while #out > (max or 8) do table.remove(out) end
    return out
end

-- Off the route: far from the current step (or no step at all)
function FG:OffRoute()
    local step = self.currentStep
    if not step then return true end
    if not (step.map and step.x) then return false end
    local dist = self:GetVectorTo(step.map, step.x, step.y)
    return dist == nil or dist > 1500
end

function FG:NearbyLine()
    if ForeverGuideDB.nearby == false or not self:OffRoute() then return nil end
    local list = self:NearbyList(3)
    if #list == 0 then return nil end
    local q = list[1]
    return ("|cff99ccffOff the route? Nearby:|r %s (%d) - %s %.0f, %.0f%s |cff888888(/fg nearby)|r"):format(
        q.title, q.level, q.giver, q.x, q.y, #list > 1 and (" +" .. (#list - 1) .. " more") or "")
end

function FG:PrintNearby()
    local list = self:NearbyList(8)
    if #list == 0 then
        self:Print("No off-route quests for your level around here. The guide's next step: /fg")
        return
    end
    self:Print("Quests near you that suit your level (not on the route - Classic data, Forever may differ):")
    for _, q in ipairs(list) do
        self:Print(("  |cffffffff%s|r (level %d) - %s at %.1f, %.1f"):format(q.title, q.level, q.giver, q.x, q.y))
    end
    self:Print("|cff888888The guide picks back up where you are when you return (/fg sync).|r")
end
