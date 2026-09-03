--------------------------------------------------------------------------------
-- PeaversMiniMap - Buttons
--
-- Collects the addon buttons that scatter themselves around the minimap and
-- lays them out in a tidy grid beside the square.
--
-- Why this is not a one-liner: a minimap button is not a standard thing. Some
-- come from LibDBIcon and reposition themselves on a radius whenever anything
-- changes; some are hand-rolled frames from 2009 that drag on OnUpdate; some
-- are hidden by their own addon and must stay hidden. So the module:
--
--   * identifies buttons by exclusion, never by an addon whitelist,
--   * reparents them and then neutralises SetPoint on the instance, so a
--     button that tries to re-place itself simply has no effect,
--   * remembers every value it overwrites so Restore() is exact.
--
-- Performance: the grid is rebuilt on demand, never on a timer, and the rebuild
-- is coalesced so twenty buttons appearing at login cost one layout pass. The
-- module registers no OnUpdate at all, and it removes the drag handlers that
-- make LibDBIcon buttons run one while you hold them.
--------------------------------------------------------------------------------

local _, PMM = ...

local PeaversCommons = _G.PeaversCommons
local Utils = PeaversCommons.Utils

local Buttons = {}
PMM.Buttons = Buttons

-- Unoverridable widget methods; see the note in Square.lua.
local scratch = CreateFrame("Frame")
local RawSetPoint = scratch.SetPoint
local RawClearAllPoints = scratch.ClearAllPoints
local RawSetParent = scratch.SetParent

local NOOP = function() end

--------------------------------------------------------------------------------
-- What is and is not an addon button
--------------------------------------------------------------------------------

-- Blizzard's own minimap furniture. These are relocated by Square.lua, not
-- collected here.
local IGNORE_EXACT = {
    MinimapBackdrop = true,
    MinimapCluster = true,
    MinimapZoomIn = true,
    MinimapZoomOut = true,
    MinimapNorthTag = true,
    MinimapZoneTextButton = true,
    MinimapCompassTexture = true,
    GameTimeFrame = true,
    TimeManagerClockButton = true,
    QueueStatusButton = true,
    QueueStatusMinimapButton = true,
    ExpansionLandingPageMinimapButton = true,
    GarrisonLandingPageMinimapButton = true,
    AddonCompartmentFrame = true,
    HybridMinimap = true,
    MiniMapMailFrame = true,
    MiniMapTracking = true,
    MiniMapTrackingButton = true,
    MiniMapWorldMapButton = true,
    MiniMapInstanceDifficulty = true,
    GuildInstanceDifficulty = true,
    MiniMapChallengeMode = true,
    MiniMapBattlefieldFrame = true,
    MiniMapLFGFrame = true,
    MiniMapVoiceChatFrame = true,
    MinimapMailFrame = true,
}

-- This addon's own furniture. Named explicitly rather than by a "^Peavers"
-- pattern: that pattern also swallowed PeaversGetThereMinimapButton and every
-- other sibling addon's button, which are exactly what we are here to collect.
local IGNORE_SELF = {
    PeaversMiniMapButtonBar = true,
    PeaversMiniMapButtonToggle = true,
    PeaversMiniMapBorder = true,
}

-- Anything matching one of these is either Blizzard's or another button bar's.
-- Collecting a rival bar's container would nest one grid inside another.
--
-- Blizzard's own buttons are deliberately listed here even though several of
-- them do end up in the grid: they get there through Square.lua's widget table,
-- which knows what each one is, rather than by being guessed at.
local IGNORE_PATTERNS = {
    "^Minimap",
    "^MiniMap",
    "^GameTime",
    "^QueueStatus",
    "^Expansion",
    "^Garrison",
    "^TimeManager",
    "^AddonCompartment",
    "^Hybrid",
    "^SexyMap",
    "^ButtonCollect",
    "^GatherMate",       -- map pins, not a button
    "Ping$",
}

-- A minimap button is icon-sized. Anything outside this range is a container,
-- a backdrop, or an overlay.
local MIN_EDGE, MAX_EDGE = 12, 52

