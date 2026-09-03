--------------------------------------------------------------------------------
-- PeaversMiniMap - Square
--
-- Turns Blizzard's round minimap into a square anchored to a corner of the
-- screen, and moves the widgets that live around it (tracking, mail, difficulty,
-- the expansion button, queue status) onto the square's own corners.
--
-- Two rules govern everything in this file:
--
--   1. Nothing runs per frame. Every reapply is triggered by an event or by
--      somebody else moving the map, never by a ticker. The hooks below fire
--      only when another addon or Blizzard changes something we own.
--   2. Everything is reversible. Every value this file overwrites is captured
--      once, before the first write, and Restore() puts it all back.
--------------------------------------------------------------------------------

local _, PMM = ...

local PeaversCommons = _G.PeaversCommons
local Utils = PeaversCommons.Utils

local Square = {}
PMM.Square = Square

-- Widget methods lifted off a scratch frame. Calling these bypasses any
-- instance-level override an addon (including ours) has installed, which is how
-- we move frames we have deliberately nailed down. Same trick the established
-- minimap addons use; the methods are shared across every frame type.
local scratch = CreateFrame("Frame")
local RawSetPoint = scratch.SetPoint
local RawClearAllPoints = scratch.ClearAllPoints
local RawSetSize = scratch.SetSize

local SOLID = "Interface\\ChatFrame\\ChatFrameBackground"

-- Where the square can live. Offsets in config are applied outward from here.
Square.ANCHORS = {
    { key = "TOPRIGHT", label = "Top right", x = -1, y = -1 },
    { key = "TOPLEFT", label = "Top left", x = 1, y = -1 },
    { key = "BOTTOMRIGHT", label = "Bottom right", x = -1, y = 1 },
    { key = "BOTTOMLEFT", label = "Bottom left", x = 1, y = 1 },
}

Square.SIZE_MIN = 100
Square.SIZE_MAX = 400

local applying = false      -- reentrancy guard for our own hooks
local initialized = false
local active = false
local original = nil        -- captured Blizzard state; nil until first Apply

--------------------------------------------------------------------------------
-- Frame resolution
--
-- Blizzard moves these around between expansions and some are created by
-- load-on-demand addons, so nothing here may assume a frame exists. Resolve()
-- walks a dotted path and returns nil rather than erroring.
--------------------------------------------------------------------------------

local function Resolve(path)
    local node = _G
    for segment in string.gmatch(path, "[^%.]+") do
        if type(node) ~= "table" then return nil end
        node = node[segment]
        if node == nil then return nil end
    end
    return node
end

Square.Resolve = Resolve

-- Blizzard widgets we relocate onto the square's corners. `inset` is measured
-- from the named corner of the minimap. Anything missing is skipped silently.
local PLACEMENTS = {
    { path = "MinimapCluster.Tracking", point = "TOPLEFT", x = 2, y = -2 },
    { path = "MinimapCluster.InstanceDifficulty", point = "TOPLEFT", x = 2, y = -34 },
    { path = "MinimapCluster.IndicatorFrame", point = "BOTTOMLEFT", x = 2, y = 2 },
    { path = "QueueStatusButton", point = "BOTTOMLEFT", x = 2, y = 34 },
    { path = "ExpansionLandingPageMinimapButton", point = "BOTTOMRIGHT", x = -2, y = 2 },
    { path = "GameTimeFrame", point = "TOPRIGHT", x = -2, y = -2 },
    { path = "AddonCompartmentFrame", point = "TOPRIGHT", x = -2, y = -34 },
}

-- Textures and frames that only make sense around a circle.
local ROUND_ART = {
    "MinimapCompassTexture",
    "MinimapBorder",
    "MinimapBorderTop",
    "MinimapNorthTag",
    "MinimapCluster.BorderTop",
}

--------------------------------------------------------------------------------
-- Capture / restore
--------------------------------------------------------------------------------

local function CapturePoints(frame)
    local points = {}
    for i = 1, frame:GetNumPoints() do
        points[i] = { frame:GetPoint(i) }
    end
    return points
end

local function RestorePoints(frame, points)
    if not points then return end
    RawClearAllPoints(frame)
    for _, p in ipairs(points) do
        pcall(RawSetPoint, frame, unpack(p))
    end
end

