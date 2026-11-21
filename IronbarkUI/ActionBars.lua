-------------------------------------------------------------------------------
--  Ironbark UI - action bars
--    * macro names hidden on buttons (keybinds and counts stay)
--    * gryphons sized to the bar stack
--    * /ibui keybinds  : 1-5 Q E R F Z X Tab, Shift and Ctrl rows (undoable)
--    * /ibui arrange   : your class's bar layout + the Att macro (undoable),
--                        and (druids) ClickLegend's enemy Wrath/Starfire/Moonfire rules
--    * /ibui bars      : dump what's on every action slot (for support)
-------------------------------------------------------------------------------
local _, ns = ...

-------------------------------------------------------------------------------
--  Hide macro names: the name text on every action button goes invisible
--  (alpha only, so Blizzard's own updates never fight it and it's safe in
--  combat). Keybind and count text are untouched.
-------------------------------------------------------------------------------
local BUTTON_PREFIXES = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarRightButton", "MultiBarLeftButton",
    "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
}

function ns.RefreshMacroNames()
    local alpha = ns.db.hideMacroNames and 0 or 1
    for _, prefix in ipairs(BUTTON_PREFIXES) do
        for i = 1, 12 do
            local b = _G[prefix .. i]
            local name = b and (b.Name or _G[prefix .. i .. "Name"])
            if name then name:SetAlpha(alpha) end
        end
    end
end

