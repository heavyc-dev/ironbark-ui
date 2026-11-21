-------------------------------------------------------------------------------
--  Ironbark UI - one bag, with sections
--
--  A single bag window built from Blizzard's own templates (portrait frame +
--  ContainerFrameItemButtonTemplate), so items click, drag, sell, use and show
--  tooltips exactly like stock bags. Items are grouped into sections and
--  sorted inside each one automatically; nothing moves inside your real bags.
--
--    Equipment | Consumables | Quest | Gathering | Reagents | Other | Junk
--
--  Blizzard's combined bag stays in charge of open/close state (keybinds,
--  merchant, bank, Esc) but is parked on a hidden parent; this window mirrors
--  whether it is open. Bank bags are untouched.
--
--  Secure item buttons must never be CREATED in combat (that taints item use).
--  Buttons are created out of combat and reused; anything missing in combat
--  is filled in when combat ends.
-------------------------------------------------------------------------------
local _, ns = ...

local COLUMNS, SIZE, GAP = 10, 37, 4
local EMPTY_SLOT = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
local SECTION_GAP, HEADER_H = 8, 16
local BACKPACK, LAST_BAG = 0, NUM_BAG_SLOTS or 4

local IC = Enum.ItemClass or {}
local CLS_CONSUMABLE = IC.Consumable or 0
local CLS_WEAPON     = IC.Weapon or 2
local CLS_ARMOR      = IC.Armor or 4
local CLS_REAGENT    = IC.Reagent or 5
local CLS_TRADEGOODS = IC.Tradegoods or 7
local CLS_QUEST      = IC.Questitem or 12
local POOR = (Enum.ItemQuality and Enum.ItemQuality.Poor) or 0

-- Trade goods that come from gathering: cloth, leather, metal & stone, meat,
-- herbs, elemental.
local GATHERED = { [5] = true, [6] = true, [7] = true, [8] = true, [9] = true, [10] = true }

local SECTIONS = {
    { key = "equipment",   label = "Equipment" },
    { key = "consumables", label = "Consumables" },
    { key = "quest",       label = "Quest" },
    { key = "gathering",   label = "Gathering" },
    { key = "reagents",    label = "Reagents" },
    { key = "other",       label = "Other" },
    { key = "junk",        label = "Junk" },
}

local win, content
local buttons = {}      -- [bag*1000+slot] = item button (reused)
local headers = {}      -- [sectionKey] = FontString
local pendingCombat = false

-------------------------------------------------------------------------------
--  Classification
-------------------------------------------------------------------------------
local function Classify(bag, slot, info)
    if info.quality == POOR then return "junk" end
    local q = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
    local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(info.itemID or info.itemLink)
    if (q and (q.isQuestItem or q.questID)) or classID == CLS_QUEST then return "quest" end
    if classID == CLS_WEAPON or classID == CLS_ARMOR then return "equipment" end
    if classID == CLS_CONSUMABLE then return "consumables" end
    if classID == CLS_TRADEGOODS then
        return GATHERED[subID] and "gathering" or "reagents"
    end
    if classID == CLS_REAGENT then return "reagents" end
    return "other", classID, subID
end

-- Every field normalised to a number first, so the order is always consistent.
local function SortItems(a, b)
    local qa, qb = a.quality or 0, b.quality or 0
    if qa ~= qb then return qa > qb end
    local ca, cb = a.classID or 99, b.classID or 99
    if ca ~= cb then return ca < cb end
    local sa, sb = a.subID or 99, b.subID or 99
    if sa ~= sb then return sa < sb end
    local ia, ib = a.itemID or 0, b.itemID or 0
    if ia ~= ib then return ia < ib end
    if a.count ~= b.count then return a.count > b.count end
    return a.key < b.key
end

-------------------------------------------------------------------------------
--  Category sort: physically moves items in your normal bags into section
--  order (sorted inside each section the same way as the sections view).
--  One move at a time, waiting for the server to unlock items between moves.
--  Stops on combat, when you pick something up, or after a safety limit.
--  Quivers, ammo pouches and soul bags are left alone.
-------------------------------------------------------------------------------
local SECTION_INDEX = {}
for i, s in ipairs(SECTIONS) do SECTION_INDEX[s.key] = i end

