-------------------------------------------------------------------------------
--  Ironbark UI - nature colors
--
--    * cast bar: Blizzard's green channel fill, colored by spell type:
--      heals green, channels blue, damage orange, utility gold
--    * mana regen spark: moonlight blue (ManaRegen.lua reads ns.MOONLIGHT)
--    * XP bar: your class color on Blizzard's own XP texture
--
--  Failed, interrupted and uninterruptible casts keep Blizzard's colors so
--  those signals still read. Only status bar textures/colors change.
-------------------------------------------------------------------------------
local _, ns = ...

ns.MOONLIGHT = { 0.72, 0.84, 1.00 }

-- Every cast uses Blizzard's own green channel fill. Heals keep it as is;
-- other spell types use the SAME texture desaturated to grey and tinted, so
-- the detail stays identical and only the color changes. Fallback if the
-- atlas is missing: a plain bar tinted the same colors.
local GREEN_FILL = "ui-castingbar-filling-channel"
local FALLBACK_BAR = "Interface\\TargetingFrame\\UI-StatusBar"

local CAST_COLORS = {
    heal    = nil,                   -- untouched Blizzard green
    channel = { 0.35, 0.62, 1.00 },  -- blue
    damage  = { 1.00, 0.50, 0.15 },  -- orange
    utility = { 1.00, 0.82, 0.35 },  -- soft gold (hearthstone, crafting, mounts)
}
local FALLBACK_HEAL = { 0.36, 0.72, 0.30 }

local function HasGreenFill()
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(GREEN_FILL) ~= nil
end

local isSecret = issecretvalue or function() return false end

local function Helpful(spellID)
    if C_Spell and C_Spell.IsSpellHelpful then return C_Spell.IsSpellHelpful(spellID) end
    if IsHelpfulSpell then return IsHelpfulSpell(C_Spell.GetSpellName(spellID)) end
end

local function Harmful(spellID)
    if C_Spell and C_Spell.IsSpellHarmful then return C_Spell.IsSpellHarmful(spellID) end
    if IsHarmfulSpell then return IsHarmfulSpell(C_Spell.GetSpellName(spellID)) end
end

-- What the last cast looked like, for /ibui debug.
local lastCast = {}

-- When the spell's own flags can't be read (spell ID hidden in combat, or
-- the lookup gives nothing), go by what you're targeting.
-- No usable flag: casting at something hostile is damage; anything else
-- (hearthstone, mounts, opening things...) is utility, never "heal".
local function KindFromTarget()
    if UnitExists("target") and UnitCanAttack("player", "target") then return "damage" end
    return "utility"
end

-- channel beats everything; then the spell's helpful/harmful flag; then target
local function CastKind(bar, channel)
    wipe(lastCast)
    lastCast.barType = tostring(bar.barType)
    if channel then lastCast.kind = "channel" return "channel" end
    local unit = bar.unit or "player"
    local _, _, _, _, _, isTradeSkill, _, _, spellID = UnitCastingInfo(unit)
    local secret = spellID ~= nil and isSecret(spellID)
    lastCast.spellID = secret and "secret" or tostring(spellID)
    -- crafting is always utility
    if isTradeSkill and not isSecret(isTradeSkill) then lastCast.kind = "utility" return "utility" end
    local kind
    if spellID and not secret then
        local okH, help = pcall(Helpful, spellID)
        local okX, harm = pcall(Harmful, spellID)
        lastCast.helpful, lastCast.harmful = tostring(okH and help), tostring(okX and harm)
        if okX and harm and not isSecret(harm) then
            kind = "damage"
        elseif okH and help and not isSecret(help) then
            kind = "heal"
        end
        -- a spell that is neither (and not a tradeskill) is utility only if
        -- the game said so plainly; unknown answers fall through to target
        if not kind and okH and okX and help == false and harm == false then kind = "utility" end
    end
    kind = kind or KindFromTarget()
    lastCast.kind = kind
    return kind
end

-------------------------------------------------------------------------------
--  Cast bar
-------------------------------------------------------------------------------
local function TintCastBar(bar)
    if not bar then return end
    local tex = bar:GetStatusBarTexture()
    local kind = bar.barType
    local channel = kind == "channel" or (kind == nil and bar.channeling)
    local casting = kind == "standard" or (kind == nil and bar.casting)
    if not ns.db.natureColors or not (channel or casting) then
        -- Blizzard's own states (interrupted, failed, uninterruptible) must
        -- never inherit our desaturation
        if tex and tex.SetDesaturated then tex:SetDesaturated(false) end
        return
    end
    local color = CAST_COLORS[CastKind(bar, channel)]
    if HasGreenFill() then
        bar:SetStatusBarTexture(GREEN_FILL)
        tex = bar:GetStatusBarTexture()
        if tex and tex.SetDesaturated then tex:SetDesaturated(color ~= nil) end
        local c = color or { 1, 1, 1 }
        bar:SetStatusBarColor(c[1], c[2], c[3])
        lastCast.desaturated = tex and tex.IsDesaturated and tostring(tex:IsDesaturated()) or "n/a"
        lastCast.atlas = tex and tex.GetAtlas and tostring(tex:GetAtlas()) or "n/a"
    else
        local c = color or FALLBACK_HEAL
        bar:SetStatusBarTexture(FALLBACK_BAR)
        bar:SetStatusBarColor(c[1], c[2], c[3])
    end
