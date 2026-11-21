-------------------------------------------------------------------------------
--  Ironbark UI - Options (Esc > Options > AddOns > Ironbark UI, or /ibui)
--  Built on Blizzard's own Settings panel so it looks native. Kept short on
--  purpose: everything else is simply how Ironbark works.
-------------------------------------------------------------------------------
local _, ns = ...

local category

-- the chat features behind the single "Chat polish" switch
local CHAT_FLAGS = {
    "chatShortTags", "chatHideButtons", "chatClearBg", "chatClassColors", "chatTimestamps",
    "chatShiftScroll", "chatUrls", "chatStickyWhisper", "chatHistory", "chatSpamFilter", "chatOnlyMine",
}

local function Build()
    if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
    local cat, layout = Settings.RegisterVerticalLayoutCategory("Ironbark UI")
    category = cat

    local function Checkbox(key, label, tooltip, onChange)
        local setting = Settings.RegisterAddOnSetting(cat, "IRONBARKUI_" .. key, key,
            ns.db, Settings.VarType.Boolean, label, ns.defaults[key])
        if onChange then setting:SetValueChangedCallback(onChange) end
        Settings.CreateCheckbox(cat, setting, tooltip)
    end
    local function Button(label, onClick, tooltip)
        layout:AddInitializer(CreateSettingsButtonInitializer("", label, onClick, tooltip, true))
    end
    local function Header(text)
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
    end

    Header("Setup")
    Button("Apply Ironbark", function() StaticPopup_Show("IRONBARKUI_APPLYALL") end,
        "Saves your current layout, keybinds, bars, chat tabs and game options, then applies Ironbark and reloads.")
    Button("Revert everything", function() StaticPopup_Show("IRONBARKUI_REVERTALL") end,
        "Puts back everything Ironbark changed, from the copy saved when you applied it.")
    Checkbox("manageUIScale", "Use Ironbark's UI scale (0.64)",
        "Set the game's UI scale when applying. Off: keep your own.")

    Header("Frames")
    Checkbox("classColors", "Class-colored health",
        "Player, target, focus and party health in class colors. Turning off needs /reload.", ns.RefreshFrames)
    Checkbox("compactText", "Compact health text (961 | 100%)",
        "One line of value | percent, shown on mouseover and in combat.", ns.RefreshFrames)
    Checkbox("castBarAlways", "Always show cast bar",
        "Keep an empty cast bar frame on screen between casts.",
        function() if ns.UpdateCastGhost then ns.UpdateCastGhost() end end)
    Checkbox("tooltipCursor", "Tooltips follow mouse",
        "Tooltips that normally sit in the bottom-right corner appear beside your cursor instead. Off: they stay in the corner, above the meters.")
    Checkbox("tooltipCombatHide", "Hide tooltips in combat",
        "No tooltips while you're in combat. Hold Alt while pointing at something to see its tooltip anyway.")

    Header("Party & raid")
    Checkbox("buffReminders", "Missing buff reminders",
        "Glowing icons on you, party and raid frames for your buffs they're missing (click to cast). Out of combat only.",
        function() if ns.RefreshBuffReminders then ns.RefreshBuffReminders() end end)
    Checkbox("hotIcons", "Your HoTs on party frames",
        "Your heal-over-time spells and shields (Rejuvenation, Regrowth, Renew, Power Word: Shield) under the left side of each teammate's frame, with a timer. Updates in combat.",
        function() if ns.RefreshHots then ns.RefreshHots() end end)

    Header("Bags")
    Checkbox("combinedBags", "One bag window",
        "All bags in one window with a category sort and a Sections view. Turning off needs /reload.",
        function() if ns.RefreshBags then ns.RefreshBags() end end)

    Header("Chat")
    local chat = Settings.RegisterAddOnSetting(cat, "IRONBARKUI_chatPolish", "chatPolish",
        ns.db, Settings.VarType.Boolean, "Chat polish", ns.defaults.chatPolish)
    chat:SetValueChangedCallback(function(_, value)
        for _, k in ipairs(CHAT_FLAGS) do ns.db[k] = value and true or false end
        if ns.RefreshChat then ns.RefreshChat() end
    end)
    Settings.CreateCheckbox(cat, chat,
        "Short channel tags, buttons and background on mouseover, class-colored names, timestamps, clickable links, sticky whispers, message history, spam filter and loot from your group only. Turning off needs /reload.")

    Checkbox("chatAutoHide", "Auto-hide chat",
        "Chat fades away 30 seconds after the last activity: your mouse over it, typing, or a message from a person (say, whispers, party, raid, guild). World channels and loot don't count. Hover where it sits, type, or get a whisper to bring it back.",
        function() if ns.ChatActivity then ns.ChatActivity() end end)

    Header("Quests")
    Checkbox("questTracker", "Ironbark quest tracker",
        "Grouped by zone under the minimap. Click a zone to collapse, Ctrl-click to pin, right-click a quest to hide its objectives.",
        function() if ns.RefreshQuest then ns.RefreshQuest() end end)

    Header("Minimap")
    Checkbox("minimapCollect", "Tuck addon buttons into one button",
        "Addon minimap buttons slide out from one button on the minimap's edge. Turning off needs /reload.",
        function() if ns.RefreshMinimapButtons then ns.RefreshMinimapButtons() end end)

    Header("Meters")
    Checkbox("meters", "Damage and healing meters",
        "Two small meters at the bottom-right: always in dungeons and raids, elsewhere only in combat. Shift-click a title to reset, right-click for this fight only.",
        function() if ns.RefreshMeters then ns.RefreshMeters() end end)
    Button("Show / hide meters now", function() if ns.ToggleMeterTest then ns.ToggleMeterTest() end end,
        "Shows the meters right away (sample numbers until a real fight) so you can see them. Click again to hide. Same as /ibui meters.")
    Button("Preview buff icons", function() if ns.ToggleBuffTest then ns.ToggleBuffTest() end end,
        "Shows every buff reminder icon on your frames so you can see where they sit. Click again to stop. Same as /ibui buffs test.")

    Settings.RegisterAddOnCategory(cat)
end

function ns.OpenOptions()
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    else
        if ns.PrintHelp then ns.PrintHelp() else ns.Print("Commands: /ibui apply, /ibui revert") end
    end
end

ns.OnLogin(function()
    local ok, err = pcall(Build)
    if not ok then
        ns.Print("Options panel unavailable (%s). Slash commands still work: /ibui", tostring(err))
    end
end)
