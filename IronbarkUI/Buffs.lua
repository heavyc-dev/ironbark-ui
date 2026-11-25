-------------------------------------------------------------------------------
--  Ironbark UI - missing buff reminders on party frames
--
--  Small icons on your player frame and each party / raid member frame for buffs
--  YOU can cast that they are missing (group versions count too):
--    Druid   Mark of the Wild on everyone, Thorns on the tank and you
--    Priest  Fortitude on everyone, Divine Spirit on mana users, Inner Fire on you
--    Mage    Arcane Intellect on mana users, an armor on you
--    Paladin a Blessing on everyone (Wisdom for mana users, Might for the rest;
--            any of your Blessings counts), an Aura on you
--    Shaman  Lightning Shield and a weapon imbue on you
--    Hunter  an Aspect and Trueshot Aura on you
--    Warlock Demon Skin / Demon Armor on you
--    Warrior Battle Shout on you
--  Situational ones (Shadow Protection, resist auras, Unending Breath) are left
--  to you. Rogue poisons are items, not spells, so they aren't tracked.
--  Only buffs you have learned are checked. Dead/offline members are skipped.
--
--  Each icon is our own secure spell button (click = cast that buff on that
--  unit), configured only out of combat; the party frames themselves are never
--  touched. In combat (see "Combat" below) the buttons sit in fixed slots and
--  only their looks change; aura data the client hides then reads as "unknown".
-------------------------------------------------------------------------------
local _, ns = ...

local _, CLASS = UnitClass("player")
local ICON, PAD = 20, 2 -- about the size of target frame auras
local isSecret = issecretvalue or function() return false end

local MANA_CLASSES = {
    DRUID = true, HUNTER = true, MAGE = true, PALADIN = true,
    PRIEST = true, SHAMAN = true, WARLOCK = true,
}

-- ids: every spell that satisfies the buff (matched by name, so all ranks
-- count). cast: what the icon casts, best first (the first one you know); by
-- default the first id. castMana: what mana users get instead (Blessings).
-- weapon: a temporary weapon enchant on you instead of an aura.
-- who: all | mana | tank (and you) | self (only you)
local BUFFS = {
    DRUID   = { { ids = { 1126, 21849 }, who = "all" },                     -- Mark / Gift of the Wild
                { ids = { 467 }, who = "tank" } },                          -- Thorns: the tank and you
    PRIEST  = { { ids = { 1243, 21562 }, who = "all" },                     -- Fortitude / Prayer of Fortitude
                { ids = { 14752, 27681 }, who = "mana" },                   -- Divine Spirit / Prayer of Spirit (talent)
                { ids = { 588 }, who = "self" } },                          -- Inner Fire
    MAGE    = { { ids = { 1459, 23028 }, who = "mana" },                    -- Arcane Intellect / Brilliance
                { ids = { 168, 7302, 6117 }, cast = { 6117, 7302, 168 }, who = "self" } }, -- Mage / Ice / Frost Armor
    WARLOCK = { { ids = { 687, 706 }, cast = { 706, 687 }, who = "self" } },  -- Demon Armor / Demon Skin
    PALADIN = { { ids = { 19740, 19742, 20217, 1038, 19977, 20911,          -- any Blessing (and Greater ones)
                          25782, 25894, 25898, 25895, 25890, 25899 },
                  cast = { 19740 }, castMana = { 19742 }, who = "all" },    -- Might / Wisdom for mana users
                { ids = { 465, 7294, 19746, 19876, 19888, 19891, 20218 },   -- any Aura
                  cast = { 465 }, who = "self" } },                         -- Devotion Aura
    SHAMAN  = { { ids = { 324 }, who = "self" },                            -- Lightning Shield
                { weapon = true, cast = { 8232, 8024, 8033, 8017 }, who = "self" } }, -- Windfury / Flametongue / Frostbrand / Rockbiter
    HUNTER  = { { ids = { 13165, 13163, 5118, 13159, 20043, 13161 },        -- any Aspect
                  cast = { 13165, 13163 }, who = "self" },                  -- Hawk, else Monkey
                { ids = { 19506 }, who = "self" } },                        -- Trueshot Aura (talent)
    WARRIOR = { { ids = { 6673 }, who = "self" } },                         -- Battle Shout
}

local myBuffs -- resolved: { names = {set}, icon, who }

-- Dispels: debuff type -> your spells that remove it, best first (by rank 1 id).
local DISPELS = {
    DRUID   = { Curse = { 2782 }, Poison = { 2893, 8946 } },                -- Remove Curse; Abolish / Cure Poison
    PRIEST  = { Magic = { 527 }, Disease = { 552, 528 } },                    -- Dispel Magic; Abolish / Cure Disease
    PALADIN = { Magic = { 4987 }, Poison = { 4987, 1152 }, Disease = { 4987, 1152 } }, -- Cleanse / Purify
    SHAMAN  = { Poison = { 526 }, Disease = { 2870 } },                       -- Cure Poison / Cure Disease
    MAGE    = { Curse = { 475 } },                                            -- Remove Lesser Curse
}
local myDispels -- debuff type -> { spellID, cast }

