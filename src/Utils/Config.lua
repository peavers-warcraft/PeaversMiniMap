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
    size = 200,
    scale = 1.0,
    borderSize = 2,
    borderColor = { r = 0, g = 0, b = 0, a = 1 },

    -- Position. anchorEnabled = false hands the minimap back to Edit Mode.
    anchorEnabled = true,
    anchor = "TOPRIGHT",
    offsetX = 12,
    offsetY = 12,

    -- Blizzard furniture
    zoneTextMode = "overlay",   -- "overlay" | "above" | "hidden"
    hideZoomButtons = true,
    hiddenWidgets = {},         -- [frame path from Square.PLACEMENTS] = true

    -- Addon button grid
    collectButtons = true,
    visibility = "always",      -- "always" | "hover" | "toggle"
    growDirection = "BOTTOM",   -- "BOTTOM" | "TOP" | "LEFT" | "RIGHT"
    buttonSize = 26,
    buttonSpacing = 2,
    buttonsPerRow = 6,
    barBackground = true,
    barBackgroundAlpha = 0.5,
    excluded = {},              -- [button frame name] = true, left where it is

    debugMode = false,
    DEBUG_ENABLED = false,
}

PMM.Config = ConfigManager:New(PMM, PMM_DEFAULTS, {
    savedVariablesName = "PeaversMiniMapDB",
})

return PMM.Config
