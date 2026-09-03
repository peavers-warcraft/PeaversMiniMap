--------------------------------------------------------------------------------
-- Ultra Performance case: what PeaversMiniMap costs while you play.
--
-- This addon is not a bar or a meter - it lays out a minimap once and then gets
-- out of the way. So the claim being tested is a negative one: after everything
-- is set up, the addon does no work per frame and no work per second.
--
-- A negative claim is exactly the kind that rots quietly, which is why it is
-- measured rather than asserted. The case loads the real Square.lua and
-- Buttons.lua, drives a full login (square applied, thirty addon buttons
-- collected, grid built), then hunts down every OnUpdate handler the addon
-- installed on any frame it created and ticks them for a simulated second. If
-- somebody adds a ticker later, these numbers stop being zero.
--------------------------------------------------------------------------------

local Stubs = dofile(HARNESS_LIB .. "/wow-stubs.lua").Install()

-- fengari is Lua 5.3; the addon is written against WoW's Lua 5.1, where unpack
-- is a global.
_G.unpack = _G.unpack or table.unpack

local Count = Stubs.Count

--------------------------------------------------------------------------------
-- A slightly richer frame than the shared stub
--
-- Square.lua and Buttons.lua both read layout state back (they capture every
-- anchor point before overwriting it, so Restore can be exact). The shared stub
-- makes an unknown method an inert counted no-op, which returns nil - and
-- `for i = 1, frame:GetNumPoints()` needs a number. Anything added here follows
-- the harness counting rule: geometry reads that force a layout are counted,
-- trivial state reads are not.
--------------------------------------------------------------------------------

local baseCreateFrame = _G.CreateFrame
local createdFrames = {}
local frameNames = {}