-------------------------------------------------------------------------------
--  Quieter buttons: keybind text in soft grey always; when a spell is out of
--  range the whole icon turns red (instead of Blizzard's red hotkey text).
--  Colors only, so it's safe in combat. Range answers that are hidden from
--  addons are left to Blizzard.
-------------------------------------------------------------------------------
local isSecretValue = issecretvalue or function() return false end
local HOTKEY_GREY = { 0.6, 0.6, 0.6 }
local OUT_OF_RANGE = { 0.8, 0.15, 0.15 }

local function GreyHotkey(btn)
    local hk = btn.HotKey
    if hk then hk:SetVertexColor(HOTKEY_GREY[1], HOTKEY_GREY[2], HOTKEY_GREY[3]) end
end

local function RangeTint(btn, checksRange, inRange)
    if not btn or isSecretValue(checksRange) or isSecretValue(inRange) then return end
    GreyHotkey(btn)
    local icon = btn.icon or btn.Icon
    if not icon then return end
    if checksRange and inRange == false then
        btn.__ibuiOutOfRange = true
        icon:SetVertexColor(OUT_OF_RANGE[1], OUT_OF_RANGE[2], OUT_OF_RANGE[3])
    elseif btn.__ibuiOutOfRange then
        btn.__ibuiOutOfRange = nil
        -- back in range: let Blizzard put its own usable / out-of-mana color back
        if btn.UpdateUsable then btn:UpdateUsable()
        elseif ActionButton_UpdateUsable then ActionButton_UpdateUsable(btn)
        else icon:SetVertexColor(1, 1, 1) end
    end
end

-- Blizzard re-colors the icon for usable / mana changes; keep it red while out of range
local function KeepRed(btn)
    if btn and btn.__ibuiOutOfRange then
        local icon = btn.icon or btn.Icon
        if icon then icon:SetVertexColor(OUT_OF_RANGE[1], OUT_OF_RANGE[2], OUT_OF_RANGE[3]) end
    end
end

local function HookRange()
    if ActionButton_UpdateRangeIndicator then
        hooksecurefunc("ActionButton_UpdateRangeIndicator", RangeTint)
    end
    if ActionButton_UpdateUsable then hooksecurefunc("ActionButton_UpdateUsable", KeepRed) end
    for _, prefix in ipairs(BUTTON_PREFIXES) do
        for i = 1, 12 do
            local b = _G[prefix .. i]
            if b then
                GreyHotkey(b)
                if type(b.UpdateRangeIndicator) == "function" then hooksecurefunc(b, "UpdateRangeIndicator", RangeTint) end
                if type(b.UpdateUsable) == "function" then hooksecurefunc(b, "UpdateUsable", KeepRed) end
                if type(b.UpdateHotkeys) == "function" then hooksecurefunc(b, "UpdateHotkeys", GreyHotkey) end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Keybind scheme (one-time, on request): the three stacked bars get
--    Action Bar 1  1 2 3 4 5 Q E R F Z X Tab
--    Bar 2         SHIFT- the same
--    Bar 3         CTRL-  the same
--  Every binding touched (the keys, and old keys on those buttons) is backed
--  up first; /ibui keybinds undo restores them. Not allowed in combat.
-------------------------------------------------------------------------------
local KEYS = { "1", "2", "3", "4", "5", "Q", "E", "R", "F", "Z", "X", "TAB" }
local ROWS = {
    { prefix = "",       command = "ACTIONBUTTON%d" },           -- Action Bar 1
    { prefix = "SHIFT-", command = "MULTIACTIONBAR1BUTTON%d" },  -- Bar 2 (bottom left)
    { prefix = "CTRL-",  command = "MULTIACTIONBAR2BUTTON%d" },  -- Bar 3 (bottom right)
}

local function SaveBinds()
    local set = GetCurrentBindingSet and GetCurrentBindingSet() or 2
    SaveBindings(set)
end

function ns.ApplyKeybinds()
    if InCombatLockdown() then return ns.Print("Can't change keybinds in combat.") end
    local backup = { keys = {}, commands = {} }
    -- 1. remember and clear old keys on the buttons we're rebinding
    for _, row in ipairs(ROWS) do
        for i = 1, #KEYS do
            local cmd = row.command:format(i)
            local old = { GetBindingKey(cmd) }
            backup.commands[cmd] = old
            -- keep mouse-button binds (e.g. Mouse 4/5 on the middle bar)
            for _, k in ipairs(old) do
                if not k:find("BUTTON%d") then SetBinding(k) end
            end
        end
    end
    -- 2. remember what the new keys did, then bind them
    for _, row in ipairs(ROWS) do
        for i, key in ipairs(KEYS) do
            local full = row.prefix .. key
            if backup.keys[full] == nil then backup.keys[full] = GetBindingAction(full) or "" end
            SetBinding(full, row.command:format(i))
        end
    end
    SaveBinds()
    ns.db.keybindBackup = ns.db.keybindBackup or backup -- keep the oldest backup
    ns.Print("Keybinds set: top 1-5 Q E R F Z X Tab, middle Shift, bottom Ctrl. /ibui keybinds undo to revert.")
end

function ns.UndoKeybinds()
    local b = ns.db.keybindBackup
    if not b then return ns.Print("No keybind backup to restore.") end
    if InCombatLockdown() then return ns.Print("Can't change keybinds in combat.") end
    -- clear what we set, then put the old keys back on their old actions
    for key in pairs(b.keys) do SetBinding(key) end
    for key, action in pairs(b.keys) do
        if action ~= "" then SetBinding(key, action) end
    end
    for cmd, keys in pairs(b.commands) do
        for _, k in ipairs(keys) do SetBinding(k, cmd) end
    end
    SaveBinds()
    ns.db.keybindBackup = nil
    ns.Print("Keybinds restored.")
end

-------------------------------------------------------------------------------
--  /ibui bars: record what's on every action slot (spell / item / macro) into
--  IronbarkUIDB.barDump, readable from SavedVariables after a /reload.
--  Slot ranges (druid): 1-12 Action Bar 1, 13-24 its page 2, 25-36 Right,
--  37-48 Right 2, 49-60 Bottom Right (Bar 3), 61-72 Bottom Left (Bar 2),
--  73-84 Cat, 85-96 Prowl, 97-108 Bear, 109-120 Moonkin.
-------------------------------------------------------------------------------
local SLOT_GROUPS = {
    { 1, "Bar1" }, { 13, "Bar1 page2" }, { 25, "Right" }, { 37, "Right2" },
    { 49, "Bar3 (bottom)" }, { 61, "Bar2 (middle)" }, { 73, "Cat" },
    { 85, "Prowl" }, { 97, "Bear" }, { 109, "Moonkin" },
}

function ns.DumpBars()
    local out = {}
    for _, g in ipairs(SLOT_GROUPS) do
        local parts = {}
        for i = 0, 11 do
            local slot = g[1] + i
            local kind, id = GetActionInfo(slot)
            local name
            if kind == "spell" then
                name = C_Spell.GetSpellName(id)
            elseif kind == "item" then
                name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id) or ("item " .. tostring(id))
            elseif kind == "macro" then
                name = "macro: " .. tostring(GetActionText(slot) or id)
            elseif kind then
                name = kind
            end
            if name then parts[#parts + 1] = (i + 1) .. "=" .. name end
        end
        if #parts > 0 then out[#out + 1] = g[2] .. ": " .. table.concat(parts, ", ") end
    end
    ns.db.barDump = out
    for _, line in ipairs(out) do print("|cff8fbc5aIBUI|r " .. line) end
    ns.Print("Saved. /reload so it can be read from SavedVariables.")
end

-------------------------------------------------------------------------------
--  /ibui arrange: place your class's layout onto the three stacked bars (and
--  its stance / form / stealth pages). Out of combat only.
--    top row (1-5 Q E R F Z X Tab): main attacks / heals; F Z X = stance or
--      form keys where the class has them (on every page, so the same key goes
--      in and out); Tab = Att (target + auto-attack) or Shoot (wand casters)
--    Shift row: buffs, utility, cooldowns
--    Ctrl row: hearthstone, professions, pet (packed: whatever you have)
--  Spells you haven't learned yet are skipped (their slot is left as it is);
--  "a / b" entries take the first one you know.
--
--  Sources, in order: spellbook (highest rank) / bags / the Att macro by
--  name; for things with no other source (pet summons, equipped items) the
--  slot they already sit on. Before changing anything every slot 1-120 is
--  recorded; /ibui arrange undo puts it all back.
-------------------------------------------------------------------------------
local ATT_NAME = "Att"
local ATT_BODY = "#showtooltip 16\n/targetenemy\n/startattack"
local ATT_ICON = 134400 -- the "?" icon, so #showtooltip shows the weapon / spell

