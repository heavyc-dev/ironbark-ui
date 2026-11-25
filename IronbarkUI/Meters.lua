-------------------------------------------------------------------------------
--  Ironbark UI - simple damage + healing meters
--
--  Two small windows (Damage, Healing) at the bottom-right, drawn from
--  Blizzard's own combat data (C_DamageMeter): everything since the last reset, top 5,
--  class-colored bars, name, total and per second; you are highlighted.
--
--  Shown: always inside dungeons / raids; elsewhere only during combat (and a
--  few seconds after). Never in town or while questing out of combat.
--  Shift-click a title to reset.
--
--  In combat some values are hidden ("secret") from addons. They are passed
--  straight to bars and text (which accept them) - no math on them, and they
--  are never used to look anything up.
-------------------------------------------------------------------------------
local _, ns = ...

-- WoW Forever's own HUD frame art: the bronze-lined box drawn round the micro
-- menu ("UI-HUD-ActionBar-Frame", a 55-unit square with a dark body). It is
-- cut into nine pieces (corners keep their size, edges and body stretch), so
-- the windows wear the same line as the HUD. Clients without that art get the
-- classic dialog backdrop and header plate instead.
local SLIM_ATLAS = "UI-HUD-ActionBar-Frame"
local SLIM = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(SLIM_ATLAS) or nil
local WIDTH, ROW_H, ROWS = 260, 18, 5
local PAD = SLIM and 7 or 12            -- border thickness the rows sit inside
local TITLE_H = SLIM and 18 or 14       -- title line (slim) / room under the header plate
local GAP = SLIM and 6 or 22            -- between windows (the plate pokes above its border)
local WIN_H = PAD + TITLE_H + ROWS * (ROW_H + 1) + PAD
local BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 24,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
}
local LINGER = 5 -- seconds the meters stay after combat (outside instances)
local isSecret = issecretvalue or function() return false end
local Abbrev = AbbreviateNumbers or function(v) return v end

local windows, container, ticker = {}, nil, nil
local lingerUntil = 0

-- bars: the same plain bar texture as the class-colored unit frame health
local PLAIN_BAR = "Interface\\TargetingFrame\\UI-StatusBar"
local CLASS_SHEET = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local IDLE_ALPHA = 0.5 -- in a dungeon between pulls, unless hovered
local SMOOTH = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut

-- which numbers: everything since the last reset, or just this fight
local function SessionType()
    if ns.db.meterSession == "current" then return Enum.DamageMeterSessionType.Current end
    return Enum.DamageMeterSessionType.Overall
end

-- thin outline on the game's own font, so names read over bright bars
local function Outlined(fs)
    local font, size = fs:GetFont()
    if font then fs:SetFont(font, size, "OUTLINE") end
    fs:SetShadowOffset(0, 0)
end

local function InInstance()
    local inside, kind = IsInInstance()
    return inside and (kind == "party" or kind == "raid")
end

-- Combat as the events tell it: when PLAYER_REGEN_DISABLED arrives the
-- lockdown hasn't started yet, so asking InCombatLockdown() right then says
-- "no" and the meters stayed hidden for the whole fight.
local fighting = false
local function InCombat() return fighting or InCombatLockdown() end

local function ShouldShow()
    if ns.meterTest then return true end
    if not ns.db.meters then return false end
    return InInstance() or InCombat() or GetTime() < lingerUntil
end

-------------------------------------------------------------------------------
--  Windows
-------------------------------------------------------------------------------
local function Row(w, i)
    local r = w.rows[i]
    if r then return r end
    r = CreateFrame("StatusBar", nil, w)
    r:SetHeight(ROW_H)
    local y = -(PAD + TITLE_H + (i - 1) * (ROW_H + 1))
    r:SetPoint("TOPLEFT", w, "TOPLEFT", PAD, y)
    r:SetPoint("TOPRIGHT", w, "TOPRIGHT", -PAD, y)
    -- same bar as the class-colored player / target health bars
    r:SetStatusBarTexture(PLAIN_BAR)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(0, 0, 0, 0.4)
    -- class icon at the row's start
    r.icon = r:CreateTexture(nil, "OVERLAY")
    r.icon:SetSize(ROW_H - 2, ROW_H - 2)
    r.icon:SetPoint("LEFT", 1, 0)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWidth((WIDTH - 2 * PAD) * 0.5 - ROW_H)
    r.name:SetWordWrap(false)
    Outlined(r.name)
    r.value = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.value:SetPoint("RIGHT", -4, 0)
    r.value:SetJustifyH("RIGHT")
    Outlined(r.value)
    w.rows[i] = r
    return r
