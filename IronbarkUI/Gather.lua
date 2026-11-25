-------------------------------------------------------------------------------
--  Ironbark UI - gathering pop-ups
--  The game flashes "Boar Tusk: 3/8" mid-screen for quest items. This does the
--  same for what you skin, mine, pick and fish: "Light Leather +2 (14)", the
--  number in brackets being how many you now carry, and "Skinning: 76" when a
--  gathering skill goes up. Same spot, same yellow, same fade (UIErrorsFrame).
--
--  What counts as gathered: anything looted within a few seconds of finishing
--  a gathering cast, plus leather, ore/stone and herbs however they arrive.
-------------------------------------------------------------------------------
local _, ns = ...

local isSecret = issecretvalue or function() return false end

-- rank-1 ids, only used to learn the spells' names in this client's language
local GATHER_SPELLS = { 8613, 2575, 2366, 7620 } -- Skinning, Mining, Herb Gathering, Fishing
local GATHER_SKILLS = { 8613, 2575, 2366, 7620, 2580, 2383 } -- + Find Minerals / Find Herbs (skill names differ per client)
local TRADE_GOODS, LEATHER, METAL_STONE, HERB = 7, 6, 7, 9
local WINDOW = 4 -- seconds after a gathering cast that loot still counts

local gatherNames, skillNames = {}, {}
local lastGather = 0

-- "You receive loot: %sx%d." -> a Lua pattern capturing the link and the count
local function ToPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    -- mark the placeholders (%s, %d, %1$s), escape the rest, then swap them in
    local p = fmt:gsub("%%%d?%$?([sd])", "\1%1")
    p = p:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%0")
    p = p:gsub("\1s", "(.+)"):gsub("\1d", "(%%d+)")
    return "^" .. p .. "$"
end

local patterns -- { { pattern, hasCount } }, most specific first
local function Patterns()
    if patterns then return patterns end
    patterns = {}
    for _, g in ipairs({ { LOOT_ITEM_SELF_MULTIPLE, true }, { LOOT_ITEM_PUSHED_SELF_MULTIPLE, true },
                         { LOOT_ITEM_SELF, false }, { LOOT_ITEM_PUSHED_SELF, false } }) do
        local p = ToPattern(g[1])
        if p then patterns[#patterns + 1] = { p, g[2] } end
    end
    return patterns
end

local function IsGathered(itemID)
    if GetTime() - lastGather <= WINDOW then return true end
    local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(itemID)
    return classID == TRADE_GOODS and (subID == LEATHER or subID == METAL_STONE or subID == HERB)
end

local function Flash(text)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(text, 1, 0.82, 0)
    end
end

-- several stacks of one item in one loot window become one line
local pending, order = {}, {}
local function Flush()
    for _, itemID in ipairs(order) do
        local got = pending[itemID]
        local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID) or (GetItemInfo and GetItemInfo(itemID))
        local have = C_Item.GetItemCount and C_Item.GetItemCount(itemID) or 0
        if name then
            if have and have > got then
                Flash(("%s +%d (%d)"):format(name, got, have))
            else
                Flash(("%s +%d"):format(name, got))
            end
        end
    end
    pending, order = {}, {}
end

local function OnLoot(msg)
    if not ns.db.gatherPopups or type(msg) ~= "string" or isSecret(msg) then return end
    for _, p in ipairs(Patterns()) do
        local link, count = msg:match(p[1])
        if link then
            local itemID = tonumber(link:match("item:(%d+)"))
            if not itemID or not IsGathered(itemID) then return end
            if not pending[itemID] then
                order[#order + 1] = itemID
                -- a moment later, so the bag count already includes it
                if #order == 1 then C_Timer.After(0.3, Flush) end
            end
            pending[itemID] = (pending[itemID] or 0) + (p[2] and tonumber(count) or 1)
            return
        end
    end
end

local skillPattern
local function OnSkill(msg)
    if not ns.db.gatherPopups or type(msg) ~= "string" or isSecret(msg) then return end
    skillPattern = skillPattern or ToPattern(ERR_SKILL_UP_SI)
    if not skillPattern then return end
    local skill, level = msg:match(skillPattern)
    if skill and skillNames[skill] then
        Flash(("%s: %s"):format(skill, level))
    end
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, a, _, spellID)
    if event == "CHAT_MSG_LOOT" then
        pcall(OnLoot, a)
    elseif event == "CHAT_MSG_SKILL" then
        pcall(OnSkill, a)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if a ~= "player" or isSecret(spellID) or not spellID then return end
        local name = C_Spell.GetSpellName(spellID)
        if name and gatherNames[name] then lastGather = GetTime() end
    end
end)

ns.OnLogin(function()
    for _, id in ipairs(GATHER_SPELLS) do
        local n = C_Spell.GetSpellName(id)
        if n then gatherNames[n] = true end
    end
    for _, id in ipairs(GATHER_SKILLS) do
        local n = C_Spell.GetSpellName(id)
        if n then skillNames[n] = true end
    end
    -- the skill line is "Herbalism", its gathering spell "Herb Gathering"
    if PROFESSIONS_HERBALISM then skillNames[PROFESSIONS_HERBALISM] = true end
    skillNames["Herbalism"] = true
    ev:RegisterEvent("CHAT_MSG_LOOT")
    ev:RegisterEvent("CHAT_MSG_SKILL")
    ev:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
end)
