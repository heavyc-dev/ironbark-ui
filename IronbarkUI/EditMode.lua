-------------------------------------------------------------------------------
--  Ironbark UI - Edit Mode layout builder
--
--  Builds an account-wide Edit Mode layout named "Ironbark UI" from a preset
--  and makes it active. Every frame stays the stock Blizzard frame; we only
--  write the same data Edit Mode itself saves, so the user can keep tweaking
--  in Edit Mode afterwards.
--
--  Pattern (proven by EllesmereUI on this client):
--    * start from a copy of Blizzard's "Modern" preset so every system and
--      setting exists with sane values
--    * patch anchors + a few settings
--    * C_EditMode.SaveLayouts(presets + saved layouts) then SetActiveLayout
--    * ReloadUI right after, so Edit Mode picks it up untainted
--  EditModeManagerFrame:ImportLayout is avoided: it errors until Edit Mode has
--  been opened once in the session.
-------------------------------------------------------------------------------
local _, ns = ...

local function Enum_(tbl, key)
    local t = Enum and Enum[tbl]
    return t and t[key]
end

local function DeepCopy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = DeepCopy(v) end
    return c
end

local function EditModeOpen()
    local emf = EditModeManagerFrame
    return emf and (emf.editModeActive or emf:IsShown()) or false
end

-- Presets first, then saved layouts: the shape SaveLayouts expects.
local function LayoutsForSave()
    local ok, info = pcall(C_EditMode.GetLayouts)
    if not ok or type(info) ~= "table" or type(info.layouts) ~= "table" then return nil end
    local mgr = EditModePresetLayoutManager
    local presets = mgr and mgr.GetCopyOfPresetLayouts and mgr:GetCopyOfPresetLayouts()
    if type(presets) ~= "table" or #presets == 0 then return nil end
    local n = #presets
    for i = 1, #info.layouts do presets[n + i] = info.layouts[i] end
    info.layouts = presets
    return info, n, presets[1]
end

local function FindSystem(layout, system, index)
    for _, sys in ipairs(layout.systems) do
        if sys.system == system and (index == nil or sys.systemIndex == index) then
            return sys
        end
    end
end
ns.LayoutsForSave, ns.FindSystem = LayoutsForSave, FindSystem

