-- Group panel: party members who run ForeverGuide share their level, XP,
-- rested XP, professions, food / Well Fed, hearthstone, durability, free bag
-- slots, zone and guide step over a hidden addon channel. Works whether or
-- not they use the guide itself (/fg options).
local _, FG = ...

local PREFIX = "FGRP"
local VERSION = "1"
local SEP, LIST = "\t", ";"

-- Dungeon Finder groups only hear addon messages on INSTANCE_CHAT (PARTY goes nowhere for pugs)
local function groupChannel()
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    return (IsInRaid and IsInRaid()) and "RAID" or "PARTY"
end

FG.groupData = {}   -- [name] = { level, xp, xpMax, rested, zone, step, fed, food, hearth, dur, bags, profs = {...}, seen }

---------------------------------------------------------------------------
-- Gathering this player's info
---------------------------------------------------------------------------
local function durabilityPct()
    local cur, max = 0, 0
    for slot = 1, 18 do
        local c, m = GetInventoryItemDurability(slot)
        if c and m and m > 0 then cur, max = cur + c, max + m end
    end
    return max > 0 and math.floor(cur / max * 100 + 0.5) or 100
end

local function freeBagSlots()
    local free = 0
    local getFree = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
    if not getFree then return 0 end
    for bag = 0, 4 do
        local n, family = getFree(bag)
        if n and (family == nil or family == 0) then free = free + n end
    end
    return free
end

local function professions()
    local out = {}
    if GetNumSkillLines then
        local section
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
            if isHeader then section = name
            elseif section == (TRADE_SKILLS or "Professions") or section == (SECONDARY_SKILLS or "Secondary Skills") then
                table.insert(out, { name, rank or 0, maxRank or 0 })
            end
        end
    end
    if #out == 0 then   -- fallback: the skills the guide tracks
        for _, n in ipairs({ "First Aid", "Cooking", "Fishing", "Alchemy", "Herbalism", "Skinning", "Mining",
                             "Leatherworking", "Tailoring", "Blacksmithing", "Enchanting", "Engineering" }) do
            local r = FG:SkillRank(n)
            if r then table.insert(out, { n, r, 0 }) end
        end
    end
    return out
end

