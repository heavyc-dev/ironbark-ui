-------------------------------------------------------------------------------
--  Ironbark UI - chat polish (Blizzard's chat frames, lighter)
--
--    chatShortTags     [2. Trade - English] -> [T], Guild -> [G], Party -> [P]...
--    chatHideButtons   side buttons (menu, social, voice, scroll) on mouseover only
--    chatClearBg       background hidden until you mouse over the chat
--    chatClassColors   class-colored names in every channel
--    chatTimestamps    short grey HH:MM timestamps
--    chatShiftScroll   Shift + wheel jumps to top / bottom
--    chatUrls          URLs become links; click to copy
--    chatStickyWhisper Enter keeps whispering the last person you whispered
--    chatHistory       Up / Down recall what you typed (no Alt), kept across reloads
--
--  Messages can carry hidden ("secret") values on this client; rewriting skips
--  those. Nothing here is protected: chat frames are plain frames.
-------------------------------------------------------------------------------
local _, ns = ...

local isSecret = issecretvalue or function() return false end
local HISTORY_MAX = 30

-------------------------------------------------------------------------------
--  Message rewriting (short tags, timestamps, URLs)
-------------------------------------------------------------------------------
-- channel name prefix (before " - ") -> short tag; anything else -> its number
local CHANNEL_SHORT = {
    Trade = "T", General = "Gen", LocalDefense = "LD", WorldDefense = "WD",
    LookingForGroup = "LFG", GuildRecruitment = "GR", Services = "S",
}

local URL_PATTERNS = {
    "(%a+://[%w_%-%./%%%?=&#:+~]+)",       -- scheme://...
    "(www%.[%w_%-%./%%%?=&#:+~]+)",        -- www.example.com/...
    "(discord%.gg/[%w_%-]+)",              -- discord.gg/invite
}
local URL_LINK = "|cff6fb8ff|Hironbarkurl:%1|h[%1]|h|r"

local function ShortChannel(num, name)
    local base = name:match("^([^%s%-]+)") or name
    local short = CHANNEL_SHORT[base]
    return short or num
end

local function Rewrite(text)
    if type(text) ~= "string" or isSecret(text) or text:find("|K", 1, true) then return text end
    if ns.db.chatShortTags then
        -- "|Hchannel:channel:2|h[2. Trade - English]|h" -> "|Hchannel:channel:2|h[T]|h"
        text = text:gsub("(|Hchannel:[^|]-|h)%[(%d+)%. ([^%]]-)%](|h)", function(open, num, name, close)
            return open .. "[" .. ShortChannel(num, name) .. "]" .. close
        end)
    end
    if ns.db.chatTimestamps then
        text = text:gsub("^(%d%d?:%d%d) ", "|cff808080%1|r ", 1)
    end
    if ns.db.chatUrls and not text:find("|Hironbarkurl:", 1, true) then
        -- don't touch text that's already inside another link
        local plain = text:gsub("|H.-|h.-|h", "")
        if plain:find("://", 1, true) or plain:find("www.", 1, true) or plain:find("discord.gg/", 1, true) then
            -- first pattern that matches wins, so https://www.x isn't wrapped twice
            for _, p in ipairs(URL_PATTERNS) do
                local new, n = text:gsub(p, URL_LINK)
                if n > 0 then text = new break end
            end
        end
    end
    return text
end

local function HookAddMessage(cf)
    if not cf or cf.__ibuiChat or cf == ChatFrame2 then return end -- leave the combat log
    cf.__ibuiChat = true
    local orig = cf.AddMessage
    cf.AddMessage = function(self, text, ...)
        return orig(self, Rewrite(text), ...)
    end
end

-- Guild / party / raid / whisper prefixes come from these format strings.
local SHORT_GET = {
    CHAT_GUILD_GET = "|Hchannel:GUILD|h[G]|h %s: ",
    CHAT_OFFICER_GET = "|Hchannel:OFFICER|h[O]|h %s: ",
    CHAT_PARTY_GET = "|Hchannel:PARTY|h[P]|h %s: ",
    CHAT_PARTY_LEADER_GET = "|Hchannel:PARTY|h[PL]|h %s: ",
    CHAT_RAID_GET = "|Hchannel:RAID|h[R]|h %s: ",
    CHAT_RAID_LEADER_GET = "|Hchannel:RAID|h[RL]|h %s: ",
    CHAT_RAID_WARNING_GET = "[RW] %s: ",
    CHAT_INSTANCE_CHAT_GET = "|Hchannel:INSTANCE_CHAT|h[I]|h %s: ",
    CHAT_INSTANCE_CHAT_LEADER_GET = "|Hchannel:INSTANCE_CHAT|h[IL]|h %s: ",
    CHAT_WHISPER_GET = "[W] %s: ",
    CHAT_WHISPER_INFORM_GET = "[To] %s: ",
}
local originalGet = {}

local function ApplyShortGet()
    for key, short in pairs(SHORT_GET) do
        if originalGet[key] == nil then originalGet[key] = _G[key] end
        if ns.db.chatShortTags then _G[key] = short else _G[key] = originalGet[key] end
    end
end

-------------------------------------------------------------------------------
--  URL copy popup
-------------------------------------------------------------------------------
StaticPopupDialogs["IRONBARKUI_URL"] = {
    text = "Copy the link (Ctrl+C):",
    button1 = CLOSE or "Close",
    hasEditBox = true,
    editBoxWidth = 320,
    OnShow = function(self, url)
        local eb = self.editBox or self.EditBox
        eb:SetText(url or "")
        eb:HighlightText()
        eb:SetFocus()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

hooksecurefunc("SetItemRef", function(link)
    if type(link) ~= "string" or isSecret(link) then return end
    local url = link:match("^ironbarkurl:(.+)$")
    if url then StaticPopup_Show("IRONBARKUI_URL", nil, nil, url) end
end)

-------------------------------------------------------------------------------
--  Side buttons + background: shown only while the mouse is over the chat
-------------------------------------------------------------------------------
local BG_HOVER_ALPHA = 0.45

local function SideButtons()
    local list = {
        ChatFrameMenuButton, ChatFrameChannelButton, QuickJoinToastButton,
        ChatFrameToggleVoiceDeafenButton, ChatFrameToggleVoiceMuteButton,
        _G.FriendsMicroButton, _G.ChatFrame1ButtonFrame,
    }
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local bf = _G["ChatFrame" .. i .. "ButtonFrame"]
        if bf then list[#list + 1] = bf end
    end
    return list
end

local function BgTextures(cf)
    local out, name = {}, cf:GetName()
    for _, piece in ipairs(CHAT_FRAME_TEXTURES or { "Background" }) do
        local t = _G[name .. piece]
        if t then out[#out + 1] = t end
    end
    return out
end

local function MouseOverChat()
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local cf = _G["ChatFrame" .. i]
        if cf and cf:IsVisible() and cf:IsMouseOver(20, -10, -10, 30) then return true end
    end
    for _, b in ipairs(SideButtons()) do
        if b and b:IsVisible() and b:IsMouseOver() then return true end
    end
    local eb = ChatFrame1EditBox
    return eb and eb:HasFocus() or false
end

local lastHover
local function HoverTick()
    if ns.IsChatHidden and ns.IsChatHidden() then return end -- hidden: nothing to fade
    if not (ns.db.chatHideButtons or ns.db.chatClearBg) then return end
    local hover = MouseOverChat()
    if hover == lastHover then return end
    lastHover = hover
    if ns.db.chatHideButtons then
        for _, b in ipairs(SideButtons()) do
            if b then b:SetAlpha(hover and 1 or 0) end
        end
    end
    if ns.db.chatClearBg then
        for i = 1, NUM_CHAT_WINDOWS or 10 do
            local cf = _G["ChatFrame" .. i]
            if cf then
                for _, t in ipairs(BgTextures(cf)) do t:SetAlpha(hover and BG_HOVER_ALPHA or 0) end
            end
        end
    end
end

-- Event-driven: polling only runs while the mouse is over the chat (started
-- by the chat's own OnEnter), and stops itself once it has left.
local hoverTicker
local function StartHover()
    if ns.ChatActivity then ns.ChatActivity() end -- brings auto-hidden chat back
    HoverTick()
    if hoverTicker then return end
    hoverTicker = C_Timer.NewTicker(0.15, function()
        HoverTick()
        if not MouseOverChat() then
            hoverTicker:Cancel()
            hoverTicker = nil
            HoverTick()
        end
    end)
end

local function HookHover(f)
    if not f or f.__ibuiHover then return end
    f.__ibuiHover = true
    f:HookScript("OnEnter", StartHover)
    if f.HookScript and f:HasScript("OnEditFocusGained") then
        f:HookScript("OnEditFocusGained", StartHover)
        f:HookScript("OnEditFocusLost", StartHover)
    end
end

-------------------------------------------------------------------------------
--  Class colors, timestamps, sticky whispers
-------------------------------------------------------------------------------
local CLASS_COLOR_GROUPS = {
    "SAY", "EMOTE", "YELL", "GUILD", "OFFICER", "WHISPER", "PARTY", "PARTY_LEADER",
    "RAID", "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER",
}

local function ApplyClassColors()
    if not ns.db.chatClassColors then return end
    local groups = { unpack(CLASS_COLOR_GROUPS) }
    for i = 1, 20 do groups[#groups + 1] = "CHANNEL" .. i end
    for _, g in ipairs(groups) do
        if SetChatColorNameByClass then
            pcall(SetChatColorNameByClass, g, true)
        elseif ToggleChatColorNamesByClassGroup then
            pcall(ToggleChatColorNamesByClassGroup, true, g)
        end
    end
end

local function ApplyCVars()
    local r = ns.db.revert
    local function set(name, value)
        local cur = GetCVar(name)
        if cur == nil then return end
        if r and r.cvars and r.cvars[name] == nil then r.cvars[name] = cur end
        if cur ~= value then SetCVar(name, value) end
    end
    if ns.db.chatTimestamps then set("showTimestamps", "%H:%M ") end
    if ns.db.chatStickyWhisper then
        if ChatTypeInfo and ChatTypeInfo.WHISPER then ChatTypeInfo.WHISPER.sticky = 1 end
        if ChatTypeInfo and ChatTypeInfo.BN_WHISPER then ChatTypeInfo.BN_WHISPER.sticky = 1 end
    end
end

-------------------------------------------------------------------------------
--  Shift + wheel to top / bottom
-------------------------------------------------------------------------------
local function HookWheel(cf)
    if not cf or cf.__ibuiWheel then return end
    cf.__ibuiWheel = true
    cf:HookScript("OnMouseWheel", function(self, delta)
        if not (ns.db.chatShiftScroll and IsShiftKeyDown()) then return end
        if delta > 0 then self:ScrollToTop() else self:ScrollToBottom() end
    end)
end

-------------------------------------------------------------------------------
--  Typed history: Up / Down without Alt, remembered across reloads
-------------------------------------------------------------------------------
-- Our own history (Blizzard's Alt-arrow history doesn't behave on this
-- client; Tust_EUI does it this way too): remember each line you send, and
-- handle Up / Down ourselves. Up = older, Down = newer, past the newest clears.
local function RememberLine(text)
    if not ns.db.chatHistory or type(text) ~= "string" or isSecret(text) then return end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return end
    local lines = ns.db.chatHistoryLines or {}
    for i = #lines, 1, -1 do -- a repeat moves to the newest spot
        if lines[i] == text then table.remove(lines, i) break end
    end
    lines[#lines + 1] = text
    while #lines > HISTORY_MAX do table.remove(lines, 1) end
    ns.db.chatHistoryLines = lines
end

local function HookEditBox(eb)
    if not eb or eb.__ibuiHistory then return end
    eb.__ibuiHistory = true
    local state = { index = 0 }
    if eb.SetAltArrowKeyMode then eb:SetAltArrowKeyMode(false) end
    -- what's in the box when Enter is pressed (it's cleared right after)
    eb:HookScript("OnTextChanged", function(self, userInput)
        local t = self:GetText()
        if type(t) == "string" and not isSecret(t) and (userInput or t ~= "") then state.pending = t end
    end)
    eb:HookScript("OnEnterPressed", function()
        if state.pending then RememberLine(state.pending) end
        state.pending, state.index = nil, 0
    end)
    eb:HookScript("OnEditFocusLost", function() state.index = 0 end)
    eb:HookScript("OnKeyDown", function(self, key)
        if not ns.db.chatHistory or (key ~= "UP" and key ~= "DOWN") or IsAltKeyDown() then return end
        local lines = ns.db.chatHistoryLines or {}
        local n = #lines
        if n == 0 then return end
        if key == "UP" then
            state.index = math.min(state.index + 1, n)
        else
            state.index = state.index - 1
            if state.index < 1 then
                state.index = 0
                self:SetText("")
                return
            end
        end
        self:SetText(lines[n - state.index + 1])
        self:SetCursorPosition(#lines[n - state.index + 1])
    end)
end

-------------------------------------------------------------------------------
--  Spam filter: the same person posting the same text again within
--  SPAM_WINDOW seconds is hidden (public channels, say, yell). Case and extra
--  spaces don't count. Never your own messages, never whispers/party/guild.
--  Filters run once per chat frame for the same line, so a repeat is a
--  different line ID with the same text.
-------------------------------------------------------------------------------
local SPAM_WINDOW = 120
local seen = {}

local function Normalize(msg)
    msg = msg:lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return (msg:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

local function SpamFilter(_, _, msg, author, ...)
    if not ns.db.chatSpamFilter then return false end
    if type(msg) ~= "string" or type(author) ~= "string" or isSecret(msg) or isSecret(author) then return false end
    local me = UnitName("player")
    if author == me or author:match("^([^%-]+)") == me then return false end
    local lineID = select(9, ...) -- arg11
    local key = author .. "\1" .. Normalize(msg)
    local now = GetTime()
    local s = seen[key]
    if s and s.id == lineID then return false end           -- same line, another frame
    if s and now - s.t < SPAM_WINDOW then return true end    -- a repeat: hide
    seen[key] = { t = now, id = lineID }
    return false
end

-------------------------------------------------------------------------------
--  Only you and your group: loot / crafting / opening messages about players
--  outside your group are hidden (cities are full of them). Lines with no
--  player attached (money, currency, your skill-ups) always show.
-------------------------------------------------------------------------------
local function InMyGroup(name)
    local short = name:match("^([^%-]+)") or name
    if short == UnitName("player") then return true end
    if UnitInParty and UnitInParty(short) then return true end
    if UnitInRaid and UnitInRaid(short) then return true end
    return false
end

local function OthersFilter(_, _, msg, author, ...)
    if not ns.db.chatOnlyMine then return false end
    if type(msg) ~= "string" or isSecret(msg) then return false end
    if type(author) == "string" and not isSecret(author) and author ~= "" then
        return not InMyGroup(author)
    end
    -- no author field: fall back to the text; yours start with "You"
    if msg:find("^You") then return false end
    local who = msg:match("^([^%s]+) ")
    return who ~= nil and not InMyGroup(who)
end

-------------------------------------------------------------------------------
--  Social tab: of the loot lines, only group loot rolls (need / greed / won /
--  passed) and gear of green quality or better - who got what in the group.
--  Junk, cloth, money and the like stay on the Loot tab.
-------------------------------------------------------------------------------
local ROLL_WORDS = { "roll", "need", "greed", "won", "passed", "disenchant" }
local GOOD_COLORS = { "|cff1eff00", "|cff0070dd", "|cffa335ee", "|cffff8000", "|cffe6cc80" }

local function IsSocialFrame(frame)
    local id = frame and frame.GetID and frame:GetID()
    local name = id and GetChatWindowInfo(id)
    return name == "Social"
end

local function GroupLootWorthy(msg)
    local lower = msg:lower()
    for _, w in ipairs(ROLL_WORDS) do
        if lower:find(w, 1, true) then return true end
    end
    -- quality as a color token (|cnIQ2: = green and up) or a classic hex color
    local q = msg:match("|cnIQ(%d+):")
    if q and tonumber(q) >= 2 then return true end
    lower = msg:lower()
    for _, c in ipairs(GOOD_COLORS) do
        if lower:find(c, 1, true) then return true end
    end
    return false
end

local function SocialLootFilter(frame, _, msg)
    if not IsSocialFrame(frame) then return false end
    if type(msg) ~= "string" or isSecret(msg) then return false end
    return not GroupLootWorthy(msg)
end

-- tabs set up by an earlier version: add loot to Social once (filtered above)
local function AddLootToSocial()
    if ns.db.chatSocialLoot or not ns.db.chatBackup then return end
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local cf = _G["ChatFrame" .. i]
        if cf and IsSocialFrame(cf) then
            -- (Call() is defined further down)
            if cf.AddMessageGroup then pcall(cf.AddMessageGroup, cf, "LOOT")
            elseif ChatFrame_AddMessageGroup then pcall(ChatFrame_AddMessageGroup, cf, "LOOT") end
            ns.db.chatSocialLoot = true
        end
    end
end

-- (No combat log filter changes from here: those functions are Blizzard-only
-- on this client and setting them at load got Ironbark UI blocked. Use the
-- "My actions" button on the Combat Log tab; Blizzard remembers it.)

local function PruneSeen()
    local now = GetTime()
    for k, s in pairs(seen) do
        if now - s.t > SPAM_WINDOW then seen[k] = nil end
    end
end

-------------------------------------------------------------------------------
--  /ibui chatsetup: build the tabs and join the channels (one-time, confirmed)
--    General | Combat Log | Social | World | Loot
-------------------------------------------------------------------------------
local TABS = {
    { name = "General", groups = {
        "SAY", "EMOTE", "YELL", "SYSTEM", "ERRORS", "AFK", "DND", "IGNORED",
        "MONSTER_SAY", "MONSTER_YELL", "MONSTER_EMOTE", "MONSTER_WHISPER",
        "MONSTER_BOSS_EMOTE", "MONSTER_BOSS_WHISPER",
        "BG_HORDE", "BG_ALLIANCE", "BG_NEUTRAL", "ACHIEVEMENT", "PING", "ENCOUNTER_EVENT",
    } },
    { name = "Social", reuse = { "Friends", "Social" }, groups = {
        "WHISPER", "BN_WHISPER", "BN_INLINE_TOAST_ALERT",
        "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING",
        "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "GUILD", "OFFICER", "GUILD_ACHIEVEMENT",
        "LOOT", -- only rolls and green-or-better gear here (SocialLootFilter)
    } },
    -- public channels; renames an earlier "Trade" tab from a previous run
    { name = "World", reuse = { "World", "Trade" }, groups = {}, allChannels = true },
    { name = "Loot", reuse = { "Loot" }, groups = {
        "LOOT", "MONEY", "CURRENCY", "SKILL", "COMBAT_XP_GAIN", "COMBAT_FACTION_CHANGE",
        "COMBAT_HONOR_GAIN", "TRADESKILLS", "GUILD_ITEM_LOOTED",
    } },
}
local JOIN = { "LookingForGroup" } -- General / Trade / LocalDefense join by zone

-- 12.x moved some of these onto the frame; use whichever exists
local function Call(cf, method, global, ...)
    if cf[method] then return pcall(cf[method], cf, ...) end
    if _G[global] then return pcall(_G[global], cf, ...) end
end

local function WindowNamed(names)
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local name = GetChatWindowInfo(i)
        for _, want in ipairs(names) do
            if name == want then return _G["ChatFrame" .. i] end
        end
    end
end

local function JoinedChannels()
    local list, raw = {}, { GetChannelList() }
    for i = 1, #raw, 3 do
        local name = raw[i + 1]
        if type(name) == "string" then list[#list + 1] = name end
    end
    return list
end

-------------------------------------------------------------------------------
--  Chat tab snapshot / restore, so "Revert everything" can put your old tabs
--  back: each window's name, message groups, channels and docked state.
-------------------------------------------------------------------------------
local function SnapshotChat()
    local snap = {}
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local name, _, _, _, _, _, shown, _, docked = GetChatWindowInfo(i)
        if name and name ~= "" then
            local channels, raw = {}, { GetChatWindowChannels(i) }
            for k = 1, #raw, 2 do channels[#channels + 1] = raw[k] end
            snap[i] = {
                name = name, shown = shown and true or false, docked = docked,
                groups = { GetChatWindowMessages(i) }, channels = channels,
            }
        end
    end
    return snap
end

function ns.RestoreChat()
    local snap = ns.db.chatBackup
    if not snap then return false end
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local cf, s = _G["ChatFrame" .. i], snap[i]
        if cf and i ~= 2 then -- never touch the combat log
            if s then
                if FCF_SetWindowName then FCF_SetWindowName(cf, s.name) end
                Call(cf, "RemoveAllMessageGroups", "ChatFrame_RemoveAllMessageGroups")
                Call(cf, "RemoveAllChannels", "ChatFrame_RemoveAllChannels")
                for _, g in ipairs(s.groups) do Call(cf, "AddMessageGroup", "ChatFrame_AddMessageGroup", g) end
                for _, ch in ipairs(s.channels) do Call(cf, "AddChannel", "ChatFrame_AddChannel", ch) end
            else
                -- a tab we created (World / Loot): close it
                local name = GetChatWindowInfo(i)
                if name and name ~= "" and FCF_Close then pcall(FCF_Close, cf) end
            end
        end
    end
    ns.db.chatBackup = nil
    return true
end

function ns.ChatSetup(onDone)
    if InCombatLockdown() then return ns.Print("Not in combat, please.") end
    if not ns.db.chatBackup then ns.db.chatBackup = SnapshotChat() end
    for _, ch in ipairs(JOIN) do pcall(JoinPermanentChannel, ch) end

    C_Timer.After(1, function() -- let channel joins land before routing them
        local dockIndex = 3 -- after General (1) and Combat Log (2)
        for _, tab in ipairs(TABS) do
            local cf
            if tab.name == "General" then
                cf = ChatFrame1
            else
                cf = WindowNamed(tab.reuse or { tab.name })
                if not cf and FCF_OpenNewWindow then
                    cf = FCF_OpenNewWindow(tab.name) or WindowNamed({ tab.name })
                end
            end
            if cf then
                if cf ~= ChatFrame1 and FCF_SetWindowName then FCF_SetWindowName(cf, tab.name) end
                Call(cf, "RemoveAllMessageGroups", "ChatFrame_RemoveAllMessageGroups")
                Call(cf, "RemoveAllChannels", "ChatFrame_RemoveAllChannels")
                for _, g in ipairs(tab.groups) do
                    Call(cf, "AddMessageGroup", "ChatFrame_AddMessageGroup", g)
                end
                if tab.allChannels then
                    for _, ch in ipairs(JoinedChannels()) do
                        Call(cf, "AddChannel", "ChatFrame_AddChannel", ch)
                    end
                end
                if cf ~= ChatFrame1 and FCF_DockFrame then
                    FCF_DockFrame(cf, dockIndex)
                    dockIndex = dockIndex + 1
                end
                HookAddMessage(cf)
                HookWheel(cf)
            else
                ns.Print("Couldn't create the %s tab.", tab.name)
            end
        end
        if FCF_SelectDockFrame then FCF_SelectDockFrame(ChatFrame1) end
        ns.Print("Chat tabs set: General, Combat Log, Social, World, Loot.")
        if onDone then onDone() end
    end)
end

StaticPopupDialogs["IRONBARKUI_CHATSETUP"] = {
    text = "Set up chat tabs?\n\nGeneral | Combat Log | Social | World | Loot\n\nYour Friends tab becomes Social, World and Loot are created, and LookingForGroup is joined.",
    button1 = ACCEPT,
    button2 = CANCEL,
    OnAccept = function() ns.ChatSetup() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-------------------------------------------------------------------------------
--  Hide-chat button, left of the General tab (same arrow as the bag bar).
--  Hides every chat window, tab and chat button (alpha + mouse only, so
--  Blizzard's own showing/hiding never fights it). Remembered across reloads.
--  Pressing Enter to type brings the chat straight back.
-------------------------------------------------------------------------------
local HIDE_ARROW = "Interface\\RaidFrame\\RaidPanel-Toggle"
local hideButton

local function ChatParts()
    local parts = { GeneralDockManager }
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        parts[#parts + 1] = _G["ChatFrame" .. i]
        parts[#parts + 1] = _G["ChatFrame" .. i .. "Tab"]
        parts[#parts + 1] = _G["ChatFrame" .. i .. "ButtonFrame"]
    end
    for _, b in ipairs(SideButtons()) do parts[#parts + 1] = b end
    return parts
end

-- Two ways to be hidden: by the button (remembered; mouse blocked there too)
-- or by auto-hide (this session only; hovering the chat area brings it back).
local function IsHidden() return ns.db.chatHidden or ns.chatAutoHidden end
ns.IsChatHidden = IsHidden

-- Blizzard fades tabs back in on new messages and hover; while hidden, undo it
local settingAlpha = false
local function KeepHidden(f)
    if f.__ibuiKeepHidden then return end
    f.__ibuiKeepHidden = true
    hooksecurefunc(f, "SetAlpha", function(self, a)
        if settingAlpha or not IsHidden() or (a or 0) == 0 then return end
        settingAlpha = true
        self:SetAlpha(0)
        settingAlpha = false
    end)
end

function ns.SetChatHidden(hidden, auto)
    if auto then
        ns.chatAutoHidden = hidden and true or nil
    else
        ns.db.chatHidden = hidden and true or nil
        if not hidden then ns.chatAutoHidden = nil end
    end
    local h = IsHidden()
    settingAlpha = true
    for _, f in pairs(ChatParts()) do
        if f then
            KeepHidden(f)
            f:SetAlpha(h and 0 or 1)
            -- only the button's hide blocks the mouse; auto-hide must still feel hover
            if f.EnableMouse and f ~= GeneralDockManager then f:EnableMouse(not ns.db.chatHidden) end
        end
    end
    settingAlpha = false
    if hideButton then
        -- right half of the arrow points left (hide), left half points right (show)
        local l, r = 0.5, 1
        if h then l, r = 0, 0.5 end
        for _, tex in ipairs({ hideButton:GetNormalTexture(), hideButton:GetPushedTexture(), hideButton:GetHighlightTexture() }) do
            if tex then tex:SetTexCoord(l, r, 0, 1) end
        end
    end
    -- give the hover logic a clean start when the chat comes back
    if not h then C_Timer.After(0, function() if ns.RefreshChat then ns.RefreshChat() end end) end
end

-------------------------------------------------------------------------------
--  Auto-hide: chat fades away AUTO_HIDE_DELAY seconds after the last activity
--  that matters - your mouse over it, typing, or a message from a person
--  (say/yell/emote, whispers, party/raid/instance, guild). World channels,
--  loot and system messages don't count, or chat would never hide in a city.
-------------------------------------------------------------------------------
local AUTO_HIDE_DELAY = 30
local PERSON_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
}
local autoTimer

function ns.ChatActivity()
    if ns.chatAutoHidden then ns.SetChatHidden(false, true) end
    if autoTimer then autoTimer:Cancel() autoTimer = nil end
    if not ns.db.chatAutoHide or ns.db.chatHidden then return end
    autoTimer = C_Timer.NewTimer(AUTO_HIDE_DELAY, function()
        autoTimer = nil
        if IsHidden() then return end
        local eb = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
        if (eb and eb:HasFocus()) or MouseOverChat() then
            ns.ChatActivity() -- still in use: wait another round
            return
        end
        ns.SetChatHidden(true, true)
    end)
end

local function BuildHideButton()
    if hideButton or not ChatFrame1Tab then return end
    local b = CreateFrame("Button", "IronbarkChatToggle", UIParent)
    b:SetSize(14, 26)
    b:SetFrameStrata("MEDIUM")
    b:SetPoint("RIGHT", ChatFrame1Tab, "LEFT", -1, -2)
    local useRaid = not GetFileIDFromPath or GetFileIDFromPath(HIDE_ARROW)
    local art = useRaid and HIDE_ARROW or "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up"
    b:SetNormalTexture(art)
    b:SetPushedTexture(art)
    b:SetHighlightTexture(art, "ADD")
    b:GetHighlightTexture():SetAlpha(0.4)
    b:SetScript("OnClick", function()
        if IsHidden() then
            ns.SetChatHidden(false)
            ns.ChatActivity()
        else
            ns.SetChatHidden(true)
        end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(IsHidden() and "Show chat" or "Hide chat")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    hideButton = b
    -- typing (Enter) always brings the chat back
    local eb = ChatFrame1EditBox
    if eb then
        eb:HookScript("OnEditFocusGained", function()
            if ns.db.chatHidden then ns.SetChatHidden(false) end
            ns.ChatActivity()
        end)
    end
    ns.SetChatHidden(ns.db.chatHidden)
end

-------------------------------------------------------------------------------
--  Wiring
-------------------------------------------------------------------------------
local function HookAll()
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local cf = _G["ChatFrame" .. i]
        HookAddMessage(cf)
        HookWheel(cf)
        HookEditBox(_G["ChatFrame" .. i .. "EditBox"])
        HookHover(cf)
        HookHover(_G["ChatFrame" .. i .. "Tab"])
        HookHover(_G["ChatFrame" .. i .. "EditBox"])
    end
    for _, b in ipairs(SideButtons()) do HookHover(b) end
end

function ns.RefreshChat()
    HookAll()
    ApplyShortGet()
    ApplyClassColors()
    ApplyCVars()
    lastHover = nil
    if not ns.db.chatHideButtons then
        for _, b in ipairs(SideButtons()) do if b then b:SetAlpha(1) end end
    end
    HoverTick()
end

ns.OnLogin(function()
    ns.RefreshChat()
    BuildHideButton()
    -- auto-hide: messages from people count as activity
    local act = CreateFrame("Frame")
    for _, e in ipairs(PERSON_EVENTS) do pcall(act.RegisterEvent, act, e) end
    act:SetScript("OnEvent", function() ns.ChatActivity() end)
    ns.ChatActivity()
    -- spam filter on public channels, say and yell
    if ChatFrame_AddMessageEventFilter then
        for _, e in ipairs({ "CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_YELL" }) do
            ChatFrame_AddMessageEventFilter(e, SpamFilter)
        end
        C_Timer.NewTicker(60, PruneSeen)
        for _, e in ipairs({ "CHAT_MSG_LOOT", "CHAT_MSG_TRADESKILLS", "CHAT_MSG_OPENING" }) do
            ChatFrame_AddMessageEventFilter(e, OthersFilter)
        end
        ChatFrame_AddMessageEventFilter("CHAT_MSG_LOOT", SocialLootFilter)
        if not InCombatLockdown() then pcall(AddLootToSocial) end
    end
    -- temporary windows (whisper tabs) get the same treatment
    if FCF_OpenTemporaryWindow then
        hooksecurefunc("FCF_OpenTemporaryWindow", function() C_Timer.After(0, HookAll) end)
    end
end)
