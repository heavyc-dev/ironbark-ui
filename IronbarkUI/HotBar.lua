-------------------------------------------------------------------------------
--  Ironbark UI - your HoTs on health bars
--  A lighter green stretch past the end of someone's health: the healing your
--  heal-over-time spells still have to give them, stopping at full.
--
--  In combat this client hides auras and health numbers from addons, so none
--  of this reads them. It works from your own casts instead: who you cast the
--  HoT on, how much that rank heals over how long (from the spell's own
--  description), and the clock. The stretch is a status bar pinned to the end
--  of the health fill and measured against max health by the game itself, so
--  no hidden number is ever used in a calculation. Out of combat, a HoT that
--  is gone early (dispelled, clicked off) is noticed and dropped.
-------------------------------------------------------------------------------
local _, ns = ...

local isSecret = issecretvalue or function() return false end
local _, CLASS = UnitClass("player")

local HOTS = {
    DRUID  = { 774, 8936 }, -- Rejuvenation, Regrowth (rank 1: only for their names)
    PRIEST = { 139 },       -- Renew
}
local TICK = 3 -- seconds between ticks

local hotNames = {}   -- spell name -> true
local sentTo = {}     -- spell name -> who the cast in flight is aimed at
local active = {}     -- target name -> { [spell name] = { total, dur, start } }
local overlays = {}   -- [health bar] = status bar
local ticker