local DEBUFF_COLORS = {
    Magic = { 0.2, 0.6, 1.0 }, Curse = { 0.6, 0.0, 1.0 },
    Poison = { 0.0, 0.6, 0.0 }, Disease = { 0.6, 0.4, 0.0 },
}

local function Known(id)
    return (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) or false
end

local function Resolve()
    myDispels = {}
    for kind, ids in pairs(DISPELS[CLASS] or {}) do
        for _, id in ipairs(ids) do
            if Known(id) then
                myDispels[kind] = { spellID = id, cast = C_Spell.GetSpellName(id) }
                break
            end
        end
    end
    myBuffs = {}
    -- first id of a list you know
    local function FirstKnown(list)
        for _, id in ipairs(list or {}) do
            if Known(id) then return id end
        end
    end
    for _, b in ipairs(BUFFS[CLASS] or {}) do
        local id = FirstKnown(b.cast or { b.ids[1] })
        if id then
            local names = {}
            for _, aid in ipairs(b.ids or {}) do
                local n = C_Spell.GetSpellName(aid)
                if n then names[n] = true end
            end
            local entry = {
                names = names, who = b.who, weapon = b.weapon,
                spellID = id, icon = C_Spell.GetSpellTexture(id),
                cast = C_Spell.GetSpellName(id), -- by name = highest rank
            }
            local manaID = b.castMana and FirstKnown(b.castMana)
            if manaID then
                entry.manaID = manaID
                entry.manaIcon = C_Spell.GetSpellTexture(manaID)
                entry.manaCast = C_Spell.GetSpellName(manaID)
            end
            myBuffs[#myBuffs + 1] = entry
        end
    end
end

-- does the client say auras are hidden from addons right now?
local function AurasHidden()
    local cs = C_Secrets
    if not (cs and cs.ShouldAurasBeSecret) then return false end
    local ok, secret = pcall(cs.ShouldAurasBeSecret)
    return not ok or isSecret(secret) or secret == true
end

-- Debuffs on unit that you can remove: { [type] = { icon } } (one per type),
-- and whether some couldn't be read (hidden in combat). Empty when you have
-- no dispels.
local function Dispellable(unit)
    local found = {}
    if not (myDispels and next(myDispels) and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return found, false end
    if not UnitIsFriend("player", unit) then return found, false end
    local unknown = AurasHidden()
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HARMFUL")
        if not aura then break end
        local kind = aura.dispelName
        if isSecret(kind) then
            unknown = true
        elseif kind and myDispels[kind] and not found[kind] then
            found[kind] = { icon = aura.icon }
        end
    end
    return found, unknown
end

-- true / false, or nil when the auras can't be read right now
local function HasBuff(unit, names)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    if AurasHidden() then return nil end
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        if not aura then
            -- in combat an empty list can mean "hidden" rather than "no buffs"
            if i == 1 and InCombatLockdown() then return nil end
            return false
        end
        local name = aura.name
        if isSecret(name) then return nil end
        if names[name] then return true end
    end
    return false
end

local function GroupHasTank()
    if not UnitGroupRolesAssigned then return false end
    if UnitGroupRolesAssigned("player") == "TANK" then return true end
    for i = 1, 4 do
        if UnitExists("party" .. i) and UnitGroupRolesAssigned("party" .. i) == "TANK" then return true end
    end
    return false
end

local function Wants(unit, who, tankAssigned)
    if who == "all" then return true end
    local isMe = UnitIsUnit(unit, "player")
    if who == "self" then return isMe end
    local _, class = UnitClass(unit)
    if who == "mana" then return MANA_CLASSES[class] or false end
    if who == "tank" then
        if isMe then return true end
        if tankAssigned then return UnitGroupRolesAssigned(unit) == "TANK" end
        return class == "WARRIOR"
    end
end

-- What each unit had the last time its buffs could be read (out of combat):
-- lastHad[unit][buff's spell] = true / false. Auras are already hidden by the
-- time combat is announced, so the combat icons start from this.
local lastHad = {}

-- Is this buff missing on unit? (weapon imbues: no main-hand enchant on you)
local function Missing(unit, b, tankAssigned)
    if b.weapon then
        if not UnitIsUnit(unit, "player") or not GetWeaponEnchantInfo then return false end
        local has = GetWeaponEnchantInfo()
        return not has
    end
    if not Wants(unit, b.who, tankAssigned) then return false end
    local has = HasBuff(unit, b.names)
    if has ~= nil and b.cast then
        lastHad[unit] = lastHad[unit] or {}
        lastHad[unit][b.cast] = has
    end
    return has == false
end

-- what the icon casts on unit: the mana version for mana users (Wisdom)
local function CastFor(unit, b)
    if b.manaID then
        local _, class = UnitClass(unit)
        if MANA_CLASSES[class] then return b.manaCast, b.manaIcon, b.manaID end
    end
    return b.cast, b.icon, b.spellID
end

-------------------------------------------------------------------------------
--  Icons
-------------------------------------------------------------------------------
local holders = {} -- [member frame] = holder with .icons

local function Holder(member)
    local h = holders[member]
    if h then return h end
    h = CreateFrame("Frame", nil, member)
    if member.healthbar and member.manabar then
        -- classic party frame: just under its bottom-right corner, clear of
        -- the health/mana bars
        local below = member.manabar
        h:SetPoint("TOPRIGHT", below, "BOTTOMRIGHT", 0, -3)
    else
        -- raid-style block: inside its bottom-right corner
        h:SetPoint("BOTTOMRIGHT", member, "BOTTOMRIGHT", -3, 3)
    end
    h:SetSize(ICON, ICON)
    h:SetFrameLevel(member:GetFrameLevel() + 10)
    h:EnableMouse(false)
    h.icons = {}
    holders[member] = h
    return h
end

-------------------------------------------------------------------------------
--  Glow: Blizzard's proc glow (the golden border action buttons get when a
--  spell procs). If this client doesn't expose it, a soft pulse instead.
-------------------------------------------------------------------------------
-- Our own glow: the classic gold item-border glow, pulsing. Deliberately NOT
-- Blizzard's spell-alert system: that is shared with the real action buttons,
-- and touching it from an addon gets Blizzard's own later use of it in combat
-- blocked ("Ironbark UI has been blocked from an action...").
local GLOW_TEX = "Interface\\Buttons\\UI-ActionButton-Border"

local function Glow(f)
    if f.glow then return f.glow end
    local g = CreateFrame("Frame", nil, f) -- plain child: animating it is always allowed
    g:SetPoint("CENTER")
    g:SetSize(ICON * 1.9, ICON * 1.9)
    g:EnableMouse(false)
    local t = g:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints()
    t:SetTexture(GLOW_TEX)
    t:SetBlendMode("ADD")
    t:SetVertexColor(1, 0.82, 0.25)
    g.tex = t
    local ag = g:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.35)
    a:SetDuration(0.7)
    a:SetSmoothing("IN_OUT")
    g.pulse = ag
    g:Hide()
    f.glow = g
    return g
end

-- color: nil = gold (buffs), or a debuff-type color for dispel icons
local function GlowOn(f, color)
    if not ns.db.buffGlow then return end
    local g = Glow(f)
    local c = color or { 1, 0.82, 0.25 }
    g.tex:SetVertexColor(c[1], c[2], c[3])
    if not g:IsShown() then
        g:Show()
        g.pulse:Play()
    end
end

local function GlowOff(f)
    local g = f.glow
    if g and g:IsShown() then
        g.pulse:Stop()
        g:Hide()
    end
end


-- Each icon is a secure spell button: click to cast the buff on that unit.
-- Created, configured and shown only out of combat.
local function Icon(h, i)
    local f = h.icons[i]
    if f then return f end
    f = CreateFrame("Button", nil, h, "SecureActionButtonTemplate")
    f:SetSize(ICON, ICON)
    f:RegisterForClicks("AnyUp", "AnyDown") -- works with either "cast on key down" setting
    f:SetAttribute("type1", "spell")
    f:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    f:SetScript("OnEnter", function(self)
        if not self.spellID or self:GetAlpha() == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(self.spellID)
        GameTooltip:AddLine("Click to cast on " .. (UnitName(self:GetAttribute("unit") or "") or "them"), 0.4, 1, 0.4)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- debuff-type border (dispel icons only)
    f.border = f:CreateTexture(nil, "BACKGROUND")
    f.border:SetPoint("TOPLEFT", -2, 2)
    f.border:SetPoint("BOTTOMRIGHT", 2, -2)
    f.border:SetColorTexture(1, 1, 1, 1)
    f.border:Hide()
    if i == 1 then
        f:SetPoint("TOPRIGHT", h, "TOPRIGHT")
    else
        f:SetPoint("RIGHT", h.icons[i - 1], "LEFT", -PAD, 0)
    end
    f:HookScript("OnHide", GlowOff)
    h.icons[i] = f
    return f
end

-- The icons are secure buttons, so their holders can only be shown/hidden
-- out of combat (PLAYER_REGEN_DISABLED still counts: lockdown starts after it).
local function HideAll()
    if InCombatLockdown() then return end
    for _, h in pairs(holders) do h:Hide() end
end

-- every frame that can show a person; missing ones are skipped (no gaps,
-- or ipairs would stop early and drop everything after a missing frame)
local function Members()
    local members = {}
    local function add(f) if f then members[#members + 1] = f end end
    add(PlayerFrame) -- your own frame too, solo or grouped
    for _, f in ipairs(ns.ClassicPartyMembers and ns.ClassicPartyMembers() or {}) do add(f) end
    for i = 1, 5 do add(_G["CompactPartyFrameMember" .. i]) end
    if IsInRaid() then
        -- raid frames: named by group, or flat when groups are combined
        for g = 1, 8 do
            for m = 1, 5 do add(_G["CompactRaidGroup" .. g .. "Member" .. m]) end
        end
        for i = 1, 40 do add(_G["CompactRaidFrame" .. i]) end
    end
    return members
end

-- same on-screen size as auras on the target frame, whatever the party
-- frame's own scale
local function FitHolder(h, m)
    local ref = TargetFrame or UIParent
    local ms = m:GetEffectiveScale()
    if ms and ms > 0 then h:SetScale(ref:GetEffectiveScale() / ms) end
end

local HideDispelEngines -- combat's debuff displays (below)

local function Update()
    if InCombatLockdown() then return end -- combat has its own pass (below)
    if HideDispelEngines then HideDispelEngines() end
    if not ns.db.buffReminders or not myBuffs or (#myBuffs == 0 and not next(myDispels or {})) then
        HideAll()
        return
    end
    local tankAssigned = GroupHasTank()
    for _, m in ipairs(Members()) do
        if m then
            local unit = m.unit or m:GetAttribute("unit")
            local h = Holder(m)
            FitHolder(h, m)
            h.combat = nil
            local n = 0
            if unit and m:IsVisible() and UnitExists(unit) and UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) then
                for _, b in ipairs(myBuffs) do
                    if ns.buffTest or Missing(unit, b, tankAssigned) then
                        local cast, icon, sid = CastFor(unit, b)
                        n = n + 1
                        local f = Icon(h, n)
                        f.tex:SetTexture(icon)
                        f.border:Hide()
                        f.spellID = sid
                        f:SetAttribute("spell1", cast)
                        f:SetAttribute("unit", unit)
                        f.slot = nil
                        f:SetAlpha(1)
                        f:Show()
                        if ns.db.buffGlow then GlowOn(f, nil) else GlowOff(f) end
                    end
                end
                -- debuffs you can remove: the debuff's icon in its type color;
                -- click casts your dispel on them
                for kind, d in pairs(Dispellable(unit)) do
                    n = n + 1
                    local f = Icon(h, n)
                    f.tex:SetTexture(d.icon)
                    local c = DEBUFF_COLORS[kind] or { 1, 0, 0 }
                    f.border:SetVertexColor(c[1], c[2], c[3])
                    f.border:Show()
                    f.spellID = myDispels[kind].spellID
                    f:SetAttribute("spell1", myDispels[kind].cast)
                    f:SetAttribute("unit", unit)
                    f.slot = nil
                    f:SetAlpha(1)
                    f:Show()
                    GlowOn(f, c)
                end
            end
            for k = n + 1, #h.icons do h.icons[k]:Hide() end
            h:SetShown(n > 0)
        end
    end
end

-------------------------------------------------------------------------------
--  Combat. Secure buttons can't be shown, hidden or re-aimed once combat
--  starts, so just before it does every member gets a full set in fixed slots:
--  each buff they should have from you, then each dispel you know. From then
--  on only looks change (always allowed): a slot is bright and glowing while
--  it's needed, invisible while it isn't (dispel slots: dim when there is no
--  telling).
--  An invisible slot still casts if clicked.
--
--  This client hides every aura from addons for the whole fight, so "needed"
--  can't be read then. Buffs go by what was missing at the pull, minus what
--  you have cast since. Dispels are handed to the game's own aura display
--  (an "AuraContainer", as for the HoT icons further down): one per dispel
--  slot, told to draw debuffs of that slot's types on that unit. It still
--  sees them in combat, so the debuff's icon appears right on top of our
--  (then invisible) dispel button, and clicks fall through to the button.
--  Party and your own frame only; in a raid, or if the display isn't
--  available, the dispel buttons just sit dim.
-------------------------------------------------------------------------------
local KIND_ORDER = { "Magic", "Curse", "Poison", "Disease" }

local dispelEngines = {} -- [button] = { [kinds key] = { host, container, unit } }
local dispelEngineOK     -- nil = not tried, false = unavailable

local function InitDispelButton(button, color)
    pcall(button.SetMouseClickEnabled, button, false)
    if button.SetMouseMotionEnabled then pcall(button.SetMouseMotionEnabled, button, false) end
    button:SetSize(ICON, ICON)
    local border = button:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetColorTexture(color[1], color[2], color[3], 1)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button:SetIcon(icon)
end

local function DispelEngine(f, kinds)
    if dispelEngineOK == false then return nil end
    local key = table.concat(kinds, ",")
    dispelEngines[f] = dispelEngines[f] or {}
    local e = dispelEngines[f][key]
    if e then return e end
    if C_AddOns and C_AddOns.LoadAddOn and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    local host = CreateFrame("Frame", nil, UIParent)
    host:SetSize(ICON, ICON)
    host:EnableMouse(false)
    host:Hide()
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, host, "CustomAuraContainerTemplate")
    if not ok or not c or not c.AddAuraGroup then
        dispelEngineOK = false
        return nil
    end
    c:SetPoint("TOPLEFT", host, "TOPLEFT")
    c:SetSize(1, 1)
    local anchorFn = c.SetFlowLayoutAnchorPoint or c.SetAuraLayoutAnchorPoint
    if anchorFn then pcall(anchorFn, c, "TOPLEFT") end
    local types = {}
    for _, kind in ipairs(kinds) do types[kind] = true end
    local color = DEBUFF_COLORS[kinds[1]] or { 1, 0, 0 }
    local okGroup = pcall(c.AddAuraGroup, c, "dispel", "HARMFUL", {
        maxFrameCount = 1,
        candidateFilters = { includeDispelTypes = types },
        initializeFrame = function(button) InitDispelButton(button, color) end,
    })
    if not okGroup then
        dispelEngineOK = false
        return nil
    end
    dispelEngineOK = true
    e = { host = host, container = c }
    dispelEngines[f][key] = e
    return e
end

function HideDispelEngines()
    for _, byKey in pairs(dispelEngines) do
        for _, e in pairs(byKey) do e.host:Hide() end
    end
end

-- out of combat: sit the display exactly on its dispel button
local function PlaceDispelEngine(f, unit)
    local s = f.slot
    s.engine = nil
    local x, y = f:GetLeft(), f:GetTop()
    if not (x and y) then return end
    local e = DispelEngine(f, s.kinds)
    if not e then return end
    local host = e.host
    host:SetScale(f:GetEffectiveScale() / UIParent:GetEffectiveScale())
    host:SetFrameStrata(f:GetFrameStrata())
    host:SetFrameLevel(f:GetFrameLevel() + 5)
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y) -- same effective scale as the button
    if e.unit ~= unit then
        e.container:SetUnit(unit)
        e.unit = unit
    end
    host:Show()
    if e.container.UpdateAllAuras then e.container:UpdateAllAuras() end
    s.engine = true
end

-- state: true = needed, false = not, nil = can't tell right now
local function Paint(f, state, icon, color)
    if state == false then
        f:SetAlpha(0)
        GlowOff(f)
        return
    end
    f.tex:SetTexture(icon)
    f.border:SetShown(color ~= nil)
    if color then f.border:SetVertexColor(color[1], color[2], color[3]) end
    f:SetAlpha(state and 1 or 0.35)
    if state then GlowOn(f, color) else GlowOff(f) end
end

local function PaintCombat()
    for _, h in pairs(holders) do
        if h.combat then
            local unit = h.unit
            local alive = UnitExists(unit) and UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit)
            local found, unknown
            for _, f in ipairs(h.icons) do
                local s = f.slot
                if s and not alive then
                    Paint(f, false)
                elseif s and s.buff then
                    local state
                    if s.buff.weapon then
                        state = not GetWeaponEnchantInfo()
                    else
                        local has = HasBuff(unit, s.buff.names)
                        if has ~= nil then state = not has end
                    end
                    if state == nil then state = s.missing end -- as of the pull
                    Paint(f, state, s.icon)
                elseif s then
                    if not found then found, unknown = Dispellable(unit) end
                    local hit
                    for _, kind in ipairs(s.kinds) do
                        if found[kind] then hit = kind break end
                    end
                    local state = false
                    -- unreadable: the game's display on top of the slot shows it (or dim without one)
                    if hit then state = true elseif unknown and not s.engine then state = nil end
                    Paint(f, state, hit and found[hit].icon or s.icon, DEBUFF_COLORS[hit or s.kinds[1]])
                end
            end
        end
    end
