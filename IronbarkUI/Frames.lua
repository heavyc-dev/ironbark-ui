-------------------------------------------------------------------------------
--  Ironbark UI - small polish on the stock frames
--    * class-colored health (player / target / focus / party)
--    * compact "961 | 100%" health + power text, shown on mouseover / in combat
--    * Blizzard's classic party frames laid out in a centered row
--    * target frame scaled to match the player frame
--    * tooltips follow the mouse (option)
--
--  WoW Forever runs the 12.x engine: unit health/power can be "secret" values
--  in combat. Never do math on them; hand them to AbbreviateNumbers /
--  UnitHealthPercent / SetFormattedText, which accept secrets.
-------------------------------------------------------------------------------
local _, ns = ...

-------------------------------------------------------------------------------
--  Health bar class colors
-------------------------------------------------------------------------------
local WHITE_BAR = "Interface\\TargetingFrame\\UI-StatusBar"

local function ClassColorFor(unit)
    if not unit or not UnitIsPlayer(unit) then return nil end
    local _, class = UnitClass(unit)
    return class and (C_ClassColor and C_ClassColor.GetClassColor(class) or RAID_CLASS_COLORS[class])
end

local function ColorHealthBar(bar, unit)
    if not ns.db.classColors or not bar then return end
    unit = unit or bar.unit
    local tex = bar:GetStatusBarTexture()
    if bar.__ibuiAtlas == nil then
        -- remember Blizzard's art so NPC targets can get it back
        bar.__ibuiAtlas = tex and tex.GetAtlas and tex:GetAtlas() or false
    end
    local c = ClassColorFor(unit)
    if c then
        -- Blizzard's health art is a green atlas; tinting it gives mud
        bar:SetStatusBarTexture(WHITE_BAR)
        bar:SetStatusBarColor(c.r, c.g, c.b)
        bar.__ibuiColored = true
    elseif bar.__ibuiColored then
        bar.__ibuiColored = nil
        if bar.__ibuiAtlas then bar:SetStatusBarTexture(bar.__ibuiAtlas) end
        bar:SetStatusBarColor(1, 1, 1)
    end
end

local function UnitFrames()
    return { PlayerFrame, TargetFrame, FocusFrame }
end

local function RecolorAll()
    for _, f in ipairs(UnitFrames()) do
        if f and f.healthbar then ColorHealthBar(f.healthbar, f.unit) end
    end
end

-------------------------------------------------------------------------------
--  Compact text: "961 | 100%"
-------------------------------------------------------------------------------
local Abbrev = AbbreviateNumbers or function(v) return v end
local SCALE100 = CurveConstants and CurveConstants.ScaleTo100

local function HealthText(fs, unit)
    if UnitHealthPercent and SCALE100 then
        fs:SetFormattedText("%s | %d%%", Abbrev(UnitHealth(unit)), UnitHealthPercent(unit, true, SCALE100))
    else
        local cur, max = UnitHealth(unit), UnitHealthMax(unit)
        fs:SetFormattedText("%s | %d%%", Abbrev(cur), max > 0 and cur / max * 100 or 0)
    end
end

local function PowerText(fs, unit)
    local pType = UnitPowerType(unit)
    if UnitPowerPercent and SCALE100 then
        fs:SetFormattedText("%s | %d%%", Abbrev(UnitPower(unit, pType)),
            UnitPowerPercent(unit, pType, true, SCALE100))
    else
        local cur, max = UnitPower(unit, pType), UnitPowerMax(unit, pType)
        fs:SetFormattedText("%s | %d%%", Abbrev(cur), max > 0 and cur / max * 100 or 0)
    end
end

local function HookText(bar, isHealth)
    if not bar or bar.__ibuiText or not bar.UpdateTextStringWithValues then return end
    bar.__ibuiText = true
    hooksecurefunc(bar, "UpdateTextStringWithValues", function(self, textString)
        if not ns.db.compactText then return end
        local unit = self.unit
        if not unit or not UnitExists(unit) or UnitIsDeadOrGhost(unit) then return end
        local fs = textString or self.TextString
        if not fs or not fs:IsShown() then return end
        if isHealth then HealthText(fs, unit) else PowerText(fs, unit) end
    end)
end