-- support notes, kept in the saved settings (last 30 lines): what each HoT
-- cast was understood as, and what got drawn for it on your own frame
local function Log(fmt, ...)
    local ok, line = pcall(string.format, fmt, ...)
    if not ok then return end
    local log = ns.db.hotLog
    if type(log) ~= "table" then
        log = {}
        ns.db.hotLog = log
    end
    log[#log + 1] = ("%.1f %s"):format(GetTime(), line)
    while #log > 30 do table.remove(log, 1) end
end

local function N(v)
    if v == nil or isSecret(v) then return tostring(v ~= nil and "hidden" or nil) end
    return tostring(math.floor(v))
end

local function Snapshot()
    local hb = PlayerFrame and (PlayerFrame.healthbar or PlayerFrame.healthBar)
    local bar = hb and overlays[hb]
    local fill = hb and hb.GetStatusBarTexture and hb:GetStatusBarTexture()
    local names = {}
    for who, list in pairs(active) do
        for spell, a in pairs(list) do names[#names + 1] = who .. ":" .. spell .. "=" .. a.total .. "/" .. a.dur end
    end
    Log("draw: on=%s me=%s hb=%s fill=%s hbW=%s fillW=%s overlay=%s shown=%s visible=%s barW=%s active=[%s]",
        tostring(ns.db.hotBars), tostring((UnitName("player"))), tostring(hb ~= nil), tostring(fill ~= nil),
        N(hb and hb:GetWidth()), N(fill and fill:GetWidth()),
        tostring(bar ~= nil), tostring(bar and bar:IsShown()), tostring(bar and bar:IsVisible()),
        N(bar and bar:GetWidth()), table.concat(names, ", "))
end

-- "…for 32 over 12 sec." / "…and another 98 over 21 sec." / "…of 45 damage over 15 sec."
local function Parse(spellID)
    local desc = C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(spellID)
    if type(desc) ~= "string" or isSecret(desc) then return end
    local total, dur = desc:match("(%d[%d,]*)[%a ]- over (%d+) sec")
    total = total and tonumber((total:gsub(",", "")))
    dur = tonumber(dur)
    if total and dur and dur > 0 then return total, dur end
end

local function Name(unit)
    local ok, name = pcall(UnitName, unit)
    if ok and name and not isSecret(name) then return name end
end

-- Which entry of `active` is this unit? A cast names its target the way the
-- game displays it, which isn't always what UnitName gives (this client has
-- "First Last" names; elsewhere a realm gets tacked on). So: an exact match on
-- any spelling the game has for the unit, else an entry that starts with the
-- unit's name followed by a space or a dash.
local function Key(unit)
    local ok, name, realm = pcall(UnitName, unit)
    if not ok or not name or isSecret(name) then return nil end
    if active[name] then return name end
    local spellings = {}
    if realm and not isSecret(realm) and realm ~= "" then
        spellings[#spellings + 1] = name .. "-" .. realm
        spellings[#spellings + 1] = name .. " " .. realm
    end
    for _, full in ipairs({ true, false }) do
        local ok2, n = pcall(GetUnitName, unit, full)
        if ok2 and n and not isSecret(n) then spellings[#spellings + 1] = n end
    end
    for _, s in ipairs(spellings) do
        if active[s] then return s end
    end
    for key in pairs(active) do
        local nextChar = key:sub(#name + 1, #name + 1)
        if key:sub(1, #name) == name and (nextChar == " " or nextChar == "-") then return key end
    end
end

-- healing still to come from your HoTs on this unit (0 = none)
local function Remaining(unit)
    local name = Key(unit)
    local list = name and active[name]
    if not list then return 0 end
    local now, sum = GetTime(), 0
    local readable = not InCombatLockdown() and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
    for spell, a in pairs(list) do
        local left = a.start + a.dur - now
        local gone = left <= 0
        -- out of combat the aura itself can be checked (a moment after the cast)
        if not gone and readable and now - a.start > 1 then
            local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, spell, "HELPFUL|PLAYER")
            if ok and not aura then gone = true end
        end
        if gone then
            list[spell] = nil
        else
            local ticks = a.dur / TICK
            sum = sum + a.total * math.min(ticks, math.ceil(left / TICK)) / ticks
        end
    end
    if not next(list) then active[name] = nil end
    return sum
end

local function Overlay(hb)
    local bar = overlays[hb]
    if bar then return bar end
    local fill = hb.GetStatusBarTexture and hb:GetStatusBarTexture()
    if not fill then return nil end
    -- a window the size of the health bar: whatever pokes past full is cut off
    local clip = CreateFrame("Frame", nil, hb)
    clip:SetAllPoints(hb)
    clip:SetClipsChildren(true)
    clip:SetFrameLevel(hb:GetFrameLevel() + 1)
    clip:EnableMouse(false)
    bar = CreateFrame("StatusBar", nil, clip)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.45, 1, 0.6, 0.6)
    bar:SetPoint("TOPLEFT", fill, "TOPRIGHT")
    bar:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT")
    bar:EnableMouse(false)
    bar:Hide()
    overlays[hb] = bar
    return bar
end

local function Bars()
    local list = {}
    local function add(f, hb)
        local unit = f and (f.unit or (f.GetAttribute and f:GetAttribute("unit")))
        hb = hb or (f and (f.healthbar or f.healthBar))
        if unit and hb then list[#list + 1] = { hb = hb, unit = unit } end
    end
    add(PlayerFrame)
    add(TargetFrame)
    for _, f in ipairs(ns.ClassicPartyMembers and ns.ClassicPartyMembers() or {}) do add(f) end
    for i = 1, 5 do add(_G["CompactPartyFrameMember" .. i]) end
    if IsInRaid() then
        for g = 1, 8 do
            for m = 1, 5 do add(_G["CompactRaidGroup" .. g .. "Member" .. m]) end
        end
        for i = 1, 40 do add(_G["CompactRaidFrame" .. i]) end
    end
    return list
end

local function Draw()
    local any = next(active) ~= nil
    for _, b in ipairs(Bars()) do
        local heal = 0
        if any and ns.db.hotBars and b.hb:IsVisible() and UnitExists(b.unit) then
            heal = Remaining(b.unit)
        end
        local bar = overlays[b.hb]
        if heal > 0 then
            bar = bar or Overlay(b.hb)
            if bar then
                bar:SetWidth(math.max(1, b.hb:GetWidth()))
                bar:SetMinMaxValues(0, UnitHealthMax(b.unit)) -- may be hidden: the game does the division
                bar:SetValue(heal)
                bar:Show()
            end
        elseif bar then
            bar:Hide()
        end
    end
    if not next(active) and ticker then
        ticker:Cancel()
        ticker = nil
        for _, bar in pairs(overlays) do bar:Hide() end
    end
end

local lastError
local function SafeDraw()
    local ok, err = pcall(Draw)
    if not ok and err ~= lastError then
        lastError = err
        Log("draw error: %s", tostring(err))
    end
end

local function Start()
    SafeDraw()
    if not ticker and next(active) then ticker = C_Timer.NewTicker(0.25, SafeDraw) end
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, unit, a2, a3, a4)
    if event == "PLAYER_TARGET_CHANGED" or event == "GROUP_ROSTER_UPDATE" then
        if next(active) then SafeDraw() end
        return
    end
    if unit ~= "player" then return end
    if event == "UNIT_SPELLCAST_SENT" then
        -- unit, target name, cast id, spell id
        if isSecret(a4) or not a4 then return end
        local spell = C_Spell.GetSpellName(a4)
        if spell and hotNames[spell] then
            local target = a2
            if isSecret(target) or not target or target == "" then target = Name("player") end
            sentTo[spell] = target
            Log("sent: %s (%s) at %s", spell, tostring(a4), tostring(target))
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- unit, cast id, spell id
        if isSecret(a3) or not a3 then return end
        local spell = C_Spell.GetSpellName(a3)
        local target = spell and sentTo[spell]
        if not target then return end
        sentTo[spell] = nil
        local total, dur = Parse(a3)
        local desc = C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(a3)
        Log("cast: %s (%s) at %s -> %s over %s | %s", spell, tostring(a3), tostring(target),
            tostring(total), tostring(dur), isSecret(desc) and "secret" or tostring(desc):sub(1, 110))
        C_Timer.After(0.6, function() pcall(Snapshot) end)
        if not total then return end
        active[target] = active[target] or {}
        active[target][spell] = { total = total, dur = dur, start = GetTime() }
        if ns.db.hotBars then Start() end
    end
end)

function ns.RefreshHotBars()
    if next(active) then Start() end
end

ns.OnLogin(function()
    if not HOTS[CLASS] then return end
    for _, id in ipairs(HOTS[CLASS]) do
        local name = C_Spell.GetSpellName(id)
        if name then
            hotNames[name] = true
            -- have the description of the rank you use on hand before the first cast
            local info = C_Spell.GetSpellInfo(name)
            if info and info.spellID and C_Spell.RequestLoadSpellData then
                C_Spell.RequestLoadSpellData(info.spellID)
            end
        end
    end
    for _, e in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED",
        "PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
end)
