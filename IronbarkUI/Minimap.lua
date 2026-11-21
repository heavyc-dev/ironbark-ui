-------------------------------------------------------------------------------
--  Ironbark UI - minimap addon buttons tucked into one button
--
--  Addon minimap buttons (LibDBIcon ones like Leatrix, Questie, TrainerSpells,
--  plus others named like "...MinimapButton", e.g. ClickLegend's) are gathered
--  into a flyout. One small button on the minimap's bottom-left edge slides
--  them out of its left side (more rows stack upward); click again to tuck away.
--  Blizzard's own minimap buttons (zoom, tracking, mail, clock, calendar,
--  queue, addon compartment) are never touched.
-------------------------------------------------------------------------------
local _, ns = ...

local SIZE, GAP, PER_ROW = 31, 2, 6

local BLIZZARD_PREFIX = {
    "MiniMap", "Minimap", "GameTimeFrame", "TimeManager", "QueueStatus",
    "AddonCompartment", "ExpansionLandingPage", "GarrisonLandingPage", "MinimapCluster",
    "IronbarkMinimapToggle",
}

local collected, order = {}, {}
local flyout, toggle

local function IsBlizzard(name)
    for _, p in ipairs(BLIZZARD_PREFIX) do
        if name:sub(1, #p) == p and not name:find("MinimapButton", 1, true) then return true end
    end
    return false
end

local function IsAddonButton(f)
    local name = f.GetName and f:GetName()
    if not name or not f:IsObjectType("Button") then return false end
    if name:find("^LibDBIcon10_") then return true end
    if IsBlizzard(name) then return false end
    return name:find("MinimapButton$") or name:find("MinimapIcon$") or name:find("MiniMapButton$") or false
end

-------------------------------------------------------------------------------
--  Layout
-------------------------------------------------------------------------------
local function Place(btn, i)
    local col = (i - 1) % PER_ROW
    local row = math.floor((i - 1) / PER_ROW)
    btn.__ibuiSetting = true
    btn:SetParent(flyout)
    btn:ClearAllPoints()
    -- first row level with the gear button, filling leftward; more rows stack upward
    btn:SetPoint("BOTTOMRIGHT", flyout, "BOTTOMRIGHT", -col * (SIZE + GAP), row * (SIZE + GAP))
    btn.__ibuiSetting = nil
    btn:SetAlpha(1)
end

local function Layout()
    table.sort(order, function(a, b) return (a:GetName() or "") < (b:GetName() or "") end)
    local shown = 0
    for _, btn in ipairs(order) do
        -- a button its addon has hidden ("hide minimap icon") leaves no gap
        if btn:IsShown() then
            shown = shown + 1
            Place(btn, shown)
        end
    end
    local cols = math.max(1, math.min(shown, PER_ROW))
    local rows = math.max(1, math.ceil(shown / PER_ROW))
    flyout:SetSize(cols * (SIZE + GAP) - GAP, rows * (SIZE + GAP) - GAP)
    toggle:SetShown(shown > 0 and ns.db.minimapCollect)
end

local function Collect(btn)
    if collected[btn] then return end
    collected[btn] = true
    order[#order + 1] = btn
    -- addons re-anchor their buttons around the minimap now and then; keep ours
    hooksecurefunc(btn, "SetPoint", function(self)
        if self.__ibuiSetting or not ns.db.minimapCollect then return end
        C_Timer.After(0, Layout)
    end)
    -- re-pack when an addon shows or hides its own button
    hooksecurefunc(btn, "Show", function() C_Timer.After(0, Layout) end)
    hooksecurefunc(btn, "Hide", function() C_Timer.After(0, Layout) end)
end

local function Scan()
    if not ns.db.minimapCollect or not flyout then return end
    local lib = LibStub and LibStub("LibDBIcon-1.0", true)
    if lib and lib.objects then
        for _, btn in pairs(lib.objects) do Collect(btn) end
    end
    for _, parent in ipairs({ Minimap, MinimapBackdrop, MinimapCluster }) do
        if parent then
            for _, child in ipairs({ parent:GetChildren() }) do
                if IsAddonButton(child) then Collect(child) end
            end
        end
    end
    Layout()
end

-------------------------------------------------------------------------------
--  Toggle + slide
-------------------------------------------------------------------------------
local function Build()
    if flyout then return end
    flyout = CreateFrame("Frame", "IronbarkMinimapFlyout", UIParent)
    flyout:SetFrameStrata("MEDIUM")
    flyout:Hide()
    -- slides out of the gear button's left side + fades in
    local function Home(dx)
        flyout:ClearAllPoints()
        flyout:SetPoint("BOTTOMRIGHT", toggle, "BOTTOMLEFT", -2 + dx, 0)
    end
    local ag = flyout:CreateAnimationGroup()
    local move = ag:CreateAnimation("Translation")
    move:SetOffset(-20, 0)
    move:SetDuration(0.15)
    move:SetSmoothing("OUT")
    local fade = ag:CreateAnimation("Alpha")
    fade:SetFromAlpha(0)
    fade:SetToAlpha(1)
    fade:SetDuration(0.15)
    flyout.slide = ag
    flyout:SetScript("OnShow", function(self)
        -- start tucked against the button, end in place
        self.slide:Stop()
        Home(20)
        self.slide:Play()
    end)
    ag:SetScript("OnFinished", function() Home(0) end)
    flyout.Home = Home

    -- the one button: styled like a stock minimap button
    toggle = CreateFrame("Button", "IronbarkMinimapToggle", Minimap)
    toggle:SetSize(SIZE, SIZE)
    toggle:SetFrameStrata("MEDIUM")
    toggle:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    toggle:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", -4, -4)
    toggle:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local bgTex = toggle:CreateTexture(nil, "BACKGROUND")
    bgTex:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bgTex:SetSize(20, 20)
    bgTex:SetPoint("TOPLEFT", 7, -5)
    local icon = toggle:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\AddOns\\IronbarkUI\\IronbarkUI-Logo.png")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexCoord(0.14, 0.86, 0.12, 0.84) -- inside the logo's painted frame
    local border = toggle:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    toggle:SetScript("OnClick", function()
        flyout:SetShown(not flyout:IsShown())
    end)
    toggle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Addon buttons")
        GameTooltip:AddLine("Click to show or hide.", 1, 1, 1)
        GameTooltip:Show()
    end)
    toggle:SetScript("OnLeave", GameTooltip_Hide)
    toggle:Hide()
    flyout.Home(0)
end

function ns.RefreshMinimapButtons()
    Build()
    if ns.db.minimapCollect then
        Scan()
    else
        -- hand them back: a reload lets each addon re-anchor its own button
        toggle:Hide()
        flyout:Hide()
    end
end

-------------------------------------------------------------------------------
--  Zoom with the mouse wheel; the +/- buttons are hidden
-------------------------------------------------------------------------------
local function HideZoomButtons()
    for _, b in ipairs({ Minimap.ZoomIn, Minimap.ZoomOut, MinimapZoomIn, MinimapZoomOut }) do
        if b and not b.__ibuiHidden then
            b.__ibuiHidden = true
            b:Hide()
            hooksecurefunc(b, "Show", b.Hide) -- Blizzard re-shows them on hover
        end
    end
end

local function WheelZoom()
    if Minimap.__ibuiWheel then return end
    Minimap.__ibuiWheel = true
    Minimap:EnableMouseWheel(true)
    Minimap:HookScript("OnMouseWheel", function(self, delta)
        local z, max = self:GetZoom(), self:GetZoomLevels() - 1
        z = math.max(0, math.min(max, z + (delta > 0 and 1 or -1)))
        self:SetZoom(z)
    end)
end

ns.OnLogin(function()
    HideZoomButtons()
    WheelZoom()
    ns.RefreshMinimapButtons()
    -- addons create their buttons at different times
    C_Timer.After(2, Scan)
    C_Timer.After(8, Scan)
    local lib = LibStub and LibStub("LibDBIcon-1.0", true)
    if lib and lib.RegisterCallback then
        lib.RegisterCallback(ns, "LibDBIcon_IconCreated", function() C_Timer.After(0, Scan) end)
    end
end)