-- Snapshot everything we are about to overwrite. Runs exactly once, before the
-- first change, so Restore() always has an untouched Blizzard state to go back
-- to even after the user has toggled the addon a dozen times.
local function CaptureOriginal()
    if original then return end

    local minimap = _G.Minimap
    local cluster = _G.MinimapCluster

    original = {
        getMinimapShape = _G.GetMinimapShape,
        minimapPoints = CapturePoints(minimap),
        minimapWidth = minimap:GetWidth(),
        minimapHeight = minimap:GetHeight(),
        clusterPoints = CapturePoints(cluster),
        clusterScale = cluster:GetScale(),
        placements = {},
        roundArtShown = {},
        zoomShown = {},
        zoneText = nil,
    }

    local zoneButton = Resolve("MinimapCluster.ZoneTextButton")
    if zoneButton then
        original.zoneText = {
            parent = zoneButton:GetParent(),
            points = CapturePoints(zoneButton),
            width = zoneButton:GetWidth(),
            height = zoneButton:GetHeight(),
            shown = zoneButton:IsShown(),
        }
    end

    for _, placement in ipairs(PLACEMENTS) do
        local frame = Resolve(placement.path)
        if frame then
            original.placements[placement.path] = {
                points = CapturePoints(frame),
                parent = frame:GetParent(),
                scale = frame:GetScale(),
            }
        end
    end

    for _, path in ipairs(ROUND_ART) do
        local art = Resolve(path)
        if art then
            original.roundArtShown[path] = art:IsShown()
        end
    end

    for _, path in ipairs({ "Minimap.ZoomIn", "Minimap.ZoomOut" }) do
        local button = Resolve(path)
        if button then
            original.zoomShown[path] = button:IsShown()
        end
    end
end

--------------------------------------------------------------------------------
-- The border and the zone-text overlay
--------------------------------------------------------------------------------

local function EnsureBorder()
    if Square.border then return Square.border end

    local border = CreateFrame("Frame", "PeaversMiniMapBorder", _G.Minimap, "BackdropTemplate")
    border:SetFrameStrata(_G.Minimap:GetFrameStrata())
    border:SetFrameLevel(math.max(_G.Minimap:GetFrameLevel() - 1, 0))
    border:EnableMouse(false)
    Square.border = border
    return border
end

local function ApplyBorder(config)
    local width = config.borderSize or 0
    local border = Square.border

    if width <= 0 then
        if border then border:Hide() end
        return
    end

    border = EnsureBorder()
    RawClearAllPoints(border)
    RawSetPoint(border, "TOPLEFT", _G.Minimap, "TOPLEFT", -width, width)
    RawSetPoint(border, "BOTTOMRIGHT", _G.Minimap, "BOTTOMRIGHT", width, -width)
    border:SetBackdrop({ edgeFile = SOLID, edgeSize = width })

    local c = config.borderColor or {}
    border:SetBackdropBorderColor(c.r or 0, c.g or 0, c.b or 0, c.a or 1)
    border:Show()
end

-- Blizzard's zone-text bar is a wide piece of art sized for the round map's
-- header. On a square it reads better as a plain label pinned to the top edge,
-- so we hide the art and re-anchor the button that carries the text.
local function ApplyZoneText(config)
    local button = Resolve("MinimapCluster.ZoneTextButton")
    if not button then return end

    local mode = config.zoneTextMode or "overlay"

    if mode == "hidden" then
        button:Hide()
        return
    end

    -- Adopting the button onto the map keeps the zone name visible even when
    -- the header art it used to live in has been hidden.
    if button:GetParent() ~= _G.Minimap then
        button:SetParent(_G.Minimap)
    end
    button:Show()
    RawClearAllPoints(button)
    if mode == "above" then
        RawSetPoint(button, "BOTTOM", _G.Minimap, "TOP", 0, 4 + (config.borderSize or 0))
    else
        RawSetPoint(button, "TOP", _G.Minimap, "TOP", 0, -2)
    end
    RawSetSize(button, config.size or 200, 20)

    local text = _G.MinimapZoneText
    if text then
        text:ClearAllPoints()
        text:SetPoint("CENTER", button, "CENTER", 0, 0)
        text:SetWidth((config.size or 200) - 8)
    end
end

--------------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------------

local function AnchorFor(key)
    for _, anchor in ipairs(Square.ANCHORS) do
        if anchor.key == key then return anchor end
    end
    return Square.ANCHORS[1]
end

-- Tell the ecosystem the map is square. LibDBIcon and friends read this global
-- to decide how to place buttons around the edge; leaving it round is what makes
-- third-party buttons scatter off the corners of a square map.
local function ApplyShapeGlobal(square)
    if square then
        _G.GetMinimapShape = function() return "SQUARE" end
    elseif original then
        _G.GetMinimapShape = original.getMinimapShape
    end