-------------------------------------------------------------------------------
--  Classic party frames in a centered row. Blizzard stacks them vertically
--  inside PartyFrame; after each of its layouts we re-place the shown members
--  side by side, centred on PartyFrame (our layout anchors it by its TOP
--  centre). Members are secure frames, so this only runs out of combat.
-------------------------------------------------------------------------------
local ROW_GAP = 28

local function ClassicPartyMembers()
    local list, pf = {}, PartyFrame
    if pf and pf.PartyMemberFramePool and pf.PartyMemberFramePool.EnumerateActive then
        for f in pf.PartyMemberFramePool:EnumerateActive() do list[#list + 1] = f end
    else
        for i = 1, 4 do
            local f = (pf and pf["MemberFrame" .. i]) or _G["PartyMemberFrame" .. i]
            if f then list[#list + 1] = f end
        end
    end
    table.sort(list, function(a, b)
        return (a.layoutIndex or a:GetID() or 0) < (b.layoutIndex or b:GetID() or 0)
    end)
    return list
end
ns.ClassicPartyMembers = ClassicPartyMembers

local function LayoutPartyRow()
    local pf = PartyFrame
    if not pf then return end
    if InCombatLockdown() then
        ns.RunOutOfCombat("partyRow", LayoutPartyRow)
        return
    end
    local shown = {}
    for _, f in ipairs(ClassicPartyMembers()) do
        if f:IsShown() then shown[#shown + 1] = f end
    end
    if #shown == 0 then return end
    -- tanks first (leftmost): the assigned tank role, or - when nobody has a
    -- role - warriors; otherwise Blizzard's order
    local anyRole = false
    for _, f in ipairs(shown) do
        if f.unit and UnitGroupRolesAssigned and UnitGroupRolesAssigned(f.unit) == "TANK" then anyRole = true end
    end
    local function IsTank(f)
        if not (f.unit and UnitExists(f.unit)) then return false end
        if anyRole then return UnitGroupRolesAssigned(f.unit) == "TANK" end
        return select(2, UnitClass(f.unit)) == "WARRIOR"
    end
    local order = {}
    for i, f in ipairs(shown) do order[f] = (IsTank(f) and 0 or 10) + i end
    table.sort(shown, function(a, b) return order[a] < order[b] end)
    local w = shown[1]:GetWidth()
    local total = #shown * w + (#shown - 1) * ROW_GAP
    -- PartyFrame stacks members vertically, so with a full party it reaches
    -- past the bottom of the screen and is pushed up (kept on screen) - our row
    -- went up with it. So the row uses PartyFrame's own anchor (the spot Edit
    -- Mode gave it, which the push doesn't change) instead of its moved top.
    local point, relTo, relPoint, x, y = pf:GetPoint(1)
    local k = pf:GetEffectiveScale() / shown[1]:GetEffectiveScale()
    local pinned = point == "TOP" and relTo ~= nil
    for i, f in ipairs(shown) do
        f:ClearAllPoints()
        local dx = -total / 2 + (i - 1) * (w + ROW_GAP)
        if pinned then
            f:SetPoint("TOPLEFT", relTo, relPoint, (x or 0) * k + dx, (y or 0) * k)
        else
            f:SetPoint("TOPLEFT", pf, "TOP", dx, 0)
        end
    end
    if ns.PlaceHots then C_Timer.After(0, ns.PlaceHots) end -- HoT icons follow the row
    ns.partyRowInfo = ("pfPoint=%s rel=%s/%s x=%s y=%s k=%.2f pinned=%s pfTop=%s rowTop=%s"):format(
        tostring(point), tostring(relTo and relTo.GetName and relTo:GetName()), tostring(relPoint),
        tostring(x), tostring(y), k, tostring(pinned), tostring(pf:GetTop() and math.floor(pf:GetTop())),
        tostring(shown[1]:GetTop() and math.floor(shown[1]:GetTop())))
end

local function QueueRow() C_Timer.After(0, LayoutPartyRow) end

-------------------------------------------------------------------------------
--  Level badge on each teammate's portrait: a dark circle with a gold rim at
--  the portrait's bottom-left, like your own frame's level circle. The number
--  is colored by difficulty (grey / green / yellow / orange / red vs. you).
--  Plain (non-secure) frames, so it updates in combat too.
-------------------------------------------------------------------------------
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local BADGE = 18

local function LevelBadge(m)
    if m.__ibuiLevel then return m.__ibuiLevel end
    local portrait = m.portrait or m.Portrait or (m.PartyMemberFrameContainer and m.PartyMemberFrameContainer.Portrait)
    local b = CreateFrame("Frame", nil, m)
    b:SetSize(BADGE, BADGE)
    if portrait then
        b:SetPoint("CENTER", portrait, "BOTTOMLEFT", 5, 5)
    else
        b:SetPoint("TOPLEFT", m, "TOPLEFT", 2, -30)
    end
    b:SetFrameLevel(m:GetFrameLevel() + 8)
    b:EnableMouse(false)
    local rim = b:CreateTexture(nil, "BORDER")
    rim:SetTexture(CIRCLE)
    rim:SetAllPoints()
    rim:SetVertexColor(0.72, 0.6, 0.3) -- worn gold, like the frame art
    local bg = b:CreateTexture(nil, "ARTWORK")
    bg:SetTexture(CIRCLE)
    bg:SetPoint("TOPLEFT", 1.5, -1.5)
    bg:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
    bg:SetVertexColor(0.05, 0.05, 0.05, 0.95)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER", 0.5, 0)
    m.__ibuiLevel = b
    return b
end

local function UpdatePartyLevels()
    for _, m in ipairs(ClassicPartyMembers()) do
        local unit = m.unit
        local b = LevelBadge(m)
        if unit and UnitExists(unit) then
            local lvl = UnitLevel(unit)
            if lvl and lvl > 0 then
                b.text:SetText(lvl)
                local c = GetQuestDifficultyColor and GetQuestDifficultyColor(lvl)
                if c then b.text:SetTextColor(c.r, c.g, c.b) else b.text:SetTextColor(1, 0.82, 0) end
            else
                b.text:SetText("??")
                b.text:SetTextColor(1, 0.1, 0.1)
            end
            b:Show()
        else
            b:Hide()
        end
    end
end
ns.UpdatePartyLevels = UpdatePartyLevels

-- No buff list popup when hovering a teammate's frame (Blizzard's
-- PartyMemberBuffTooltip); the normal unit tooltip still shows.
local function NoPartyBuffTooltip()
    local t = _G.PartyMemberBuffTooltip
    if not t or t.__ibuiOff then return end
    t.__ibuiOff = true
    t:HookScript("OnShow", t.Hide)
    t:Hide()
end

local function HookParty()
    NoPartyBuffTooltip()
    local pf = PartyFrame
    if not pf or pf.__ibuiRow then return end
    pf.__ibuiRow = true
    for _, fn in ipairs({ "Layout", "UpdatePartyFrames", "UpdatePartyMemberBackground" }) do
        if type(pf[fn]) == "function" then hooksecurefunc(pf, fn, QueueRow) end
    end
    for _, f in ipairs(ClassicPartyMembers()) do
        f:HookScript("OnShow", QueueRow)
        f:HookScript("OnHide", QueueRow)
        -- same text + combat-text treatment as player/target
        HookText(f.healthbar, true)
        HookText(f.manabar, false)
    end
end

-------------------------------------------------------------------------------
--  Health/power text: mouseover always works (statusText CVar 0); during
--  combat we hold it shown by switching that CVar to 1 and back.
--
--  Not through the bars' ShowStatusBarText(): called from an addon it runs
--  Blizzard's text update as addon code, which may not compare the (secret)
--  health values and errors out, and it leaves the bar's lock counter written
--  by an addon so every later update of that bar fails the same way.
-------------------------------------------------------------------------------
local function TextBars()
    local bars, frames = {}, UnitFrames()
    for _, f in ipairs(ClassicPartyMembers()) do frames[#frames + 1] = f end
    for _, f in ipairs(frames) do
        if f then
            bars[#bars + 1] = f.healthbar
            bars[#bars + 1] = f.manabar
        end
    end
    return bars
end

local combatShown -- nil until the first call, so login always settles it
local function SetCombatText(show)
    show = show and true or false
    if show == combatShown then return end
    combatShown = show
    if show then
        if GetCVar("statusText") == "1" then return end -- already always shown
        ns.db.combatTextHeld = true -- survives a crash mid-fight: undone at next login
        pcall(SetCVar, "statusText", "1")
    else
        if not ns.db.combatTextHeld then return end
        ns.db.combatTextHeld = nil
        pcall(SetCVar, "statusText", "0")
    end
    -- the game re-reads the CVar at the bar's next change; until then show /
    -- hide the text ourselves (plain widget calls, nothing of Blizzard's run)
    for _, bar in ipairs(TextBars()) do
        local fs = bar.TextString
        if fs then
            if show then
                fs:Show()
                local unit = bar.unit
                if ns.db.compactText and unit and UnitExists(unit) and not UnitIsDeadOrGhost(unit) then
                    local f = bar:GetParent()
                    while f and not f.healthbar do f = f:GetParent() end
                    pcall((f and f.healthbar == bar) and HealthText or PowerText, fs, unit)
                end
            elseif not bar:IsMouseOver() then
                fs:Hide()
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Target frame the same size as the player frame (mirrored): scale it so its
--  health bar is exactly as wide on screen as the player's. Out of combat
--  only; re-run after Edit Mode re-applies frame sizes.
-------------------------------------------------------------------------------
local function BarScreenWidth(frame)
    local hb = frame and frame.healthbar
    if not (hb and hb:GetWidth()) then return nil end
    return hb:GetWidth() * hb:GetEffectiveScale()
end

local function MatchTargetSize()
    local p, t = PlayerFrame, TargetFrame
    if not (p and t) then return end
    if InCombatLockdown() then
        ns.RunOutOfCombat("targetSize", MatchTargetSize)
        return
    end
    local pw, tw = BarScreenWidth(p), BarScreenWidth(t)
    if not (pw and tw) or pw <= 0 or tw <= 0 then return end
    local ratio = pw / tw
    if math.abs(ratio - 1) < 0.005 then return end
    t:SetScale(t:GetScale() * ratio)
end

local function HookTargetSize()
    local t = TargetFrame
    if not t or t.__ibuiSize then return end
    t.__ibuiSize = true
    local function Queue() C_Timer.After(0, MatchTargetSize) end
    for _, fn in ipairs({ "UpdateSystemSettingFrameSize", "ApplySystemAnchor" }) do
        if type(t[fn]) == "function" then hooksecurefunc(t, fn, Queue) end
    end
    if PlayerFrame and type(PlayerFrame.UpdateSystemSettingFrameSize) == "function" then
        hooksecurefunc(PlayerFrame, "UpdateSystemSettingFrameSize", Queue)
    end
end

-------------------------------------------------------------------------------
--  Fewer tooltips in combat (hold Alt to see one anyway): only the ones that
--  get in the way of playing, i.e. friendly units (players, pets, NPCs, their
--  unit frames) and action buttons. Enemies, items, loot, buffs and debuffs,
--  minimap pins and interface buttons keep theirs.
-------------------------------------------------------------------------------
local function OwnerUnit(owner)
    if not owner then return end
    if type(owner.unit) == "string" then return owner.unit end
    if owner.GetAttribute then
        local u = owner:GetAttribute("unit")
        if type(u) == "string" then return u end
    end
end

local function IsActionButton(owner)
    if not owner or owner == UIParent then return false end
    if owner.action ~= nil then return true end -- action bars 1-8
    local name = owner.GetName and owner:GetName()
    return type(name) == "string"
        and (name:find("^PetActionButton") or name:find("^StanceButton")) and true or false
end

-- true for a tooltip this option hides. Anything unreadable (the client keeps
-- some combat data secret) counts as "leave it alone".
local function Unwanted(tip)
    local owner = tip:GetOwner()
    if IsActionButton(owner) then return true end
    local isUnit
    if tip.GetTooltipData and Enum and Enum.TooltipDataType then
        local data = tip:GetTooltipData()
        isUnit = data and data.type == Enum.TooltipDataType.Unit
    elseif tip.GetUnit then
        isUnit = select(2, tip:GetUnit()) ~= nil
    end
    if not isUnit then return false end
    -- the world unit under the cursor, else the unit frame the tooltip belongs to
    local unit = (owner == nil or owner == UIParent) and UnitExists("mouseover") and "mouseover"
        or OwnerUnit(owner) or (UnitExists("mouseover") and "mouseover")
    if not unit then return false end
    return UnitIsFriend("player", unit) and true or false
end

local function HideInCombat(tip)
    if tip ~= GameTooltip then return end
    if not (ns.db and ns.db.tooltipCombatHide and InCombatLockdown()) or IsAltKeyDown() then return end
    local ok, unwanted = pcall(Unwanted, tip)
    if ok and unwanted then tip:Hide() end
end

GameTooltip:HookScript("OnShow", HideInCombat)
-- a shown tooltip can change what it describes without re-showing
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and TooltipDataProcessor.AllTypes then
    TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, HideInCombat)
end
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    -- lockdown starts just after this event: hide whatever is up a frame later
    f:SetScript("OnEvent", function()
        C_Timer.After(0, function() HideInCombat(GameTooltip) end)
    end)
end

-------------------------------------------------------------------------------
--  Tooltips that use Blizzard's default anchor (units in the world, most
--  buttons): beside the cursor, or - with that option off - in the bottom-right
--  corner but above the meters when they're up.
-------------------------------------------------------------------------------
hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
    if not ns.db then return end
    if ns.db.tooltipCursor then
        -- down-right of the pointer so it never covers what you're pointing at
        tooltip:SetOwner(parent, "ANCHOR_CURSOR_RIGHT", 24, -24)
    else
        local meters = _G.IronbarkMeters
        if meters and meters:IsShown() then
            tooltip:ClearAllPoints()
            tooltip:SetPoint("BOTTOMRIGHT", meters, "TOPRIGHT", 0, 8)
        end
    end
end)

-------------------------------------------------------------------------------
--  Wiring
-------------------------------------------------------------------------------
local ev = CreateFrame("Frame")

ns.OnLogin(function()
    for _, f in ipairs(UnitFrames()) do
        if f then
            HookText(f.healthbar, true)
            HookText(f.manabar, false)
        end
    end
    if UnitFrameHealthBar_Update then
        hooksecurefunc("UnitFrameHealthBar_Update", function(bar, unit) ColorHealthBar(bar, unit) end)
    end
    HookParty()
    HookTargetSize()
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
        "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "EDIT_MODE_LAYOUTS_UPDATED",
        "UNIT_LEVEL", "PLAYER_LEVEL_UP" }) do
        pcall(ev.RegisterEvent, ev, e) -- PLAYER_ROLES_ASSIGNED may not exist
    end
end)

ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        SetCombatText(true)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then SetCombatText(false) end
    if event ~= "GROUP_ROSTER_UPDATE" and event ~= "PLAYER_ROLES_ASSIGNED" then RecolorAll() end
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" or event == "PLAYER_ENTERING_WORLD"
        or event == "EDIT_MODE_LAYOUTS_UPDATED" or event == "PLAYER_REGEN_ENABLED" then
        HookParty()
        QueueRow()
    end
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event == "UNIT_LEVEL"
        or event == "PLAYER_LEVEL_UP" then
        C_Timer.After(0, function() pcall(UpdatePartyLevels) end)
    end
    if event == "PLAYER_ENTERING_WORLD" or event == "EDIT_MODE_LAYOUTS_UPDATED" then
        C_Timer.After(0, MatchTargetSize)
    end
end)