local function IsIgnoredName(name)
    if IGNORE_EXACT[name] or IGNORE_SELF[name] then return true end
    for _, pattern in ipairs(IGNORE_PATTERNS) do
        if string.match(name, pattern) then return true end
    end
    return false
end

local collected = {}      -- [button] = snapshot for Restore()
local order = {}          -- stable, alphabetical display order
local bar                 -- the grid frame
local toggle              -- explicit show/hide affordance
local layoutQueued = false
local hoverTimerArmed = false
local active = false

local function IsCollectible(frame)
    if not frame or collected[frame] then return false end
    if frame == bar or frame == toggle then return false end
    if not frame.GetObjectType then return false end

    local objectType = frame:GetObjectType()
    if objectType ~= "Button" and objectType ~= "Frame" then return false end

    -- Unnamed frames parented to the minimap are overwhelmingly Blizzard
    -- internals or texture holders. Requiring a name is what keeps this
    -- heuristic from eating the map itself.
    local name = frame:GetName()
    if not name or name == "" then return false end
    if IsIgnoredName(name) then return false end
    if PMM.Config.excluded[name] then return false end

    local width, height = frame:GetWidth(), frame:GetHeight()
    if not width or not height then return false end
    if width < MIN_EDGE or width > MAX_EDGE then return false end
    if height < MIN_EDGE or height > MAX_EDGE then return false end

    return true
end

--------------------------------------------------------------------------------
-- Adoption
--------------------------------------------------------------------------------

local function CapturePoints(frame)
    local points = {}
    for i = 1, frame:GetNumPoints() do
        points[i] = { frame:GetPoint(i) }
    end
    return points
end

local function RequestLayout()
    if layoutQueued or not active then return end
    layoutQueued = true
    -- Coalesce: twenty buttons registering during login produce one layout pass
    -- on the next frame, not twenty. C_Timer.After fires once and stops.
    C_Timer.After(0, function()
        layoutQueued = false
        Buttons:Layout()
    end)
end

-- Some Blizzard buttons resize themselves after we have placed them (the
-- expansion/Omnium Folio button is the notorious one). The hook fires only when
-- something else calls SetSize, so it costs nothing while nothing happens, and
-- it goes inert the moment the button leaves the grid.
local sizeGuard = false

local function LockSize(button)
    hooksecurefunc(button, "SetSize", function(self, w)
        if sizeGuard or not collected[self] then return end
        local target = PMM.Config.buttonSize or 26
        if w ~= target then
            sizeGuard = true
            self:SetSize(target, target)
            sizeGuard = false
        end
    end)
end

