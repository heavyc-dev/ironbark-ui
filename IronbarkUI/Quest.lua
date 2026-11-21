-------------------------------------------------------------------------------
--  Ironbark UI - quest tracker
--
--  Ironbark's own tracker, drawn from your quest log in Blizzard's fonts:
--    * "Quests n/max" title - click to collapse the whole tracker
--    * zones (the quest log's own headers) - click to collapse, Ctrl-click to
--      pin to the top; the zone you're in comes first after pinned ones
--    * [level] titles in difficulty colors, sorted by level within a zone
--    * left-click a quest: open it in the quest log; right-click: hide/show
--      its objectives
--    * completed quests become one "(Turn in)" line
--    * inside a dungeon/raid only that instance's quests
--    * Blizzard tooltip background + border while the mouse is over it
--    * fades to 25% in combat, mouseover brings it back
--  While it's on, Questie's and Blizzard's tracker windows are hidden on
--  screen. Nothing in either addon's settings is changed.
-------------------------------------------------------------------------------
local _, ns = ...

local WIDTH, MAX_HEIGHT = 260, 460
local PAD = 8
local FADE_ALPHA = 0.25
local INDENT_QUEST, INDENT_OBJ = 10, 22
local ZONE_GAP = 8
-- zone headers stay neutral so difficulty-colored quest titles stand apart
local ZONE_COLOR = { 0.82, 0.82, 0.82 }

local tracker, bg, lines = nil, nil, {}
local pending = false

local function Store(key)
    ns.db[key] = ns.db[key] or {}
    return ns.db[key]
end

-------------------------------------------------------------------------------
--  Quest log reading (newer C_QuestLog API, or the classic functions)
-------------------------------------------------------------------------------
local function Objectives(index, questID)
    local list = {}
    if C_QuestLog and C_QuestLog.GetQuestObjectives and questID then
        for _, o in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
            list[#list + 1] = { text = o.text, done = o.finished }
        end
        if #list > 0 then return list end
    end
    if GetNumQuestLeaderBoards then
        for j = 1, GetNumQuestLeaderBoards(index) or 0 do
            local text, _, done = GetQuestLogLeaderBoard(j, index)
            list[#list + 1] = { text = text, done = done }
        end
    end
    return list
end

local function ReadQuestLog()
    local zones, current, total = {}, nil, 0
    local n = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries())
        or (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0
    for i = 1, n do
        local title, level, isHeader, complete, questID
        if C_QuestLog and C_QuestLog.GetInfo then
            local info = C_QuestLog.GetInfo(i)
            if info then
                title, level, isHeader, questID = info.title, info.level, info.isHeader, info.questID
                complete = C_QuestLog.IsComplete and questID and C_QuestLog.IsComplete(questID)
            end
        else
            local _
            title, level, _, isHeader, _, complete, _, questID = GetQuestLogTitle(i)
            complete = complete == 1 or complete == true
        end
        if title then
            if isHeader then
                current = { zone = title, quests = {}, order = #zones }
                zones[#zones + 1] = current
            elseif current then
                total = total + 1
                current.quests[#current.quests + 1] = {
                    title = title, level = level or 0, complete = complete and true or false,
                    index = i, questID = questID, objectives = Objectives(i, questID),
                }
            end
        end
    end
    return zones, total
end

local function SortZones(zones)
    local pinned, here = Store("questPinned"), GetRealZoneText and GetRealZoneText()
    table.sort(zones, function(a, b)
        local pa, pb = pinned[a.zone] and 1 or 0, pinned[b.zone] and 1 or 0
        if pa ~= pb then return pa > pb end
        local ha, hb = (a.zone == here) and 1 or 0, (b.zone == here) and 1 or 0
        if ha ~= hb then return ha > hb end
        return a.order < b.order
    end)
    if ns.db.questSortLevel then
        for _, z in ipairs(zones) do
            table.sort(z.quests, function(a, b)
                if a.level ~= b.level then return a.level < b.level end
                return a.index < b.index
            end)
        end
    end
end

-------------------------------------------------------------------------------
--  Lines
-------------------------------------------------------------------------------
local Queue

local function OnClick(self, button)
    local kind = self.kind
    if kind == "title" then
        ns.db.questMinimized = not ns.db.questMinimized
    elseif kind == "zone" then
        if IsControlKeyDown() then
            local pinned = Store("questPinned")
            pinned[self.zone] = (not pinned[self.zone]) or nil
        else
            local c = Store("questZoneCollapsed")
            c[self.zone] = (not c[self.zone]) or nil
        end
    elseif kind == "quest" then
        if button == "RightButton" then
            local c = Store("questObjCollapsed")
            local key = self.questID or self.questTitle
            c[key] = (not c[key]) or nil
        elseif not InCombatLockdown() then
            if QuestMapFrame_OpenToQuestDetails and self.questID then
                QuestMapFrame_OpenToQuestDetails(self.questID)
            elseif QuestLog_SetSelection and QuestLogFrame then
                ShowUIPanel(QuestLogFrame)
                QuestLog_SetSelection(self.questIndex)
                if QuestLog_Update then QuestLog_Update() end
            end
        end
        return
    else
        return
    end
    Queue()
end

local function Line(i)
    local l = lines[i]
    if l then return l end
    l = CreateFrame("Button", nil, tracker)
    l.text = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.text:SetPoint("TOPLEFT")
    l.text:SetJustifyH("LEFT")
    l.text:SetWordWrap(true)
    l.text:SetShadowOffset(1, -1)
    l.text:SetShadowColor(0, 0, 0, 1)
    l.right = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    l.right:SetPoint("TOPRIGHT")
    l.right:SetJustifyH("RIGHT")
    l.right:SetShadowOffset(1, -1)
    -- faint divider under zone headers
    l.rule = l:CreateTexture(nil, "ARTWORK")
    l.rule:SetColorTexture(1, 1, 1, 0.18)
    l.rule:SetHeight(1)
    l.rule:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -1)
    l.rule:SetPoint("TOPRIGHT", l, "BOTTOMRIGHT", 0, -1)
    l.rule:Hide()
    l:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    l:SetScript("OnClick", OnClick)
    l:SetScript("OnEnter", function(self)
        if self.kind then self.text:SetAlpha(0.75) end
        if ns.QuestHover then ns.QuestHover() end -- background fades in while hovered
    end)
    l:SetScript("OnLeave", function(self) self.text:SetAlpha(1) end)
    lines[i] = l
    return l
end

-- one line; returns its height
local function Set(i, y, indent, font, text, r, g, b, right, rightColor, data)
    local l = Line(i)
    l.text:SetFontObject(font)
    l.right:SetFontObject(font)
    l.right:SetText(right or "")
    local rc = rightColor or { 0.35, 0.85, 0.35 }
    l.right:SetTextColor(rc[1], rc[2], rc[3])
    local rightW = right and (l.right:GetStringWidth() + 6) or 0
    l.text:SetWidth(WIDTH - PAD * 2 - indent - rightW)
    l.text:SetText(text)
    l.text:SetTextColor(r, g, b)
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", tracker, "TOPLEFT", PAD + indent, -y)
    l:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", -PAD, -y)
    local h = math.max(l.text:GetStringHeight(), 12)
    l:SetHeight(h)
    l.kind = data and data.kind or nil
    l.zone = data and data.zone or nil
    l.questIndex = data and data.index or nil
    l.questID = data and data.questID or nil
    l.questTitle = data and data.title or nil
    l:EnableMouse(l.kind ~= nil)
    l.rule:SetShown(l.kind == "zone")
    l:Show()
    return h + 2
end

-------------------------------------------------------------------------------
--  Drawing
-------------------------------------------------------------------------------
local function Draw()
    pending = false
    if not tracker then return end
    if not ns.db.questTracker then tracker:Hide() return end

    local zones, total = ReadQuestLog()
    SortZones(zones)
    local inInstance, kind = IsInInstance()
    local here = ns.db.questDungeon and inInstance and (kind == "party" or kind == "raid") and GetInstanceInfo()
    local zoneCollapsed, objCollapsed = Store("questZoneCollapsed"), Store("questObjCollapsed")
    local pinned = Store("questPinned")

    local i, y, hidden = 0, PAD, 0
    local maxQuests = MAX_QUESTS or C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept() or 20
    i = i + 1
    y = y + Set(i, y, 0, GameFontNormal, ("%s Quests"):format(ns.db.questMinimized and "+" or "-"),
        1, 0.82, 0, ("%d/%d"):format(total, maxQuests), { 0.8, 0.8, 0.8 }, { kind = "title" })

    if not ns.db.questMinimized then
        for _, z in ipairs(zones) do
            if #z.quests > 0 and (not here or z.zone == here) then
                if y > MAX_HEIGHT then
                    hidden = hidden + #z.quests
                else
                    y = y + ZONE_GAP
                    local closed = zoneCollapsed[z.zone]
                    local label = (closed and "+ " or "- ") .. z.zone
                    local pin = pinned[z.zone] and "pinned" or (closed and tostring(#z.quests) or nil)
                    i = i + 1
                    y = y + Set(i, y, 0, GameFontNormalSmall, label,
                        ZONE_COLOR[1], ZONE_COLOR[2], ZONE_COLOR[3], pin, { 0.6, 0.6, 0.6 },
                        { kind = "zone", zone = z.zone }) + 2 -- room for the divider
                    if not closed then
                        for _, q in ipairs(z.quests) do
                            if y > MAX_HEIGHT then
                                hidden = hidden + 1
                            else
                                local c = GetQuestDifficultyColor and GetQuestDifficultyColor(q.level)
                                    or { r = 1, g = 1, b = 1 }
                                local title = (ns.db.questLevels and q.level > 0)
                                    and ("[" .. q.level .. "] " .. q.title) or q.title
                                local turnIn = (ns.db.questCollapse and q.complete) and "(Turn in)" or nil
                                i = i + 1
                                y = y + Set(i, y, INDENT_QUEST, GameFontNormalSmall, title, c.r, c.g, c.b,
                                    turnIn, nil, { kind = "quest", index = q.index, questID = q.questID, title = q.title })
                                if not turnIn and not objCollapsed[q.questID or q.title] then
                                    for _, o in ipairs(q.objectives) do
                                        if o.text and not o.done then
                                            i = i + 1
                                            y = y + Set(i, y, INDENT_OBJ, GameFontHighlightSmall, o.text,
                                                0.85, 0.85, 0.85)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        if hidden > 0 then
            i = i + 1
            y = y + Set(i, y, INDENT_QUEST, GameFontDisableSmall, ("+%d more"):format(hidden), 0.6, 0.6, 0.6)
        end
    end
    for k = i + 1, #lines do lines[k]:Hide() end
    tracker:SetHeight(y + PAD)
    tracker:Show()
end

function Queue()
    if pending then return end
    pending = true
    C_Timer.After(0.2, Draw)
end

-------------------------------------------------------------------------------
--  Hide Questie's / Blizzard's tracker windows while ours is on (screen only)
-------------------------------------------------------------------------------
local OTHERS = { "Questie_BaseFrame", "ObjectiveTrackerFrame", "QuestWatchFrame" }

local function HideOthers()
    for _, name in ipairs(OTHERS) do
        local f = _G[name]
        if f and not f.__ibuiHook then
            f.__ibuiHook = true
            f:HookScript("OnShow", function(self)
                if ns.db.questTracker and not (self:IsProtected() and InCombatLockdown()) then self:Hide() end
            end)
        end
        if f and ns.db.questTracker and f:IsShown() and not (f:IsProtected() and InCombatLockdown()) then
            f:Hide()
        end
    end
end

-------------------------------------------------------------------------------
--  Hover background + combat fade (one ticker; alpha only)
-------------------------------------------------------------------------------
local BG_SPEED = 0.15
local function Tick()
    if not tracker or not tracker:IsShown() then return end
    local over = tracker:IsMouseOver()
    -- background + border while hovered
    local a = bg:GetAlpha()
    local wantBg = over and 1 or 0
    if a ~= wantBg then
        bg:SetAlpha(wantBg > a and math.min(1, a + BG_SPEED) or math.max(0, a - BG_SPEED))
    end
    -- combat fade
    local want = (ns.db.questFade and InCombatLockdown() and not over) and FADE_ALPHA or 1
    if tracker:GetAlpha() ~= want then tracker:SetAlpha(want) end
    return over or InCombatLockdown() or bg:GetAlpha() > 0 or tracker:GetAlpha() ~= 1
end

-- Event-driven: the timer runs only while hovered, in combat, or still
-- fading, then stops itself.
local ticker
function ns.QuestHover()
    if ticker or not tracker then return end
    ticker = C_Timer.NewTicker(0.05, function()
        if not Tick() then
            ticker:Cancel()
            ticker = nil
        end
    end)
end

-------------------------------------------------------------------------------
--  Wiring
-------------------------------------------------------------------------------
local function Build()
    if tracker then return end
    tracker = CreateFrame("Frame", "IronbarkQuestTracker", UIParent)
    tracker:SetWidth(WIDTH)
    tracker:SetPoint("TOPRIGHT", MinimapCluster or Minimap, "BOTTOMRIGHT", -4, -10)
    tracker:SetFrameStrata("LOW")
    -- Blizzard tooltip background + border, shown on hover
    bg = CreateFrame("Frame", nil, tracker, "BackdropTemplate")
    bg:SetAllPoints()
    bg:SetFrameLevel(tracker:GetFrameLevel())
    bg:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    bg:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
    bg:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    bg:SetAlpha(0)
end

function ns.RefreshQuest()
    Build()
    if ns.db.questTracker then
        HideOthers()
    else
        for _, name in ipairs(OTHERS) do
            local f = _G[name]
            if f and not (f:IsProtected() and InCombatLockdown()) then f:Show() end
        end
    end
    Draw()
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        ns.QuestHover() -- combat fade in / back out
        return
    end
    if event == "PLAYER_ENTERING_WORLD" or event == "ADDON_LOADED" then HideOthers() end
    Queue()
end)

ns.OnLogin(function()
    ns.RefreshQuest()
    for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "UNIT_QUEST_LOG_CHANGED",
        "QUEST_ACCEPTED", "QUEST_REMOVED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD",
        "PLAYER_LEVEL_UP", "ADDON_LOADED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    C_Timer.After(3, HideOthers)
    C_Timer.After(10, HideOthers)
end)