local function guideStep()
    if not (ForeverGuideDB and ForeverGuideDB.showGuide ~= false) then return "" end
    local guide, name = FG:GetGuide()
    if not guide then return "" end
    local idx = FG.currentStep and FG.currentStep.index or #guide.steps
    return ("%s #%d/%d"):format(name, idx, #guide.steps)
end

function FG:MyGroupInfo()
    local f = self:BestFood()
    local food = f and (self:ItemCount(f[2]) + (f[7] and self:ItemCount(f[7]) or 0)) or 0
    local _, class = UnitClass("player")
    return {
        class = class, level = UnitLevel("player"), xp = UnitXP("player"), xpMax = UnitXPMax("player"),
        rested = GetXPExhaustion and GetXPExhaustion() or 0,
        zone = GetZoneText and GetZoneText() or "", step = guideStep(),
        fed = self:HasBuff("Well Fed") and 1 or 0, food = food, hearth = self:HearthCooldown(),
        dur = durabilityPct(), bags = freeBagSlots(), profs = professions(), seen = GetTime(),
    }
end

---------------------------------------------------------------------------
-- Messages: "S" status and "P" professions, tab-separated
---------------------------------------------------------------------------
function FG:EncodeStatus(i)
    local fl = math.floor
    return table.concat({ "S", VERSION, i.class or "", fl(i.level or 0), fl(i.xp or 0), fl(i.xpMax or 0), fl(i.rested or 0),
                          i.fed, fl(i.food or 0), fl(i.hearth or 0), fl(i.dur or 100), fl(i.bags or 0), i.zone or "", i.step or "" }, SEP)
end

function FG:EncodeProfs(i)
    local parts = {}
    for _, p in ipairs(i.profs) do table.insert(parts, ("%s:%d:%d"):format(p[1], math.floor(p[2] or 0), math.floor(p[3] or 0))) end
    return "P" .. SEP .. VERSION .. SEP .. table.concat(parts, LIST)
end

-- What you're wearing: E <version> <class> <localized class> <localized race> <slot:itemID;...>
function FG:EncodeGear()
    local parts = {}
    for slot = 1, 18 do
        local id = GetInventoryItemID and GetInventoryItemID("player", slot)
        if id then table.insert(parts, slot .. ":" .. id) end
    end
    local className, class = UnitClass("player")
    local raceName = UnitRace("player")
    return table.concat({ "E", VERSION, class or "", className or "", raceName or "", table.concat(parts, LIST) }, SEP)
end

function FG:DecodeMessage(sender, msg)
    local f = {}
    for field in (msg .. SEP):gmatch("(.-)" .. SEP) do table.insert(f, field) end
    local d = self.groupData[sender] or {}
    if f[1] == "S" then
        d.class, d.level, d.xp, d.xpMax = f[3], tonumber(f[4]), tonumber(f[5]), tonumber(f[6])
        d.rested, d.fed, d.food, d.hearth = tonumber(f[7]), f[8] == "1", tonumber(f[9]), tonumber(f[10])
        d.dur, d.bags, d.zone, d.step = tonumber(f[11]), tonumber(f[12]), f[13], f[14]
    elseif f[1] == "P" then
        d.profs = {}
        for item in ((f[3] or "") .. LIST):gmatch("(.-)" .. LIST) do
            local n, r, m = item:match("^(.+):(%d+):(%d+)$")
            if n then table.insert(d.profs, { n, tonumber(r), tonumber(m) }) end
        end
    elseif f[1] == "E" then
        d.class, d.className, d.raceName = f[3], f[4], f[5]
        d.gear = {}
        for slot, id in (f[6] or ""):gmatch("(%d+):(%d+)") do d.gear[tonumber(slot)] = tonumber(id) end
        d.seen = GetTime()
        self.groupData[sender] = d
        if self.RefreshBagIcons then self:RefreshBagIcons() end
        return
    elseif f[1] == "Q" then
        if self.SetPartyBags then self:SetPartyBags(sender, f[3]) end   -- bag sizes: Q <version> <s1;s2;s3;s4>
        return
    elseif f[1] == "L" then
        if self.SetSharedCloth then self:SetSharedCloth(sender, f[3], f[4]) end   -- cloth plan: L <version> <alt> <clothID:need:tier;...>
        return
    elseif f[1] == "H" then
        -- what a member carries of the wanted materials: H <version> <itemID:count;...>
        if self.SetPartyHave then self:SetPartyHave(sender, f[3]) end
        return
    elseif f[1] == "G" then
        -- materials a crafter is missing for party upgrades: G <version> <itemID:count:who:delta;...>
        if self.SetPartyGather then self:SetPartyGather(sender, f[3]) end
        return
    elseif f[1] == "C" then
        -- crafting offers: C <version> <name:slot:itemID:delta:ready;...>
        if self.SetCraftOffers then self:SetCraftOffers(sender, f[3]) end
        return
    elseif f[1] == "N" then
        -- keep list in chunks: N <version> <seq>/<total> <id:code;...>
        local seq, total = (f[3] or ""):match("^(%d+)/(%d+)$")
        seq, total = tonumber(seq), tonumber(total)
        if not seq then return end
        self.needBuffer = self.needBuffer or {}
        local buf = self.needBuffer[sender]
        if seq == 1 or not buf or buf.total ~= total then buf = { total = total, parts = {}, n = 0 } end
        if not buf.parts[seq] then buf.parts[seq] = f[4] or ""; buf.n = buf.n + 1 end
        self.needBuffer[sender] = buf
        if buf.n == total then
            local list = {}
            for i = 1, total do self:DecodeNeeds(buf.parts[i] or "", list) end
            self:SetPartyNeeds(sender, list)
            self.needBuffer[sender] = nil
        end
        return
    elseif f[1] == "B" then
        d.blessing = f[3]       -- the paladin blessing they want
        self.groupData[sender] = d
        if self.UpdateBuffBar then self:UpdateBuffBar() end
        return
    elseif f[1] == "O" then
        if self.SetRole then self:SetRole(f[3], f[4], true) end   -- role assignment: O <version> <name> <role>
        return
    elseif f[1] == "R" then
        self:BroadcastGroupInfo(true)   -- someone asked for everyone's info
        self:BroadcastNeeds(true)
        if self.BroadcastCraftOffers then self:BroadcastCraftOffers(true) end
        return
    else
        return
    end
    d.seen = GetTime()
    self.groupData[sender] = d
    self:UpdateGroupPanel()
end

---------------------------------------------------------------------------
-- Sending (throttled) and receiving
---------------------------------------------------------------------------
-- Share this player's [Keep] list so party members see it on their loot
local lastNeeds = ""
-- Share our best craft per person and slot so crafters don't duplicate each other
local lastOffers = ""
function FG:BroadcastCraftOffers(force)
    if not (IsInGroup and IsInGroup()) or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    if not self.CraftOfferEntries then return end
    local entries = self:CraftOfferEntries()
    local text = table.concat(entries, LIST)
    if #text > 230 then   -- keep it in one message: biggest upgrades first
        table.sort(entries, function(a, b) return tonumber(a:match(":(%d+):%d$")) > tonumber(b:match(":(%d+):%d$")) end)
        local cut = {}
        for _, e in ipairs(entries) do
            if #table.concat(cut, LIST) + #e + 1 > 230 then break end
            table.insert(cut, e)
        end
        text = table.concat(cut, LIST)
    end
    local gather = self.CraftGatherEntries and table.concat(self:CraftGatherEntries(), LIST) or ""
    if #gather > 230 then gather = gather:sub(1, 230):gsub(";[^;]*$", "") end
    if not force and text == lastOffers and gather == self.lastGather then return end
    lastOffers = text
    self.lastGather = gather
    local channel = groupChannel()
    C_ChatInfo.SendAddonMessage(PREFIX, table.concat({ "C", VERSION, text }, SEP), channel)
    C_ChatInfo.SendAddonMessage(PREFIX, table.concat({ "G", VERSION, gather }, SEP), channel)
end

local lastHave = ""
function FG:SendHave()
    if not (IsInGroup and IsInGroup()) or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    if not self.HaveEntries then return end
    local text = table.concat(self:HaveEntries(), LIST)
    if #text > 230 then text = text:sub(1, 230):gsub(";[^;]*$", "") end
    if text == lastHave then return end
    lastHave = text
    local channel = groupChannel()
    C_ChatInfo.SendAddonMessage(PREFIX, table.concat({ "H", VERSION, text }, SEP), channel)
end

function FG:BroadcastNeeds(force)
    if not (IsInGroup and IsInGroup()) or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    local chunks = self:EncodeNeeds()
    local joined = table.concat(chunks, "|")
    if not force and joined == lastNeeds then return end
    lastNeeds = joined
    local channel = groupChannel()
    for i, chunk in ipairs(chunks) do
        C_ChatInfo.SendAddonMessage(PREFIX, table.concat({ "N", VERSION, i .. "/" .. #chunks, chunk }, SEP), channel)
    end
end

local lastSent, lastProfs = 0, ""
function FG:BroadcastGroupInfo(force)
    if not (IsInGroup and IsInGroup()) or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then
        self:UpdateGroupPanel()
        return
    end
    if not force and GetTime() - lastSent < 5 then return end
    lastSent = GetTime()
    local channel = groupChannel()
    local info = self:MyGroupInfo()
    C_ChatInfo.SendAddonMessage(PREFIX, self:EncodeStatus(info), channel)
    local profs = self:EncodeProfs(info)
    if force or profs ~= lastProfs then
        lastProfs = profs
        C_ChatInfo.SendAddonMessage(PREFIX, profs, channel)
    end
    if force and self.RoleOf then
        -- share the roles we know for everyone in the group
        local units = { "player" }
        for n = 1, 4 do if UnitExists("party" .. n) then table.insert(units, "party" .. n) end end
        for _, u in ipairs(units) do
            local name = UnitName(u)
            if name and ForeverGuideDB.roles and ForeverGuideDB.roles[name] then
                C_ChatInfo.SendAddonMessage(PREFIX, table.concat({ "O", VERSION, name, ForeverGuideDB.roles[name] }, SEP), channel)
            end
        end
    end
    if self.BagSizes then
        local bags = table.concat(self:BagSizes(), LIST)
        if force or bags ~= self.lastBags then
            self.lastBags = bags
            C_ChatInfo.SendAddonMessage(PREFIX, table.concat({ "Q", VERSION, bags }, SEP), channel)
        end
    end
    if self.ClothEncode then
        local alt, wants = self:ClothEncode()
        if alt then
            local cloth = table.concat({ "L", VERSION, alt, wants }, SEP)
            if force or cloth ~= self.lastCloth then
                self.lastCloth = cloth
                C_ChatInfo.SendAddonMessage(PREFIX, cloth, channel)
            end
        end
    end
    local blessing = self.WantedBlessing and self:WantedBlessing() or ""
    if force or blessing ~= self.lastBlessing then
        self.lastBlessing = blessing
        C_ChatInfo.SendAddonMessage(PREFIX, table.concat({ "B", VERSION, blessing }, SEP), channel)
    end
    local gear = self:EncodeGear()
    if force or gear ~= self.lastGear then
        self.lastGear = gear
        C_ChatInfo.SendAddonMessage(PREFIX, gear, channel)
    end
    self:UpdateGroupPanel()
end

function FG:SendRole(name, role)
    if not (IsInGroup and IsInGroup()) or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    local channel = groupChannel()
    C_ChatInfo.SendAddonMessage(PREFIX, table.concat({ "O", VERSION, name, role }, SEP), channel)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
        -- after Init.lua has set up saved variables (it handles PLAYER_LOGIN later)
        C_Timer.After(0, function() FG:CreateGroupPanel() end)
        for _, e in ipairs({ "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP",
                             "SKILL_LINES_CHANGED", "ZONE_CHANGED_NEW_AREA", "UPDATE_INVENTORY_DURABILITY",
                             "BAG_UPDATE_DELAYED", "UNIT_AURA", "PLAYER_EQUIPMENT_CHANGED" }) do
            self:RegisterEvent(e)
        end
        C_Timer.NewTicker(30, function() FG:BroadcastGroupInfo(true) end)
        C_Timer.After(3, function()
            if IsInGroup and IsInGroup() and C_ChatInfo then
                C_ChatInfo.SendAddonMessage(PREFIX, "R", groupChannel())
            end
            FG:BroadcastGroupInfo(true)
            FG:BroadcastNeeds(true)
        end)
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, _, sender = ...
        if prefix ~= PREFIX then return end
        sender = Ambiguate and Ambiguate(sender, "short") or sender
        if sender == UnitName("player") then return end
        FG:DecodeMessage(sender, msg)
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- drop people who left, ask newcomers for their info
        local inGroup = {}
        for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
            local n = UnitName((IsInRaid and IsInRaid()) and ("raid" .. i) or ("party" .. i))
            if n then inGroup[n] = true end
        end
        for n in pairs(FG.groupData) do
            if not inGroup[n] then
                FG.groupData[n] = nil; FG:SetPartyNeeds(n, {})
                if FG.partyHave then FG.partyHave[n] = nil end
                if FG.partyGather then FG.partyGather[n] = nil end
                if FG.craftOffers then FG.craftOffers[n] = nil end
                FG.craftCache = nil
            end
        end
        if IsInGroup and IsInGroup() and C_ChatInfo then
            C_ChatInfo.SendAddonMessage(PREFIX, "R", groupChannel())
        end
        FG:BroadcastGroupInfo(true)
        FG:BroadcastNeeds(true)
    elseif event == "UNIT_AURA" then
        if ... == "player" then FG:BroadcastGroupInfo() end
    else
        FG:BroadcastGroupInfo()
    end
end)

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local ROW_H, WIDTH = 46, 300

local function classColor(class)
    local c = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
    local fl = math.floor
    return c and ("|cff%02x%02x%02x"):format(fl(c.r * 255), fl(c.g * 255), fl(c.b * 255)) or "|cffffffff"
end

local SHORT = { ["First Aid"] = "FA", Cooking = "Cook", Fishing = "Fish", Alchemy = "Alch", Herbalism = "Herb",
                Skinning = "Skin", Mining = "Mine", Leatherworking = "LW", Tailoring = "Tail",
                Blacksmithing = "BS", Enchanting = "Ench", Engineering = "Eng" }

function FG:CreateGroupPanel()
    local f = CreateFrame("Frame", "ForeverGuideGroupPanel", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetWidth(WIDTH)
    f:SetHeight(40)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local left, top = self:GetLeft(), self:GetTop()
        if left and top then
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            ForeverGuideDB.groupPos = { left, top }
        end
    end)
    if f.SetBackdrop then
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                        tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        f:SetBackdropColor(0, 0, 0, 0.75)
        f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    end
    local pos = ForeverGuideDB.groupPos
    if pos then f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos[1], pos[2])
    else f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -220) end

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 10, -8)
    f.title:SetText("Group")
    f.rows = {}
    self.groupPanel = f
    self:UpdateGroupPanel()