local function GetSetting(sys, setting)
    for _, s in ipairs(sys.settings) do
        if s.setting == setting then return s end
    end
    local s = { setting = setting, value = 0 }
    sys.settings[#sys.settings + 1] = s
    return s
end

local function SetSetting(sys, settingKey, enumTbl, value)
    local setting = Enum_(enumTbl, settingKey)
    if setting == nil or not sys then return false end
    GetSetting(sys, setting).value = value
    return true
end

-- Slider settings: some are stored as the display value, some as a step index
-- ((value - min) / step). Best source is the live system frame: compare its
-- raw and display values and read min/step from Blizzard's display info.
-- Fallback: compare the untouched preset's raw value to the known default.
-- Skip (and report) if neither proves the encoding.
local skipped = {}

local function SliderInfo(system, setting)
    local mgr = EditModeSettingDisplayInfoManager
    local list = mgr and mgr.GetSystemSettingDisplayInfo and mgr:GetSystemSettingDisplayInfo(system)
    for _, info in ipairs(list or {}) do
        if info.setting == setting then return info end
    end
end
ns.SliderInfo = SliderInfo

local function EncodeFromLiveFrame(frameName, system, setting, value)
    local frame = frameName and _G[frameName]
    if not (frame and frame.GetSettingValue) then return nil end
    local okR, raw = pcall(frame.GetSettingValue, frame, setting, true)
    local okD, disp = pcall(frame.GetSettingValue, frame, setting)
    if not (okR and okD and type(raw) == "number" and type(disp) == "number") then return nil end
    if raw == disp then return value end
    local info = SliderInfo(system, setting)
    local min = info and info.minValue
    if not min then return nil end
    -- never write past what the Edit Mode slider allows
    if info.maxValue then value = math.min(value, info.maxValue) end
    value = math.max(value, min)
    -- stored as (value - min) / step; seen on this client with the slider's
    -- step (icon size) and with step 1 even when the slider moves by 2 (party
    -- frame width/height: raw 26 = 98 wide, min 72)
    for _, step in ipairs({ info.stepSize or 1, 1 }) do
        if step > 0 and math.abs(raw - (disp - min) / step) < 0.01 then
            return math.floor((value - min) / step + 0.5)
        end
    end
end

local function SetSlider(sys, baseSys, settingKey, enumTbl, value, spec, frameName)
    local setting = Enum_(enumTbl, settingKey)
    if setting == nil or not sys or not baseSys then return end
    local encoded = EncodeFromLiveFrame(frameName, sys.system, setting, value)
    local raw = GetSetting(baseSys, setting).value
    if encoded then
        -- proven by the live frame
    elseif raw == spec.default then
        encoded = value
    elseif spec.min and spec.step and raw == (spec.default - spec.min) / spec.step then
        encoded = math.floor((value - spec.min) / spec.step + 0.5)
    end
    if encoded then
        GetSetting(sys, setting).value = encoded
    else
        skipped[#skipped + 1] = settingKey
    end
end

local function SetAnchor(sys, a)
    if not sys or not a then return end
    sys.isInDefaultPosition = false
    sys.anchorInfo = {
        point = a[1], relativeTo = a[2], relativePoint = a[3],
        offsetX = a[4], offsetY = a[5],
    }
    -- second anchor slot (used by a few systems) must not fight the first
    sys.anchorInfo2 = nil
end

-------------------------------------------------------------------------------
--  Patch a layout table in place from a preset.
-------------------------------------------------------------------------------
local ICON_SIZE   = { default = 100, min = 50, step = 10 }
local PARTY_W     = { default = 72 }
local PARTY_H     = { default = 36 }
local FRAME_SIZE  = { default = 100 }

-- Edit Mode system frames, for reading live slider encodings.
local BAR_FRAME = {
    MainBar = "MainActionBar", Bar2 = "MultiBarBottomLeft", Bar3 = "MultiBarBottomRight",
    RightBar1 = "MultiBarRight", RightBar2 = "MultiBarLeft",
    ExtraBar1 = "MultiBar5", ExtraBar2 = "MultiBar6", ExtraBar3 = "MultiBar7",
    StanceBar = "StanceBar", PetActionBar = "PetActionBar",
}
local UNIT_FRAME = { Player = "PlayerFrame", Target = "TargetFrame", Focus = "FocusFrame", Party = "PartyFrame" }

-- Stacked bars: each bar frame has its own padding around its buttons (Action
-- Bar 1 carries extra art space), so equal anchor gaps don't look equal.
-- Measure the live frames and return the anchor offset that gives exactly
-- `gap` UI units between the lower bar's buttons and this bar's buttons.
local BUTTON_PREFIX = {
    MainActionBar = "ActionButton", MultiBarBottomLeft = "MultiBarBottomLeftButton",
    MultiBarBottomRight = "MultiBarBottomRightButton",
}

local function ButtonPadding(frameName)
    local f, prefix = _G[frameName], BUTTON_PREFIX[frameName]
    if not (f and prefix and f:GetTop()) then return nil end
    local ui = UIParent:GetEffectiveScale()
    local fs = f:GetEffectiveScale() / ui
    local top, bottom
    for i = 1, 12 do
        local b = _G[prefix .. i]
        if b and b:IsShown() and b:GetTop() then
            local s = b:GetEffectiveScale() / ui
            top = math.max(top or -math.huge, b:GetTop() * s)
            bottom = math.min(bottom or math.huge, b:GetBottom() * s)
        end
    end
    if not top then return nil end
    -- Action Bar 1's outline (shown with the gryphons) is part of what you
    -- see, so measure from it rather than from the buttons
    local art = f.BorderArt
    if art and art:IsShown() and art:GetTop() then
        local s = art:GetEffectiveScale() / ui
        top = math.max(top, art:GetTop() * s)
        bottom = math.min(bottom, art:GetBottom() * s)
    end
    return f:GetTop() * fs - top, bottom - f:GetBottom() * fs, fs
end

-- for /ibui debug: the visible gaps between the stacked bars, in UI units
function ns.BarGaps()
    local function edges(name)
        local padTop, padBottom, fs = ButtonPadding(name)
        local f = _G[name]
        if not (padTop and f and f:GetTop()) then return nil end
        return f:GetTop() * fs - padTop, f:GetBottom() * fs + padBottom
    end
    local _, mainBottom = edges("MainActionBar")
    local b2Top, b2Bottom = edges("MultiBarBottomLeft")
    local b3Top = edges("MultiBarBottomRight")
    local function gap(a, b) return (a and b) and string.format("%.1f", a - b) or "?" end
    return ("barGaps: main-bar2=%s bar2-bar3=%s"):format(gap(mainBottom, b2Top), gap(b2Bottom, b3Top))
end

local function StackedOffset(selfName, belowName, gap)
    local belowTop = select(1, ButtonPadding(belowName))
    local _, selfBottom, selfScale = ButtonPadding(selfName)
    if not (belowTop and selfBottom) then return nil end
    -- anchor offsets are in the anchored frame's own scale
    return (gap - belowTop - selfBottom) / selfScale
end

local function ApplyPresetToLayout(layout, base, preset)
    local S = Enum.EditModeSystem

    -- Action bars
    local AB = S.ActionBar
    for key, cfg in pairs(preset.actionBars.bars) do
        local idx = Enum_("EditModeActionBarSystemIndices", key)
        local sys = idx and FindSystem(layout, AB, idx)
        local baseSys = idx and FindSystem(base, AB, idx)
        if sys then
            local anchor = cfg.anchor
            if cfg.stackGap then
                local y = StackedOffset(BAR_FRAME[key], anchor[2], cfg.stackGap)
                if y then anchor = { anchor[1], anchor[2], anchor[3], anchor[4], y } end
            end
            SetAnchor(sys, anchor)
            local H = Enum_("ActionBarOrientation", "Horizontal") or 0
            local V = Enum_("ActionBarOrientation", "Vertical") or 1
            if cfg.horizontal ~= nil then
                SetSetting(sys, "Orientation", "EditModeActionBarSetting", cfg.horizontal and H or V)
            end
            if cfg.rows  then SetSetting(sys, "NumRows",  "EditModeActionBarSetting", cfg.rows)  end
            if cfg.icons then SetSetting(sys, "NumIcons", "EditModeActionBarSetting", cfg.icons) end
            if cfg.hideArt ~= nil then
                SetSetting(sys, "HideBarArt", "EditModeActionBarSetting", cfg.hideArt and 1 or 0)
            end
            if cfg.hideScrolling ~= nil then
                SetSetting(sys, "HideBarScrolling", "EditModeActionBarSetting", cfg.hideScrolling and 1 or 0)
            end
            if cfg.showEmpty ~= nil then
                SetSetting(sys, "AlwaysShowButtons", "EditModeActionBarSetting", cfg.showEmpty and 1 or 0)
            end
            if cfg.visible then
                local v = Enum_("ActionBarVisibleSetting", cfg.visible)
                if v then SetSetting(sys, "VisibleSetting", "EditModeActionBarSetting", v) end
            end
            if cfg.iconSize then
                SetSlider(sys, baseSys, "IconSize", "EditModeActionBarSetting", cfg.iconSize, ICON_SIZE,
                    BAR_FRAME[key])
            end
        end
    end

    -- Unit frames
    local UF = S.UnitFrame
    for key, cfg in pairs(preset.unitFrames) do
        local idx = Enum_("EditModeUnitFrameSystemIndices", key)
        local sys = idx and FindSystem(layout, UF, idx)
        local baseSys = idx and FindSystem(base, UF, idx)
        if sys then
            SetAnchor(sys, cfg.anchor)
            if cfg.raidStyle ~= nil then
                SetSetting(sys, "UseRaidStylePartyFrames", "EditModeUnitFrameSetting", cfg.raidStyle and 1 or 0)
            end
            if cfg.horizontal ~= nil then
                SetSetting(sys, "UseHorizontalGroups", "EditModeUnitFrameSetting", cfg.horizontal and 1 or 0)
            end
            if cfg.width then
                SetSlider(sys, baseSys, "FrameWidth", "EditModeUnitFrameSetting", cfg.width, PARTY_W, UNIT_FRAME[key])
            end
            if cfg.height then
                SetSlider(sys, baseSys, "FrameHeight", "EditModeUnitFrameSetting", cfg.height, PARTY_H, UNIT_FRAME[key])
            end
            if cfg.frameSize then
                SetSlider(sys, baseSys, "FrameSize", "EditModeUnitFrameSetting", cfg.frameSize, FRAME_SIZE, UNIT_FRAME[key])
            end
        end
    end

    -- Gryphons. On WoW Forever each end cap is its own Edit Mode system; by
    -- default they sit at the outer ends of the classic row (bar + micro +
    -- bags). Read each cap frame's system id at runtime: no enum name needed.
    local bar = MainActionBar or MainMenuBar
    local caps = bar and bar.EndCaps
    for side, a in pairs(preset.endCaps or {}) do
        local cap = caps and caps[side .. "EndCap"]
        local sys = cap and cap.system and FindSystem(layout, cap.system, cap.systemIndex)
        if sys then
            SetAnchor(sys, a)
        else
            skipped[#skipped + 1] = side .. " gryphon"
        end
    end

    -- Player cast bar
    if S.CastBar then
        local cb = FindSystem(layout, S.CastBar)
        SetSetting(cb, "LockToPlayerFrame", "EditModeCastBarSetting", preset.castBarLockToPlayer and 1 or 0)
        if preset.castBarShowTime ~= nil then
            SetSetting(cb, "ShowCastTime", "EditModeCastBarSetting", preset.castBarShowTime and 1 or 0)
        end
    end

    -- Everything else: anchors (+ chat size)
    for key, cfg in pairs(preset.systems or {}) do
        local system = S[cfg.system or key]
        -- systems with several frames (buffs / debuffs) name theirs by index
        local index = cfg.index and Enum_("EditMode" .. (cfg.system or key) .. "SystemIndices", cfg.index)
        local sys = system and (not cfg.index or index) and FindSystem(layout, system, index)
        if cfg.index and not sys then skipped[#skipped + 1] = key end
        if sys then
            SetAnchor(sys, cfg.anchor)
            if key == "ChatFrame" and cfg.width and cfg.height then
                -- chat size is stored split into hundreds + remainder
                local E = "EditModeChatFrameSetting"
                if Enum_(E, "WidthHundreds") then
                    SetSetting(sys, "WidthHundreds", E, math.floor(cfg.width / 100))
                    SetSetting(sys, "WidthTensAndOnes", E, cfg.width % 100)
                    SetSetting(sys, "HeightHundreds", E, math.floor(cfg.height / 100))
                    SetSetting(sys, "HeightTensAndOnes", E, cfg.height % 100)
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Non-layout bits of a preset: which bars are on, UI scale, party CVars.
-------------------------------------------------------------------------------
local BAR_PROXY = {
    Bar2 = "PROXY_SHOW_ACTIONBAR_2", Bar3 = "PROXY_SHOW_ACTIONBAR_3",
    RightBar1 = "PROXY_SHOW_ACTIONBAR_4", RightBar2 = "PROXY_SHOW_ACTIONBAR_5",
    ExtraBar1 = "PROXY_SHOW_ACTIONBAR_6", ExtraBar2 = "PROXY_SHOW_ACTIONBAR_7",
    ExtraBar3 = "PROXY_SHOW_ACTIONBAR_8",
}

local function ApplyBarToggles(enabled)
    local okAll = true
    if Settings and Settings.SetValue then
        for key, proxy in pairs(BAR_PROXY) do
            if enabled[key] ~= nil then
                local ok = pcall(Settings.SetValue, proxy, enabled[key])
                okAll = okAll and ok
            end
        end
        if okAll then return end
    end
    if SetActionBarToggles then
        local e = enabled
        pcall(SetActionBarToggles, e.Bar2, e.Bar3, e.RightBar1, e.RightBar2,
            e.ExtraBar1, e.ExtraBar2, e.ExtraBar3)
    end
end

-------------------------------------------------------------------------------
--  UI scale. The layout's groups each hang off a screen edge, so scaling up
--  can't make frames overlap inside a group; the only limit is side to side,
--  where the bottom-left group (chat, raid) and the top-left group (micro menu
--  + open bag bar) meet the center column (bars + gryphons, stance bar +
--  player frame, XP bar). Both widths are fixed in UI units, and the screen is
--  768 / scale units tall, so the biggest scale that keeps them apart depends
--  only on the screen's shape.
-------------------------------------------------------------------------------
ns.MIN_UI_SCALE = 0.64
local CENTER_HALF = 380 -- widest half of the center column (stance bar / gryphon tip)
local SIDE_REACH  = 420 -- right edge of the chat from the left screen edge
local SIDE_MARGIN = 10

function ns.MaxUIScale()
    local w, h
    if GetPhysicalScreenSize then w, h = GetPhysicalScreenSize() end
    if not (w and h and h > 0) then w, h = UIParent:GetWidth(), UIParent:GetHeight() end
    local max = 384 * (w / h) / (CENTER_HALF + SIDE_REACH + SIDE_MARGIN)
    max = math.floor(max * 100 + 0.001) / 100 -- whole slider steps
    return math.max(ns.MIN_UI_SCALE, math.min(1, max))
end

-- the scale Ironbark applies: the saved one, kept inside what this screen fits
function ns.LayoutScale()
    local s = tonumber(ns.db.uiScale) or ns.presets.ironbark.uiScale
    s = math.floor(s * 100 + 0.5) / 100
    return math.max(ns.MIN_UI_SCALE, math.min(ns.MaxUIScale(), s))
end

-- Set the game's UI scale now (no reload: the layout is the same at any scale).
function ns.ApplyUIScale()
    if not ns.db.manageUIScale then return end
    if InCombatLockdown() then
        ns.RunOutOfCombat("uiScale", ns.ApplyUIScale)
        return
    end
    SetCVar("useUiScale", "1")
    SetCVar("uiScale", string.format("%.2f", ns.LayoutScale()))
    -- EllesmereUI (kept for its QoL modules) scales UIParent itself at every
    -- login from its own saved value: keep that value in step with ours.
    local pp = EllesmereUI and EllesmereUI.PP
    if pp and pp.SetUIScale and math.abs(UIParent:GetScale() - ns.LayoutScale()) > 0.001 then
        pcall(pp.SetUIScale, ns.LayoutScale())
    end
end

-- with the layout applied, the scale is ours at every login (see above)
ns.OnLogin(function()
    if ns.db.revert and EllesmereUI and EllesmereUI.PP then
        C_Timer.After(1, ns.ApplyUIScale)
    end
end)

local function ApplyCVars(preset)
    ns.ApplyUIScale()
    local party = preset.unitFrames.Party
    if party and party.raidStyle ~= nil then
        SetCVar("useCompactPartyFrames", party.raidStyle and "1" or "0")
    end
    if ns.db.classColors then
        SetCVar("raidFramesDisplayClassColor", "1")
    end
    -- raid frames: a power bar (mana / rage / energy) on everyone
    SetCVar("raidFramesDisplayPowerBars", "1")
    SetCVar("raidFramesDisplayOnlyHealerPowerBars", "0")
    if ns.db.compactText then
        -- our formatter rewrites the NUMERIC string
        SetCVar("statusTextDisplay", "NUMERIC")
    end
    -- 0 = text on mouseover (Frames.lua also shows it during combat)
    SetCVar("statusText", "0")
    -- auto loot; hold a key to keep casting its spell (when this client has it)
    SetCVar("autoLootDefault", "1")
    if GetCVar("ActionButtonUseKeyHeldSpell") ~= nil then SetCVar("ActionButtonUseKeyHeldSpell", "1") end
end

-------------------------------------------------------------------------------
--  Public: apply a preset (out of combat), then reload.
-------------------------------------------------------------------------------
function ns.ApplyPreset(key)
    local preset = ns.presets[key]
    if not preset then
        ns.Print("Unknown preset '%s'. Try /ibui presets", tostring(key))
        return false
    end
    if InCombatLockdown() then
        ns.Print("Can't change layout in combat; will apply when combat ends.")
        ns.RunOutOfCombat("applyPreset", function() ns.ApplyPreset(key) end)
        return false
    end
    if EditModeOpen() then
        ns.Print("Close Edit Mode first.")
        return false
    end
    if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts
        and C_EditMode.SetActiveLayout and Enum and Enum.EditModeSystem) then
        ns.Print("Edit Mode API not available on this client.")
        return false
    end

    local info, presetCount, modern = LayoutsForSave()
    if not info then
        ns.Print("Edit Mode layouts not ready yet; try again in a moment.")
        return false
    end

    -- First apply only: remember what to put back for /ibui revert.
    if not ns.db.revert then
        local prev = info.layouts[info.activeLayout]
        local cvars = {}
        for _, name in ipairs(ns.REVERT_CVARS) do cvars[name] = GetCVar(name) end
        local bars = {}
        if Settings and Settings.GetValue then
            for key, proxy in pairs(BAR_PROXY) do
                local ok, v = pcall(Settings.GetValue, proxy)
                if ok then bars[key] = v end
            end
        end
        ns.db.revert = {
            layoutName = prev and prev.layoutName,
            layoutType = prev and prev.layoutType,
            presetIndex = (info.activeLayout <= presetCount) and info.activeLayout or nil,
            cvars = cvars,
            bars = bars,
        }
    end
    -- settings added since the first apply: remember their originals too
    for _, name in ipairs(ns.REVERT_CVARS) do
        if ns.db.revert.cvars[name] == nil then ns.db.revert.cvars[name] = GetCVar(name) end
    end

    wipe(skipped)
    local layout = DeepCopy(modern)
    layout.layoutName = ns.LAYOUT_NAME
    layout.layoutType = Enum.EditModeLayoutType.Account
    ApplyPresetToLayout(layout, modern, preset)

    -- replace any earlier copy of our layout
    local layouts = info.layouts
    for i = #layouts, presetCount + 1, -1 do
        if layouts[i].layoutName == ns.LAYOUT_NAME then table.remove(layouts, i) end
    end
    -- keep it grouped with Account layouts (before the first Character layout)
    local slot = #layouts + 1
    for i = presetCount + 1, #layouts do
        if layouts[i].layoutType == Enum.EditModeLayoutType.Character then
            slot = i
            break
        end
    end
    table.insert(layouts, slot, layout)
    info.activeLayout = slot

    C_EditMode.SaveLayouts(info)
    C_EditMode.SetActiveLayout(slot)

    ApplyBarToggles(preset.actionBars.enabled)
    ApplyCVars(preset)

    ns.db.preset = key
    ns.db.appliedOnce = true
    ns.db.layoutVersion = ns.LAYOUT_VERSION
    if #skipped > 0 then
        -- stash for after reload so the user actually sees it
        ns.db.skippedSettings = table.concat(skipped, ", ")
    else
        ns.db.skippedSettings = nil
    end
    ReloadUI()
    return true
end

-------------------------------------------------------------------------------
--  Revert: put back the Edit Mode layout, bars and CVars from before the first
--  apply, and delete the "Ironbark UI" layout. Needed because layouts and some
--  CVars live on Blizzard's servers, so restoring WTF files alone won't undo them.
-------------------------------------------------------------------------------
ns.REVERT_CVARS = {
    "useUiScale", "uiScale", "useCompactPartyFrames", "raidFramesDisplayClassColor",
    "statusText", "statusTextDisplay", "combinedBags", "expandBagBar",
    "raidFramesDisplayPowerBars", "raidFramesDisplayOnlyHealerPowerBars",
    "autoLootDefault", "ActionButtonUseKeyHeldSpell",
}

function ns.Revert()
    local r = ns.db.revert
    if not r then
        ns.Print("Nothing to revert: no layout has been applied yet.")
        return
    end
    if InCombatLockdown() or EditModeOpen() then
        ns.Print("Leave combat and close Edit Mode first.")
        return
    end
    local info, presetCount = LayoutsForSave()
    if not info then
        ns.Print("Edit Mode layouts not ready yet; try again in a moment.")
        return
    end
    local layouts = info.layouts
    for i = #layouts, presetCount + 1, -1 do
        if layouts[i].layoutName == ns.LAYOUT_NAME then table.remove(layouts, i) end
    end
    local target = r.presetIndex or 1
    if not r.presetIndex and r.layoutName then
        for i = presetCount + 1, #layouts do
            if layouts[i].layoutName == r.layoutName and layouts[i].layoutType == r.layoutType then
                target = i
                break
            end
        end
    end
    info.activeLayout = target
    C_EditMode.SaveLayouts(info)
    C_EditMode.SetActiveLayout(target)

    for name, value in pairs(r.cvars or {}) do
        if value ~= nil then SetCVar(name, value) end
    end
    if r.bars and next(r.bars) then ApplyBarToggles(r.bars) end

    ns.db.revert = nil
    ns.db.appliedOnce = true -- don't prompt again after reverting
    ns.Print("Reverted. Reloading...")
    ReloadUI()
end

-- (the welcome / apply-everything / revert-everything flow lives in Setup.lua)
ns.OnLogin(function()
    if ns.db.skippedSettings then
        ns.Print("Couldn't set: %s. Adjust these in Edit Mode if needed.", ns.db.skippedSettings)
        ns.db.skippedSettings = nil
    end
end)
