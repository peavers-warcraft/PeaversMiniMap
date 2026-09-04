--------------------------------------------------------------------------------
-- PeaversMiniMap Configuration
--
-- Account-wide by design: where the minimap sits and how big it is are
-- properties of the screen, not of the character, so this uses the flat
-- (non-profile) ConfigManager variant.
--------------------------------------------------------------------------------

local addonName, PMM = ...

local PeaversCommons = _G.PeaversCommons
local ConfigManager = PeaversCommons.ConfigManager

PMM.name = PMM.name or addonName

local PMM_DEFAULTS = {
    -- Master toggle. The addon does not touch the minimap until this is on.
    enabled = true,

    -- Shape and size
    squareShape = true,
    size = 155,
    scale = 1.0,
    borderSize = 0,
    borderColor = { r = 0, g = 0, b = 0, a = 1 },

    -- Position. anchorEnabled = false hands the minimap back to Edit Mode.
    anchorEnabled = true,
    anchor = "TOPRIGHT",
    offsetX = 0,
    offsetY = 0,

    -- Blizzard furniture
    zoneTextMode = "hidden",    -- "overlay" | "above" | "hidden"
    hideZoomButtons = true,

    -- Per-widget disposition, keyed by Square.WIDGETS[].key:
    -- "corner" | "grid" | "hidden". Anything absent uses that widget's own
    -- default, so a widget added in a later patch does not need a migration.
    widgets = {},

    -- Sparse per-widget placement for anything in "corner" mode:
    -- [key] = { point = "TOPLEFT", x = 2, y = 34, scale = 1 }. Offsets are
    -- positive insets measured inward from the anchor; Square derives the sign.
    widgetLayout = {},

    -- Blizzard anchors the quest tracker to MinimapCluster, so moving the
    -- minimap drags it too. "detach" gives it an anchor of its own, once;
    -- "leave" keeps Blizzard's behaviour.
    objectiveTracker = "detach",

    -- Addon button grid
    collectButtons = true,
    visibility = "toggle",      -- "always" | "hover" | "toggle"
    growDirection = "LEFT",     -- "BOTTOM" | "TOP" | "LEFT" | "RIGHT"
    buttonSize = 26,
    buttonSpacing = 2,
    buttonsPerRow = 2,
    barBackground = false,
    barBackgroundAlpha = 0.5,
    excluded = {},              -- [button frame name] = true, left where it is

    debugMode = false,
    DEBUG_ENABLED = false,
}

PMM.Config = ConfigManager:New(PMM, PMM_DEFAULTS, {
    savedVariablesName = "PeaversMiniMapDB",
})

return PMM.Config
