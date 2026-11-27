-------------------------------------------------------------------------------
--  Ironbark UI - quest tracker
--
--  Ironbark's own tracker, drawn from your quest log in Blizzard's fonts:
--    * "Quests n/max" title - click to collapse the whole tracker
--    * zones (the quest log's own headers) - click to collapse, Ctrl-click to
--      pin to the top; the zone you're in comes first after pinned ones
--    * [level] titles in difficulty colors, sorted by level within a zone
--    * left-click a quest: open it in the quest log; right-click: a menu
--      (hide objectives, stop tracking, share, link in chat, abandon).
--      Right-click a zone or the title for their own short menus.
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

local function OpenQuest(questID, index)
    if InCombatLockdown() then return end
    if QuestMapFrame_OpenToQuestDetails and questID then
        QuestMapFrame_OpenToQuestDetails(questID)
    elseif QuestLog_SetSelection and QuestLogFrame then
        ShowUIPanel(QuestLogFrame)
        QuestLog_SetSelection(index)
        if QuestLog_Update then QuestLog_Update() end
    end
end

-- make this quest the quest log's selected one (what share / abandon act on)
local function SelectQuest(questID, index)
    if C_QuestLog and C_QuestLog.SetSelectedQuest and questID then
        C_QuestLog.SetSelectedQuest(questID)
        return true
    elseif SelectQuestLogEntry and index then
        SelectQuestLogEntry(index)
        return true
    end
    return false
end

local function CanShare(questID, index)
    if not IsInGroup() then return false end
    if C_QuestLog and C_QuestLog.IsPushableQuest and questID then return C_QuestLog.IsPushableQuest(questID) end
    if GetQuestLogPushable and SelectQuestLogEntry and index then
        SelectQuestLogEntry(index)
        return GetQuestLogPushable() and true or false
    end
    return false
end

local function LinkQuest(questID, title)
    local link = questID and GetQuestLink and GetQuestLink(questID) or ("[" .. tostring(title) .. "]")
    if not (ChatEdit_InsertLink and ChatEdit_InsertLink(link)) and ChatFrame_OpenChat then
        ChatFrame_OpenChat(link)
    end
end

-- the game's own "Abandon?" box where it exists, else ours
StaticPopupDialogs["IRONBARKUI_ABANDON"] = {
    text = "Abandon \"%s\"?",
    button1 = YES, button2 = NO,
    OnAccept = function()
        if C_QuestLog and C_QuestLog.AbandonQuest then C_QuestLog.AbandonQuest() elseif AbandonQuest then AbandonQuest() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local function Abandon(questID, index, title)
    if not SelectQuest(questID, index) then return end
    if C_QuestLog and C_QuestLog.SetAbandonQuest then C_QuestLog.SetAbandonQuest() elseif SetAbandonQuest then SetAbandonQuest() end
    StaticPopup_Show(StaticPopupDialogs["ABANDON_QUEST"] and "ABANDON_QUEST" or "IRONBARKUI_ABANDON", title)
end

-- right-click menus (Blizzard's context menu); false when this client has none
local function Menu(self)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return false end
    local kind, zone = self.kind, self.zone
    local questID, index, title = self.questID, self.questIndex, self.questTitle
    local key = questID or title
    MenuUtil.CreateContextMenu(self, function(_, root)
        if kind == "quest" then
            root:CreateTitle(title or "Quest")
            root:CreateButton("Open in quest log", function() OpenQuest(questID, index) end)
            local c = Store("questObjCollapsed")
            root:CreateButton(c[key] and "Show objectives" or "Hide objectives", function()
                c[key] = (not c[key]) or nil
                Queue()
            end)
            root:CreateButton("Stop tracking", function()
                Store("questHidden")[key] = true
                Queue()
            end)
            root:CreateButton("Link in chat", function() LinkQuest(questID, title) end)
            if CanShare(questID, index) then
                root:CreateButton("Share with party", function()
                    if SelectQuest(questID, index) and QuestLogPushQuest then QuestLogPushQuest() end
                end)
            end
            root:CreateDivider()
            root:CreateButton("|cffff5555Abandon|r", function() Abandon(questID, index, title) end)
        elseif kind == "zone" then
            root:CreateTitle(zone or "Zone")
            local pinned, closed = Store("questPinned"), Store("questZoneCollapsed")
            root:CreateButton(pinned[zone] and "Unpin" or "Pin to top", function()
                pinned[zone] = (not pinned[zone]) or nil
                Queue()
            end)
            root:CreateButton(closed[zone] and "Expand" or "Collapse", function()
                closed[zone] = (not closed[zone]) or nil
                Queue()
            end)
        else
            root:CreateTitle("Quests")
            local hidden, n = Store("questHidden"), 0
            for _ in pairs(hidden) do n = n + 1 end
            if n > 0 then
                root:CreateButton(("Track all again (%d hidden)"):format(n), function()
                    wipe(hidden)
                    Queue()
                end)
            end
            root:CreateButton(ns.db.questSortLevel and "Sort: quest log order" or "Sort: by level", function()
                ns.db.questSortLevel = not ns.db.questSortLevel
                Queue()
            end)
            root:CreateButton("Collapse all zones", function()
                local closed = Store("questZoneCollapsed")
                for _, l in ipairs(lines) do
                    if l:IsShown() and l.kind == "zone" and l.zone then closed[l.zone] = true end
                end
                Queue()
            end)
            root:CreateButton("Expand all zones", function()
                wipe(Store("questZoneCollapsed"))
                Queue()
            end)
        end
    end)
    return true
end

local function OnClick(self, button)
    local kind = self.kind
    if button == "RightButton" and kind and Menu(self) then return end
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
        elseif IsShiftKeyDown() then
            -- into the open chat line, or opens one with the link in it
            LinkQuest(self.questID, self.questTitle)
        else
            OpenQuest(self.questID, self.questIndex)
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

-- Scrolling: the "Quests" title stays put; everything under it lives on
-- `body`, a sheet as tall as the whole list, seen through `view` (a window
-- that cuts off what doesn't fit). The mouse wheel slides the sheet.
local view, body, thumb
local scroll, bodyHeight, viewHeight = 0, 0, 0

local function ApplyScroll()
    if not body then return end
    local max = math.max(0, bodyHeight - viewHeight)
    scroll = math.max(0, math.min(scroll, max))
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", view, "TOPLEFT", 0, scroll)
    body:SetPoint("TOPRIGHT", view, "TOPRIGHT", 0, scroll)
    tracker:EnableMouseWheel(max > 0) -- otherwise the wheel keeps zooming the camera
    if max > 0 and viewHeight > 0 then
        -- a slim marker on the right edge: where you are in the list
        local h = math.max(16, viewHeight * viewHeight / bodyHeight)
        thumb:SetHeight(h)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", view, "TOPRIGHT", -3, -(viewHeight - h) * scroll / max)
        thumb:Show()
    else
        thumb:Hide()
    end
end

-- one line on `parent` (the tracker for the title, the sheet for the rest);
-- returns its height
local function Set(parent, i, y, indent, font, text, r, g, b, right, rightColor, data)
    local l = Line(i)
    if l:GetParent() ~= parent then l:SetParent(parent) end
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
    l:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + indent, -y)
    l:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PAD, -y)
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
    local stopped = Store("questHidden")
    if next(stopped) then
        for _, z in ipairs(zones) do
            local keep = {}
            for _, q in ipairs(z.quests) do
                if not stopped[q.questID or q.title] then keep[#keep + 1] = q end
            end
            z.quests = keep
        end
    end
    SortZones(zones)
    local inInstance, kind = IsInInstance()
    local here = ns.db.questDungeon and inInstance and (kind == "party" or kind == "raid") and GetInstanceInfo()
    local zoneCollapsed, objCollapsed = Store("questZoneCollapsed"), Store("questObjCollapsed")
    local pinned = Store("questPinned")

    local i = 0
    local maxQuests = MAX_QUESTS or C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept() or 20
    i = i + 1
    local top = PAD + Set(tracker, i, PAD, 0, GameFontNormal, ("%s Quests"):format(ns.db.questMinimized and "+" or "-"),
        1, 0.82, 0, ("%d/%d"):format(total, maxQuests), { 0.8, 0.8, 0.8 }, { kind = "title" })

    -- the list itself, on the sheet (y counts from the sheet's top)
    local y = 0
    if not ns.db.questMinimized then
        for _, z in ipairs(zones) do
            if #z.quests > 0 and (not here or z.zone == here) then
                y = y + ZONE_GAP
                local closed = zoneCollapsed[z.zone]
                local label = (closed and "+ " or "- ") .. z.zone
                local pin = pinned[z.zone] and "pinned" or (closed and tostring(#z.quests) or nil)
                i = i + 1
                y = y + Set(body, i, y, 0, GameFontNormalSmall, label,
                    ZONE_COLOR[1], ZONE_COLOR[2], ZONE_COLOR[3], pin, { 0.6, 0.6, 0.6 },
                    { kind = "zone", zone = z.zone }) + 2 -- room for the divider
                if not closed then
                    for _, q in ipairs(z.quests) do
                        local c = GetQuestDifficultyColor and GetQuestDifficultyColor(q.level)
                            or { r = 1, g = 1, b = 1 }
                        local title = (ns.db.questLevels and q.level > 0)
                            and ("[" .. q.level .. "] " .. q.title) or q.title
                        local turnIn = (ns.db.questCollapse and q.complete) and "(Turn in)" or nil
                        i = i + 1
                        y = y + Set(body, i, y, INDENT_QUEST, GameFontNormalSmall, title, c.r, c.g, c.b,
                            turnIn, nil, { kind = "quest", index = q.index, questID = q.questID, title = q.title })
                        if not turnIn and not objCollapsed[q.questID or q.title] then
                            for _, o in ipairs(q.objectives) do
                                if o.text and not o.done then
                                    i = i + 1
                                    y = y + Set(body, i, y, INDENT_OBJ, GameFontHighlightSmall, o.text,
                                        0.85, 0.85, 0.85)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    for k = i + 1, #lines do lines[k]:Hide() end

    -- as tall as the list, up to MAX_HEIGHT; past that it scrolls
    bodyHeight = y
    viewHeight = math.max(0, math.min(bodyHeight, MAX_HEIGHT - top - PAD))
    body:SetHeight(math.max(1, bodyHeight))
    view:ClearAllPoints()
    view:SetPoint("TOPLEFT", tracker, "TOPLEFT", 0, -top)
    view:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", 0, -top)
    view:SetHeight(math.max(1, viewHeight))
    tracker:SetHeight(top + viewHeight + PAD)
    ApplyScroll()
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

    view = CreateFrame("Frame", nil, tracker)
    view:SetClipsChildren(true)
    body = CreateFrame("Frame", nil, view)
    thumb = tracker:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(1, 1, 1, 0.35)
    thumb:SetWidth(2)
    thumb:Hide()
    tracker:SetScript("OnMouseWheel", function(_, delta)
        scroll = scroll - delta * 36
        ApplyScroll()
    end)
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