local function Enrich(frame, name, objectType, parent)
    frame._name = name
    frame._objectType = objectType or "Frame"
    frame._parent = parent
    frame._points = {}
    frame._children = {}
    frame._scale = 1
    frame._movable = false
    frame._width = frame._width or 30
    frame._height = frame._height or 30

    function frame:GetName() return self._name end
    function frame:GetObjectType() return self._objectType end
    function frame:IsObjectType(t) return self._objectType == t end
    function frame:GetParent() return self._parent end
    function frame:GetScale() return self._scale end
    function frame:SetScale(v) Count("SetScale") self._scale = v end
    function frame:IsMovable() return self._movable end
    function frame:SetMovable(v) Count("SetMovable") self._movable = v end
    function frame:IsMouseOver() return false end
    function frame:GetFrameStrata() return "MEDIUM" end
    function frame:GetFrameLevel() return 1 end
    function frame:GetChildren() return unpack(self._children) end

    -- Anchor bookkeeping. SetPoint/ClearAllPoints stay counted by the shared
    -- stub's own definitions; these wrap them so the addon can read points back.
    function frame:SetPoint(...)
        Count("SetPoint")
        self._points[#self._points + 1] = { ... }
    end
    function frame:ClearAllPoints()
        Count("ClearAllPoints")
        self._points = {}
    end
    function frame:GetNumPoints()
        -- A layout-forcing read, same class as GetWidth/GetHeight.
        Count("GetNumPoints")
        return #self._points
    end
    function frame:GetPoint(i)
        Count("GetPoint")
        local p = self._points[i]
        if not p then return nil end
        return unpack(p)
    end

    function frame:SetParent(newParent)
        Count("SetParent")
        self._parent = newParent
        if newParent and newParent._children then
            newParent._children[#newParent._children + 1] = self
        end
    end

    return frame
end

_G.CreateFrame = function(objectType, name, parent, _template)
    local frame = Enrich(baseCreateFrame(), name, objectType, parent)
    createdFrames[#createdFrames + 1] = frame
    if name then frameNames[name] = frame end
    if parent and parent._children then
        parent._children[#parent._children + 1] = frame
    end
    return frame
end

local function NewNamed(name, objectType, parent, width)
    local frame = _G.CreateFrame(objectType or "Frame", name, parent)
    frame._width = width or 30
    frame._height = width or 30
    frame._shown = true
    return frame
end

--------------------------------------------------------------------------------
-- The world the addon expects
--------------------------------------------------------------------------------

Enrich(_G.UIParent, "UIParent", "Frame")

_G.hooksecurefunc = function(target, method, hook)
    -- Real hooksecurefunc wraps the method; the case only needs the wrapping to
    -- happen so that anything the addon triggers through it is still counted.
    if type(target) == "string" then target, method, hook = _G, target, method end
    local original = target[method]
    target[method] = function(...)
        local result = original(...)
        hook(...)
        return result
    end
end

-- A deferred C_Timer, unlike the shared stub's immediate one. The addon's
-- coalescing depends on After(0) actually landing on the next frame, and
-- measuring it with a synchronous timer would measure the wrong thing.
local pending = {}
_G.C_Timer = {
    After = function(delay, fn)
        pending[#pending + 1] = { delay = delay, fn = fn }
    end,
    NewTicker = function()
        error("PeaversMiniMap must not create a ticker", 2)
    end,
}

-- Run every timer whose delay has elapsed. Returns how many fired.
local function FlushTimers(maxDelay)
    local due, remaining = {}, {}
    for _, entry in ipairs(pending) do
        if entry.delay <= (maxDelay or 0) then
            due[#due + 1] = entry
        else
            remaining[#remaining + 1] = entry
        end
    end
    pending = remaining
    for _, entry in ipairs(due) do entry.fn() end
    return #due
end

_G.GameTooltip = Enrich(baseCreateFrame(), "GameTooltip", "Frame")

_G.PeaversCommons = {
    Utils = {
        Debug = function() end,
        Print = function() end,
    },
}

--------------------------------------------------------------------------------
-- Blizzard's minimap
--------------------------------------------------------------------------------

local Minimap = NewNamed("Minimap", "Frame", nil, 198)
local MinimapCluster = NewNamed("MinimapCluster", "Frame", nil, 240)
Minimap._parent = MinimapCluster
MinimapCluster._children[#MinimapCluster._children + 1] = Minimap

_G.Minimap = Minimap
_G.MinimapCluster = MinimapCluster
_G.MinimapBackdrop = NewNamed("MinimapBackdrop", "Frame", Minimap, 198)
_G.MinimapCompassTexture = NewNamed("MinimapCompassTexture", "Frame", Minimap, 198)
_G.MinimapZoneText = Stubs.NewTexture()
_G.GetMinimapShape = function() return "ROUND" end

Minimap.ZoomIn = NewNamed("MinimapZoomIn", "Button", Minimap, 32)
Minimap.ZoomOut = NewNamed("MinimapZoomOut", "Button", Minimap, 32)

MinimapCluster.BorderTop = NewNamed("MinimapClusterBorderTop", "Frame", MinimapCluster, 200)
MinimapCluster.ZoneTextButton = NewNamed("MinimapZoneTextButton", "Button", MinimapCluster, 150)
MinimapCluster.Tracking = NewNamed("MiniMapTracking", "Frame", MinimapCluster, 32)
MinimapCluster.InstanceDifficulty = NewNamed("MiniMapInstanceDifficulty", "Frame", MinimapCluster, 32)
MinimapCluster.IndicatorFrame = NewNamed("MinimapIndicatorFrame", "Frame", MinimapCluster, 32)

_G.ExpansionLandingPageMinimapButton = NewNamed("ExpansionLandingPageMinimapButton", "Button", Minimap, 32)
_G.QueueStatusButton = NewNamed("QueueStatusButton", "Button", Minimap, 32)
_G.GameTimeFrame = NewNamed("GameTimeFrame", "Button", Minimap, 32)
_G.AddonCompartmentFrame = NewNamed("AddonCompartmentFrame", "Button", Minimap, 32)

--------------------------------------------------------------------------------
-- Thirty third-party buttons, placed the way the real ones place themselves
--------------------------------------------------------------------------------

local BUTTON_COUNT = 30
local addonButtons = {}

for i = 1, BUTTON_COUNT do
    local button = NewNamed(string.format("LibDBIcon10_TestAddon%02d", i), "Button", Minimap, 31)
    button:SetPoint("CENTER", Minimap, "CENTER", i, -i)

    -- A LibDBIcon button installs an OnUpdate for the duration of a drag, and
    -- that handler calls SetPoint every frame. This is the per-frame work the
    -- addon removes; modelling it is the only way the removal can be measured.
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(inner)
            inner:ClearAllPoints()
            inner:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
        end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    addonButtons[i] = button
end

--------------------------------------------------------------------------------
-- Load the real addon source
--------------------------------------------------------------------------------

local PMM = { name = "PeaversMiniMap" }

-- Config is a ConfigManager instance in game; the case supplies the same shape
-- with the addon's own documented defaults so the code under test is real.
PMM.Config = {
    enabled = true,
    squareShape = true,
    size = 200,
    scale = 1.0,
    borderSize = 2,
    borderColor = { r = 0, g = 0, b = 0, a = 1 },
    anchorEnabled = true,
    anchor = "TOPRIGHT",
    offsetX = 12,
    offsetY = 12,
    zoneTextMode = "overlay",
    hideZoomButtons = true,
    hiddenWidgets = {},
    collectButtons = true,
    visibility = "always",
    growDirection = "BOTTOM",
    buttonSize = 26,
    buttonSpacing = 2,
    buttonsPerRow = 6,
    barBackground = true,
    barBackgroundAlpha = 0.5,
    excluded = {},
    Save = function() end,
}

assert(loadfile(ADDON_DIR .. "/src/Core/Square.lua"))("PeaversMiniMap", PMM)
assert(loadfile(ADDON_DIR .. "/src/Core/Buttons.lua"))("PeaversMiniMap", PMM)

--------------------------------------------------------------------------------
-- Drive a login
--------------------------------------------------------------------------------

Stubs.ResetCounts()

PMM.Square:Initialize()
PMM.Buttons:Initialize()
FlushTimers(0)              -- the coalesced layout pass lands here

-- Addons register their buttons at wildly different points during login, so the
-- addon sweeps again at 2, 6 and 15 seconds. Firing those here is what makes the
-- "idle" scenario below a genuine steady state rather than a snapshot taken
-- while work is still pending.
FlushTimers(15)
local setupCalls = Stubs.TotalCalls()

assert(#pending == 0,
    #pending .. " timer(s) still queued once login has settled; the addon should be inert by now")

local collected = PMM.Buttons:Count()
assert(collected == BUTTON_COUNT,
    string.format("expected %d buttons collected, got %d", BUTTON_COUNT, collected))
assert(_G.GetMinimapShape() == "SQUARE", "minimap shape was not squared")

-- Every drag handler is gone, so no collected button can start an OnUpdate.
local dragHandlersLeft = 0
for _, button in ipairs(addonButtons) do
    if button:GetScript("OnDragStart") or button:GetScript("OnDragStop") then
        dragHandlersLeft = dragHandlersLeft + 1
    end
end
assert(dragHandlersLeft == 0,
    dragHandlersLeft .. " collected buttons kept their drag handler")

--------------------------------------------------------------------------------
-- Scenario 1: steady state
--
-- Collect every OnUpdate handler on every frame the addon created, plus the
-- minimap frames it touched, and tick them. The expected count of handlers is
-- zero; driving them anyway means the number stays honest if that changes.
--------------------------------------------------------------------------------

local function CollectOnUpdateHandlers()
    local handlers = {}
    local seen = {}

    local function consider(frame)
        if not frame or seen[frame] then return end
        seen[frame] = true
        local fn = frame._scripts and frame._scripts.OnUpdate
        if fn then handlers[#handlers + 1] = { frame = frame, fn = fn } end
    end

    for _, frame in ipairs(createdFrames) do consider(frame) end
    consider(Minimap)
    consider(MinimapCluster)
    for _, button in ipairs(addonButtons) do consider(button) end
    return handlers
end

local function MeasureSteadyState(label, frames, fps)
    local handlers = CollectOnUpdateHandlers()
    local ticked = 0
    local perFrame = Stubs.Drive(function(step)
        for _, entry in ipairs(handlers) do
            -- WoW does not tick a hidden frame; neither do we.
            if entry.frame:IsShown() then
                entry.fn(entry.frame, step)
                ticked = ticked + 1
            end
        end
    end, frames, 1 / fps)

    return {
        name = label,
        callsPerFrame = perFrame,
        notes = string.format("%d OnUpdate handler(s) across %d frames; %d tick(s)",
            #handlers, frames, ticked),
    }
end

--------------------------------------------------------------------------------
-- Scenario 2: an idle second
--------------------------------------------------------------------------------

local function MeasureIdle(fps)
    local handlers = CollectOnUpdateHandlers()
    Stubs.ResetCounts()
    for _ = 1, fps do
        Stubs.time = Stubs.time + 1 / fps
        for _, entry in ipairs(handlers) do
            if entry.frame:IsShown() then entry.fn(entry.frame, 1 / fps) end
        end
    end
    -- Nothing is queued either: a pending timer is work about to happen.
    local queued = #pending
    return {
        name = "idle, one second at " .. fps .. "fps",
        callsPerFrame = 0,
        idleCallsPerSecond = Stubs.TotalCalls(),
        notes = string.format("%d handler(s), %d queued timer(s)", #handlers, queued),
    }
end

--------------------------------------------------------------------------------
-- Scenario 3: a burst of late-registering buttons
--
-- Ten addons finishing their load in the same frame must produce one layout
-- pass, not ten. This is the only place the addon does real work during play,
-- so it is the only place a regression could hide.
--------------------------------------------------------------------------------

local function MeasureBurst()
    local burst = {}
    for i = 1, 10 do
        local button = NewNamed(string.format("LibDBIcon10_LateAddon%02d", i), "Button", Minimap, 31)
        button:SetPoint("CENTER", Minimap, "CENTER", i, i)
        burst[i] = button
    end

    Stubs.ResetCounts()
    local before = PMM.Buttons:Count()
    PMM.Buttons:Scan()
    local passes = FlushTimers(0)
    local after = PMM.Buttons:Count()

    assert(after - before == #burst,
        string.format("burst: expected %d new buttons, got %d", #burst, after - before))
    assert(passes == 1,
        string.format("burst: expected 1 coalesced layout pass, got %d", passes))

    return {
        name = "10 addons register buttons in one frame",
        callsPerFrame = 0,
        notes = string.format("%d client calls, 1 coalesced layout pass, %d buttons in the grid",
            Stubs.TotalCalls(), after),
    }
end

--------------------------------------------------------------------------------
-- Scenario 4: full teardown
--
-- Restore is the promise the README makes. Measuring it keeps it cheap and,
-- more usefully, keeps it from silently breaking.
--------------------------------------------------------------------------------

local function MeasureRestore()
    Stubs.ResetCounts()
    PMM.Buttons:Disable()
    PMM.Square:Restore()
    local calls = Stubs.TotalCalls()

    assert(PMM.Buttons:Count() == 0, "buttons were not released")
    assert(_G.GetMinimapShape() == "ROUND", "minimap shape was not restored")
    for _, button in ipairs(addonButtons) do
        assert(button:GetScript("OnDragStart"), "a button did not get its drag handler back")
    end

    return {
        name = "disable and restore Blizzard's minimap",
        callsPerFrame = 0,
        notes = calls .. " client calls, one-off",
    }
end

local burst = MeasureBurst()
local steady = MeasureSteadyState("steady state, 144fps", 144, 144)
local steady60 = MeasureSteadyState("steady state, 60fps", 60, 60)
local idle = MeasureIdle(144)
local restore = MeasureRestore()

return {
    {
        name = "login: square applied, " .. BUTTON_COUNT .. " buttons collected",
        callsPerFrame = 0,
        notes = setupCalls .. " client calls, one-off",
    },
    burst,
    steady,
    steady60,
    idle,
    restore,
}