-- Damage spells (for the ClickLegend conversion below).
local ATTACK_SPELLS = { "Wrath", "Moonfire", "Starfire" }
-- name -> { body, spell (for the icon), ours (we may update it) }
local MACROS = { [ATT_NAME] = { body = ATT_BODY } }
-- Wrath / Moonfire / Starfire go on the bars as plain spells: press-and-hold
-- casting only repeats real spells, not macros. (ClickLegend's mouse rules for
-- them still start auto-attack; Att does it from the keyboard.)

-- slot = first slot of the bar; entries: { "spell"|"item"|"macro"|"pet", name }
-- (name may be a list: the first one you have). false = leave that button
-- empty. pack = true: what you have is placed side by side, the rest skipped
-- quietly (professions differ per character).
-- Bar slots: 1-12 top row, 61-72 Shift row, 49-60 Ctrl row; stance / form
-- pages replace the top row: 73-84, 85-96, 97-108.
local function S(name) return { "spell", name } end
local function I(name) return { "item", name } end
local ATT, SHOOT = { "macro", ATT_NAME }, { "spell", "Shoot" }

-- the Ctrl row for every class but the druid (who has its own below)
local CTRL_ROW = { slot = 49, pack = true, list = {
    I("Hearthstone"), S("First Aid"), S("Cooking"), S("Fishing"), S("Find Herbs"), S("Find Minerals"),
    S("Smelting"), S("Disenchant"), S("Alchemy"), S("Blacksmithing"), S("Enchanting"), S("Engineering"),
    S("Leatherworking"), S("Tailoring"), { "pet" },
} }