end

local function getRow(f, i)
    local row = f.rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, f)
    row:SetSize(WIDTH - 16, ROW_H)
    row:SetPoint("TOPLEFT", 8, -24 - (i - 1) * ROW_H)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("TOPLEFT", 0, 0)
    row.name:SetWidth(WIDTH - 16)
    row.name:SetJustifyH("LEFT")
    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.bar:SetSize(WIDTH - 16, 6)
    row.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    row.bar:SetStatusBarColor(0.6, 0.2, 0.8)
    row.bar:SetMinMaxValues(0, 1)
    row.rest = row.bar:CreateTexture(nil, "BACKGROUND")
    row.rest:SetColorTexture(0.2, 0.4, 0.9, 0.5)
    row.rest:SetPoint("LEFT")
    row.rest:SetHeight(6)
    row.info = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.info:SetPoint("TOPLEFT", row.bar, "BOTTOMLEFT", 0, -2)
    row.info:SetWidth(WIDTH - 16)
    row.info:SetJustifyH("LEFT")
    f.rows[i] = row
    return row
end

local function fill(row, name, d)
    local pct = (d.xpMax and d.xpMax > 0) and d.xp / d.xpMax or 0
    local restPct = (d.xpMax and d.xpMax > 0) and math.min(1, (d.xp + (d.rested or 0)) / d.xpMax) or 0
    row.bar:SetValue(pct)
    row.rest:SetWidth(math.max(1, (WIDTH - 16) * restPct))
    local fed = d.fed and "|cff00ff00Fed|r" or "|cffff8040Hungry|r"
    local hearth = (d.hearth or 0) > 0 and ("|cffff4040HS %dm|r"):format(math.ceil(d.hearth / 60)) or "|cff00ff00HS|r"
    local dur = (d.dur or 100) < 30 and ("|cffff4040Dur %d%%|r"):format(math.floor(d.dur)) or ("Dur %d%%"):format(math.floor(d.dur or 100))
    local fl = math.floor
    row.name:SetText(("%s%s|r  L%d  %d%%%s   %s  Food %d  %s  %s  Bags %d"):format(
        classColor(d.class), name, fl(d.level or 0), fl(pct * 100),
        (d.rested or 0) > 0 and ("  |cff6699ff+%d%% rested|r"):format(fl((d.rested / (d.xpMax or 1)) * 100)) or "",
        fed, fl(d.food or 0), hearth, dur, fl(d.bags or 0)))
    local profs = {}
    for _, p in ipairs(d.profs or {}) do table.insert(profs, ("%s %d"):format(SHORT[p[1]] or p[1], math.floor(p[2] or 0))) end
    row.info:SetText(table.concat(profs, " · ") .. ((d.zone and d.zone ~= "") and ("\n" .. d.zone) or "")
        .. ((d.step and d.step ~= "") and ("  |cff888888" .. d.step .. "|r") or ""))
    row:Show()