end

local function Window(key, label, meterType)
    local w = CreateFrame("Frame", nil, container, "BackdropTemplate")
    w:SetSize(WIDTH, WIN_H)
    w.meterType = meterType
    w.rows = {}
    local header
    if SLIM then
        -- nine pieces of the HUD box: corners at the art's size (12 of its 55
        -- units hold the chamfer), edges and the dark body stretched between
        local C, S = 12, 55
        local L, T = SLIM.leftTexCoord, SLIM.topTexCoord
        local W, H = SLIM.rightTexCoord - L, SLIM.bottomTexCoord - T
        local c = C / S
        local cols = { { 0, c }, { c, 1 - c }, { 1 - c, 1 } }
        local file = SLIM.file or SLIM.filename
        for row = 1, 3 do
            for col = 1, 3 do
                local t = w:CreateTexture(nil, "BACKGROUND")
                t:SetTexture(file)
                local u, v = cols[col], cols[row]
                t:SetTexCoord(L + W * u[1], L + W * u[2], T + H * v[1], T + H * v[2])
                -- each piece by its top-left and bottom-right corners: x from
                -- the window's left or right edge, y from its top or bottom
                local xL = ({ { "LEFT", 0 }, { "LEFT", C }, { "RIGHT", -C } })[col]
                local xR = ({ { "LEFT", C }, { "RIGHT", -C }, { "RIGHT", 0 } })[col]
                local yT = ({ { "TOP", 0 }, { "TOP", -C }, { "BOTTOM", C } })[row]
                local yB = ({ { "TOP", -C }, { "BOTTOM", C }, { "BOTTOM", 0 } })[row]
                t:SetPoint("TOPLEFT", w, yT[1] .. xL[1], xL[2], yT[2])
                t:SetPoint("BOTTOMRIGHT", w, yB[1] .. xR[1], xR[2], yB[2])
            end
        end
        -- gold title on the top line, like Forever's window titles
        w.title = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        w.title:SetPoint("TOPLEFT", PAD + 3, -PAD - 2)
        w.title:SetText(label)
        header = w.title
    else
        w:SetBackdrop(BACKDROP)
        header = w:CreateTexture(nil, "ARTWORK")
        header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
        header:SetSize(180, 45)
        header:SetPoint("TOP", 0, 10)
        w.title = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        w.title:SetPoint("TOP", header, "TOP", 0, -10)
        w.title:SetText(label)
    end
    w.time = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    w.time:SetPoint("TOPRIGHT", -PAD - 3, -PAD - (SLIM and 3 or 0))
    w.empty = w:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    w.empty:SetPoint("TOPLEFT", PAD + 4, -(PAD + TITLE_H + 3))
    w.empty:SetText("No fight yet")
    -- Shift-click the header to reset; the rest of the window lets clicks through
    local hit = CreateFrame("Button", nil, w)
    if SLIM then
        -- the whole title line
        hit:SetPoint("TOPLEFT", w, "TOPLEFT", PAD, -PAD)
        hit:SetPoint("TOPRIGHT", w, "TOPRIGHT", -PAD, -PAD)
        hit:SetHeight(TITLE_H)
    else
        hit:SetPoint("TOPLEFT", header, "TOPLEFT", 30, -2)
        hit:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -30, 20)
    end
    hit:SetFrameLevel(w:GetFrameLevel() + 10)
    hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    hit:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            -- both meters switch together: this fight <-> since the last reset
            ns.db.meterSession = (ns.db.meterSession == "current") and "overall" or "current"
            if ns.RefreshMeters then ns.RefreshMeters() end
        elseif IsShiftKeyDown() and C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
            C_DamageMeter.ResetAllCombatSessions()
            ns.Print("Meters reset.")
            if ns.RefreshMeters then ns.RefreshMeters() end
        end
    end)
    hit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(label)
        GameTooltip:AddLine(ns.db.meterSession == "current" and "This fight only." or "Totals since the last reset.", 1, 1, 1)
        GameTooltip:AddLine("Right-click: this fight / since the last reset.", 0.4, 1, 0.4)
        GameTooltip:AddLine("Shift-click: reset both meters.", 0.4, 1, 0.4)
        GameTooltip:Show()
    end)
    hit:SetScript("OnLeave", GameTooltip_Hide)
    w.label = label
    windows[key] = w
    return w
