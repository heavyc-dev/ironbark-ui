-------------------------------------------------------------------------------
--  Ironbark UI - Core
--  Namespace, saved settings, combat-safe queue, slash commands.
-------------------------------------------------------------------------------
local ADDON, ns = ...
_G.IronbarkUI = ns

ns.LAYOUT_NAME = "Ironbark UI"

-- Defaults for per-account settings. Layout data lives in Presets.lua.
-- Defaults. Only a handful are switches in the options panel; the rest are
-- simply how Ironbark behaves (kept as settings so code reads clearly).
ns.defaults = {
    -- options panel
    manageUIScale     = true,     -- Ironbark sets the game's UI scale
    uiScale           = 0.64,     -- that scale (slider; capped by ns.MaxUIScale)
    classColors       = true,     -- class-colored health on player/target/focus/party
    compactText       = true,     -- "961 | 100%" health/power text (mouseover + combat)
    tooltipCursor     = true,     -- tooltips follow the mouse
    tooltipCombatHide = true,     -- combat: no friendly-unit / action button tooltips (Alt shows one)
    castBarAlways     = true,     -- empty cast bar frame stays on screen between casts
    buffReminders     = true,     -- missing-buff icons on you, party and raid frames
    buffCombat        = true,     -- ...kept up (and clickable) in combat
    hotIcons          = true,     -- your HoTs under the left side of party frames
    hotBars           = true,     -- healing your HoTs still owe, drawn past the end of health bars
    combinedBags      = true,     -- one bag window
    chatPolish        = true,     -- master switch for every chat* below
    chatAutoHide      = true,     -- chat fades away 30s after the last activity that matters
    questTracker      = true,     -- Ironbark's own quest tracker
    gatherPopups      = true,     -- "Light Leather +2 (14)" mid-screen when you gather
    minimapCollect    = true,     -- addon minimap buttons in one slide-out button
    meters            = true,     -- small damage + healing meters (instances / combat only)
    meterSession      = "overall", -- meters: "overall" (since reset) or "current" (this fight)

    -- fixed behavior
    hideMacroNames    = true,     -- no macro name text on action buttons
    gryphonFit        = true,     -- gryphons reach from the bottom bar to the top of Action Bar 1
    gryphonScale      = 1.3,      -- gryphon size if fitting isn't possible
    natureColors      = true,     -- cast bar colored by spell type, moonlight mana spark
    manaRegenSweep    = true,     -- 5-second-rule spark on the player mana bar
    buffGlow          = true,     -- pulsing glow on missing-buff icons
    nameplateTweaks   = true,     -- class colors, stacking, fade on Blizzard plates
    classTheme        = true,     -- class crest as the bag window portrait
    bagView           = "bags",   -- "bags" = real slot order, "sections" = grouped
    bagBarOpen        = false,    -- bag bar next to the micro menu starts collapsed
    chatShortTags     = true,     -- [T] [G] [P] instead of long channel names
    chatHideButtons   = true,     -- side buttons on mouseover only
    chatClearBg       = true,     -- background on mouseover only
    chatClassColors   = true,     -- class-colored names everywhere
    chatTimestamps    = true,     -- grey HH:MM
    chatShiftScroll   = true,     -- Shift+wheel to top/bottom
    chatUrls          = true,     -- clickable / copyable links
    chatStickyWhisper = true,     -- Enter keeps whispering the same person
    chatHistory       = true,     -- Up/Down recall typed lines, kept across reloads
    chatSpamFilter    = true,     -- hide repeats of the same message within 2 min
    chatOnlyMine      = true,     -- loot/crafting/opening: only you and your group
    questLevels       = true,     -- [level] before quest names
    questCollapse     = true,     -- completed quests as one "(Turn in)" line
    questSortLevel    = true,     -- quests sorted by level within a zone
    questFade         = true,     -- fade to 25% in combat, mouseover restores
    questDungeon      = true,     -- in an instance, only that instance's quests
    welcomed          = false,    -- welcome popup answered
}

-- saved records needed to undo; /ibui reset keeps these
local BACKUP_KEYS = { "revert", "keybindBackup", "arrangeBackup", "clickLegendBackup", "chatBackup" }

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if dst[k] == nil then dst[k] = v end
    end
end

function ns.Print(msg, ...)
    print("|cff8fbc5aIronbark UI|r: " .. string.format(msg, ...))
end