local LAYOUTS = {
    DRUID = {
        { slot = 1, list = { -- Action Bar 1 (top, no modifier)
            S("Wrath"), S("Moonfire"), S("Starfire"),
            S("Healing Touch"), S("Regrowth"), S("Rejuvenation"),
            S("Entangling Roots"), S("Nature's Grasp"), S("Bear Form"),
            S("Cat Form"), false, ATT,
        } },
        { slot = 61, list = { -- Bar 2 (middle, Shift)
            S("Mark of the Wild"), S("Thorns"), S("Remove Curse"),
            S("Cure Poison"), S("Rebirth"), S("Hibernate"),
            S("Revive"), S("Skysight"), S("Faerie Fire"),
            S("Walk on Air"), S("Teleport: Moonglade"), I("Hearthstone"),
        } },
        { slot = 49, list = { -- Bar 3 (bottom, Ctrl)
            I("Minor Healthstone"), I("Minor Mana Potion"), I("Conjured Purified Water"),
            I("Refreshing Spring Water"), I("Shiny Red Apple"), I("Melon Juice"),
            S("First Aid"), S("Cooking"), I("Fishing Pole"),
            S("Skinning"), { "pet" }, S("Leatherworking"),
        } },
        { slot = 108, list = { ATT } }, -- Bear page, button 12
        { slot = 84,  list = { ATT } }, -- Cat page, button 12
        -- Form keys on every form page: F (button 9) = Bear, Z (10) = Cat.
        -- Your current form's key drops you to caster; the other shifts directly.
        { slot = 105, list = { S("Bear Form"), S("Cat Form") } }, -- Bear page
        { slot = 81,  list = { S("Bear Form"), S("Cat Form") } }, -- Cat page
        { slot = 93,  list = { S("Bear Form"), S("Cat Form") } }, -- Prowl page
    },

    -- Warriors are always in a stance, so each stance page is a full bar.
    -- F / Z / X = Battle / Defensive / Berserker Stance on every page.
    WARRIOR = {
        { slot = 73, list = { -- Battle Stance
            S("Heroic Strike"), S("Rend"), S("Overpower"), S("Thunder Clap"), S("Hamstring"),
            S("Charge"), S("Mocking Blow"), S("Execute"),
            S("Battle Stance"), S("Defensive Stance"), S("Berserker Stance"), ATT,
        } },
        { slot = 85, list = { -- Defensive Stance
            S("Heroic Strike"), S("Sunder Armor"), S("Revenge"), S("Shield Block"), S("Shield Bash"),
            S("Taunt"), S("Shield Wall"), S("Disarm"),
            S("Battle Stance"), S("Defensive Stance"), S("Berserker Stance"), ATT,
        } },
        { slot = 97, list = { -- Berserker Stance
            S("Heroic Strike"), S("Whirlwind"), S("Bloodthirst"), S("Execute"), S("Hamstring"),
            S("Intercept"), S("Pummel"), S("Berserker Rage"),
            S("Battle Stance"), S("Defensive Stance"), S("Berserker Stance"), ATT,
        } },
        { slot = 1, list = { -- no stance (rare): same as Battle
            S("Heroic Strike"), S("Rend"), S("Overpower"), S("Thunder Clap"), S("Hamstring"),
            S("Charge"), S("Mocking Blow"), S("Execute"),
            S("Battle Stance"), S("Defensive Stance"), S("Berserker Stance"), ATT,
        } },
        { slot = 61, list = {
            S("Battle Shout"), S("Demoralizing Shout"), S("Bloodrage"), S("Intimidating Shout"),
            S("Cleave"), S("Sweeping Strikes"), S("Mortal Strike"), S("Slam"),
            S("Piercing Howl"), S("Challenging Shout"), S("Retaliation"), S("Recklessness"),
        } },
        CTRL_ROW,
    },

    -- Stealth swaps in its own page. F = Stealth, Z = Evasion, X = Vanish on both.
    ROGUE = {
        { slot = 1, list = {
            S("Sinister Strike"), S("Eviscerate"), S("Slice and Dice"), S("Backstab"), S("Gouge"),
            S("Kick"), S("Kidney Shot"), S("Sprint"),
            S("Stealth"), S("Evasion"), S("Vanish"), ATT,
        } },
        { slot = 73, list = { -- Stealth page
            S("Cheap Shot"), S("Ambush"), S("Garrote"), S("Sap"), S("Pick Pocket"),
            S("Distract"), S("Premeditation"), S("Sprint"),
            S("Stealth"), S("Evasion"), S("Vanish"), ATT,
        } },
        { slot = 61, list = {
            S("Expose Armor"), S("Rupture"), S("Feint"), S("Blind"), S("Riposte"), S("Ghostly Strike"),
            S("Hemorrhage"), S("Cold Blood"), S("Adrenaline Rush"), S("Blade Flurry"), S("Preparation"),
            S("Pick Lock"),
        } },
        CTRL_ROW,
    },

    -- F / Z = Aspect of the Hawk / Monkey, X = Feign Death. The pet has its own bar.
    HUNTER = {
        { slot = 1, list = {
            S("Auto Shot"), S("Serpent Sting"), S("Arcane Shot"), S("Multi-Shot"), S("Aimed Shot"),
            S("Concussive Shot"), S("Raptor Strike"), S("Wing Clip"),
            S("Aspect of the Hawk"), S("Aspect of the Monkey"), S("Feign Death"), ATT,
        } },
        { slot = 61, list = {
            S("Hunter's Mark"), S("Mend Pet"), S("Call Pet"), S("Revive Pet"), S("Feed Pet"),
            S("Dismiss Pet"), S("Aspect of the Cheetah"), S("Aspect of the Pack"),
            S("Freezing Trap"), S("Immolation Trap"), S("Frost Trap"), S("Rapid Fire"),
        } },
        CTRL_ROW,
    },

    MAGE = {
        { slot = 1, list = {
            S("Frostbolt"), S("Fireball"), S("Fire Blast"), S("Arcane Missiles"), S("Frost Nova"),
            S("Counterspell"), S("Polymorph"), S("Blink"),
            S("Cone of Cold"), S("Arcane Explosion"), S("Ice Block"), SHOOT,
        } },
        { slot = 61, list = {
            S("Arcane Intellect"), S({ "Mage Armor", "Ice Armor", "Frost Armor" }), S("Mana Shield"),
            S("Remove Lesser Curse"), S("Evocation"), S("Conjure Water"), S("Conjure Food"),
            S({ "Conjure Mana Ruby", "Conjure Mana Citrine", "Conjure Mana Jade", "Conjure Mana Agate" }),
            S("Dampen Magic"), S("Amplify Magic"), S("Slow Fall"), S("Blizzard"),
        } },
        CTRL_ROW,
    },

    -- Shadowform swaps in its own page. F = Shadowform on both, X = Fade.
    PRIEST = {
        { slot = 1, list = {
            S("Smite"), S("Shadow Word: Pain"), S("Mind Blast"), S("Renew"), S("Flash Heal"),
            S("Power Word: Shield"), S({ "Greater Heal", "Heal", "Lesser Heal" }), S("Psychic Scream"),
            S("Shadowform"), S("Holy Fire"), S("Fade"), SHOOT,
        } },
        { slot = 73, list = { -- Shadowform page
            S("Mind Flay"), S("Shadow Word: Pain"), S("Mind Blast"), S("Vampiric Embrace"), S("Devouring Plague"),
            S("Power Word: Shield"), S("Silence"), S("Psychic Scream"),
            S("Shadowform"), S("Mind Control"), S("Fade"), SHOOT,
        } },
        { slot = 61, list = {
            S("Power Word: Fortitude"), S("Inner Fire"), S("Divine Spirit"), S("Shadow Protection"),
            S("Dispel Magic"), S({ "Abolish Disease", "Cure Disease" }), S("Resurrection"),
            S("Prayer of Healing"), S("Prayer of Fortitude"), S("Inner Focus"), S("Levitate"),
            S("Shackle Undead"),
        } },
        CTRL_ROW,
    },

    WARLOCK = {
        { slot = 1, list = {
            S("Shadow Bolt"), S("Corruption"), S("Curse of Agony"), S("Immolate"), S("Drain Life"),
            S("Fear"), S("Death Coil"), S("Howl of Terror"),
            S("Life Tap"), S("Drain Soul"), S("Searing Pain"), SHOOT,
        } },
        { slot = 61, list = {
            S({ "Demon Armor", "Demon Skin" }), S("Summon Imp"), S("Summon Voidwalker"), S("Summon Succubus"),
            S("Summon Felhunter"), S("Health Funnel"),
            S({ "Create Healthstone (Major)", "Create Healthstone (Greater)", "Create Healthstone",
                "Create Healthstone (Lesser)", "Create Healthstone (Minor)" }),
            S({ "Create Soulstone (Major)", "Create Soulstone (Greater)", "Create Soulstone",
                "Create Soulstone (Lesser)", "Create Soulstone (Minor)" }),
            S("Curse of Weakness"), S("Curse of Recklessness"), S("Banish"), S("Ritual of Summoning"),
        } },
        CTRL_ROW,
    },

    PALADIN = {
        { slot = 1, list = {
            S("Seal of Righteousness"), S("Judgement"), S("Holy Light"), S("Flash of Light"),
            S("Hammer of Justice"), S("Seal of the Crusader"), S({ "Divine Shield", "Divine Protection" }),
            S("Lay on Hands"), S("Consecration"), S("Exorcism"), S("Holy Shock"), ATT,
        } },
        { slot = 61, list = {
            S("Blessing of Might"), S("Blessing of Wisdom"), S("Blessing of Kings"), S("Blessing of Salvation"),
            S("Blessing of Protection"), S("Blessing of Freedom"), S({ "Cleanse", "Purify" }), S("Redemption"),
            S("Devotion Aura"), S("Retribution Aura"), S("Concentration Aura"), S("Righteous Fury"),
        } },
        CTRL_ROW,
    },

    SHAMAN = {
        { slot = 1, list = {
            S("Lightning Bolt"), S("Earth Shock"), S("Flame Shock"), S("Healing Wave"), S("Lesser Healing Wave"),
            S("Frost Shock"), S("Chain Lightning"), S("Chain Heal"),
            S("Stormstrike"), S("Purge"), S("Ghost Wolf"), ATT,
        } },
        { slot = 61, list = {
            S({ "Windfury Weapon", "Flametongue Weapon", "Frostbrand Weapon", "Rockbiter Weapon" }),
            S("Lightning Shield"), S("Searing Totem"), S("Stoneskin Totem"), S("Strength of Earth Totem"),
            S("Mana Spring Totem"), S("Healing Stream Totem"), S("Windfury Totem"), S("Grace of Air Totem"),
            S("Tremor Totem"), S({ "Cure Poison", "Cure Disease" }), S("Ancestral Spirit"),
        } },
        CTRL_ROW,
    },
}