end

function Square:Apply()
    local config = PMM.Config
    if not config.enabled then return end

    local minimap = _G.Minimap
    local cluster = _G.MinimapCluster
    if not minimap or not cluster then
        Utils.Debug(PMM, "Minimap frames unavailable; nothing applied")
        return
    end

    CaptureOriginal()
    applying = true
    active = true

    local size = math.max(self.SIZE_MIN, math.min(self.SIZE_MAX, config.size or 200))

    -- Shape
    ApplyShapeGlobal(config.squareShape ~= false)
    if config.squareShape ~= false then
        minimap:SetMaskTexture(SOLID)
        -- The quest and archaeology blobs are drawn against a circular ring;
        -- zeroing the scalar keeps them inside a square without smearing.
        pcall(minimap.SetArchBlobRingScalar, minimap, 0)
        pcall(minimap.SetArchBlobRingAlpha, minimap, 0)
        pcall(minimap.SetQuestBlobRingScalar, minimap, 0)
        pcall(minimap.SetQuestBlobRingAlpha, minimap, 0)
    end

    -- Size: the cluster box and the map itself are the same square.
    RawSetSize(minimap, size, size)
    RawSetSize(cluster, size, size)
    cluster:SetScale(config.scale or 1)

    -- Position
    if config.anchorEnabled ~= false then
        local anchor = AnchorFor(config.anchor)
        local x = (config.offsetX or 12) * anchor.x
        local y = (config.offsetY or 12) * anchor.y
        RawClearAllPoints(cluster)
        RawSetPoint(cluster, anchor.key, _G.UIParent, anchor.key, x, y)
        cluster:SetClampedToScreen(false)
    end

    RawClearAllPoints(minimap)
    RawSetPoint(minimap, "TOPLEFT", cluster, "TOPLEFT", 0, 0)
    RawSetPoint(minimap, "BOTTOMRIGHT", cluster, "BOTTOMRIGHT", 0, 0)

    -- Round-only art
    for _, path in ipairs(ROUND_ART) do
        local art = Resolve(path)
        if art then
            if config.squareShape ~= false then art:Hide() else art:Show() end
        end
    end

    -- Zoom buttons: the mouse wheel already zooms, so they are clutter by
    -- default. Kept behind a toggle rather than removed outright.
    for _, path in ipairs({ "Minimap.ZoomIn", "Minimap.ZoomOut" }) do
        local button = Resolve(path)
        if button then
            if config.hideZoomButtons ~= false then
                button:Hide()
            else
                button:Show()
                RawClearAllPoints(button)
                if path == "Minimap.ZoomIn" then
                    RawSetPoint(button, "BOTTOMRIGHT", minimap, "BOTTOMRIGHT", 0, 0)
                else
                    RawSetPoint(button, "RIGHT", Resolve("Minimap.ZoomIn"), "LEFT", -4, 0)
                end
            end
        end
    end

    -- Corner widgets
    for _, placement in ipairs(PLACEMENTS) do
        local frame = Resolve(placement.path)
        if frame and not (config.hiddenWidgets or {})[placement.path] then
            frame:Show()
            RawClearAllPoints(frame)
            RawSetPoint(frame, placement.point, minimap, placement.point, placement.x, placement.y)
        elseif frame then
            frame:Hide()
        end
    end

    ApplyZoneText(config)
    ApplyBorder(config)

    -- The hybrid (city) minimap draws through its own mask, so squaring the
    -- main map without this leaves a circular map in capital cities. The addon
    -- is load-on-demand; ContinueOnAddOnLoaded fires immediately if it is
    -- already up, and PeaversCommons.Events owns the shared ADDON_LOADED slot.
    if config.squareShape ~= false and not self.hybridHooked then
        self.hybridHooked = true
        if _G.EventUtil and _G.EventUtil.ContinueOnAddOnLoaded then
            _G.EventUtil.ContinueOnAddOnLoaded("Blizzard_HybridMinimap", function()
                local hybrid = _G.HybridMinimap
                if not hybrid or not hybrid.MapCanvas then return end
                hybrid.MapCanvas:SetUseMaskTexture(false)
                hybrid.CircleMask:SetTexture("Interface\\BUTTONS\\WHITE8X8")
                hybrid.MapCanvas:SetUseMaskTexture(true)
            end)
        end
    end

    applying = false

    if PMM.Buttons then PMM.Buttons:Layout() end
