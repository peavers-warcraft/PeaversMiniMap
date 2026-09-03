--------------------------------------------------------------------------------
-- PeaversMiniMap - Positioner
--
-- Drag the map's widgets around on the map itself, instead of guessing at a
-- corner and two offsets in a settings window.
--
-- Three things make this harder than "make the frame movable":
--
--   1. The widgets belong to Blizzard and have their own click behaviour - the
--      tracking button opens a menu, the calendar opens the calendar. So the
--      user never drags the widget. Each one gets a proxy handle laid over it,
--      and the handle is what moves.
--   2. Half of them are contextual. The difficulty flag only exists in an
--      instance and the eye only while queued, so unlocking force-shows
--      everything and locking puts that back - otherwise you cannot place the
--      widgets that most need placing.
--   3. Dragging must not cost a frame. StartMoving/StopMovingOrSizing are
--      engine-side, and the widget is anchored to its handle for the duration,
--      so the map's icons follow the cursor with no Lua running per frame. The
--      perf case asserts that unlocking adds no OnUpdate anywhere.
--------------------------------------------------------------------------------

local _, PMM = ...

local PeaversCommons = _G.PeaversCommons
local Utils = PeaversCommons.Utils

local Positioner = {}
PMM.Positioner = Positioner

local scratch = CreateFrame("Frame")
local RawSetPoint = scratch.SetPoint
local RawClearAllPoints = scratch.ClearAllPoints

local handles = {}          -- [widget key] = proxy handle
local forcedVisible = {}    -- [widget key] = true when unlocking revealed it
local unlocked = false
local overlay

--------------------------------------------------------------------------------
-- Geometry
--
-- Kept as plain arithmetic on numbers rather than reaching into frames, so the
-- rule it encodes - which corner a dropped widget belongs to, and how far it
-- sits from that corner - can be asserted directly by the perf case.
--------------------------------------------------------------------------------

--- Work out which corner a widget was dropped nearest, and its inset from it.
--- All arguments and results are in the same units (screen pixels).
--- Insets are positive and measured inward, matching how Square stores them.
function Positioner.ResolveAnchor(map, widget)
    local mapRight = map.left + map.width
    local mapTop = map.bottom + map.height

    local centreX = widget.left + widget.width / 2
    local centreY = widget.bottom + widget.height / 2

    local horizontal = (centreX < map.left + map.width / 2) and "LEFT" or "RIGHT"
    local vertical = (centreY > map.bottom + map.height / 2) and "TOP" or "BOTTOM"
    local point = vertical .. horizontal

    local insetX
    if horizontal == "LEFT" then
        insetX = widget.left - map.left
    else
        insetX = mapRight - (widget.left + widget.width)
    end

    local insetY
    if vertical == "TOP" then
        insetY = mapTop - (widget.bottom + widget.height)
    else
        insetY = widget.bottom - map.bottom
    end

    -- A widget dragged past the edge snaps back onto the map rather than being
    -- stored at a negative inset that would put it somewhere unreachable.
    local maxX = math.max(0, map.width - widget.width)
    local maxY = math.max(0, map.height - widget.height)
    insetX = math.max(0, math.min(maxX, insetX))
    insetY = math.max(0, math.min(maxY, insetY))

    return point, math.floor(insetX + 0.5), math.floor(insetY + 0.5)
end

-- Frame rects in screen pixels. Mixing a frame's own coordinate space with the
-- minimap's is the classic way to get placement subtly wrong at non-default UI
-- scales, so everything is normalised here once.
local function ScreenRect(frame)
    local scale = frame:GetEffectiveScale()
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    if not left or not bottom then return nil end
    return {
        left = left * scale,
        bottom = bottom * scale,
        width = frame:GetWidth() * scale,
        height = frame:GetHeight() * scale,
    }
end

--------------------------------------------------------------------------------
-- Handles
--------------------------------------------------------------------------------

local function CommitHandle(widget, handle)
    local minimap = _G.Minimap
    local map = ScreenRect(minimap)
    local dropped = ScreenRect(handle)
    if not map or not dropped then return end

    local point, insetX, insetY = Positioner.ResolveAnchor(map, dropped)

    -- SetPoint offsets are in the widget's own coordinate space, so an inset
    -- measured in screen pixels has to come back out of it before being stored.
    local frame = PMM.Square.ResolveWidget(widget)
    local frameScale = frame and frame:GetEffectiveScale() or 1
    if frameScale > 0 then
        insetX = math.floor(insetX / frameScale + 0.5)
        insetY = math.floor(insetY / frameScale + 0.5)
    end

    PMM.Square:SetLayout(widget, "point", point)
    PMM.Square:SetLayout(widget, "x", insetX)
    PMM.Square:SetLayout(widget, "y", insetY)

    PMM.Square:Apply()
    Positioner:RefreshHandles()
end

local function AdjustScale(widget, delta)
    local Square = PMM.Square
    local layout = Square:GetLayout(widget)
    local scale = layout.scale + delta
    scale = math.max(Square.WIDGET_SCALE_MIN, math.min(Square.WIDGET_SCALE_MAX, scale))
    Square:SetLayout(widget, "scale", scale)
    Square:Apply()
    Positioner:RefreshHandles()
end