function ns.HasArrangeLayout()
    local _, class = UnitClass("player")
    return LAYOUTS[class] ~= nil
end

-- Create any of our macros that don't exist yet (account-wide). Existing ones,
-- like your own Att, are left exactly as they are.
local function MacroIcon(m)
    if m.spell then
        local tex = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(m.spell)
        if tex then return tex end
    end
    return ATT_ICON
end

local function EnsureMacros(onlyExisting)
    for name, m in pairs(MACROS) do
        local icon = MacroIcon(m)
        local idx = GetMacroIndexByName(name)
        if idx == 0 and onlyExisting then
            -- leave missing ones alone until /ibui arrange
        elseif idx == 0 then
            local ok = pcall(CreateMacro, name, icon, m.body, nil)
            if ok and GetMacroIndexByName(name) > 0 then
                ns.Print("Created macro %s.", name)
            else
                ns.Print("Couldn't create macro %s (macro slots full?).", name)
            end
        elseif m.ours then
            -- keep our own macros current (icon + text); never touch yours
            local _, curIcon, curBody = GetMacroInfo(idx)
            if curBody ~= m.body or curIcon ~= icon then
                pcall(EditMacro, idx, name, icon, m.body)
            end
        end
    end
end

-------------------------------------------------------------------------------
--  ClickLegend: if it's loaded, its enemy rules for Wrath / Starfire /
--  Moonfire become macro text that also starts auto-attack. ClickLegend only
--  allows text rules without conditions (the conditions go inside the text),
--  and nothing after such a rule can fire, so the rules that followed (a plain
--  Target or Menu) are folded into the text, behind a /stopmacro. Keys with
--  anything else after the enemy rule, or with "else my target", are skipped.
-------------------------------------------------------------------------------
local ATTACK_SET = {}
for _, s in ipairs(ATTACK_SPELLS) do ATTACK_SET[s] = true end

local function DeepCopy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = DeepCopy(v) end
    return c
end

local function ClickLegendSet()
    local db, char = _G.ClickLegendCastDB, _G.ClickLegendCharDB
    local name = char and char.cast and char.cast.set
    local set = db and db.sets and name and db.sets[name]
    return set, name
end