end

-- Cast time sits centered under the bar instead of off its right end (where
-- it ran into the target frame). Plain text, so safe to move any time.
local function PlaceCastTime(bar)
    local t = bar.CastTimeText or (bar:GetName() and _G[bar:GetName() .. "CastTimeText"])
    if not t then return end
    -- the border art hangs below the bar's own frame; go under whichever is lower
    local under = bar
    local border = bar.Border
    if border and border.GetBottom and border:GetBottom() and bar:GetBottom()
        and border:GetBottom() < bar:GetBottom() then
        under = border
    end
    -- a bit smaller than Blizzard's: 80% of its own size, same font + outline
    local font, size, flags = t:GetFont()
    if font and size then
        t.__ibuiBaseSize = t.__ibuiBaseSize or size
        local want = t.__ibuiBaseSize * 0.8
        if math.abs(size - want) > 0.1 then t:SetFont(font, want, flags) end
    end
    local p, rel, _, _, y = t:GetPoint(1)
    if p == "TOP" and rel == under and y == -12 then return end
    t:ClearAllPoints()
    t:SetPoint("TOP", under, "BOTTOM", 0, -12)
    t:SetJustifyH("CENTER")
end

-------------------------------------------------------------------------------
--  Always-show cast bar: an empty, still copy of the cast bar's own frame art
--  (border + background, same textures, same place) shown while the real bar
--  is hidden. Casting shows the real bar on top as usual. Nothing fights
--  Blizzard's own show/fade logic.
-------------------------------------------------------------------------------
local ghost
local function BuildGhost(bar)
    if ghost then return end
    ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetAllPoints(bar)
    ghost:SetFrameStrata(bar:GetFrameStrata())
    ghost:SetFrameLevel(math.max(bar:GetFrameLevel() - 1, 0))
    -- only the bar's own background and border: everything else on a cast bar
    -- (name plate, glows, flash, shield, spark) made a mess when copied
    local wanted = {}
    for _, k in ipairs({ "Background", "Border" }) do
        local r = bar[k]
        if r and r.IsObjectType and r:IsObjectType("Texture") then wanted[#wanted + 1] = r end
    end
    ghost.copied = 0
    for _, r in ipairs(wanted) do
        do
            pcall(function()
                local layer, sub = r:GetDrawLayer()
                local t = ghost:CreateTexture(nil, layer, nil, sub)
                local atlas = r.GetAtlas and r:GetAtlas()
                if atlas then t:SetAtlas(atlas) else t:SetTexture(r:GetTexture()) end
                t:SetTexCoord(r:GetTexCoord())
                t:SetVertexColor(r:GetVertexColor())
                t:SetBlendMode(r:GetBlendMode())
                t:SetSize(r:GetSize())
                for i = 1, r:GetNumPoints() do
                    local p, rel, rp, x, y = r:GetPoint(i)
                    t:SetPoint(p, rel == bar and ghost or rel, rp, x, y)
                end
                if r:GetNumPoints() == 0 then t:SetAllPoints(ghost) end
                t:SetShown(r:IsShown())
                ghost.copied = ghost.copied + 1
            end)
        end
    end
    -- couldn't copy the art: a simple dark bar with a thin border instead
    if ghost.copied == 0 then
        local f = CreateFrame("Frame", nil, ghost, "BackdropTemplate")
        f:SetPoint("TOPLEFT", -2, 2)
        f:SetPoint("BOTTOMRIGHT", 2, -2)
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        f:SetBackdropColor(0, 0, 0, 0.5)
        f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
        ghost.fallback = true
    end
end

local function UpdateGhost()
    local bar = PlayerCastingBarFrame or CastingBarFrame
    if not bar then return end
    if ns.db.castBarAlways then
        local ok, err = pcall(BuildGhost, bar)
        if not ok then ns.castGhostError = tostring(err) end
        if ghost then ghost:SetShown(not bar:IsVisible()) end
    elseif ghost then
        ghost:Hide()
    end
end

-- for /ibui debug
function ns.CastGhostStats()
    local bar = PlayerCastingBarFrame or CastingBarFrame
    return ("castGhost: option=%s built=%s shown=%s copied=%s fallback=%s barVisible=%s size=%s err=%s"):format(
        tostring(ns.db.castBarAlways), tostring(ghost ~= nil), tostring(ghost and ghost:IsShown()),
        tostring(ghost and ghost.copied), tostring(ghost and ghost.fallback),
        tostring(bar and bar:IsVisible()),
        ghost and ("%.0fx%.0f"):format(ghost:GetWidth() or 0, ghost:GetHeight() or 0) or "-",
        tostring(ns.castGhostError))
end
ns.UpdateCastGhost = UpdateGhost

local function HookCastBar()
    local bar = PlayerCastingBarFrame or CastingBarFrame
    if not bar or bar.__ibuiTint then return end
    bar.__ibuiTint = true
    bar:HookScript("OnShow", UpdateGhost)
    bar:HookScript("OnHide", UpdateGhost)
    bar:HookScript("OnEvent", function(self)
        TintCastBar(self)
        PlaceCastTime(self)
    end)
    bar:HookScript("OnShow", PlaceCastTime)
    PlaceCastTime(bar)
    if bar.UpdateCastBarTexture then
        hooksecurefunc(bar, "UpdateCastBarTexture", TintCastBar)
    end
end

-------------------------------------------------------------------------------
--  XP bar
-------------------------------------------------------------------------------
-- The XP bar is the status bar whose frame carries the rested-XP marker
-- (ExhaustionTick / ExhaustionLevelFillBar); found by searching the status
-- bar container, since its name differs between clients.
local xpBar
local function FindXPBar(frame, depth)
    if not frame or depth > 5 then return nil end
    if frame.ExhaustionTick or frame.ExhaustionLevelFillBar then
        if frame.StatusBar then return frame.StatusBar end
        if frame.IsObjectType and frame:IsObjectType("StatusBar") then return frame end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        local found = FindXPBar(child, depth + 1)
        if found then return found end
    end
end

local function ExpStatusBar()
    if xpBar then return xpBar end
    for _, root in ipairs({ MainStatusTrackingBarContainer, SecondaryStatusTrackingBarContainer,
        StatusTrackingBarManager, ExpBar, MainMenuExpBar }) do
        xpBar = FindXPBar(root, 0)
        if xpBar then return xpBar end
    end
end

-- Class color the same way the health bars do it: Blizzard's plain white bar
-- tinted in the class color. (Greyed or textured fills came out dull / busy.)
local XP_BAR_TEX = "Interface\\TargetingFrame\\UI-StatusBar"

local function TintXP()
    local sb = ExpStatusBar()
    if not (sb and sb.SetStatusBarColor) then return end
    local _, class = UnitClass("player")
    local c = class and (C_ClassColor and C_ClassColor.GetClassColor(class) or RAID_CLASS_COLORS[class])
    if not c then return end
    sb.__ibuiSetting = true
    sb:SetStatusBarTexture(XP_BAR_TEX)
    sb:SetStatusBarColor(c.r, c.g, c.b)
    sb.__ibuiSetting = nil
end

local function HookXP()
    local sb = ExpStatusBar()
    if not sb or sb.__ibuiTint then return end
    sb.__ibuiTint = true
    -- Blizzard recolors it on updates; put the class color back each time
    hooksecurefunc(sb, "SetStatusBarColor", function(self)
        if not self.__ibuiSetting then TintXP() end
    end)
    if sb.SetStatusBarTexture then
        hooksecurefunc(sb, "SetStatusBarTexture", function(self)
            if not self.__ibuiSetting then TintXP() end
        end)
    end
end

-------------------------------------------------------------------------------
--  Wiring
-------------------------------------------------------------------------------
function ns.RefreshTheme()
    HookCastBar()
    HookXP()
    TintXP()
    C_Timer.After(1, UpdateGhost) -- after the layout has placed the cast bar
end

-- for /ibui debug
function ns.ThemeStats()
    local parts = {}
    for k, v in pairs(lastCast) do parts[#parts + 1] = k .. "=" .. tostring(v) end
    table.sort(parts)
    return ("theme: greenFill=%s expBar=%s castBar=%s IsSpellHelpful=%s | lastCast: %s"):format(
        tostring(HasGreenFill()), tostring(ExpStatusBar() ~= nil),
        tostring((PlayerCastingBarFrame or CastingBarFrame) ~= nil),
        tostring(C_Spell and C_Spell.IsSpellHelpful ~= nil), table.concat(parts, " "))
end

ns.OnLogin(function()
    ns.RefreshTheme()
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("UPDATE_EXHAUSTION")
    ev:RegisterEvent("PLAYER_XP_UPDATE")
    ev:SetScript("OnEvent", function()
        HookXP() -- the bar can be built after login
        TintXP()
    end)
end)
