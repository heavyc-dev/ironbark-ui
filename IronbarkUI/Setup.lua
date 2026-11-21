-------------------------------------------------------------------------------
--  Ironbark UI - welcome, apply everything, revert everything
--
--  Apply saves a copy of every setting Ironbark changes, then applies all of
--  it and reloads once:
--    keybinds (1-5 Q E R F Z X Tab / Shift / Ctrl), your class's bar layout
--    (+ the Att macro; druids: ClickLegend enemy rules), chat tabs, and the Edit Mode layout with its
--    game settings (UI scale, party/raid frame options, bags, nameplates...).
--  Revert puts every one of those back from the saved copies and reloads.
--
--  An addon can't copy files, so the "backup" is Ironbark's own record of
--  each setting it changes, kept in its saved variables.
-------------------------------------------------------------------------------
local _, ns = ...

local WELCOME = "|cff8fbc5aIronbark UI|r\n\n"
    .. "A light polish for the default UI: Blizzard's own frames, arranged and tidied - "
    .. "stacked action bars with gryphons, frames around your cast bar, a party row, "
    .. "one bag window, cleaner chat and a quest tracker.\n\n"
    .. "Applying first saves a copy of every setting it changes (layout, keybinds, bars, "
    .. "chat tabs, game options), then applies everything and reloads.\n\n"
    .. "You can undo it all any time: Options > AddOns > Ironbark UI > Revert everything."

function ns.ApplyAll()
    if InCombatLockdown() then
        return ns.Print("Leave combat first, then apply.")
    end
    ns.db.welcomed = true
    ns.Print("Saving your current settings and applying Ironbark...")

    if ns.ApplyKeybinds then ns.ApplyKeybinds() end
    if ns.Arrange and ns.HasArrangeLayout and ns.HasArrangeLayout() then ns.Arrange(true) end

    -- chat tabs need a moment (channel joins); the layout reloads at the end
    local function Finish()
        -- the layout step reloads; if it can't run, reload anyway so the rest lands
        local ok = ns.ApplyPreset and ns.ApplyPreset("ironbark")
        if not ok then ReloadUI() end
    end
    if ns.ChatSetup then ns.ChatSetup(Finish) else Finish() end
end

function ns.RevertAll()
    if InCombatLockdown() then
        return ns.Print("Leave combat first, then revert.")
    end
    if ns.db.keybindBackup and ns.UndoKeybinds then ns.UndoKeybinds() end
    if (ns.db.arrangeBackup or ns.db.clickLegendBackup) and ns.UndoArrange then ns.UndoArrange(true) end
    if ns.RestoreChat then ns.RestoreChat() end
    ns.db.welcomed = true
    if ns.db.revert and ns.Revert then
        ns.Revert() -- Edit Mode layout + game settings; reloads
    else
        ns.Print("Reverted. Reloading...")
        ReloadUI()
    end
end

StaticPopupDialogs["IRONBARKUI_WELCOME"] = {
    text = WELCOME,
    button1 = "Apply",
    button2 = "Not now",
    OnAccept = function() ns.ApplyAll() end,
    OnCancel = function()
        ns.db.welcomed = true
        ns.Print("No changes made. Apply any time from Options > AddOns > Ironbark UI.")
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["IRONBARKUI_APPLYALL"] = {
    text = "Apply Ironbark?\n\nYour current layout, keybinds, bars, chat tabs and game options are saved first; Revert everything puts them back.",
    button1 = ACCEPT,
    button2 = CANCEL,
    OnAccept = function() ns.ApplyAll() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["IRONBARKUI_REVERTALL"] = {
    text = "Revert everything Ironbark changed?\n\nYour saved layout, keybinds, bars, chat tabs and game options are put back and the UI reloads.\n\n(To also turn off Ironbark's own touches, disable the addon.)",
    button1 = ACCEPT,
    button2 = CANCEL,
    OnAccept = function() ns.RevertAll() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- the layout itself changed in an update: offer to re-apply just the layout
-- (keybinds, bars and chat are left alone; the original copy is kept)
StaticPopupDialogs["IRONBARKUI_LAYOUTUPDATE"] = {
    text = "Ironbark's layout was updated.\n\nApply the new layout now? (Reloads the UI. Keybinds, bars and chat aren't touched.)",
    button1 = ACCEPT,
    button2 = "Later",
    OnAccept = function() ns.ApplyPreset("ironbark") end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

ns.OnLogin(function()
    -- earlier versions marked a finished apply as appliedOnce
    if ns.db.appliedOnce then ns.db.welcomed = true end
    if not ns.db.welcomed then
        C_Timer.After(3, function() StaticPopup_Show("IRONBARKUI_WELCOME") end)
    elseif ns.db.revert and (ns.db.layoutVersion or 1) < (ns.LAYOUT_VERSION or 1) then
        C_Timer.After(3, function() StaticPopup_Show("IRONBARKUI_LAYOUTUPDATE") end)
    end
end)