local function ConvertClickLegend()
    local set, setName = ClickLegendSet()
    if not (set and set.bindings) then return 0, {} end
    local changed, skipped = 0, {}
    for bi, binding in ipairs(set.bindings) do
        local rules = binding.rules or {}
        for ri, rule in ipairs(rules) do
            local a, w = rule.action or {}, rule.when or {}
            if a.type == "spell" and ATTACK_SET[a.name] and w.reaction == "harm" and not w.unit then
                -- what follows must be plain Target / Menu rules we can fold in
                local tail, ok = {}, not binding.orTarget
                for k = ri + 1, #rules do
                    local t, tw = rules[k].action and rules[k].action.type, rules[k].when or {}
                    if (t == "target" or t == "menu") and next(tw) == nil then
                        tail[#tail + 1] = t
                    else
                        ok = false
                    end
                end
                if not ok then
                    skipped[#skipped + 1] = (binding.key or "?") .. " (" .. a.name .. ")"
                else
                    ns.db.clickLegendBackup = ns.db.clickLegendBackup or { set = setName, bindings = {} }
                    if not ns.db.clickLegendBackup.bindings[bi] then
                        ns.db.clickLegendBackup.bindings[bi] = DeepCopy(binding.rules)
                    end
                    local c = "[@mouseover,harm]"
                    local lines = {
                        "/startattack " .. c,
                        "/target " .. c,
                        "/cast " .. c .. " " .. a.name,
                    }
                    if #tail > 0 then lines[#lines + 1] = "/stopmacro " .. c end
                    for _, t in ipairs(tail) do
                        lines[#lines + 1] = (t == "target") and "/target [@mouseover,exists]"
                            or "/click [@mouseover,exists] {menu}"
                    end
                    local new = {}
                    for k = 1, ri - 1 do new[k] = rules[k] end
                    new[ri] = { when = {}, action = { type = "text", text = table.concat(lines, "\n") } }
                    binding.rules = new
                    changed = changed + 1
                end
                break
            end
        end
    end
    return changed, skipped
end

local function RestoreClickLegend()
    local b = ns.db.clickLegendBackup
    if not b then return false end
    local db = _G.ClickLegendCastDB
    local set = db and db.sets and db.sets[b.set]
    if set and set.bindings then
        for bi, rules in pairs(b.bindings) do
            if set.bindings[bi] then set.bindings[bi].rules = DeepCopy(rules) end
        end
    end
    ns.db.clickLegendBackup = nil
    return true
end

StaticPopupDialogs["IRONBARKUI_RELOAD"] = {
    text = "%s\n\nReload now so it takes effect?",
    button1 = RELOADUI or "Reload",
    button2 = CANCEL,
    OnAccept = function() ReloadUI() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- what's on a slot, by name (for finding things that only exist on a bar)
local function SlotName(slot)
    local kind, id = GetActionInfo(slot)
    if kind == "spell" then return kind, C_Spell.GetSpellName(id) end
    if kind == "item" then return kind, C_Item.GetItemNameByID(id) end
    if kind == "macro" then return kind, GetActionText(slot) end
    return kind
end

local function FindOnBars(kind, name, avoid)
    for slot = 1, 120 do
        if not avoid[slot] then
            local k, n = SlotName(slot)
            if k and (kind == "pet" and (k == "summonpet" or k == "companion") or (k == kind and n == name)) then
                return slot
            end
        end
    end
end

local function BagItemID(name)
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and C_Item.GetItemNameByID(info.itemID) == name then return info.itemID end
        end
    end
end

local PickupSpellFn = (C_Spell and C_Spell.PickupSpell) or PickupSpell
local PickupItemFn = (C_Item and C_Item.PickupItem) or PickupItem

-- puts the wanted thing on the cursor; returns true + the name it took (an
-- entry's name may be a list of alternatives: the first one you have)
local function PickOne(kind, name, avoid)
    ClearCursor()
    if kind == "spell" then
        -- by name resolves to your highest known rank; unknown spells pick up nothing
        local info = C_Spell.GetSpellInfo(name)
        if info and info.spellID and (not IsPlayerSpell or IsPlayerSpell(info.spellID)
            or (IsSpellKnown and IsSpellKnown(info.spellID))) then
            PickupSpellFn(info.spellID)
        end
    elseif kind == "item" then
        local id = BagItemID(name)
        if id then PickupItemFn(id) end
    elseif kind == "macro" then
        local idx = GetMacroIndexByName(name)
        if idx > 0 then PickupMacro(idx) end
    end
    if GetCursorInfo() then return true end
    -- no other source: take it from wherever it already sits on a bar
    local from = FindOnBars(kind, name, avoid)
    if from then
        PickupAction(from)
        return GetCursorInfo() ~= nil
    end
    return false
end

local function PickUp(entry, avoid)
    local kind, name = entry[1], entry[2]
    if type(name) == "table" then
        for _, n in ipairs(name) do
            if PickOne(kind, n, avoid) then return true, n end
        end
        return false
    end
    return PickOne(kind, name, avoid), name
end

local function EntryLabel(entry)
    local n = entry[2]
    if type(n) == "table" then return table.concat(n, " / ") end
    return n or "pet summon"
end

local function Snapshot()
    local snap = {}
    for slot = 1, 120 do
        local kind, id, sub = GetActionInfo(slot)
        if kind then snap[slot] = { kind = kind, id = id, sub = sub } end
    end
    return snap
end

function ns.Arrange(quiet) -- quiet: no reload prompt (the setup flow reloads once at the end)
    if InCombatLockdown() then return ns.Print("Can't arrange bars in combat.") end
    local _, class = UnitClass("player")
    local layout = LAYOUTS[class]
    if not layout then
        return ns.Print("/ibui arrange has no layout for your class; your bars weren't touched.")
    end
    EnsureMacros()
    if not ns.db.arrangeBackup then ns.db.arrangeBackup = Snapshot() end -- keep the original

    -- slots we're about to fill: never pull a source from one we've already placed
    local placed, placedName, missing = {}, {}, {}
    for _, group in ipairs(layout) do
        local nextSlot = group.slot
        for i, entry in ipairs(group.list) do
            local slot = group.pack and nextSlot or (group.slot + i - 1)
            if group.pack and slot > group.slot + 11 then break end
            if entry == false then
                PickupAction(slot)
                ClearCursor()
            else
                local ok, name = PickUp(entry, placed)
                if ok then
                    PlaceAction(slot)
                    ClearCursor() -- whatever was there before is dropped
                    placed[slot], placedName[slot] = entry, name
                    nextSlot = nextSlot + 1
                elseif not group.pack then
                    missing[#missing + 1] = EntryLabel(entry)
                end
            end
        end
    end
    ClearCursor()

    -- read every slot back: anything that didn't land gets named
    local notPlaced = {}
    for slot, entry in pairs(placed) do
        local kind, name = SlotName(slot)
        local want = entry[1] == "pet" and (kind == "summonpet" or kind == "companion")
            or (kind == entry[1] and name == placedName[slot])
        if not want then notPlaced[#notPlaced + 1] = EntryLabel(entry) .. " (slot " .. slot .. ")" end
    end

    if #missing > 0 then ns.Print("Not learned / not found yet (slot left as it was): %s", table.concat(missing, ", ")) end
    if #notPlaced > 0 then ns.Print("Not placed: %s", table.concat(notPlaced, ", ")) end
    local keys = {
        DRUID = "F = Bear, Z = Cat on every form page.",
        WARRIOR = "F / Z / X = Battle / Defensive / Berserker Stance on every stance page.",
        ROGUE = "F = Stealth (its own page), Z = Evasion, X = Vanish.",
        PRIEST = "F = Shadowform (its own page), X = Fade.",
        HUNTER = "F / Z = Aspect of the Hawk / Monkey, X = Feign Death.",
    }
    ns.Print("Arranged. %s /ibui arrange undo to put your old bars back.", keys[class] or "")

    -- ClickLegend: same auto-attack for its enemy Wrath / Starfire / Moonfire
    if class ~= "DRUID" then return end
    local changed, skipped = ConvertClickLegend()
    if #skipped > 0 then
        ns.Print("ClickLegend keys left as they were: %s", table.concat(skipped, ", "))
    end
    if changed > 0 and not quiet then
        StaticPopup_Show("IRONBARKUI_RELOAD",
            ("Updated %d ClickLegend key(s) so Wrath / Starfire / Moonfire also start auto-attack."):format(changed))
    end
end

function ns.UndoArrange(quiet)
    local snap = ns.db.arrangeBackup
    if InCombatLockdown() then return ns.Print("Can't arrange bars in combat.") end
    if not snap then
        if RestoreClickLegend() then
            if not quiet then StaticPopup_Show("IRONBARKUI_RELOAD", "Your ClickLegend keys were put back.") end
        else
            ns.Print("No saved bars to restore.")
        end
        return
    end
    local failed = 0
    for slot = 1, 120 do
        local s = snap[slot]
        ClearCursor()
        if s then
            if s.kind == "spell" then PickupSpellFn(s.id)
            elseif s.kind == "item" then PickupItemFn(s.id)
            elseif s.kind == "macro" then PickupMacro(s.id)
            elseif s.kind == "summonpet" and C_PetJournal then C_PetJournal.PickupPet(s.id)
            end
            if GetCursorInfo() then
                PlaceAction(slot)
            else
                failed = failed + 1
            end
        elseif GetActionInfo(slot) then
            PickupAction(slot)
        end
        ClearCursor()
    end
    ns.db.arrangeBackup = nil
    ns.Print(failed > 0 and ("Bars restored (%d buttons couldn't be put back)."):format(failed) or "Bars restored.")
    if RestoreClickLegend() then
        if not quiet then StaticPopup_Show("IRONBARKUI_RELOAD", "Your ClickLegend keys were put back.") end
    end
end

StaticPopupDialogs["IRONBARKUI_ARRANGE"] = {
    text = "Arrange your bars into the Ironbark layout for your class?\n\nYour current bars are saved first; /ibui arrange undo restores them.",
    button1 = ACCEPT,
    button2 = CANCEL,
    OnAccept = function() ns.Arrange() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["IRONBARKUI_KEYBINDS"] = {
    text = "Rebind your bars?\n\nTop: 1-5 Q E R F Z X Tab\nMiddle: Shift + same\nBottom: Ctrl + same\n\nReplaces those keys (including Q/E strafe). Mouse-button binds are kept. /ibui keybinds undo reverts.",
    button1 = ACCEPT,
    button2 = CANCEL,
    OnAccept = function() ns.ApplyKeybinds() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-------------------------------------------------------------------------------
--  Bigger gryphons. Each end cap is its own frame (and Edit Mode system on
--  this client); scale it, remembering whatever scale Blizzard last set so we
--  multiply that rather than compounding. Art only: safe in combat.
-------------------------------------------------------------------------------
local function EndCaps()
    local bar = MainActionBar or MainMenuBar
    local caps = bar and bar.EndCaps
    return caps and caps.LeftEndCap, caps and caps.RightEndCap
end

-- Top of Action Bar 1 as you see it (its outline art if shown, else its
-- buttons), in UIParent units.
local function TopBarTop()
    local ui = UIParent:GetEffectiveScale()
    local top
    local function add(f)
        if f and f:IsVisible() and f:GetTop() then
            local t = f:GetTop() * f:GetEffectiveScale() / ui
            top = top and math.max(top, t) or t
        end
    end
    for i = 1, 12 do add(_G["ActionButton" .. i]) end
    local bar = MainActionBar
    if bar and bar.BorderArt then add(bar.BorderArt) end
    return top
end

-- Scale that makes the cap reach from its feet to the top of Action Bar 1.
-- Two passes: the anchor offset scales with the frame, moving the feet a hair.
local function FitScale(cap)
    local top = TopBarTop()
    if not top then return nil end
    local ui = UIParent:GetEffectiveScale()
    local scale = cap:GetScale()
    for _ = 1, 2 do
        local bottom, h = cap:GetBottom(), cap:GetHeight()
        if not (bottom and h and h > 0) then return nil end
        local eff = cap:GetEffectiveScale() / ui
        local want = top - bottom * eff
        if want <= 0 then return nil end
        scale = scale * want / (h * eff)
        cap.__ibuiSetting = true
        cap:SetScale(scale)
        cap.__ibuiSetting = nil
    end
    return scale
end

local function ScaleCap(cap)
    if not cap then return end
    if cap:IsProtected() and InCombatLockdown() then
        ns.RunOutOfCombat("gryphons", ns.RefreshGryphons)
        return
    end
    if cap.__ibuiBase == nil then cap.__ibuiBase = cap:GetScale() end
    if ns.db.gryphonFit and FitScale(cap) then return end
    cap.__ibuiSetting = true
    cap:SetScale(cap.__ibuiBase * (ns.db.gryphonScale or 1))
    cap.__ibuiSetting = nil
end

function ns.RefreshGryphons()
    for _, cap in ipairs({ EndCaps() }) do
        if cap and not cap.__ibuiScaleHook then
            cap.__ibuiScaleHook = true
            -- Blizzard set a new scale: take it as the base and re-apply ours
            hooksecurefunc(cap, "SetScale", function(self, s)
                if self.__ibuiSetting then return end
                self.__ibuiBase = s
                ScaleCap(self)
            end)
        end
        ScaleCap(cap)
    end
    -- refit whenever the bars may have moved
    if not ns.__gryphonEvents then
        ns.__gryphonEvents = true
        local ev = CreateFrame("Frame")
        ev:RegisterEvent("PLAYER_ENTERING_WORLD")
        ev:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
        ev:RegisterEvent("UI_SCALE_CHANGED")
        ev:SetScript("OnEvent", function() C_Timer.After(0.2, ns.RefreshGryphons) end)
        local emf = EditModeManagerFrame
        if emf then emf:HookScript("OnHide", function() C_Timer.After(0.2, ns.RefreshGryphons) end) end
    end
end

-- Earlier versions put "IB Wrath / Moonfire / Starfire" macros on the bars.
-- Swap each for the real spell (so press-and-hold works); the macros
-- themselves stay in your macro list.
local function SwapIBMacros()
    if InCombatLockdown() then return end
    local swapped = 0
    for slot = 1, 120 do
        local kind, name = SlotName(slot)
        local spell = kind == "macro" and name and name:match("^IB (%a+)$")
        if spell and ATTACK_SET[spell] then
            local info = C_Spell.GetSpellInfo(spell)
            ClearCursor()
            if info and info.spellID then PickupSpellFn(info.spellID) end
            if GetCursorInfo() then
                PlaceAction(slot)
                swapped = swapped + 1
            end
            ClearCursor()
        end
    end
    if swapped > 0 then
        ns.Print("Wrath / Moonfire / Starfire are now plain spells on your bars, so holding the key keeps casting.")
    end
end

ns.OnLogin(function()
    ns.RefreshMacroNames()
    HookRange()
    ns.RefreshGryphons()
    if not InCombatLockdown() then pcall(SwapIBMacros) end
end)