end

local function ClassColor(classFile)
    if not classFile or isSecret(classFile) then return 0.6, 0.6, 0.6 end
    local c = (C_ClassColor and C_ClassColor.GetClassColor(classFile)) or RAID_CLASS_COLORS[classFile]
    if c then return c.r, c.g, c.b end
    return 0.6, 0.6, 0.6
end

local function ShortName(name)
    if not name or isSecret(name) then return name end
    return (Ambiguate and Ambiguate(name, "short")) or name
end

-- /ibui meters test: made-up group shown when there's no real fight data
local function Sample(rows)
    local out = {}
    for i, r in ipairs(rows) do
        out[i] = { name = r[1], classFilename = r[2], totalAmount = r[3], amountPerSecond = math.floor(r[3] / 83),
            isLocalPlayer = r[1] == "You" }
    end
    return out
end
local SAMPLE = {}
local function BuildSamples()
    if not Enum.DamageMeterType then return end
    SAMPLE[Enum.DamageMeterType.DamageDone] = Sample({
        { "Thrakk", "WARRIOR", 48200 }, { "You", "DRUID", 41750 }, { "Velenna", "MAGE", 39900 },
        { "Shadowsong", "HUNTER", 31200 }, { "Mirel", "PRIEST", 6400 } })
    SAMPLE[Enum.DamageMeterType.HealingDone] = Sample({
        { "Mirel", "PRIEST", 52300 }, { "You", "DRUID", 9800 }, { "Thrakk", "WARRIOR", 2100 } })
end

function ns.ToggleMeterTest()
    ns.meterTest = not ns.meterTest
    if ns.meterTest then BuildSamples() end
    if ns.RefreshMeters then ns.RefreshMeters() end
    ns.Print(ns.meterTest and "Meters: test mode ON (always shown, sample data until a real fight). /ibui meters test again to stop."
        or "Meters: test mode off.")
end

-- a value or a fallback, without ever testing a secret one
local function Val(v, fallback)
    if isSecret(v) then return v end
    if v == nil then return fallback end
    return v
end

local function SetIcon(tex, classFile)
    if not classFile or isSecret(classFile) then tex:Hide() return end
    local atlas = "classicon-" .. classFile:lower()
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        tex:SetAtlas(atlas)
    elseif CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile] then
        tex:SetTexture(CLASS_SHEET)
        tex:SetTexCoord(unpack(CLASS_ICON_TCOORDS[classFile]))
    else
        tex:Hide()
        return
    end
    tex:Show()
end

-- slide to the new value where the client can; secret values included
local function SetBar(r, value)
    if SMOOTH and pcall(r.SetValue, r, value, SMOOTH) then return end
    r:SetValue(value)
end