end

-- on PLAYER_REGEN_DISABLED: lockdown starts right after this event
local function PrepareCombat()
    if InCombatLockdown() then return end
    if not (ns.db.buffReminders and ns.db.buffCombat) or not myBuffs
        or (#myBuffs == 0 and not next(myDispels or {})) then
        HideAll()
        return
    end
    local tankAssigned = GroupHasTank()
    HideDispelEngines()
    for _, m in ipairs(Members()) do
        local unit = m.unit or m:GetAttribute("unit")
        local h = Holder(m)
        FitHolder(h, m)
        local n = 0
        local function Slot(cast, sid, slot)
            n = n + 1
            local f = Icon(h, n)
            f.spellID = sid
            f.slot = slot
            f:SetAttribute("spell1", cast)
            f:SetAttribute("unit", unit)
            f:Show()
        end
        if unit and m:IsVisible() and UnitExists(unit) then
            for _, b in ipairs(myBuffs) do
                local applies
                if b.weapon then
                    applies = UnitIsUnit(unit, "player")
                else
                    applies = Wants(unit, b.who, tankAssigned)
                end
                if applies then
                    local cast, icon, sid = CastFor(unit, b)
                    -- unreadable here (combat is already on): go by the last
                    -- out-of-combat look; never seen = assume they have it
                    local missing = false
                    if b.weapon then
                        missing = not GetWeaponEnchantInfo()
                    else
                        local has = HasBuff(unit, b.names)
                        if has == nil then has = lastHad[unit] and lastHad[unit][b.cast] end
                        if has ~= nil then missing = not has end
                    end
                    Slot(cast, sid, { buff = b, icon = icon, cast = cast, missing = missing })
                end
            end
            -- one slot per dispel spell (Cleanse covers three debuff types)
            local bySpell = {}
            for _, kind in ipairs(KIND_ORDER) do
                local d = myDispels and myDispels[kind]
                if d then
                    local s = bySpell[d.cast]
                    if s then
                        s.kinds[#s.kinds + 1] = kind
                    else
                        s = { kinds = { kind }, icon = C_Spell.GetSpellTexture(d.spellID) }
                        bySpell[d.cast] = s
                        Slot(d.cast, d.spellID, s)
                    end
                end
            end
        end
        for k = n + 1, #h.icons do h.icons[k]:Hide() end
        h.unit = unit
        h.combat = n > 0
        h:SetShown(n > 0)
        if n > 0 and not IsInRaid() then
            for k = 1, n do
                local f = h.icons[k]
                if f.slot and f.slot.kinds then pcall(PlaceDispelEngine, f, unit) end
            end
        end
    end
    pcall(PaintCombat)
end

-------------------------------------------------------------------------------
--  Blizzard's own aura icons on the classic party frames (the row under each
--  teammate's left side) double up with ours: hidden while reminders are on.
--  Plain (non-secure) icons, so hiding them is fine even in combat.
-------------------------------------------------------------------------------
local function IsOurs(m, c) return c == holders[m] end

local function HidePartyAuras(m)
    if not ns.db.buffReminders then return end
    if m.auraPool and m.auraPool.EnumerateActive then
        for a in m.auraPool:EnumerateActive() do a:Hide() end
    end
    for _, c in ipairs({ m:GetChildren() }) do
        if not IsOurs(m, c) then
            local name = c:GetName()
            if isSecret(c.auraInstanceID) or c.auraInstanceID ~= nil or (name and (name:find("Buff%d+$") or name:find("Debuff%d+$"))) then
                c:Hide()
            end
        end
    end
    -- older named buttons: PartyMemberFrame1Buff1, ...Debuff1
    local base = m:GetName()
    if base then
        for i = 1, 8 do
            for _, k in ipairs({ "Buff", "Debuff" }) do
                local b = _G[base .. k .. i]
                if b then b:Hide() end
            end
        end
    end
end

local hookedParty = {}
local function HookPartyAuras()
    for _, m in ipairs(ns.ClassicPartyMembers and ns.ClassicPartyMembers() or {}) do
        if not hookedParty[m] then
            hookedParty[m] = true
            for _, fn in ipairs({ "UpdateAuras", "RefreshBuffs", "UpdateBuffs" }) do
                if type(m[fn]) == "function" then
                    hooksecurefunc(m, fn, HidePartyAuras)
                end
            end
            m:HookScript("OnShow", HidePartyAuras)
        end
        HidePartyAuras(m)
    end
end
if type(PartyMemberFrame_RefreshBuffs) == "function" then
    hooksecurefunc("PartyMemberFrame_RefreshBuffs", function(m) if m then HidePartyAuras(m) end end)
end

-------------------------------------------------------------------------------
--  Your HoTs: under the left side of your own frame and each classic party frame
--  (mirroring the reminders on the right), with a timer sweep. Display only,
--  so they keep updating in combat. Asked for by name with the PLAYER filter
--  (= cast by you), which works in combat; timers only when readable.
-------------------------------------------------------------------------------
local HOTS = {
    DRUID  = { 774, 8936 },   -- Rejuvenation, Regrowth
    PRIEST = { 139, 17 },     -- Renew, Power Word: Shield
}
local myHots -- { { name, icon } } for the HoTs you know

local function ResolveHots()
    myHots = {}
    for _, id in ipairs(HOTS[CLASS] or {}) do
        -- known by rank-1 id, or by name (your current rank may have another id)
        local name = C_Spell.GetSpellName(id)
        local info = name and C_Spell.GetSpellInfo(name)
        local known = Known(id) or (info and info.spellID and Known(info.spellID))
        if name and known then
            myHots[#myHots + 1] = { name = name, icon = C_Spell.GetSpellTexture(id) }
        end
    end
end

local hotHolders = {}
local function HotHolder(m)
    local h = hotHolders[m]
    if h then return h end
    h = CreateFrame("Frame", nil, m)
    h:SetPoint("TOPLEFT", m.manabar or m, m.manabar and "BOTTOMLEFT" or "BOTTOMLEFT", 0, -3)
    h:SetSize(ICON, ICON)
    h:SetFrameLevel(m:GetFrameLevel() + 10)
    h:EnableMouse(false)
    h.icons = {}
    hotHolders[m] = h
    return h
end

local function HotIcon(h, i)
    local f = h.icons[i]
    if f then return f end
    f = CreateFrame("Frame", nil, h)
    f:SetSize(ICON, ICON)
    f:EnableMouse(false)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints()
    f.cd:SetReverse(true)
    f.cd:SetDrawEdge(false)
    if f.cd.SetHideCountdownNumbers then f.cd:SetHideCountdownNumbers(true) end
    if i == 1 then
        f:SetPoint("TOPLEFT", h, "TOPLEFT")
    else
        f:SetPoint("LEFT", h.icons[i - 1], "RIGHT", PAD, 0)
    end
    h.icons[i] = f
    return f
end

-------------------------------------------------------------------------------
--  In combat, aura data is hidden from addon code, so lookups come back empty.
--  The game's own aura display (an "AuraContainer") still sees them: give it
--  a unit, a filter (HELPFUL|PLAYER = cast by you) and the HoT spell ids, and
--  it draws the icons + timers itself, in combat too. One per party frame, on a
--  host frame tied to UIParent (never to the secure party frame), placed by
--  numbers out of combat. Without the API, the lookup version below is used.
-------------------------------------------------------------------------------
-- every rank of each HoT (the container matches by spell id)
local HOT_RANKS = {
    DRUID  = { 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299,   -- Rejuvenation
               8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858 },             -- Regrowth
    PRIEST = { 139, 6074, 6075, 6076, 6077, 6078, 10927, 10928, 10929, 25315,     -- Renew
               17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901 },     -- Power Word: Shield
}
local engine = {} -- [member frame] = { host, container, unit }
local engineOK -- nil = not tried, false = unavailable

local function HotIDs()
    local ids = {}
    for _, id in ipairs(HOT_RANKS[CLASS] or {}) do ids[id] = true end
    -- plus whatever ids this client uses for the ranks you know
    for _, hot in ipairs(myHots or {}) do
        local info = C_Spell.GetSpellInfo(hot.name)
        if info and info.spellID then ids[info.spellID] = true end
    end
    return ids
end

local function InitHotButton(button)
    pcall(button.SetMouseClickEnabled, button, false)
    button:SetSize(ICON, ICON)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cd:SetAllPoints(button)
    cd:SetReverse(true)
    cd:SetDrawEdge(false)
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
    button:SetIcon(icon)
    button:SetDurationCooldown(cd)
end

local function EngineFor(m)
    local e = engine[m]
    if e then return e end
    if engineOK == false then return nil end
    if C_AddOns and C_AddOns.LoadAddOn and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    local host = CreateFrame("Frame", nil, UIParent)
    host:SetSize(ICON, ICON)
    host:SetFrameStrata("MEDIUM")
    host:Hide()
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, host, "CustomAuraContainerTemplate")
    if not ok or not c or not c.AddAuraGroup then
        engineOK = false
        return nil
    end
    c:SetPoint("TOPLEFT", host, "TOPLEFT")
    c:SetSize(1, 1)
    local anchorFn = c.SetFlowLayoutAnchorPoint or c.SetAuraLayoutAnchorPoint
    if anchorFn then anchorFn(c, "TOPLEFT") end
    local dir = AnchorUtil and AnchorUtil.FlowDirection
    local growFn = c.SetFlowLayoutGrowthDirection or c.SetAuraLayoutGrowthDirection
    if dir and growFn then growFn(c, dir.Right, dir.Down) end
    local okGroup = pcall(c.AddAuraGroup, c, "hots", "HELPFUL|PLAYER", {
        maxFrameCount = 4,
        candidateFilters = { includeSpellIDs = HotIDs() },
        initializeFrame = InitHotButton,
    })
    if not okGroup then
        engineOK = false
        return nil
    end
    engineOK = true
    e = { host = host, container = c }
    engine[m] = e
    return e
end

-- the frames that get HoT icons: your own, then each party member's
local function HotFrames()
    local list = {}
    if PlayerFrame and PlayerFrame.unit then list[#list + 1] = PlayerFrame end
    for _, m in ipairs(ns.ClassicPartyMembers and ns.ClassicPartyMembers() or {}) do list[#list + 1] = m end
    return list
end

-- out of combat: put each host under its frame's left side and bind its unit
local function PlaceEngineHots()
    if InCombatLockdown() then return end
    for _, m in ipairs(HotFrames()) do
        local e = EngineFor(m)
        if not e then return end
        local anchor = m.manabar or m
        local x, y = anchor:GetLeft(), anchor:GetBottom()
        local show = ns.db.hotIcons and m:IsVisible() and m.unit and x and y
        if show then
            -- same on-screen size as auras on the target frame
            local ref = TargetFrame or UIParent
            e.host:SetScale(ref:GetEffectiveScale() / UIParent:GetEffectiveScale())
            -- offsets are in the host's own scale
            local s = anchor:GetEffectiveScale() / e.host:GetEffectiveScale()
            e.host:ClearAllPoints()
            e.host:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x * s, y * s - 3 / e.host:GetScale())
            if e.unit ~= m.unit then
                e.container:SetUnit(m.unit)
                e.unit = m.unit
            end
            e.host:Show()
            e.container:UpdateAllAuras()
        else
            e.host:Hide()
        end
    end
end

local function UpdateHots()
    if engineOK ~= false and HOTS[CLASS] then
        PlaceEngineHots()
        if engineOK then return end -- the game draws them from here on
    end
    local list = HotFrames()
    local on = ns.db.hotIcons and myHots and #myHots > 0 and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
    for _, m in ipairs(list) do
        local unit = m.unit
        local h = HotHolder(m)
        local ref = TargetFrame or UIParent
        local ms = m:GetEffectiveScale()
        if ms and ms > 0 then h:SetScale(ref:GetEffectiveScale() / ms) end
        local n = 0
        if on and unit and m:IsVisible() and UnitExists(unit) then
            for _, hot in ipairs(myHots) do
                local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, hot.name, "HELPFUL|PLAYER")
                if ok and aura then
                    n = n + 1
                    local f = HotIcon(h, n)
                    f.tex:SetTexture(hot.icon)
                    local dur, exp = aura.duration, aura.expirationTime
                    if dur and exp and not isSecret(dur) and not isSecret(exp) and dur > 0 then
                        f.cd:SetCooldown(exp - dur, dur)
                    else
                        f.cd:Clear()
                    end
                    f:Show()
                end
            end
        end
        for k = n + 1, #h.icons do h.icons[k]:Hide() end
        h:SetShown(n > 0)
    end
end
ns.RefreshHots = function() ResolveHots() UpdateHots() end
ns.PlaceHots = function() pcall(UpdateHots) end -- after the party row moves

-- HoTs refresh straight away (no queue): their own events, per party unit,
-- plus right after you finish a cast (the aura can land a moment later).
do
    local hotEv = CreateFrame("Frame")
    local function Soon() C_Timer.After(0.1, UpdateHots) C_Timer.After(0.5, UpdateHots) end
    hotEv:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            if unit == "player" then Soon() end
        elseif unit and (unit == "player" or unit:match("^party%d$")) then
            pcall(UpdateHots)
        end
    end)
    ns.OnLogin(function()
        if not HOTS[CLASS] then return end
        hotEv:RegisterEvent("UNIT_AURA")
        hotEv:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    end)
end

-- you cast one of your buffs in combat: that slot is done. A group version
-- (not the slot's own spell) covers everyone.
local buffSentTo = {}
local function OnBuffCast(spell)
    local target = buffSentTo[spell]
    buffSentTo[spell] = nil
    for _, h in pairs(holders) do
        if h.combat then
            local ok, name = pcall(UnitName, h.unit)
            local same = ok and name and not isSecret(name) and name == target
            for _, f in ipairs(h.icons) do
                local s = f.slot
                if s and s.buff and (s.buff.names and s.buff.names[spell] or s.cast == spell)
                    and (same or s.cast ~= spell) then
                    s.missing = false
                end
            end
        end
    end
end

local pending = false
local function Queue()
    if pending then return end
    pending = true
    C_Timer.After(0.2, function()
        pending = false
        -- each step on its own: one failing must not stop the others
        if InCombatLockdown() then pcall(PaintCombat) else pcall(Update) end
        pcall(HookPartyAuras)
        pcall(UpdateHots)
    end)
end

function ns.RefreshBuffReminders()
    Resolve()
    Update()
end

-- /ibui buffs test: show every reminder icon regardless of buffs (placement check)
function ns.ToggleBuffTest()
    ns.buffTest = not ns.buffTest
    Resolve()
    Update()
    ns.Print(ns.buffTest and "Buff icons: test mode ON (all icons shown). /ibui buffs test again to stop."
        or "Buff icons: test mode off.")
end

-- for /ibui debug: what the player's own frame checked and found
function ns.BuffStats()
    local parts = { "class=" .. tostring(CLASS), "known=" .. tostring(myBuffs and #myBuffs or 0) }
    for _, b in ipairs(myBuffs or {}) do
        local wants = Wants("player", b.who, GroupHasTank())
        parts[#parts + 1] = ("%s:wants=%s has=%s"):format(tostring(b.cast), tostring(wants),
            tostring(HasBuff("player", b.names)))
    end
    local h = PlayerFrame and holders[PlayerFrame]
    if h then
        parts[#parts + 1] = ("holder shown=%s visible=%s scale=%.2f at=%s,%s"):format(tostring(h:IsShown()),
            tostring(h:IsVisible()), h:GetScale(), tostring(h:GetLeft() and math.floor(h:GetLeft())),
            tostring(h:GetTop() and math.floor(h:GetTop())))
    else
        parts[#parts + 1] = "holder=none"
    end
    -- HoTs: which are tracked, and what each party member has from you
    local hots = {}
    for _, hot in ipairs(myHots or {}) do hots[#hots + 1] = tostring(hot.name) end
    parts[#parts + 1] = "hots=[" .. table.concat(hots, ",") .. "] engine=" .. tostring(engineOK)
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) then
            local on = {}
            for _, hot in ipairs(myHots or {}) do
                local ok, a = pcall(C_UnitAuras.GetAuraDataBySpellName, u, hot.name, "HELPFUL|PLAYER")
                on[#on + 1] = hot.name .. "=" .. (ok and (a and "yes" or "no") or "err")
            end
            parts[#parts + 1] = u .. ":" .. table.concat(on, ",")
        end
    end
    return "buffs(player): " .. table.concat(parts, " ")
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, unit, a2, a3, a4)
    if event == "UNIT_SPELLCAST_SENT" or event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit ~= "player" or not InCombatLockdown() then return end
        local id = event == "UNIT_SPELLCAST_SENT" and a4 or a3
        if not id or isSecret(id) then return end
        local spell = C_Spell.GetSpellName(id)
        if not spell then return end
        if event == "UNIT_SPELLCAST_SENT" then
            local target = a2
            if isSecret(target) or not target or target == "" then target = UnitName("player") end
            buffSentTo[spell] = target
            return
        end
        if buffSentTo[spell] == nil then return end
        pcall(OnBuffCast, spell)
    end
    if event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then Resolve() ResolveHots() end
    if event == "GROUP_ROSTER_UPDATE" and not InCombatLockdown() then wipe(lastHad) end
    if event == "PLAYER_REGEN_DISABLED" then PrepareCombat() return end
    if event == "UNIT_AURA" and unit ~= "player"
        and not (unit and (unit:match("^party%d$") or unit:match("^raid%d+$"))) then return end
    Queue()
end)

ns.OnLogin(function()
    if not (BUFFS[CLASS] or DISPELS[CLASS]) then return end -- nothing for this class
    Resolve()
    ResolveHots()
    for _, e in ipairs({ "UNIT_AURA", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD",
        "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "SPELLS_CHANGED", "UNIT_CONNECTION",
        "UNIT_FLAGS", "PLAYER_ROLES_ASSIGNED", "UNIT_INVENTORY_CHANGED",
        "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    if CompactPartyFrame then CompactPartyFrame:HookScript("OnShow", Queue) end
    Update()
    HookPartyAuras()
    UpdateHots()
end)