end

--------------------------------------------------------------------------------
-- Restore
--------------------------------------------------------------------------------

function Square:Restore()
    if not original then
        active = false
        return
    end

    applying = true

    local minimap = _G.Minimap
    local cluster = _G.MinimapCluster

    ApplyShapeGlobal(false)
    minimap:SetMaskTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    pcall(minimap.SetArchBlobRingScalar, minimap, 1)
    pcall(minimap.SetArchBlobRingAlpha, minimap, 1)
    pcall(minimap.SetQuestBlobRingScalar, minimap, 1)
    pcall(minimap.SetQuestBlobRingAlpha, minimap, 1)

    RawSetSize(minimap, original.minimapWidth, original.minimapHeight)
    RestorePoints(minimap, original.minimapPoints)
    RestorePoints(cluster, original.clusterPoints)
    cluster:SetScale(original.clusterScale or 1)
    cluster:SetClampedToScreen(true)

    for path, shown in pairs(original.roundArtShown) do
        local art = Resolve(path)
        if art then
            if shown then art:Show() else art:Hide() end
        end
    end

    for path, shown in pairs(original.zoomShown) do
        local button = Resolve(path)
        if button then
            if shown then button:Show() else button:Hide() end
        end
    end

    for path, snapshot in pairs(original.placements) do
        local frame = Resolve(path)
        if frame then
            frame:Show()
            RestorePoints(frame, snapshot.points)
            frame:SetScale(snapshot.scale or 1)
        end
    end

    local zoneButton = Resolve("MinimapCluster.ZoneTextButton")
    if zoneButton and original.zoneText then
        local snapshot = original.zoneText
        zoneButton:SetParent(snapshot.parent)
        RestorePoints(zoneButton, snapshot.points)
        RawSetSize(zoneButton, snapshot.width, snapshot.height)
        if snapshot.shown then zoneButton:Show() else zoneButton:Hide() end
    end

    if self.border then self.border:Hide() end

    applying = false
    active = false
end

--------------------------------------------------------------------------------
-- Hooks
--
-- These exist so Edit Mode, a UI scale change, or another addon cannot quietly
-- undo the layout. They are cheap because they only run when someone else calls
-- the hooked method - there is no polling anywhere in this file.
--------------------------------------------------------------------------------

local function Reapply()
    if applying or not active then return end
    if not PMM.Config.enabled then return end
    Square:Apply()
end

function Square:Initialize()
    if initialized then return end
    initialized = true

    local minimap = _G.Minimap
    local cluster = _G.MinimapCluster
    if not minimap or not cluster then return end

    -- Somebody resized the map out from under us (Edit Mode, another addon).
    hooksecurefunc(minimap, "SetSize", function(_, w, h)
        if applying or not active then return end
        local size = PMM.Config.size or 200
        if w ~= size or h ~= size then Reapply() end
    end)

    -- Edit Mode rewrites the cluster's anchor when a layout is applied or the
    -- user leaves the editor.
    hooksecurefunc(cluster, "SetPoint", function()
        if applying or not active then return end
        if PMM.Config.anchorEnabled == false then return end
        -- Defer one frame: Edit Mode sets several points in a row, and
        -- reapplying inside its loop fights it. C_Timer.After(0) runs on the
        -- next frame and then stops - it is not a ticker.
        C_Timer.After(0, Reapply)
    end)

    if PMM.Config.enabled then
        self:Apply()
    end
end

function Square:Enable()
    PMM.Config.enabled = true
    PMM.Config:Save()
    self:Apply()
    if PMM.Buttons then PMM.Buttons:Enable() end
end

function Square:Disable()
    if PMM.Buttons then PMM.Buttons:Disable() end
    PMM.Config.enabled = false
    PMM.Config:Save()
    self:Restore()
end

function Square:IsActive()
    return active
end

function Square:PrintInfo()
    local minimap = _G.Minimap
    Utils.Print(PMM, string.format(
        "Minimap %dx%d, cluster scale %.2f, shape %s, anchor %s.",
        minimap:GetWidth(), minimap:GetHeight(),
        _G.MinimapCluster:GetScale(),
        (_G.GetMinimapShape and _G.GetMinimapShape()) or "unknown",
        PMM.Config.anchorEnabled == false and "free (Edit Mode)" or (PMM.Config.anchor or "TOPRIGHT")))
end

return Square