local function Adopt(button, options)
    if collected[button] then return false end
    options = options or {}

    local snapshot = {
        parent = button:GetParent(),
        points = CapturePoints(button),
        strata = button:GetFrameStrata(),
        level = button:GetFrameLevel(),
        scale = button:GetScale(),
        width = button:GetWidth(),
        height = button:GetHeight(),
        onDragStart = button:GetScript("OnDragStart"),
        onDragStop = button:GetScript("OnDragStop"),
        movable = button:IsMovable(),
    }

    -- A protected frame can refuse to be reparented in combat. Bail out before
    -- anything else is touched rather than leaving it half-adopted; the caller
    -- retries when combat ends.
    local reparented = pcall(RawSetParent, button, bar)
    if not reparented then return false end

    RawClearAllPoints(button)
    button:SetFrameStrata(bar:GetFrameStrata())
    button:SetFrameLevel(bar:GetFrameLevel() + 1)

    -- LibDBIcon re-places its buttons on a radius whenever the minimap shape,
    -- scale or its own settings change, and a hand-rolled button does the same
    -- from its drag handler. Overriding the methods on the instance is what
    -- makes a button stay where we put it; setting them back to nil restores
    -- the widget metatable lookup exactly.
    button.SetPoint = NOOP
    button.ClearAllPoints = NOOP
    button.SetParent = NOOP

    -- The drag handlers are the only per-frame work these buttons do. Removing
    -- them is a real reduction, not just tidiness - a LibDBIcon drag installs an
    -- OnUpdate that runs until you let go.
    button:SetScript("OnDragStart", nil)
    button:SetScript("OnDragStop", nil)
    button:SetMovable(false)

    -- A button that hides or shows itself changes the grid, so relayout then -
    -- and only then.
    button:HookScript("OnShow", RequestLayout)
    button:HookScript("OnHide", RequestLayout)

    collected[button] = snapshot
    order[#order + 1] = button

    if options.lockSize and not snapshot.sizeLocked then
        snapshot.sizeLocked = true
        LockSize(button)
    end

    return true
end

local function Forget(button)
    for index, entry in ipairs(order) do
        if entry == button then
            table.remove(order, index)
            return
        end
    end
end

local function Release(button)
    local snapshot = collected[button]
    if not snapshot then return end

    button.SetPoint = nil
    button.ClearAllPoints = nil
    button.SetParent = nil

    button:SetParent(snapshot.parent)
    button:ClearAllPoints()
    for _, point in ipairs(snapshot.points) do
        pcall(RawSetPoint, button, unpack(point))
    end
    button:SetFrameStrata(snapshot.strata)
    button:SetFrameLevel(snapshot.level)
    button:SetScale(snapshot.scale)
    button:SetSize(snapshot.width, snapshot.height)
    button:SetScript("OnDragStart", snapshot.onDragStart)
    button:SetScript("OnDragStop", snapshot.onDragStop)
    button:SetMovable(snapshot.movable)

    collected[button] = nil
end

--------------------------------------------------------------------------------
-- Scanning
--------------------------------------------------------------------------------

local SCAN_PARENTS = { "Minimap", "MinimapBackdrop", "MinimapCluster" }

-- Walks the minimap's children once and adopts anything that looks like an
-- addon button. Cheap and bounded: the minimap has a few dozen children, and
-- this runs a handful of times per session, never on a timer.
function Buttons:Scan()
    if not active then return 0 end

    local found = 0
    for _, parentName in ipairs(SCAN_PARENTS) do
        local parent = _G[parentName]
        if parent and parent.GetChildren then
            for _, child in ipairs({ parent:GetChildren() }) do
                if IsCollectible(child) and Adopt(child) then
                    found = found + 1
                end
            end
        end
    end

    if found > 0 then
        table.sort(order, function(a, b)
            return (a:GetName() or ""):lower() < (b:GetName() or ""):lower()
        end)
        Utils.Debug(PMM, "collected " .. found .. " minimap button(s)")
        RequestLayout()
    end

    return found
end

-- LibDBIcon tells us the moment a button is created, which removes any need to
-- poll for late-loading addons. We never bundle the library - this only hooks it
-- when some other addon has already loaded it.
local function HookLibDBIcon()
    if not _G.LibStub then return end
    local ok, lib = pcall(_G.LibStub, "LibDBIcon-1.0", true)
    if not ok or not lib or not lib.RegisterCallback then return end

    local registered = pcall(lib.RegisterCallback, PMM, "LibDBIcon_IconCreated", function(_, button)
        if active and IsCollectible(button) then
            Adopt(button)
            RequestLayout()
        end
    end)
    if registered then
        Utils.Debug(PMM, "LibDBIcon callback registered")
    end
end

--------------------------------------------------------------------------------
-- The grid
--------------------------------------------------------------------------------

local GROW = {
    BOTTOM = { point = "TOPRIGHT", relative = "BOTTOMRIGHT", x = 0, y = -6 },
    TOP = { point = "BOTTOMRIGHT", relative = "TOPRIGHT", x = 0, y = 6 },
    LEFT = { point = "TOPRIGHT", relative = "TOPLEFT", x = -6, y = 0 },
    RIGHT = { point = "TOPLEFT", relative = "TOPRIGHT", x = 6, y = 0 },
}

local function EnsureBar()
    if bar then return bar end

    bar = CreateFrame("Frame", "PeaversMiniMapButtonBar", _G.MinimapCluster, "BackdropTemplate")
    bar:SetFrameStrata("MEDIUM")
    bar:SetClampedToScreen(true)
    bar:Hide()

    -- An explicit affordance rather than a hidden right-click on the map: the
    -- user can see that there is something to open.
    toggle = CreateFrame("Button", "PeaversMiniMapButtonToggle", _G.Minimap, "BackdropTemplate")
    toggle:SetSize(16, 16)
    toggle:SetFrameStrata("MEDIUM")
    toggle:SetFrameLevel(_G.Minimap:GetFrameLevel() + 10)
    toggle:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    toggle:SetBackdropColor(0, 0, 0, 0.6)

    local chevron = toggle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chevron:SetPoint("CENTER", 0, 0)
    chevron:SetText("+")
    toggle.chevron = chevron

    toggle:SetScript("OnClick", function()
        if bar:IsShown() then
            bar:Hide()
            chevron:SetText("+")
        else
            Buttons:Layout()
            bar:Show()
            chevron:SetText("-")
        end
    end)
    toggle:SetScript("OnEnter", function(self)
        _G.GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        _G.GameTooltip:SetText("Addon buttons")
        _G.GameTooltip:AddLine("Click to show or hide the collected minimap buttons.", 0.8, 0.8, 0.8, true)
        _G.GameTooltip:Show()
    end)
    toggle:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
    toggle:Hide()

    return bar
end

Buttons.EnsureBar = EnsureBar

-- Hover mode. Both handlers are event-driven; the only timer is a single
-- one-shot that gives the pointer time to travel from the map to the grid.
local function ArmHoverHide()
    if hoverTimerArmed then return end
    hoverTimerArmed = true
    C_Timer.After(0.4, function()
        hoverTimerArmed = false
        if PMM.Config.visibility ~= "hover" then return end
        if bar and bar:IsShown() and not bar:IsMouseOver() and not _G.Minimap:IsMouseOver() then
            bar:Hide()
        end
    end)
end

local function ApplyVisibility()
    if not bar then return end
    local mode = PMM.Config.visibility or "always"

    if not active or #order == 0 then
        bar:Hide()
        if toggle then toggle:Hide() end
        return
    end

    if mode == "always" then
        bar:Show()
        if toggle then toggle:Hide() end
    elseif mode == "toggle" then
        if toggle then
            toggle:Show()
            toggle.chevron:SetText(bar:IsShown() and "-" or "+")
        end
    else -- hover
        if toggle then toggle:Hide() end
        if not _G.Minimap:IsMouseOver() and not bar:IsMouseOver() then
            bar:Hide()
        end
    end
end

function Buttons:Layout()
    if not active then return end
    EnsureBar()

    local config = PMM.Config
    local size = config.buttonSize or 26
    local spacing = config.buttonSpacing or 2
    local perRow = math.max(1, config.buttonsPerRow or 6)
    local step = size + spacing

    -- Only buttons the user has not excluded and that their own addon has not
    -- hidden take a slot in the grid.
    local visible = {}
    for _, button in ipairs(order) do
        local name = button:GetName()
        if collected[button] and not config.excluded[name] and button:IsShown() then
            visible[#visible + 1] = button
        end
    end

    local count = #visible
    if count == 0 then
        bar:SetSize(step, step)
        ApplyVisibility()
        return
    end

    local columns = math.min(perRow, count)
    local rows = math.ceil(count / perRow)

    for index, button in ipairs(visible) do
        local column = (index - 1) % perRow
        local row = math.floor((index - 1) / perRow)
        button:SetScale(1)
        button:SetSize(size, size)
        RawClearAllPoints(button)
        RawSetPoint(button, "TOPLEFT", bar, "TOPLEFT",
            spacing + column * step, -(spacing + row * step))
    end

    bar:SetSize(columns * step + spacing, rows * step + spacing)

    local grow = GROW[config.growDirection or "BOTTOM"] or GROW.BOTTOM
    bar:ClearAllPoints()
    bar:SetPoint(grow.point, _G.Minimap, grow.relative, grow.x, grow.y)

    if config.barBackground ~= false then
        bar:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
        bar:SetBackdropColor(0, 0, 0, config.barBackgroundAlpha or 0.5)
    else
        bar:SetBackdrop(nil)
    end

    if toggle then
        toggle:ClearAllPoints()
        toggle:SetPoint("BOTTOMRIGHT", _G.Minimap, "BOTTOMRIGHT", -2, 2)
    end

    ApplyVisibility()
end

--------------------------------------------------------------------------------
-- Blizzard's own buttons
--
-- Square.lua decides which of Blizzard's minimap widgets belong in the grid and
-- hands them over here. They go through exactly the same adoption as an addon
-- button, with one addition: a size lock, because several of them resize
-- themselves after the fact.
--------------------------------------------------------------------------------

function Buttons:IsCollected(frame)
    return frame ~= nil and collected[frame] ~= nil
end

function Buttons:AdoptExternal(frame)
    if not frame or collected[frame] then return collected[frame] ~= nil end
    if not active then return false end
    if not PMM.Config.enabled or PMM.Config.collectButtons == false then return false end

    EnsureBar()
    -- No name gate here: the caller already knows exactly what this frame is.
    if not Adopt(frame, { lockSize = true }) then return false end

    table.sort(order, function(a, b)
        return (a:GetName() or ""):lower() < (b:GetName() or ""):lower()
    end)
    RequestLayout()
    return true
end

function Buttons:ReleaseExternal(frame)
    if not frame or not collected[frame] then return false end
    Release(frame)
    Forget(frame)
    RequestLayout()
    return true
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Buttons:Initialize()
    if self.initialized then return end
    self.initialized = true

    EnsureBar()

    -- Hover mode needs to know when the pointer is over the map. HookScript
    -- leaves Blizzard's own handlers intact.
    if _G.Minimap then
        _G.Minimap:HookScript("OnEnter", function()
            if active and PMM.Config.visibility == "hover" and #order > 0 then
                Buttons:Layout()
                bar:Show()
            end
        end)
        _G.Minimap:HookScript("OnLeave", function()
            if active and PMM.Config.visibility == "hover" then ArmHoverHide() end
        end)
    end

    bar:SetScript("OnLeave", function()
        if active and PMM.Config.visibility == "hover" then ArmHoverHide() end
    end)

    if PMM.Config.enabled and PMM.Config.collectButtons ~= false then
        self:Enable()
    end
end

function Buttons:Enable()
    if active then return end
    if not PMM.Config.enabled or PMM.Config.collectButtons == false then return end

    active = true
    EnsureBar()
    HookLibDBIcon()
    self:Scan()

    -- Addons register their buttons at wildly different points during login.
    -- Three one-shot sweeps cover the stragglers and then the addon goes quiet
    -- for the rest of the session; LibDBIcon's callback catches anything later.
    for _, delay in ipairs({ 2, 6, 15 }) do
        C_Timer.After(delay, function()
            if active then Buttons:Scan() end
        end)
    end
end

function Buttons:Disable()
    if not active then return end
    active = false

    for _, button in ipairs(order) do
        Release(button)
    end
    order = {}
    collected = {}

    if bar then bar:Hide() end
    if toggle then toggle:Hide() end
end

function Buttons:Count()
    return #order
end

-- Every button currently under our control, for the exclusion editor.
function Buttons:GetNames()
    local names = {}
    for _, button in ipairs(order) do
        names[#names + 1] = button:GetName()
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

function Buttons:SetExcluded(name, excluded)
    PMM.Config.excluded[name] = excluded or nil
    PMM.Config:Save()

    if excluded then
        for _, button in ipairs(order) do
            if button:GetName() == name then
                Release(button)
                Forget(button)
                break
            end
        end
    else
        self:Scan()
    end

    self:Layout()
end

return Buttons
