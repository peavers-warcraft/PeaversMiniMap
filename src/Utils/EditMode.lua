local addonName, PMM = ...

--------------------------------------------------------------------------------
-- Edit Mode
--
-- This addon does not own a frame - it reshapes Blizzard's minimap, which is
-- already a system in Edit Mode with its own position and its own dialog. So
-- rather than registering a frame of our own and giving the user two things to
-- select for one thing on screen, the settings hang off Blizzard's minimap
-- dialog as an extension.
--
-- Position is deliberately absent from the schema for the same reason. Edit
-- Mode moves the minimap; anchorEnabled below decides whether this addon pins
-- it to a corner instead, and the anchor settings only appear when it does.
--
-- Two of the groups are not flat lists. The map widgets are a dozen frames each
-- with their own placement, and the collected addon buttons are whatever the
-- other addons on the machine happened to create - so both use a selector,
-- which names one at a time and rebinds the settings under it.
--------------------------------------------------------------------------------

local PeaversCommons = _G.PeaversCommons

local EditMode = {}
PMM.EditMode = EditMode

--------------------------------------------------------------------------------
-- Applying a change
--------------------------------------------------------------------------------

function PMM.ApplySetting()
    if not PMM.Config.enabled then return end

    if PMM.Square then PMM.Square:Apply() end
    if PMM.Buttons then PMM.Buttons:Layout() end
end

--------------------------------------------------------------------------------
-- Option lists
--------------------------------------------------------------------------------

local WIDGET_MODES = {
    { value = "grid", label = "In the button grid" },
    { value = "corner", label = "On the map's corner" },
    { value = "hidden", label = "Hidden" },
}