local function EnsureHandle(widget)
    local existing = handles[widget.key]
    if existing then return existing end

    -- Marked as ours, or the button collector treats a handle parked on the
    -- minimap as one more addon button and files it into the grid.
    local handle = PMM.Buttons.MarkOwned(CreateFrame("Button", nil, _G.Minimap, "BackdropTemplate"))
    handle:SetFrameStrata("FULLSCREEN_DIALOG")
    handle:SetScale(1)
    handle:SetMovable(true)
    handle:EnableMouse(true)
    handle:EnableMouseWheel(true)
    handle:RegisterForDrag("LeftButton")
    handle:RegisterForClicks("RightButtonUp")
    handle:SetClampedToScreen(true)
    handle:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeSize = 1,
    })
    handle:SetBackdropColor(0.20, 0.74, 0.97, 0.25)
    handle:SetBackdropBorderColor(0.20, 0.74, 0.97, 0.9)

    -- StartMoving is engine-side: the handle follows the cursor, and the widget
    -- follows the handle through its anchor. No OnUpdate is involved.
    handle:SetScript("OnDragStart", function(self) self:StartMoving() end)
    handle:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        CommitHandle(widget, self)
    end)

    handle:SetScript("OnMouseWheel", function(_, delta)
        AdjustScale(widget, delta > 0 and 0.05 or -0.05)
    end)

    handle:SetScript("OnClick", function()
        PMM.Square:ResetLayout(widget)
        PMM.Square:Apply()
        Positioner:RefreshHandles()
    end)

    handle:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.20, 0.74, 0.97, 0.45)
        _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        _G.GameTooltip:SetText(widget.label)
        _G.GameTooltip:AddLine("Drag to move it on the map.", 0.8, 0.8, 0.8)
        _G.GameTooltip:AddLine("Scroll to resize.", 0.8, 0.8, 0.8)
        _G.GameTooltip:AddLine("Right-click to put it back.", 0.8, 0.8, 0.8)
        _G.GameTooltip:Show()
    end)
    handle:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.20, 0.74, 0.97, 0.25)
        _G.GameTooltip:Hide()
    end)

    handles[widget.key] = handle
    return handle
end

local function EnsureOverlay()
    if overlay then return overlay end

    overlay = PMM.Buttons.MarkOwned(
        CreateFrame("Frame", "PeaversMiniMapPositionOverlay", _G.Minimap, "BackdropTemplate"))
    overlay:SetFrameStrata("FULLSCREEN_DIALOG")
    overlay:SetAllPoints(_G.Minimap)
    overlay:EnableMouse(false)
    overlay:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    overlay:SetBackdropColor(0, 0, 0, 0.35)

    local label = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOM", overlay, "BOTTOM", 0, 6)
    label:SetText("Drag the icons")
    label:SetTextColor(0.85, 0.85, 0.85)

    overlay:Hide()
    return overlay
end

--------------------------------------------------------------------------------
-- Placing the handles over the widgets
--------------------------------------------------------------------------------

function Positioner:RefreshHandles()
    if not unlocked then return end

    local Square = PMM.Square
    local minimap = _G.Minimap

    for _, widget in ipairs(Square.WIDGETS) do
        local handle = handles[widget.key]
        local frame = Square.ResolveWidget(widget)

        if handle and frame and Square.ModeFor(widget) == "corner" then
            local width = math.max(12, frame:GetWidth() * frame:GetScale())
            local height = math.max(12, frame:GetHeight() * frame:GetScale())
            handle:SetSize(width, height)

            -- Park the handle exactly over the widget, then anchor the widget to
            -- the handle so a drag carries it along with no Lua per frame.
            RawClearAllPoints(handle)
            local point, offsetX, offsetY, _ = Square.LayoutFor(widget)
            RawSetPoint(handle, point, minimap, point, offsetX, offsetY)

            RawClearAllPoints(frame)
            RawSetPoint(frame, "CENTER", handle, "CENTER", 0, 0)

            handle:Show()
        elseif handle then
            handle:Hide()
        end
    end
end

--------------------------------------------------------------------------------
-- Unlock / lock
--------------------------------------------------------------------------------

function Positioner:IsUnlocked()
    return unlocked
end

function Positioner:Unlock()
    if unlocked then return end
    if not PMM.Config.enabled then
        Utils.Print(PMM, "Enable PeaversMiniMap before moving things around on it.")
        return
    end

    unlocked = true
    EnsureOverlay():Show()

    local Square = PMM.Square
    for _, widget in ipairs(Square.WIDGETS) do
        local frame = Square.ResolveWidget(widget)
        if frame and Square.ModeFor(widget) == "corner" then
            -- The widgets that most need placing are the ones you cannot
            -- normally see. Reveal them for the duration.
            if not frame:IsShown() then
                frame:Show()
                forcedVisible[widget.key] = true
            end
            EnsureHandle(widget)
        end
    end

    self:RefreshHandles()
    Utils.Print(PMM, "Drag the icons on the minimap. Scroll one to resize it, right-click to reset it.")
end

function Positioner:Lock()
    if not unlocked then return end
    unlocked = false

    if overlay then overlay:Hide() end
    for _, handle in pairs(handles) do
        handle:Hide()
    end

    -- Put the contextual widgets back to being contextual.
    for key in pairs(forcedVisible) do
        for _, widget in ipairs(PMM.Square.WIDGETS) do
            if widget.key == key then
                local frame = PMM.Square.ResolveWidget(widget)
                if frame then frame:Hide() end
            end
        end
    end
    forcedVisible = {}

    -- Re-anchor everything to the minimap rather than to the handles.
    PMM.Square:Apply()
end

function Positioner:Toggle()
    if unlocked then self:Lock() else self:Unlock() end
    return unlocked
end

return Positioner
