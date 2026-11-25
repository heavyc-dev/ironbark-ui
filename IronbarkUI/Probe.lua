-------------------------------------------------------------------------------
--  Ironbark UI - /ibui probe
--  Support tool: for 40 seconds, once a second, notes what this client lets an
--  addon see about incoming heals and auras (in and out of combat). The notes
--  are kept in the saved settings (probeLog) so they can be read from the
--  SavedVariables file after a /reload; nothing else uses them.
-------------------------------------------------------------------------------
local _, ns = ...

local isSecret = issecretvalue or function() return false end
local SECONDS = 40

local function S(v)
    if isSecret(v) then return "secret" end
    if type(v) == "number" then return ("%.1f"):format(v) end
    return tostring(v)
end

-- call fn(...) and describe every result; "n/a" when the API isn't there
local function Try(fn, ...)
    if type(fn) ~= "function" then return "n/a" end
    local r = { pcall(fn, ...) }
    if not r[1] then return "err:" .. tostring(r[2]):sub(1, 60) end
    local out = {}
    for i = 2, math.max(2, #r) do out[#out + 1] = S(r[i]) end
    return table.concat(out, ",")
end

local function Auras(unit, filter)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return "n/a" end
    local total, named, names = 0, 0, {}
    for i = 1, 40 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
        if not ok or not a then break end
        total = total + 1
        if not isSecret(a.name) then
            named = named + 1
            local pts = ""
            if type(a.points) == "table" and not isSecret(a.points) then
                local p = {}
                for _, v in ipairs(a.points) do p[#p + 1] = S(v) end
                pts = "(" .. table.concat(p, "/") .. ")"
            end
            local kind = ""
            if isSecret(a.dispelName) then
                kind = "[?]"
            elseif a.dispelName then
                kind = "[" .. a.dispelName .. "]"
            end
            if #names < 8 then names[#names + 1] = a.name .. pts .. kind end
        end
    end
    return ("%d/%d readable %s"):format(named, total, table.concat(names, "; "))
end

local function Sample(unit)
    local parts = { unit }
    parts[#parts + 1] = "hp=" .. Try(UnitHealth, unit) .. "/" .. Try(UnitHealthMax, unit)
    parts[#parts + 1] = "incAll=" .. Try(UnitGetIncomingHeals, unit)
    parts[#parts + 1] = "incMine=" .. Try(UnitGetIncomingHeals, unit, "player")
    parts[#parts + 1] = "absorb=" .. Try(UnitGetTotalAbsorbs, unit)
    parts[#parts + 1] = "detailed=" .. Try(UnitGetDetailedHealPrediction, unit, "player")
    parts[#parts + 1] = "calc=" .. type(CreateUnitHealPredictionCalculator)
    parts[#parts + 1] = "buffs=" .. Auras(unit, "HELPFUL")
    parts[#parts + 1] = "mine=" .. Auras(unit, "HELPFUL|PLAYER")
    parts[#parts + 1] = "debuffs=" .. Auras(unit, "HARMFUL")
    parts[#parts + 1] = "dispellable=" .. Auras(unit, "HARMFUL|RAID")
    return table.concat(parts, " | ")
end

local running
function ns.Probe()
    if running then
        ns.Print("Probe is already running.")
        return
    end
    running = true
    local _, build, _, toc = GetBuildInfo()
    local log = { "client " .. tostring(toc) .. " build " .. tostring(build) }
    ns.db.probeLog = log
    ns.Print("Probe: %d seconds. Cast a heal-over-time on yourself now, then pull a mob and cast it again in combat.", SECONDS)
    local n = 0
    local ticker
    ticker = C_Timer.NewTicker(1, function()
        n = n + 1
        local cs = C_Secrets
        local head = ("t=%d combat=%s aurasSecret=%s"):format(n, tostring(InCombatLockdown()),
            cs and Try(cs.ShouldAurasBeSecret) or "n/a")
        local ok, line = pcall(Sample, "player")
        log[#log + 1] = head .. " || " .. (ok and line or ("sample failed: " .. tostring(line)))
        if UnitExists("target") and not UnitIsUnit("target", "player") then
            local ok2, line2 = pcall(Sample, "target")
            log[#log + 1] = "   " .. (ok2 and line2 or tostring(line2))
        end
        if n >= SECONDS then
            ticker:Cancel()
            running = nil
            ns.Print("Probe done. Type /reload so the notes are saved.")
        end
    end)
end
