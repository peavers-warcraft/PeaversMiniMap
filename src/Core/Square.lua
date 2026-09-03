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
local trackerDetached = false
local hiddenByUs = {}       -- [widget key] = true, so Show() is only undone by us
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
    -- Every frame and texture in WoW is a table. Insisting on one means a path
    -- that lands on something else - a method, a number, a leftover flag - is
    -- reported as absent rather than handed on to be indexed as a frame.
    if type(node) ~= "table" then return nil end
    return node
end

Square.Resolve = Resolve

-- Blizzard's own minimap widgets, and what to do with each one.
--
-- Three dispositions: "corner" pins it to an edge of the square, "grid" hands it
-- to the button grid alongside the addon buttons, and "hidden" takes it away.
-- The defaults answer the question the round minimap never had to: a calendar
-- icon and a group-finder eye are buttons like any other and belong in the grid,
-- while tracking, mail and the difficulty flag are map furniture and stay put.
--
-- `paths` is a fallback chain because Blizzard renames these: the tracking frame
-- has been both MinimapCluster.TrackingFrame and MinimapCluster.Tracking within
-- one expansion. The first path that resolves wins; a widget that resolves to
-- nothing is skipped silently, which is what keeps this table safe to carry
-- across patches.
Square.WIDGETS = {
    { key = "tracking", label = "Tracking", default = "corner",
      paths = { "MinimapCluster.TrackingFrame", "MinimapCluster.Tracking" },
      point = "TOPLEFT", x = 2, y = 2 },

    { key = "difficulty", label = "Dungeon difficulty", default = "corner",
      paths = { "MinimapCluster.InstanceDifficulty" },
      point = "TOPLEFT", x = 2, y = 34 },

    { key = "indicators", label = "Mail and crafting orders", default = "corner",
      paths = { "MinimapCluster.IndicatorFrame" },
      point = "BOTTOMLEFT", x = 2, y = 2 },

    -- On the map rather than in the grid: the eye is a status light as much as
    -- a button, and it is no use in a grid that can be hidden. Its free corner
    -- is the bottom right, since the expansion button defaults to the grid.
    { key = "queueStatus", label = "Group finder eye", default = "corner",
      paths = { "QueueStatusButton", "QueueStatusMinimapButton" },
      point = "BOTTOMRIGHT", x = 2, y = 2 },

    { key = "calendar", label = "Calendar", default = "grid",
      paths = { "GameTimeFrame" },
      point = "TOPRIGHT", x = 2, y = 2 },

    -- The expansion landing page button. Blizzard renames what it opens every
    -- expansion - it is the Omnium Folio in Midnight - but the frame is stable.
    { key = "expansion", label = "Omnium Folio (expansion button)", default = "grid",
      paths = { "ExpansionLandingPageMinimapButton", "GarrisonLandingPageMinimapButton" },
      point = "BOTTOMRIGHT", x = 2, y = 2 },

    { key = "compartment", label = "Addon compartment", default = "grid",
      paths = { "AddonCompartmentFrame" },
      point = "TOPRIGHT", x = 2, y = 34 },

    { key = "worldMap", label = "World map button", default = "grid",
      paths = { "MiniMapWorldMapButton" },
      point = "BOTTOMRIGHT", x = 2, y = 34 },

    { key = "clock", label = "Clock", default = "hidden",
      paths = { "TimeManagerClockButton" },
      point = "BOTTOM", x = 0, y = 2 },
}

local function ResolveWidget(widget)
    for _, path in ipairs(widget.paths) do
        local frame = Resolve(path)
        if frame then return frame, path end
    end
    return nil
end

Square.ResolveWidget = ResolveWidget

local function ModeFor(widget)
    local widgets = PMM.Config.widgets
    local mode = widgets and widgets[widget.key]
    return mode or widget.default
end

Square.ModeFor = ModeFor

-- Anchors a corner widget can be pinned to. CENTER is included so a widget can
-- be put anywhere on the map rather than only near an edge.
Square.WIDGET_POINTS = {
    { key = "TOPLEFT", label = "Top left" },
    { key = "TOPRIGHT", label = "Top right" },
    { key = "BOTTOMLEFT", label = "Bottom left" },
    { key = "BOTTOMRIGHT", label = "Bottom right" },
    { key = "CENTER", label = "Centre" },
}