local function AnchorOptions()
    local out = {}
    for _, anchor in ipairs(PMM.Square.ANCHORS or {}) do
        out[#out + 1] = { value = anchor.key, label = anchor.label }
    end
    return out
end

local function WidgetPoints()
    local out = {}
    for _, point in ipairs(PMM.Square.WIDGET_POINTS or {}) do
        out[#out + 1] = { value = point.key, label = point.label }
    end
    return out
end

-- The widget the selector is currently naming.
local function WidgetFor(key)
    for _, widget in ipairs(PMM.Square.WIDGETS or {}) do
        if widget.key == key then return widget end
    end
end

--------------------------------------------------------------------------------
-- Groups
--------------------------------------------------------------------------------

EditMode.SECTIONS = {
    { key = "map", label = "Map" },
    { key = "anchor", label = "Position" },
    { key = "blizzard", label = "Blizzard Furniture" },
    {
        key = "widgets", label = "Map Widgets",
        -- A dozen widgets, each with its own placement. Naming one at a time is
        -- what the settings page did with a picker, and for the same reason.
        selector = {
            label = "Adjust",
            values = function()
                local out = {}
                for _, widget in ipairs(PMM.Square.WIDGETS or {}) do
                    out[#out + 1] = { value = widget.key, label = widget.label }
                end
                return out
            end,
        },
    },
    { key = "grid", label = "Button Grid" },
    {
        key = "collected", label = "Collected Buttons",
        -- Whatever the other addons on this machine happened to create, which is
        -- not known until they have created it. The values are a function, so
        -- the list is whatever has been collected by the time you open it.
        selector = {
            label = "Button",
            values = function()
                local out = {}
                for _, name in ipairs(PMM.Buttons and PMM.Buttons:GetNames() or {}) do
                    out[#out + 1] = { value = name, label = name }
                end
                return out
            end,
        },
    },
}

EditMode.ENTRIES = {
    ------------------------------------------------------------------- map ---
    {
        key = "enabled", label = "Enabled", kind = "checkbox", section = "map",
        desc = "The minimap is left entirely alone until this is on.",
    },
    { key = "squareShape", label = "Square Shape", kind = "checkbox", section = "map" },
    {
        key = "size", label = "Size", kind = "slider", section = "map",
        min = 100, max = 400, step = 5, unit = "px",
    },
    {
        key = "scale", label = "Scale", kind = "slider", section = "map",
        min = 0.5, max = 2.0, step = 0.05, unit = "percent",
    },
    {
        key = "borderSize", label = "Border Size", kind = "slider", section = "map",
        min = 0, max = 10, step = 1, unit = "px",
    },
    { key = "borderColor", label = "Border Colour", kind = "color", section = "map" },

    ---------------------------------------------------------------- anchor ---
    {
        key = "anchorEnabled", label = "Pin To A Corner", kind = "checkbox",
        section = "anchor", revealsOthers = true,
        desc = "Off hands the minimap back to Edit Mode, which then places it "
            .. "like any other frame.",
    },
    {
        key = "anchor", label = "Corner", kind = "dropdown", section = "anchor",
        values = AnchorOptions, fallback = "TOPRIGHT",
        hidden = function(cfg) return not cfg.anchorEnabled end,
    },
    {
        key = "offsetX", label = "X Offset", kind = "slider", section = "anchor",
        min = 0, max = 200, step = 1, unit = "px",
        hidden = function(cfg) return not cfg.anchorEnabled end,
    },
    {
        key = "offsetY", label = "Y Offset", kind = "slider", section = "anchor",
        min = 0, max = 200, step = 1, unit = "px",
        hidden = function(cfg) return not cfg.anchorEnabled end,
    },

    -------------------------------------------------------------- blizzard ---
    {
        key = "zoneTextMode", label = "Zone Name", kind = "dropdown", section = "blizzard",
        fallback = "hidden",
        values = {
            { value = "overlay", label = "On the top edge" },
            { value = "above", label = "Above the map" },
            { value = "hidden", label = "Hidden" },
        },
    },
    { key = "hideZoomButtons", label = "Hide Zoom Buttons", kind = "checkbox", section = "blizzard" },
    {
        key = "objectiveTracker", label = "Quest Tracker", kind = "dropdown",
        section = "blizzard", fallback = "detach",
        values = {
            { value = "detach", label = "Leave it where it is" },
            { value = "leave", label = "Let it follow the minimap" },
        },
    },

    --------------------------------------------------------------- widgets ---
    -- Everything below is read and written against whichever widget the
    -- selector is naming, which arrives as the context.
    {
        key = "widgetMode", label = "Show", kind = "dropdown", section = "widgets",
        values = WIDGET_MODES, default = "grid",
        revealsOthers = true,
        getValue = function(_, key)
            local widget = WidgetFor(key)
            return widget and PMM.Square.ModeFor(widget) or "grid"
        end,
        setValue = function(config, key, value)
            config.widgets = config.widgets or {}
            config.widgets[key] = value
        end,
    },
    {
        key = "widgetPoint", label = "Anchor", kind = "dropdown", section = "widgets",
        values = WidgetPoints, default = "TOPLEFT",
        -- Placement only means anything for a widget sitting on the map.
        hidden = function(cfg, key)
            local widget = WidgetFor(key)
            return not widget or PMM.Square.ModeFor(widget) ~= "corner"
        end,
        getValue = function(_, key)
            local widget = WidgetFor(key)
            return widget and PMM.Square:GetLayout(widget).point
        end,
        setValue = function(_, key, value)
            local widget = WidgetFor(key)
            if widget then PMM.Square:SetLayout(widget, "point", value) end
        end,
    },
    {
        key = "widgetX", label = "Across", kind = "slider", section = "widgets",
        min = 0, max = 300, step = 1, unit = "px", default = 0,
        desc = "Measured inward from the anchor, so it reads the same whichever "
            .. "corner you pick.",
        hidden = function(cfg, key)
            local widget = WidgetFor(key)
            return not widget or PMM.Square.ModeFor(widget) ~= "corner"
        end,
        getValue = function(_, key)
            local widget = WidgetFor(key)
            return widget and PMM.Square:GetLayout(widget).x
        end,
        setValue = function(_, key, value)
            local widget = WidgetFor(key)
            if widget then PMM.Square:SetLayout(widget, "x", value) end
        end,
    },
    {
        key = "widgetY", label = "Down", kind = "slider", section = "widgets",
        min = 0, max = 300, step = 1, unit = "px", default = 0,
        hidden = function(cfg, key)
            local widget = WidgetFor(key)
            return not widget or PMM.Square.ModeFor(widget) ~= "corner"
        end,
        getValue = function(_, key)
            local widget = WidgetFor(key)
            return widget and PMM.Square:GetLayout(widget).y
        end,
        setValue = function(_, key, value)
            local widget = WidgetFor(key)
            if widget then PMM.Square:SetLayout(widget, "y", value) end
        end,
    },
    {
        key = "widgetScale", label = "Scale", kind = "slider", section = "widgets",
        min = 0.5, max = 2.5, step = 0.05, unit = "percent", default = 1,
        hidden = function(cfg, key)
            local widget = WidgetFor(key)
            return not widget or PMM.Square.ModeFor(widget) ~= "corner"
        end,
        getValue = function(_, key)
            local widget = WidgetFor(key)
            return widget and PMM.Square:GetLayout(widget).scale
        end,
        setValue = function(_, key, value)
            local widget = WidgetFor(key)
            if widget then PMM.Square:SetLayout(widget, "scale", value) end
        end,
    },

    ------------------------------------------------------------------ grid ---
    { key = "collectButtons", label = "Collect Addon Buttons", kind = "checkbox", section = "grid" },
    {
        key = "visibility", label = "Show The Grid", kind = "dropdown", section = "grid",
        fallback = "toggle",
        values = {
            { value = "always", label = "Always" },
            { value = "hover", label = "While the pointer is over the minimap" },
            { value = "toggle", label = "Only when I click the button" },
        },
    },
    {
        key = "growDirection", label = "Grow", kind = "dropdown", section = "grid",
        fallback = "LEFT",
        values = {
            { value = "BOTTOM", label = "Below the minimap" },
            { value = "TOP", label = "Above the minimap" },
            { value = "LEFT", label = "Left of the minimap" },
            { value = "RIGHT", label = "Right of the minimap" },
        },
    },
    {
        key = "buttonSize", label = "Button Size", kind = "slider", section = "grid",
        min = 16, max = 40, step = 1, unit = "px",
    },
    {
        key = "buttonSpacing", label = "Button Spacing", kind = "slider", section = "grid",
        min = 0, max = 10, step = 1, unit = "px",
    },
    {
        key = "buttonsPerRow", label = "Buttons Per Row", kind = "slider", section = "grid",
        min = 1, max = 12, step = 1,
    },
    { key = "barBackground", label = "Grid Background", kind = "checkbox", section = "grid" },
    {
        key = "barBackgroundAlpha", label = "Background Opacity", kind = "slider",
        section = "grid", min = 0, max = 1, step = 0.05, unit = "percent",
    },

    ------------------------------------------------------------- collected ---
    -- One checkbox, rebound by the selector to whichever button is named. The
    -- config stores the exclusions, so the sense is inverted: ticked means
    -- collected.
    {
        key = "buttonCollected", label = "Move Into The Grid", kind = "checkbox",
        section = "collected", default = true,
        desc = "Unticked leaves the button wherever its own addon put it.",
        getValue = function(config, name)
            if not name then return true end
            return not (config.excluded or {})[name]
        end,
        setValue = function(_, name, value)
            if name and PMM.Buttons then
                PMM.Buttons:SetExcluded(name, not value)
            end
        end,
    },
}

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

function EditMode:BuildSchema()
    if self.schema then return self.schema end

    self.schema = PeaversCommons.SettingsSchema:New({
        config = PMM.Config,
        sections = self.SECTIONS,
        entries = self.ENTRIES,
        apply = function() PMM.ApplySetting() end,
    })

    return self.schema
end

function EditMode:Register()
    if not PeaversCommons.EditMode or not PeaversCommons.EditMode.available then
        return false
    end
    if not (Enum and Enum.EditModeSystem and Enum.EditModeSystem.Minimap) then
        return false
    end

    PeaversCommons.EditMode:RegisterSystem({
        systemID = Enum.EditModeSystem.Minimap,
        name = "Peavers MiniMap",
        schema = self:BuildSchema(),
        buttons = {
            {
                text = "Scan For New Buttons",
                click = function()
                    if not PMM.Buttons then return end
                    PMM.Buttons:Scan()
                    PMM.Buttons:Layout()
                    if PeaversCommons.EditModePanel then
                        PeaversCommons.EditModePanel:Refresh()
                    end
                end,
            },
        },
    })

    return true
end

return EditMode