end

function FG:UpdateGroupPanel()
    local f = self.groupPanel
    if not f then return end
    if ForeverGuideDB.showGroup == false then f:Hide() return end
    f:Show()
    local n = 1
    fill(getRow(f, n), UnitName("player"), self:MyGroupInfo())
    local lowest = UnitLevel("player")
    for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
        local unit = "party" .. i
        local name = UnitExists and UnitExists(unit) and UnitName(unit)
        if name then
            n = n + 1
            local d = self.groupData[name]
            if d then
                fill(getRow(f, n), name, d)
            else
                local _, class = UnitClass(unit)
                local row = getRow(f, n)
                row.bar:SetValue(0)
                row.rest:SetWidth(1)
                row.name:SetText(("%s%s|r  L%d  |cff888888(no ForeverGuide)|r"):format(classColor(class), name, math.floor(UnitLevel(unit) or 0)))
                row.info:SetText("")
                row:Show()
            end
            lowest = math.min(lowest, (d and d.level) or UnitLevel(unit) or lowest)
        end
    end
    for i = n + 1, #f.rows do f.rows[i]:Hide() end
    local highest = UnitLevel("player")
    for _, d in pairs(self.groupData) do highest = math.max(highest, d.level or 0) end
    f.title:SetText(n > 1 and (highest - lowest >= 2 and ("Group  |cffff8040levels %d-%d - help the lowest catch up|r"):format(math.floor(lowest), math.floor(highest)) or "Group") or "Group (solo)")
    f:SetHeight(28 + n * ROW_H)
end