Square.WIDGET_SCALE_MIN = 0.5
Square.WIDGET_SCALE_MAX = 2.5
Square.WIDGET_OFFSET_MAX = 300

-- Where a corner widget sits and how big it is. Config holds sparse overrides;
-- anything absent falls back to the widget's own default, so a widget gains
-- sensible placement the moment it is added to the table above.
--
-- Offsets are stored as positive insets measured inward from the anchor, and
-- the sign is derived here. That is what lets one pair of sliders read the same
-- way ("24 across, 40 down") regardless of which corner the widget is pinned to
-- - storing raw signed offsets would flip their meaning per corner.
local function LayoutFor(widget)
    local override = (PMM.Config.widgetLayout or {})[widget.key] or {}
    local point = override.point or widget.point
    -- 0 is a meaningful offset, so test for nil rather than falsiness.
    local x = override.x
    if x == nil then x = widget.x end
    local y = override.y
    if y == nil then y = widget.y end
    local scale = override.scale or 1

    local signX = string.find(point, "RIGHT") and -1 or 1
    local signY = string.find(point, "TOP") and -1 or 1

    return point, x * signX, y * signY, scale
end

Square.LayoutFor = LayoutFor

-- Defaults, in the same positive-inset form the settings page edits.
function Square:DefaultLayout(widget)
    return { point = widget.point, x = widget.x, y = widget.y, scale = 1 }
end

function Square:GetLayout(widget)
    local override = (PMM.Config.widgetLayout or {})[widget.key] or {}
    local defaults = self:DefaultLayout(widget)
    return {
        point = override.point or defaults.point,
        x = override.x == nil and defaults.x or override.x,
        y = override.y == nil and defaults.y or override.y,
        scale = override.scale or defaults.scale,
    }
end

function Square:SetLayout(widget, field, value)
    local layout = PMM.Config.widgetLayout
    layout[widget.key] = layout[widget.key] or {}
    layout[widget.key][field] = value
    PMM.Config:Save()
end

function Square:ResetLayout(widget)
    PMM.Config.widgetLayout[widget.key] = nil
    PMM.Config:Save()
end

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

    for _, widget in ipairs(Square.WIDGETS) do
        local frame = ResolveWidget(widget)
        if frame then
            original.placements[widget.key] = {
                frame = frame,
                points = CapturePoints(frame),
                parent = frame:GetParent(),
                scale = frame:GetScale(),
                shown = frame:IsShown(),
                strata = frame:GetFrameStrata(),
                level = frame:GetFrameLevel(),
            }
        end
    end

    -- Read the objective tracker's position before anything moves. Blizzard's
    -- default layout anchors it to MinimapCluster, so moving the cluster drags
    -- the tracker across the screen with it - which is not what anyone asking
    -- for a square minimap had in mind. If the frame has no resolved rect yet
    -- (common at login) this stays nil and Apply falls back to placing it under
    -- the map instead.
    local tracker = _G.ObjectiveTrackerFrame
    if tracker then
        local left, top = tracker:GetLeft(), tracker:GetTop()
        original.tracker = {
            points = CapturePoints(tracker),
            left = left,
            top = top,
        }
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

    local border = PMM.Buttons.MarkOwned(
        CreateFrame("Frame", "PeaversMiniMapBorder", _G.Minimap, "BackdropTemplate"))
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

local function AnchorFor(key)
    for _, anchor in ipairs(Square.ANCHORS) do
        if anchor.key == key then return anchor end
    end
    return Square.ANCHORS[1]
end

--------------------------------------------------------------------------------
-- The objective tracker
--
-- Blizzard's default layout anchors ObjectiveTrackerFrame to MinimapCluster, so
-- pinning the minimap to a corner drags the quest list along with it. Giving the
-- tracker an anchor of its own, once, breaks that link without taking ownership
-- of where it lives - Edit Mode can still move it afterwards.
--------------------------------------------------------------------------------

