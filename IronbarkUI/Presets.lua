-------------------------------------------------------------------------------
--  Ironbark UI - the layout
--
--  An Edit Mode layout for the DEFAULT Blizzard frames. Coordinates are
--  UIParent units at the layout's uiScale. Anchors are
--  { point, relativeTo, relativePoint, x, y }; relativeTo may be another Edit
--  Mode frame so groups stay glued together on any aspect ratio.
--
--  Action bar keys map to Enum.EditModeActionBarSystemIndices:
--    MainBar = Action Bar 1, Bar2 = Bottom Left (Action Bar 2),
--    Bar3 = Bottom Right (Action Bar 3), RightBar1/2 = Action Bars 4/5,
--    ExtraBar1..3 = Action Bars 6-8
--
--  Ironbark:
--    three 12-wide bars stacked bottom-up and touching (Bar3 -> Bar2 ->
--    Action Bar 1), gryphons flanking the whole block
--    cast bar centered at y -225, player/target hugging its ends (12 gap)
--    party: Blizzard's classic party frames at 150% in a centered row below
--    raid: above the chat, groups as rows of 5, class colors + power bars
--    XP bar top of screen, minimap top-right, chat bottom-left,
--    micro menu top-left with a collapsible bag bar expanding to its right
-------------------------------------------------------------------------------
local _, ns = ...


-- bump when the layout below changes: players who applied an older one are
-- offered the new one at login (layout only)
ns.LAYOUT_VERSION = 3 -- 3: auto loot + hold to cast

ns.presets = {
    ironbark = {
        name = "Ironbark",
        description = "Stacked center bars framed by gryphons, frames around the cast bar, party row below.",
        uiScale = 0.64,
        actionBars = {
            -- which of bars 2-8 are enabled: three 12-wide bars, nothing else
            enabled = { Bar2 = true, Bar3 = true, RightBar1 = false, RightBar2 = false,
                        ExtraBar1 = false, ExtraBar2 = false, ExtraBar3 = false },
            -- 12 on Action Bar 1 so every druid form page shows all its slots.
            -- stackGap: button-to-button gap (0 = touching), measured when applying
            bars = {
                MainBar   = { anchor = { "BOTTOM", "MultiBarBottomLeft", "TOP", 0, 0 }, stackGap = 0,
                              icons = 12, rows = 1, iconSize = 90, hideArt = false, hideScrolling = true },
                Bar2      = { anchor = { "BOTTOM", "MultiBarBottomRight", "TOP", 0, 0 }, stackGap = 0,
                              icons = 12, rows = 1, iconSize = 90 },
                Bar3      = { anchor = { "BOTTOM", "UIParent", "BOTTOM", 0, 4 },
                              icons = 12, rows = 1, iconSize = 90 },
                -- forms: a small column left of your portrait, centered on it
                StanceBar = { anchor = { "RIGHT", "PlayerFrame", "LEFT", -4, 0 }, iconSize = 70,
                              horizontal = false, rows = 1 },
            },
        },
        unitFrames = {
            -- player and target hug the ends of the centered cast bar
            Player = { anchor = { "RIGHT", "PlayerCastingBarFrame", "LEFT", -12, 0 } },
            -- -2: Blizzard's target art sits ~3px higher in its frame than the player's
            Target = { anchor = { "LEFT", "PlayerCastingBarFrame", "RIGHT", 12, -2 } },
            -- classic party frames (portrait, health, power) at 150%; Frames.lua
            -- lays them out in a row centered on this TOP-center anchor
            Party  = { anchor = { "TOP", "UIParent", "CENTER", 0, -325 },
                       raidStyle = false, horizontal = false, frameSize = 150 },
            -- raid: above the chat (its tabs), groups as rows of 5
            Raid   = { anchor = { "BOTTOMLEFT", "ChatFrame1", "TOPLEFT", -4, 34 }, horizontal = true },
        },
        -- gryphons flank the whole three-bar block, feet level with the bottom bar
        endCaps = {
            Left  = { "BOTTOMRIGHT", "MultiBarBottomRight", "BOTTOMLEFT", 8, -4 },
            Right = { "BOTTOMLEFT", "MultiBarBottomRight", "BOTTOMRIGHT", -8, -4 },
        },
        castBarLockToPlayer = false,
        castBarShowTime = true,
        systems = {
            CastBar           = { anchor = { "CENTER", "UIParent", "CENTER", 0, -225 } },
            StatusTrackingBar = { anchor = { "TOP", "UIParent", "TOP", 0, 0 } },
            -- micro menu top-left; the bag bar sits to its right, hidden until
            -- its arrow is clicked
            MicroMenu         = { anchor = { "TOPLEFT", "UIParent", "TOPLEFT", 8, -4 } },
            Bags              = { anchor = { "LEFT", "MicroMenuContainer", "RIGHT", 6, 0 } },
            Minimap           = { anchor = { "TOPRIGHT", "UIParent", "TOPRIGHT", -4, -4 } },
            -- your buffs: left of the minimap, dropped clear of the XP bar
            BuffFrame         = { system = "AuraFrame", index = "BuffFrame",
                                  anchor = { "TOPRIGHT", "MinimapCluster", "TOPLEFT", -10, -18 } },
            ObjectiveTracker  = { anchor = { "TOPRIGHT", "UIParent", "TOPRIGHT", -10, -300 } },
            ChatFrame         = { anchor = { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 46, 15 },
                                  width = 372, height = 295 },
        },
    },
}
