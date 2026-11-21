-------------------------------------------------------------------------------
--  Ironbark UI - nameplate tweaks (Blizzard's own nameplates, settings only)
--
--    * class colors on enemy (and friendly) player nameplates
--    * stacking: plates push apart vertically instead of overlapping
--    * fade: plates you are not targeting drop to 60% opacity, and plates
--      behind walls fade further
--
--  Only game CVars change. Your previous values are recorded for /ibui revert.
-------------------------------------------------------------------------------
local _, ns = ...

local CVARS = {
    ShowClassColorInNameplate          = "1",   -- enemy players
    ShowClassColorInFriendlyNameplate  = "1",   -- friendly players
    nameplateMotion                    = "1",   -- 1 = stacking, 0 = overlapping
    nameplateSelectedAlpha             = "1",
    nameplateNotSelectedAlpha          = "0.6", -- fade everything you aren't targeting
    nameplateOccludedAlphaMult         = "0.4", -- behind walls / out of line of sight
}

local function Apply()
    if not ns.db.nameplateTweaks then return end
    if InCombatLockdown() then
        ns.RunOutOfCombat("nameplates", Apply)
        return
    end
    local r = ns.db.revert
    for name, value in pairs(CVARS) do
        local current = GetCVar(name)
        if current ~= nil then -- skip CVars this client doesn't have
            if r and r.cvars and r.cvars[name] == nil then r.cvars[name] = current end
            if current ~= value then SetCVar(name, value) end
        end
    end
end

ns.RefreshNameplates = Apply
ns.OnLogin(Apply)
