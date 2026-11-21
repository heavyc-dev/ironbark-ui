-------------------------------------------------------------------------------
--  Ironbark UI - five second rule spark on the player mana bar
--
--  Spirit regen stops when a spell that costs mana finishes casting and
--  resumes 5 seconds later. Each such cast starts (or restarts) a spark that
--  slides left to right across the mana bar over those 5 seconds.
--
--  Mana is a SECRET value in combat on this client, so nothing here reads
--  mana. The only signals are the cast event and the spell's cost type.
--  Approach borrowed from EllesmereUI_ManaRegenSpark.lua.
-------------------------------------------------------------------------------
local _, ns = ...

local _, CLASS = UnitClass("player")
if CLASS == "WARRIOR" or CLASS == "ROGUE" then return end

local MANA = Enum.PowerType.Mana
local WINDOW = 5
local SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"
local isSecret = issecretvalue or function() return false end

local spark, startTime
local driver = CreateFrame("Frame")
driver:Hide()

local function ManaBar()
    return PlayerFrame and PlayerFrame.manabar
end

-- A secret cost counts as a cost; only a plain 0 is free.
local function CostsMana(spellID)
    if not spellID or isSecret(spellID) then return false end
    local costs = C_Spell and C_Spell.GetSpellPowerCost and C_Spell.GetSpellPowerCost(spellID)
    for _, c in ipairs(costs or {}) do
        if not isSecret(c.type) and c.type == MANA then
            local amt = c.cost
            return isSecret(amt) or (type(amt) == "number" and amt > 0)
        end
    end
    return false
end

local function ShowingMana()
    local t = UnitPowerType("player")
    return not isSecret(t) and t == MANA
end

local function Stop()
    driver:Hide()
    startTime = nil
    if spark then spark:Hide() end
end

local function Build()
    local bar = ManaBar()
    if spark or not bar then return spark ~= nil end
    spark = bar:CreateTexture(nil, "OVERLAY", nil, 7)
    spark:SetTexture(SPARK)
    spark:SetBlendMode("ADD")
    spark:Hide()
    return true
end

driver:SetScript("OnUpdate", function()
    local bar = ManaBar()
    if not (startTime and bar and bar:IsVisible() and ShowingMana()) then
        if spark then spark:Hide() end
        if startTime and GetTime() - startTime >= WINDOW then Stop() end
        return
    end
    local p = (GetTime() - startTime) / WINDOW
    if p >= 1 then Stop() return end
    local w, h = bar:GetWidth(), bar:GetHeight()
    local tint = ns.db.natureColors and ns.MOONLIGHT
    if tint then spark:SetVertexColor(tint[1], tint[2], tint[3]) else spark:SetVertexColor(1, 1, 1) end
    spark:SetSize(12, h * 2.4)
    spark:ClearAllPoints()
    spark:SetPoint("CENTER", bar, "LEFT", w * p, 0)
    spark:Show()
end)

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, _, _, _, spellID)
    if not ns.db.manaRegenSweep or not CostsMana(spellID) then return end
    if not Build() then return end
    startTime = GetTime()
    driver:Show()
end)

function ns.RefreshManaRegen()
    if ns.db.manaRegenSweep then
        ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    else
        ev:UnregisterAllEvents()
        Stop()
    end
end

ns.OnLogin(ns.RefreshManaRegen)