local function SortableSlots()
    local list = {}
    for bag = BACKPACK, LAST_BAG do
        local _, family = C_Container.GetContainerNumFreeSlots(bag)
        if family == 0 then
            for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
                list[#list + 1] = { bag = bag, slot = slot }
            end
        end
    end
    return list
end

-- current[i] = item record or false (empty); locked = something still moving
local function Snapshot(slots)
    local current, locked = {}, false
    for i, s in ipairs(slots) do
        local info = C_Container.GetContainerItemInfo(s.bag, s.slot)
        if info then
            if info.isLocked then locked = true end
            local section = Classify(s.bag, s.slot, info)
            local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(info.itemID or info.itemLink)
            current[i] = {
                itemID = info.itemID, count = info.stackCount or 1, quality = info.quality,
                section = SECTION_INDEX[section] or 99, classID = classID, subID = subID,
                key = s.bag * 1000 + s.slot,
            }
        else
            current[i] = false
        end
    end
    return current, locked
end

local function Desired(current)
    local items = {}
    for _, it in ipairs(current) do
        if it then items[#items + 1] = it end
    end
    table.sort(items, function(a, b)
        if a.section ~= b.section then return a.section < b.section end
        return SortItems(a, b)
    end)
    for i = #items + 1, #current do items[i] = false end
    return items
end

local function Same(a, b)
    if not a or not b then return not a and not b end
    return a.itemID == b.itemID and a.count == b.count
end

local sorter, sortSteps
local MAX_STEPS = 400

local function StopSort(msg)
    if sorter then sorter:Cancel() end
    sorter = nil
    if msg then ns.Print(msg) end
    if win and win.SortButton then win.SortButton:SetButtonState("NORMAL") end
end

local function SortStep()
    if InCombatLockdown() then return StopSort("Sort stopped: combat.") end
    if GetCursorInfo() then return StopSort("Sort stopped: you picked something up.") end
    sortSteps = sortSteps + 1
    if sortSteps > MAX_STEPS then return StopSort("Sort stopped early (safety limit).") end

    local slots = SortableSlots()
    local current, locked = Snapshot(slots)
    if locked then return end -- last move still settling
    local desired = Desired(current)

    for i = 1, #slots do
        if not Same(current[i], desired[i]) then
            local want = desired[i]
            if not want then break end -- only empties left to place
            -- prefer an item that is itself out of place
            local j
            for k = i + 1, #slots do
                if Same(current[k], want) and not Same(current[k], desired[k]) then j = k break end
            end
            if not j then
                for k = i + 1, #slots do
                    if Same(current[k], want) then j = k break end
                end
            end
            if not j then return StopSort("Sort stopped: couldn't place an item.") end
            ClearCursor()
            C_Container.PickupContainerItem(slots[j].bag, slots[j].slot)
            C_Container.PickupContainerItem(slots[i].bag, slots[i].slot)
            return
        end
    end
    StopSort()
end

function ns.SortBags()
    if sorter then return StopSort("Sort cancelled.") end
    if InCombatLockdown() then return ns.Print("Can't sort bags in combat.") end
    sortSteps = 0
    if win and win.SortButton then win.SortButton:SetButtonState("PUSHED", true) end
    sorter = C_Timer.NewTicker(0.08, SortStep)
end

-------------------------------------------------------------------------------
--  Item buttons
-------------------------------------------------------------------------------
local function GetButton(bag, slot)
    local key = bag * 1000 + slot
    local btn = buttons[key]
    if btn then return btn end
    if InCombatLockdown() then return nil end
    -- the template reads its bag from the parent's ID and its slot from its own
    local holder = CreateFrame("Frame", nil, content)
    holder:SetSize(SIZE, SIZE)
    holder:SetID(bag)
    btn = CreateFrame("ItemButton", nil, holder, "ContainerFrameItemButtonTemplate")
    btn:SetAllPoints(holder)
    btn:SetID(slot)
    -- outside Blizzard's container the icon isn't anchored to anything useful
    if btn.icon then
        btn.icon:ClearAllPoints()
        btn.icon:SetAllPoints(btn)
    end
    if btn.NewItemTexture then btn.NewItemTexture:Hide() end
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    buttons[key] = btn
    return btn
end

local function PaintButton(btn, bag, slot, info)
    btn:Show() -- ContainerFrameItemButtonTemplate starts hidden
    -- The template resets its own frame level, so anything drawn on a frame
    -- behind it can end up on top. Pin levels, and draw empty slots as the
    -- button's own icon instead of a separate background.
    local holder = btn:GetParent()
    holder:SetFrameLevel(content:GetFrameLevel() + 1)
    btn:SetFrameLevel(holder:GetFrameLevel() + 1)
    -- Blizzard's bags switch these glows off for anything that isn't new;
    -- our reused buttons have to do it themselves or every slot glows blue
    for _, key in ipairs({ "NewItemTexture", "BattlepayItemTexture", "flash" }) do
        if btn[key] then btn[key]:Hide() end
    end
    for _, key in ipairs({ "newitemglowAnim", "flashAnim" }) do
        if btn[key] and btn[key].Stop then btn[key]:Stop() end
    end
    -- ...then glow only what Blizzard says is genuinely new (cleared on hover
    -- by the template, like stock bags), in the item's quality color
    if info and C_NewItems and C_NewItems.IsNewItem and C_NewItems.IsNewItem(bag, slot) and btn.NewItemTexture then
        local atlas = NEW_ITEM_ATLAS_BY_QUALITY and NEW_ITEM_ATLAS_BY_QUALITY[info.quality] or "bags-glow-white"
        btn.NewItemTexture:SetAtlas(atlas)
        btn.NewItemTexture:Show()
        if btn.flash then btn.flash:Show() end
        if btn.newitemglowAnim then btn.newitemglowAnim:Play() end
        if btn.flashAnim then btn.flashAnim:Play() end
    end

    local icon = (info and info.iconFileID) or EMPTY_SLOT
    if btn.SetItemButtonTexture then btn:SetItemButtonTexture(icon) else SetItemButtonTexture(btn, icon) end
    if btn.icon then btn.icon:Show() end
    SetItemButtonCount(btn, info and info.stackCount or 0)
    SetItemButtonDesaturated(btn, info and info.isLocked)
    if SetItemButtonQuality then
        SetItemButtonQuality(btn, info and info.quality, info and info.itemLink)
    end
    if btn.JunkIcon then btn.JunkIcon:SetShown(info and info.quality == POOR and not info.hasNoValue) end
    if btn.IconQuestTexture then
        local q = info and C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
        if q and q.questID and not q.isActive then
            btn.IconQuestTexture:SetTexture(TEXTURE_ITEM_QUEST_BANG)
            btn.IconQuestTexture:Show()
        elseif q and (q.isQuestItem or q.questID) then
            btn.IconQuestTexture:SetTexture(TEXTURE_ITEM_QUEST_BORDER)
            btn.IconQuestTexture:Show()
        else
            btn.IconQuestTexture:Hide()
        end
    end
    local cd = btn.Cooldown or _G[(btn:GetName() or "") .. "Cooldown"]
    if cd and C_Container.GetContainerItemCooldown then
        local start, dur, enable = C_Container.GetContainerItemCooldown(bag, slot)
        if CooldownFrame_Set then CooldownFrame_Set(cd, start or 0, dur or 0, enable) end
    end
    if GameTooltip:IsOwned(btn) then
        if info and btn.UpdateTooltip then btn:UpdateTooltip() else GameTooltip:Hide() end
    end
end

-------------------------------------------------------------------------------
--  Layout
-------------------------------------------------------------------------------
local function Header(key, label)
    local h = headers[key]
    if not h then
        h = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetJustifyH("LEFT")
        h:SetText(label)
        headers[key] = h
    end
    return h
end

local stats = {}
local function RefreshInner()
    wipe(stats)
    if InCombatLockdown() then pendingCombat = true end

    for _, b in pairs(buttons) do b:GetParent():Hide() end
    for _, h in pairs(headers) do h:Hide() end

    -- 1. gather
    local groups = {}
    for _, s in ipairs(SECTIONS) do groups[s.key] = {} end
    local free, freeList = 0, {}
    for bag = BACKPACK, LAST_BAG do
        local n = C_Container.GetContainerNumSlots(bag) or 0
        local _, bagFamily = C_Container.GetContainerNumFreeSlots(bag)
        for slot = 1, n do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                local section, classID, subID = Classify(bag, slot, info)
                if not classID then
                    local _
                    _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(info.itemID or info.itemLink)
                end
                table.insert(groups[section], {
                    bag = bag, slot = slot, info = info, key = bag * 1000 + slot,
                    quality = info.quality, itemID = info.itemID, count = info.stackCount or 1,
                    classID = classID, subID = subID,
                })
            elseif bagFamily == 0 then -- empty slot in a normal (non-ammo/soul) bag
                free = free + 1
                freeList[#freeList + 1] = { bag = bag, slot = slot }
            end
        end
    end

    local y, width = 0, COLUMNS * (SIZE + GAP) - GAP
    local short = false

    if ns.db.bagView ~= "sections" then
        -- 2a. bag view: every slot where it really is, so you can arrange freely
        local i = 0
        for bag = BACKPACK, LAST_BAG do
            for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
                i = i + 1
                local btn = GetButton(bag, slot)
                if btn then
                    local col, row = (i - 1) % COLUMNS, math.floor((i - 1) / COLUMNS)
                    local holder = btn:GetParent()
                    holder:ClearAllPoints()
                    holder:SetPoint("TOPLEFT", content, "TOPLEFT", col * (SIZE + GAP), -(row * (SIZE + GAP)))
                    holder:Show()
                    PaintButton(btn, bag, slot, C_Container.GetContainerItemInfo(bag, slot))
                else
                    short = true
                end
            end
        end
        y = math.max(1, math.ceil(i / COLUMNS)) * (SIZE + GAP) - GAP
        win.FreeText:SetFormattedText("%d free", free)
    else
        -- 2b. sections view: each section ends with one empty slot (a drop
        -- target right there), and every other empty slot is listed at the
        -- bottom under Free.
        local nextFree = 1
        local function PlaceGrid(entries)
            for i, e in ipairs(entries) do
                local btn = GetButton(e.bag, e.slot)
                if btn then
                    local col, row = (i - 1) % COLUMNS, math.floor((i - 1) / COLUMNS)
                    local holder = btn:GetParent()
                    holder:ClearAllPoints()
                    holder:SetPoint("TOPLEFT", content, "TOPLEFT", col * (SIZE + GAP), -(y + row * (SIZE + GAP)))
                    holder:Show()
                    PaintButton(btn, e.bag, e.slot, e.info)
                else
                    short = true
                end
            end
            y = y + math.ceil(#entries / COLUMNS) * (SIZE + GAP) - GAP + SECTION_GAP
        end
        local function PlaceHeader(key, label)
            local h = Header(key, label)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            h:Show()
            y = y + HEADER_H
        end

        for _, s in ipairs(SECTIONS) do
            local items = groups[s.key]
            if #items > 0 then
                table.sort(items, SortItems)
                local entries = {}
                for _, it in ipairs(items) do entries[#entries + 1] = it end
                if freeList[nextFree] then
                    entries[#entries + 1] = freeList[nextFree] -- info = nil -> empty
                    nextFree = nextFree + 1
                end
                PlaceHeader(s.key, s.label)
                PlaceGrid(entries)
            end
        end

        -- 3. every remaining empty slot
        local rest = {}
        for i = nextFree, #freeList do rest[#rest + 1] = freeList[i] end
        if #rest > 0 then
            PlaceHeader("free", "Free")
            PlaceGrid(rest)
        end
        win.FreeText:SetFormattedText("%d free", free)
        y = math.max(y - SECTION_GAP, SIZE)
    end -- sections view

    if short then pendingCombat = true end

    content:SetSize(width, y)
    win:SetSize(width + win.padX * 2, y + win.padTop + win.padBottom)
    if win.Money then win.Money:SetText(GetMoneyString(GetMoney(), true)) end

    for _, s in ipairs(SECTIONS) do stats[#stats + 1] = s.key .. "=" .. #groups[s.key] end
    stats[#stats + 1] = "free=" .. free
    local made, shown = 0, 0
    for _, b in pairs(buttons) do
        made = made + 1
        if b:IsVisible() then shown = shown + 1 end
    end
    stats[#stats + 1] = ("buttons=%d visible=%d short=%s"):format(made, shown, tostring(short))
end

local lastErr
local function Refresh()
    if not (win and win:IsShown()) then return end
    local ok, err = pcall(RefreshInner)
    if ok then
        ns.db.bagError, lastErr = nil, nil
    elseif err ~= lastErr then
        lastErr = err
        ns.db.bagError = tostring(err)
        ns.Print("Bag window error: %s", tostring(err))
    end
end

-- for /ibui debug
function ns.BagStats()
    local w = win
    return ("bags: window=%s shown=%s size=%.0fx%.0f content=%.0fx%.0f lvl win=%d content=%d | %s | err=%s"):format(
        tostring(w ~= nil), tostring(w and w:IsShown()), w and w:GetWidth() or 0, w and w:GetHeight() or 0,
        content and content:GetWidth() or 0, content and content:GetHeight() or 0,
        w and w:GetFrameLevel() or 0, content and content:GetFrameLevel() or 0,
        table.concat(stats, " "), tostring(ns.db.bagError))
end

-------------------------------------------------------------------------------
--  Class crest as the bag portrait
-------------------------------------------------------------------------------
local function ApplyClassTheme()
    if not win then return end
    local on = ns.db.classTheme
    local _, class = UnitClass("player")
    if win.SetPortraitToAsset then
        local crest = on and class and ("Interface\\Icons\\ClassIcon_" .. class:sub(1, 1) .. class:sub(2):lower())
        local exists = crest and (not GetFileIDFromPath or GetFileIDFromPath(crest))
        win:SetPortraitToAsset(exists and crest or "Interface\\Icons\\INV_Misc_Bag_08")
    end
end
ns.ApplyClassTheme = ApplyClassTheme

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
local function SavePosition()
    local x, y = win:GetLeft(), win:GetTop()
    if x and y then ns.db.bagPos = { x = x, y = y } end
end

local function ApplyPosition()
    win:ClearAllPoints()
    local p = ns.db.bagPos
    if p and p.x then
        win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x, p.y)
    else
        win:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -60, 120)
    end
end

local function BlizzardBagOpen()
    local f = ContainerFrameCombinedBags
    return f and f:IsShown()
end

local function Build()
    if win then return end
    local ok, f = pcall(CreateFrame, "Frame", "IronbarkBagFrame", UIParent, "PortraitFrameTemplate")
    if not ok or not f then
        f = CreateFrame("Frame", "IronbarkBagFrame", UIParent, "BasicFrameTemplateWithInset")
    end
    win = f
    win:Hide()
    win:SetFrameStrata("MEDIUM")
    win:SetToplevel(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    if win.SetTitle then win:SetTitle(BAGSLOTTEXT or "Bags") end
    if win.SetPortraitToAsset then
        win:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Bag_08")
    end
    local portrait = win.SetPortraitToAsset ~= nil
    win.padX, win.padTop, win.padBottom = 14, portrait and 64 or 32, 30

    content = CreateFrame("Frame", nil, win)
    content:SetPoint("TOPLEFT", win, "TOPLEFT", win.padX, -win.padTop)
    -- keep items above the template's art (NineSlice/Bg sit on child frames)
    content:SetFrameLevel(win:GetFrameLevel() + 10)
    ApplyClassTheme()

    -- Sort (Blizzard's broom) and a view toggle, top right under the title
    local sort = CreateFrame("Button", nil, win)
    sort:SetSize(26, 26)
    sort:SetPoint("TOPRIGHT", win, "TOPRIGHT", -12, -28)
    sort:SetFrameLevel(content:GetFrameLevel() + 5)
    sort:SetNormalAtlas("bags-button-autosort-up")
    sort:SetPushedAtlas("bags-button-autosort-down")
    sort:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    sort:SetScript("OnClick", function() ns.SortBags() end)
    sort:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Sort by category")
        GameTooltip:AddLine("Moves items into Equipment, Consumables, Quest, Gathering, Reagents, Other, Junk order. Click again to cancel.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    sort:SetScript("OnLeave", GameTooltip_Hide)
    win.SortButton = sort

    local view = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    view:SetSize(80, 22)
    view:SetPoint("RIGHT", sort, "LEFT", -6, 0)
    view:SetFrameLevel(content:GetFrameLevel() + 5)
    local function Label() view:SetText(ns.db.bagView == "sections" and "Bag view" or "Sections") end
    view:SetScript("OnClick", function()
        ns.db.bagView = (ns.db.bagView == "sections") and "bags" or "sections"
        Label()
        Refresh()
    end)
    Label()

    win.FreeText = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.FreeText:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 16, 10)
    win.Money = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.Money:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -16, 10)

    -- closing ours closes Blizzard's too, so the open state stays in sync
    win:SetScript("OnHide", function()
        if BlizzardBagOpen() then CloseAllBags() end
    end)
    win:SetScript("OnShow", function()
        ApplyPosition()
        Refresh()
    end)
    tinsert(UISpecialFrames, "IronbarkBagFrame")
end

local function Sync()
    if not win then return end
    local open = BlizzardBagOpen()
    if open and not win:IsShown() then
        win:Show()
    elseif not open and win:IsShown() then
        win:Hide()
    end
end

-- Park Blizzard's combined bag on a hidden parent: it keeps tracking open /
-- closed (we read that), but never draws.
local hiddenParent
local function ParkBlizzardBag()
    local f = ContainerFrameCombinedBags
    if not f or f.__ibuiParked then return end
    if InCombatLockdown() then
        ns.RunOutOfCombat("parkBags", ParkBlizzardBag)
        return
    end
    hiddenParent = hiddenParent or CreateFrame("Frame")
    hiddenParent:Hide()
    f:SetParent(hiddenParent)
    f.__ibuiParked = true
    for _, m in ipairs({ "Show", "Hide", "SetShown" }) do
        hooksecurefunc(f, m, function() C_Timer.After(0, Sync) end)
    end
end

-- Pre-create buttons for every slot so opening bags in combat rarely lacks one.
local function Prewarm()
    if InCombatLockdown() or not content then return end
    for bag = BACKPACK, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local b = GetButton(bag, slot)
            if b then b:GetParent():Hide() end
        end
    end
end

-------------------------------------------------------------------------------
--  Wiring
-------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        Prewarm()
        if pendingCombat then
            pendingCombat = false
            Refresh()
        end
        return
    end
    if event == "BAG_UPDATE_DELAYED" then Prewarm() end
    Refresh()
end)

-------------------------------------------------------------------------------
--  Collapsible bag bar. This client's bag bar ignores Blizzard's collapse
--  setting, so: the bag bar (anchored right of the micro menu by the layout) is
--  hidden until you click our arrow, which sits on the right of the micro menu
--  when collapsed and on the right of the bags when open. Arrow art is the
--  party/raid manager's (RaidPanel-Toggle: left half points right, right half
--  points left). Show/hide waits for the end of combat if the bar is protected.
-------------------------------------------------------------------------------
local RAID_ARROW = "Interface\\RaidFrame\\RaidPanel-Toggle"
local bagArrow

local function ApplyBagBar()
    local bar, micro = BagsBar, MicroMenuContainer
    if not (bar and bagArrow) then return end
    local open = ns.db.bagBarOpen
    local emf = EditModeManagerFrame
    local editing = emf and emf.IsEditModeActive and emf:IsEditModeActive()
    if bar:IsProtected() and InCombatLockdown() then
        ns.RunOutOfCombat("bagBar", ApplyBagBar)
    else
        bar:SetShown(open or editing)
    end
    -- Blizzard's own (non-working here) toggle would be a second arrow
    if BagBarExpandToggle then BagBarExpandToggle:SetAlpha(0); BagBarExpandToggle:EnableMouse(false) end

    bagArrow:ClearAllPoints()
    -- bags expand to the right of the micro menu; the arrow sits on the far
    -- right edge of whatever is showing
    local rightOf = (open and bar) or micro or bar
    bagArrow:SetPoint("LEFT", rightOf, "RIGHT", 2, 0)
    -- right-pointing when collapsed (click to open), left-pointing when open
    local l, r = 0, 0.5
    if open then l, r = 0.5, 1 end
    for _, tex in ipairs({ bagArrow:GetNormalTexture(), bagArrow:GetPushedTexture(), bagArrow:GetHighlightTexture() }) do
        if tex then tex:SetTexCoord(l, r, 0, 1) end
    end
end
ns.ApplyBagBar = ApplyBagBar

local function BuildBagArrow()
    if bagArrow or not BagsBar then return end
    local b = CreateFrame("Button", "IronbarkBagBarToggle", UIParent)
    b:SetSize(16, 32)
    b:SetFrameStrata("MEDIUM")
    local useRaid = not GetFileIDFromPath or GetFileIDFromPath(RAID_ARROW)
    local art = useRaid and RAID_ARROW or "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up"
    b:SetNormalTexture(art)
    b:SetPushedTexture(art)
    b:SetHighlightTexture(art, "ADD")
    b:GetHighlightTexture():SetAlpha(0.4)
    b:SetScript("OnClick", function()
        ns.db.bagBarOpen = not ns.db.bagBarOpen
        ApplyBagBar()
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(ns.db.bagBarOpen and "Hide bags" or "Show bags")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    bagArrow = b
    -- re-apply after Blizzard re-shows the bar (layout changes, Edit Mode)
    BagsBar:HookScript("OnShow", function() C_Timer.After(0, ApplyBagBar) end)
    local emf = EditModeManagerFrame
    if emf then
        emf:HookScript("OnShow", function() C_Timer.After(0, ApplyBagBar) end)
        emf:HookScript("OnHide", function() C_Timer.After(0, ApplyBagBar) end)
    end
end

function ns.RefreshBags()
    BuildBagArrow()
    ApplyBagBar()
    if not ns.db.combinedBags then return end
    local r = ns.db.revert
    for _, name in ipairs({ "combinedBags", "expandBagBar" }) do
        if r and r.cvars and r.cvars[name] == nil then r.cvars[name] = GetCVar(name) end
    end
    SetCVar("combinedBags", "1")
    SetCVar("expandBagBar", "0") -- bag bar shows just the backpack
    Build()
    ParkBlizzardBag()
    Prewarm()
    for _, fn in ipairs({ "ToggleAllBags", "OpenAllBags", "CloseAllBags", "ToggleBackpack",
        "OpenBackpack", "CloseBackpack", "ToggleBag", "OpenBag", "CloseBag" }) do
        if _G[fn] and not ns["__hooked" .. fn] then
            ns["__hooked" .. fn] = true
            hooksecurefunc(fn, function() C_Timer.After(0, Sync) end)
        end
    end
    ev:RegisterEvent("BAG_UPDATE_DELAYED")
    ev:RegisterEvent("ITEM_LOCK_CHANGED")
    ev:RegisterEvent("BAG_UPDATE_COOLDOWN")
    ev:RegisterEvent("QUEST_ACCEPTED")
    ev:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
    ev:RegisterEvent("PLAYER_MONEY")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
end

ns.OnLogin(ns.RefreshBags)