local function DetachObjectiveTracker(config, size)
    if config.objectiveTracker ~= "detach" then return end
    if trackerDetached then return end

    local tracker = _G.ObjectiveTrackerFrame
    if not tracker then return end

    RawClearAllPoints(tracker)

    local snapshot = original.tracker
    if snapshot and snapshot.left and snapshot.top then
        -- UIParent's BOTTOMLEFT is the screen origin, so the offsets read off
        -- the frame before anything moved can be used verbatim whatever scale
        -- the tracker is running at.
        RawSetPoint(tracker, "TOPLEFT", _G.UIParent, "BOTTOMLEFT", snapshot.left, snapshot.top)
    else
        -- No resolved rect when we looked, which happens at a cold login. Put it
        -- under the minimap block on the same side - where Blizzard had it
        -- anyway - rather than guessing at a pixel position.
        local anchor = AnchorFor(config.anchor)
        local top = anchor.key:find("TOP") and "TOP" or "BOTTOM"
        local side = anchor.key:find("RIGHT") and "RIGHT" or "LEFT"
        local corner = top .. side
        local y = (config.offsetY or 12) + size + 40
        RawSetPoint(tracker, corner, _G.UIParent, corner,
            (config.offsetX or 12) * anchor.x, -y * (top == "TOP" and 1 or -1))
    end

    trackerDetached = true
end

--------------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------------

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

    -- Blizzard's widgets, each to wherever the user has sent it.
    local Buttons = PMM.Buttons
    for _, widget in ipairs(Square.WIDGETS) do
        local frame = ResolveWidget(widget)
        if frame then
            local mode = ModeFor(widget)

            -- Leaving the grid has to happen before anything else, or a widget
            -- switched from "grid" to a corner would be positioned and then
            -- immediately re-placed by the next layout pass.
            if mode ~= "grid" and Buttons and Buttons:IsCollected(frame) then
                Buttons:ReleaseExternal(frame)
            end

            if mode == "hidden" then
                frame:Hide()
                hiddenByUs[widget.key] = true
            else
                -- Only undo a hide we performed. Several of these widgets are
                -- contextual - the difficulty flag outside an instance, the mail
                -- icon with an empty mailbox, the eye when not queued - and
                -- showing them unconditionally would pin them on screen
                -- permanently, which is the opposite of tidying up.
                if hiddenByUs[widget.key] then
                    frame:Show()
                    hiddenByUs[widget.key] = nil
                end

                if not (mode == "grid" and Buttons and Buttons:AdoptExternal(frame)) then
                    -- Either the user asked for a corner, or the grid declined
                    -- it (collection switched off, or a protected frame
                    -- refusing to be reparented mid-combat). A corner is always
                    -- a safe answer.
                    local point, offsetX, offsetY, scale = LayoutFor(widget)
                    frame:SetScale(scale)

                    -- These widgets are siblings of Minimap under
                    -- MinimapCluster, not children of it, so draw order is
                    -- decided by frame level. Blizzard parked them outside the
                    -- circle where that never mattered; moved onto a square map
                    -- they render behind the map art and simply vanish. Raising
                    -- them above the map is what makes any on-map position
                    -- usable at all.
                    frame:SetFrameStrata(minimap:GetFrameStrata())
                    frame:SetFrameLevel(minimap:GetFrameLevel() + 6)

                    RawClearAllPoints(frame)
                    RawSetPoint(frame, point, minimap, point, offsetX, offsetY)
                end
            end
        end
    end

    ApplyZoneText(config)
    ApplyBorder(config)
    DetachObjectiveTracker(config, size)

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
    if PMM.Positioner and PMM.Positioner:IsUnlocked() then
        PMM.Positioner:RefreshHandles()
    end
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

    for _, snapshot in pairs(original.placements) do
        local frame = snapshot.frame
        if frame then
            if PMM.Buttons and PMM.Buttons:IsCollected(frame) then
                PMM.Buttons:ReleaseExternal(frame)
            end
            RestorePoints(frame, snapshot.points)
            frame:SetScale(snapshot.scale or 1)
            if snapshot.strata then frame:SetFrameStrata(snapshot.strata) end
            if snapshot.level then frame:SetFrameLevel(snapshot.level) end
            if snapshot.shown then frame:Show() else frame:Hide() end
        end
    end

    hiddenByUs = {}

    if original.tracker and trackerDetached then
        local tracker = _G.ObjectiveTrackerFrame
        if tracker then RestorePoints(tracker, original.tracker.points) end
        trackerDetached = false
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