local function FillWindow(w)
    local sessionType = SessionType()
    local session = C_DamageMeter and C_DamageMeter.GetCombatSessionFromType
        and C_DamageMeter.GetCombatSessionFromType(sessionType, w.meterType)
    local sources = session and session.combatSources or {}
    if ns.meterTest and not sources[1] then
        sources = SAMPLE[w.meterType] or {}
        session = { durationSeconds = 83 }
    end
    w.title:SetText(ns.db.meterSession == "current" and (w.label .. " |cff999999- this fight|r") or w.label)
    -- the rows: top 5, but you always get the last one if you're further down
    local order = {}
    for i = 1, ROWS do order[i] = i end
    local mineAt
    for i = 1, #sources do
        local m = sources[i].isLocalPlayer
        if not isSecret(m) and m == true then
            mineAt = i
            break
        end
    end
    if mineAt and mineAt > ROWS then order[ROWS] = mineAt end
    local top = sources[1] and Val(sources[1].totalAmount, 1)
    local shown = 0
    for slot = 1, ROWS do
        local idx = order[slot]
        local src = sources[idx]
        local r = Row(w, slot)
        if src then
            shown = shown + 1
            local total = Val(src.totalAmount, 0)
            r:SetMinMaxValues(0, top or 1)
            SetBar(r, total)
            r:SetStatusBarColor(ClassColor(src.classFilename))
            SetIcon(r.icon, src.classFilename)
            r.name:SetFormattedText("%d. %s", idx, ShortName(src.name) or "?")
            if idx == mineAt then
                r.name:SetTextColor(1, 0.82, 0)
            else
                r.name:SetTextColor(1, 1, 1)
            end
            -- whole numbers only: per-second values are fractions. Secret ones
            -- can't be rounded in Lua, so the format string does it.
            if not isSecret(total) then total = math.floor(total + 0.5) end
            local dps = src.amountPerSecond
            if isSecret(dps) then
                r.value:SetFormattedText("%s (%.0f)", Abbrev(total), dps)
            elseif dps ~= nil then
                r.value:SetFormattedText("%s (%s)", Abbrev(total), Abbrev(math.floor(dps + 0.5)))
            else
                r.value:SetText(Abbrev(total))
            end
            r:Show()
        else
            r:Hide()
        end
    end
    w.empty:SetShown(shown == 0)
    -- timer for the numbers shown
    local dur = session and session.durationSeconds
    if not isSecret(dur) and dur == nil and C_DamageMeter and C_DamageMeter.GetSessionDurationSeconds then
        local ok, d = pcall(C_DamageMeter.GetSessionDurationSeconds, sessionType)
        if ok then dur = d end
    end
    if dur and not isSecret(dur) then
        w.time:SetFormattedText("%d:%02d", math.floor(dur / 60), math.floor(dur % 60))
    else
        w.time:SetText("")
    end
end

local function Update()
    if not container then return end
    local show = ShouldShow()
    container:SetShown(show)
    if not show then
        if ticker then ticker:Cancel() ticker = nil end
        return
    end
    for _, w in pairs(windows) do pcall(FillWindow, w) end
    -- idle in a dungeon (between pulls): half visible unless hovered
    local idle = not InCombat() and not ns.meterTest and not container:IsMouseOver()
    container:SetAlpha(idle and IDLE_ALPHA or 1)
    -- refresh while visible; stops itself when hidden
    if not ticker then ticker = C_Timer.NewTicker(0.25, Update) end
end
ns.RefreshMeters = Update

local function Build()
    if container or not (C_DamageMeter and Enum.DamageMeterType) then return end
    container = CreateFrame("Frame", "IronbarkMeters", UIParent)
    container:SetSize(WIDTH, 2 * WIN_H + GAP)
    container:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -8, 8)
    container:SetFrameStrata("LOW")
    local heal = Window("heal", "Healing", Enum.DamageMeterType.HealingDone)
    local dmg = Window("damage", "Damage", Enum.DamageMeterType.DamageDone)
    heal:SetPoint("TOPLEFT", container, "TOPLEFT")
    dmg:SetPoint("TOPLEFT", heal, "BOTTOMLEFT", 0, -GAP)
    container:Hide()
end

-- Blizzard's own meter window would double up with ours: switch it off while
-- ours are on (original recorded for "Revert everything").
local function BlizzardMeterOff()
    if not (container and ns.db.meters) or GetCVar("damageMeterEnabled") == nil then return end
    local r = ns.db.revert
    if r and r.cvars and r.cvars.damageMeterEnabled == nil then r.cvars.damageMeterEnabled = GetCVar("damageMeterEnabled") end
    if GetCVar("damageMeterEnabled") ~= "0" and not InCombatLockdown() then SetCVar("damageMeterEnabled", "0") end
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then fighting = true end
    if event == "PLAYER_REGEN_ENABLED" then
        fighting = false
        lingerUntil = GetTime() + LINGER
    end
    Update()
    if event == "PLAYER_REGEN_ENABLED" then C_Timer.After(LINGER + 0.1, Update) end
end)

ns.OnLogin(function()
    Build()
    if not container then return end
    BlizzardMeterOff()
    for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
        "ZONE_CHANGED_NEW_AREA" }) do
        ev:RegisterEvent(e)
    end
    Update()
end)