-------------------------------------------------------------------------------
--  Combat queue: protected work (Edit Mode writes, frame anchors) waits for
--  PLAYER_REGEN_ENABLED. Keyed so repeated requests collapse into one.
-------------------------------------------------------------------------------
local queued, queueOrder = {}, {}
function ns.RunOutOfCombat(key, fn)
    if not InCombatLockdown() then
        fn()
        return
    end
    if not queued[key] then queueOrder[#queueOrder + 1] = key end
    queued[key] = fn
end

-------------------------------------------------------------------------------
--  Module hooks: other files register init callbacks run at PLAYER_LOGIN.
-------------------------------------------------------------------------------
local initCallbacks = {}
function ns.OnLogin(fn) initCallbacks[#initCallbacks + 1] = fn end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        IronbarkUIDB = IronbarkUIDB or {}
        -- settings for features that were removed
        for _, k in ipairs({ "woodFrames", "moonBackplate", "fadeStacks", "castTexture", "chatAltMenu",
            "lStacks", "barGap", "textAlways", "mirrorTarget", "partyAlwaysShow", "partyCentered",
            "partyStyle", "preset", "debug", "barDump" }) do
            IronbarkUIDB[k] = nil
        end
        -- tooltips-follow-mouse became the default (0.2.1)
        if not IronbarkUIDB.tooltipCursorV2 then
            IronbarkUIDB.tooltipCursorV2 = true
            IronbarkUIDB.tooltipCursor = true
        end
        CopyDefaults(ns.defaults, IronbarkUIDB)
        ns.db = IronbarkUIDB
    elseif event == "PLAYER_LOGIN" then
        for _, fn in ipairs(initCallbacks) do
            local ok, err = pcall(fn)
            if not ok then geterrorhandler()(err) end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        local order = queueOrder
        queueOrder = {}
        for _, key in ipairs(order) do
            local fn = queued[key]
            queued[key] = nil
            if fn then fn() end
        end
    end
end)

-------------------------------------------------------------------------------
--  Slash: /ibui            options
--         /ibui apply      save + apply everything
--         /ibui revert     put everything back
--  (individual steps: chatsetup, keybinds [undo], arrange [undo]; support:
--   bars, debug, buffs test, meters [test], reset)
-------------------------------------------------------------------------------
local HELP = {
    { "/ibui", "options" },
    { "/ibui apply", "save your settings, then apply Ironbark (reloads)" },
    { "/ibui revert", "put back everything Ironbark changed" },
    { "/ibui layout", "re-apply just the Edit Mode layout (reloads)" },
    { "/ibui arrange [undo]", "your class's bar layout" },
    { "/ibui keybinds [undo]", "1-5 Q E R F Z X Tab, Shift and Ctrl rows" },
    { "/ibui chatsetup", "chat tabs: General, Combat Log, Social, World, Loot" },
    { "/ibui meters", "show / hide the meters now" },
    { "/ibui buffs test", "preview every buff reminder icon" },
    { "/ibui probe", "support: 40s of notes on heals and auras, saved on /reload" },
    { "/ibui debug", "save diagnostics (then /reload)" },
    { "/ibui bars", "save what's on every action slot (then /reload)" },
    { "/ibui reset", "Ironbark's options back to defaults (keeps your saved copies)" },
    { "/ibui help", "this list" },
}

function ns.PrintHelp()
    ns.Print("commands:")
    for _, h in ipairs(HELP) do
        print(("  |cffffd200%s|r  %s"):format(h[1], h[2]))
    end
end

SLASH_IRONBARKUI1 = "/ibui"
SLASH_IRONBARKUI2 = "/ironbark"
SlashCmdList.IRONBARKUI = function(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "help" or cmd == "?" then
        ns.PrintHelp()
    elseif cmd == "apply" then
        StaticPopup_Show("IRONBARKUI_APPLYALL")
    elseif cmd == "chatsetup" then
        StaticPopup_Show("IRONBARKUI_CHATSETUP")
    elseif cmd == "buffs" and arg == "test" then
        if ns.ToggleBuffTest then ns.ToggleBuffTest() end
    elseif cmd == "probe" then
        if ns.Probe then ns.Probe() end
    elseif cmd == "meters" then
        if ns.ToggleMeterTest then ns.ToggleMeterTest() else ns.Print("Meters aren't available on this client.") end
    elseif cmd == "arrange" then
        if arg == "undo" then ns.UndoArrange() else StaticPopup_Show("IRONBARKUI_ARRANGE") end
    elseif cmd == "bars" then
        ns.DumpBars()
    elseif cmd == "keybinds" then
        if arg == "undo" then ns.UndoKeybinds() else StaticPopup_Show("IRONBARKUI_KEYBINDS") end
    elseif cmd == "debug" then
        ns.Debug()
    elseif cmd == "layout" then
        ns.ApplyPreset("ironbark") -- just the Edit Mode layout + its game settings; reloads
    elseif cmd == "revert" then
        StaticPopup_Show("IRONBARKUI_REVERTALL")
    elseif cmd == "reset" then
        -- settings back to defaults; keep every saved copy so revert still works
        local keep = { welcomed = true, layoutVersion = ns.db.layoutVersion }
        for _, k in ipairs(BACKUP_KEYS) do keep[k] = ns.db[k] end
        IronbarkUIDB = keep
        ReloadUI()
    else
        ns.OpenOptions()
    end
end