-- options call this to re-run without a reload
function ns.RefreshFrames()
    RecolorAll()
    QueueRow()
    SetCombatText(InCombatLockdown())
end

-------------------------------------------------------------------------------
--  /ibui debug: a few facts, also saved to IronbarkUIDB.debug (readable from
--  SavedVariables after a /reload)
-------------------------------------------------------------------------------
function ns.Debug()
    local out = {}
    local function add(fmt, ...) out[#out + 1] = string.format(fmt, ...) end
    local info = ns.LayoutsForSave and ns.LayoutsForSave()
    local active = info and info.layouts[info.activeLayout]
    add("layout=%s inGroup=%s inRaid=%s combat=%s", tostring(active and active.layoutName),
        tostring(IsInGroup()), tostring(IsInRaid()), tostring(InCombatLockdown()))
    add("party members=%d", #ClassicPartyMembers())
    add("party row: %s", tostring(ns.partyRowInfo))
    add("frames: playerBar=%s targetBar=%s targetScale=%s", tostring(BarScreenWidth(PlayerFrame)),
        tostring(BarScreenWidth(TargetFrame)), tostring(TargetFrame and TargetFrame:GetScale()))
    if ns.BarGaps then add("%s", ns.BarGaps()) end
    if ns.BagStats then add("%s", ns.BagStats()) end
    if ns.ThemeStats then add("%s", ns.ThemeStats()) end
    if ns.CastGhostStats then add("%s", ns.CastGhostStats()) end
    if ns.BuffStats then add("%s", ns.BuffStats()) end
    for _, line in ipairs(out) do print("|cff8fbc5aIBUI|r " .. line) end
    ns.db.debug = out
    ns.Print("Debug saved. /reload so it can be read from SavedVariables.")
end
