local _, PMM = ...

local ConfigUI = {}
PMM.ConfigUI = ConfigUI

local PeaversCommons = _G.PeaversCommons
if not PeaversCommons then
    print("|cffff0000Error:|r PeaversCommons not found.")
    return
end

local W = PeaversCommons.Widgets

local function ResolveWidth(parentFrame, indent)
    local parentWidth = parentFrame:GetWidth() or 0
    if parentWidth > 100 then
        return parentWidth - (indent * 2) - 10
    end
    return 360
end

local function Refresh()
    if PMM.Config.enabled then
        PMM.Square:Apply()
        PMM.Buttons:Layout()
    end
end

--------------------------------------------------------------------------------
-- Minimap page
--------------------------------------------------------------------------------

function ConfigUI:BuildMinimapPage(parentFrame)
    local y = -10
    local indent = 25
    local width = ResolveWidth(parentFrame, indent)

    local Square = PMM.Square
    local controls = {}
    local updatingUI = false

    local function SetControlsEnabled(enabled)
        local alpha = enabled and 1 or 0.4
        for _, control in ipairs(controls) do
            control:SetAlpha(alpha)
        end
    end

    local _, newY = W:CreateSectionHeader(parentFrame, "Minimap", indent, y)
    y = newY - 8

    local toggle = W:CreateCheckbox(parentFrame, "Enable PeaversMiniMap", {
        checked = PMM.Config.enabled == true,
        width = width,
        onChange = function(checked)
            if checked then Square:Enable() else Square:Disable() end
            SetControlsEnabled(checked)
        end,
    })
    toggle:SetPoint("TOPLEFT", indent, y)
    y = y - 34

    local squareToggle = W:CreateCheckbox(parentFrame, "Square shape", {
        checked = PMM.Config.squareShape ~= false,
        width = width,
        onChange = function(checked)
            PMM.Config.squareShape = checked
            PMM.Config:Save()
            Refresh()
        end,
    })
    squareToggle:SetPoint("TOPLEFT", indent, y)
    y = y - 34
    table.insert(controls, squareToggle)

    local sizeSlider = W:CreateSlider(parentFrame, "Size", {
        min = Square.SIZE_MIN,
        max = Square.SIZE_MAX,
        step = 5,
        value = PMM.Config.size or 200,
        width = width,
        onChange = function(value)
            if updatingUI then return end
            PMM.Config.size = value
            PMM.Config:Save()
            Refresh()
        end,
    })
    sizeSlider:SetPoint("TOPLEFT", indent, y)
    y = y - 56
    table.insert(controls, sizeSlider)

    local scaleSlider = W:CreateSlider(parentFrame, "Scale", {
        min = 0.5, max = 2.0, step = 0.05,
        value = PMM.Config.scale or 1,
        width = width,
        format = function(v) return string.format("%.2f", v) end,
        onChange = function(value)
            if updatingUI then return end
            PMM.Config.scale = value
            PMM.Config:Save()
            Refresh()
        end,
    })
    scaleSlider:SetPoint("TOPLEFT", indent, y)
    y = y - 56
    table.insert(controls, scaleSlider)

    local borderSlider = W:CreateSlider(parentFrame, "Border width", {
        min = 0, max = 10, step = 1,
        value = PMM.Config.borderSize or 2,
        width = width,
        onChange = function(value)
            if updatingUI then return end
            PMM.Config.borderSize = value
            PMM.Config:Save()
            Refresh()
        end,
    })
    borderSlider:SetPoint("TOPLEFT", indent, y)
    y = y - 62
    table.insert(controls, borderSlider)

    local _, posY = W:CreateSectionHeader(parentFrame, "Position", indent, y)
    y = posY - 8

    local anchorOptions = {}
    for _, anchor in ipairs(Square.ANCHORS) do
        anchorOptions[#anchorOptions + 1] = { value = anchor.key, label = anchor.label }
    end

    local anchorToggle = W:CreateCheckbox(parentFrame, "Pin to a screen corner", {
        checked = PMM.Config.anchorEnabled ~= false,
        width = width,
        onChange = function(checked)
            PMM.Config.anchorEnabled = checked
            PMM.Config:Save()
            if checked then Refresh() end
        end,
    })
    anchorToggle:SetPoint("TOPLEFT", indent, y)
    y = y - 30
    table.insert(controls, anchorToggle)

    local anchorHint = W:CreateLabel(parentFrame,
        "Off hands the minimap back to Blizzard's Edit Mode so you can place it yourself.",
        { font = "GameFontNormalSmall", color = { 0.5, 0.5, 0.5 } })
    anchorHint:SetPoint("TOPLEFT", indent, y)
    y = y - 26
    table.insert(controls, anchorHint)

    local anchorDropdown = W:CreateDropdown(parentFrame, "Corner", {
        options = anchorOptions,
        selected = PMM.Config.anchor or "TOPRIGHT",
        width = width,
        onChange = function(value)
            PMM.Config.anchor = value
            PMM.Config:Save()
            Refresh()
        end,
    })
    anchorDropdown:SetPoint("TOPLEFT", indent, y)
    y = y - 56
    table.insert(controls, anchorDropdown)

    local offsetXSlider = W:CreateSlider(parentFrame, "Distance from the side", {
        min = 0, max = 200, step = 1,
        value = PMM.Config.offsetX or 12,
        width = width,
        onChange = function(value)
            if updatingUI then return end
            PMM.Config.offsetX = value
            PMM.Config:Save()
            Refresh()
        end,
    })
    offsetXSlider:SetPoint("TOPLEFT", indent, y)
    y = y - 56
    table.insert(controls, offsetXSlider)

    local offsetYSlider = W:CreateSlider(parentFrame, "Distance from the top or bottom", {
        min = 0, max = 200, step = 1,
        value = PMM.Config.offsetY or 12,
        width = width,
        onChange = function(value)
            if updatingUI then return end
            PMM.Config.offsetY = value
            PMM.Config:Save()
            Refresh()
        end,
    })
    offsetYSlider:SetPoint("TOPLEFT", indent, y)
    y = y - 62
    table.insert(controls, offsetYSlider)

    local _, clutterY = W:CreateSectionHeader(parentFrame, "Clutter", indent, y)
    y = clutterY - 8

    local zoneDropdown = W:CreateDropdown(parentFrame, "Zone name", {
        options = {
            { value = "overlay", label = "On the top edge" },
            { value = "above", label = "Above the map" },
            { value = "hidden", label = "Hidden" },
        },
        selected = PMM.Config.zoneTextMode or "overlay",
        width = width,
        onChange = function(value)
            PMM.Config.zoneTextMode = value
            PMM.Config:Save()
            Refresh()
        end,
    })
    zoneDropdown:SetPoint("TOPLEFT", indent, y)
    y = y - 56
    table.insert(controls, zoneDropdown)

    local zoomToggle = W:CreateCheckbox(parentFrame, "Hide the zoom buttons", {
        checked = PMM.Config.hideZoomButtons ~= false,
        width = width,
        onChange = function(checked)
            PMM.Config.hideZoomButtons = checked
            PMM.Config:Save()
            Refresh()
        end,
    })
    zoomToggle:SetPoint("TOPLEFT", indent, y)
    y = y - 30
    table.insert(controls, zoomToggle)

    local zoomHint = W:CreateLabel(parentFrame,
        "The mouse wheel zooms the map whether these are shown or not.",
        { font = "GameFontNormalSmall", color = { 0.5, 0.5, 0.5 } })
    zoomHint:SetPoint("TOPLEFT", indent, y)
    y = y - 30
    table.insert(controls, zoomHint)

    SetControlsEnabled(PMM.Config.enabled == true)

    parentFrame:SetHeight(math.abs(y) + 30)
end

--------------------------------------------------------------------------------
-- Blizzard page
--------------------------------------------------------------------------------

function ConfigUI:BuildBlizzardPage(parentFrame)
    local y = -10
    local indent = 25
    local width = ResolveWidth(parentFrame, indent)

    local _, newY = W:CreateSectionHeader(parentFrame, "Blizzard's minimap buttons", indent, y)
    y = newY - 8

    local intro = W:CreateLabel(parentFrame,
        "A round minimap had somewhere to put all of this. A square one does " ..
            "not, so each piece can go in the button grid, sit on a corner of " ..
            "the map, or go away entirely.",
        { font = "GameFontNormalSmall", color = { 0.7, 0.7, 0.7 } })
    intro:SetPoint("TOPLEFT", indent, y)
    intro:SetWidth(width)
    y = y - 44

    local modes = {
        { value = "grid", label = "In the button grid" },
        { value = "corner", label = "On the map's corner" },
        { value = "hidden", label = "Hidden" },
    }

    for _, widget in ipairs(PMM.Square.WIDGETS) do
        local present = PMM.Square.ResolveWidget(widget) ~= nil
        local key = widget.key
        local dropdown = W:CreateDropdown(parentFrame, widget.label, {
            options = modes,
            selected = PMM.Square.ModeFor(widget),
            width = width,
            onChange = function(value)
                PMM.Config.widgets[key] = value
                PMM.Config:Save()
                Refresh()
            end,
        })
        dropdown:SetPoint("TOPLEFT", indent, y)
        -- A widget Blizzard has not created on this character still gets a
        -- control, greyed out, rather than vanishing from the list - otherwise
        -- the settings look different depending on what you happen to have.
        if not present then dropdown:SetAlpha(0.4) end
        y = y - 56
    end

    --------------------------------------------------------------------------
    -- Placement editor
    --
    -- One set of controls that edits whichever widget is picked, rather than
    -- four controls per widget stacked down a very long page. Populating the
    -- controls has to be guarded: the shared slider fires onChange from
    -- SetValue, so an unguarded refresh would write the value it just read
    -- back into the config of whichever widget was selected before.
    --------------------------------------------------------------------------

    local _, placeY = W:CreateSectionHeader(parentFrame, "Placement", indent, y)
    y = placeY - 8

    local placeHint = W:CreateLabel(parentFrame,
        "Position and size anything set to sit on the map's corner. Offsets " ..
            "measure inward from the anchor, so they read the same way whichever " ..
            "corner you pick.",
        { font = "GameFontNormalSmall", color = { 0.7, 0.7, 0.7 } })
    placeHint:SetPoint("TOPLEFT", indent, y)
    placeHint:SetWidth(width)
    y = y - 44

    local Square = PMM.Square
    local updatingUI = false
    local selected = Square.WIDGETS[1]
    for _, widget in ipairs(Square.WIDGETS) do
        -- Default the picker to the difficulty flag: it is the one that most
        -- wants moving, being the only widget that overlaps the map's contents.
        if widget.key == "difficulty" then selected = widget end
    end

    local pointDropdown, offsetXSlider, offsetYSlider, scaleSlider

    local function RefreshPlacement()
        local layout = Square:GetLayout(selected)
        updatingUI = true
        pointDropdown:SetSelected(layout.point)
        offsetXSlider:SetValue(layout.x)
        offsetYSlider:SetValue(layout.y)
        scaleSlider:SetValue(layout.scale)
        updatingUI = false
    end

    local widgetOptions = {}
    for _, widget in ipairs(Square.WIDGETS) do
        widgetOptions[#widgetOptions + 1] = { value = widget.key, label = widget.label }
    end

    local pickerDropdown = W:CreateDropdown(parentFrame, "Adjust", {
        options = widgetOptions,
        selected = selected.key,
        width = width,
        onChange = function(value)
            for _, widget in ipairs(Square.WIDGETS) do
                if widget.key == value then selected = widget end
            end
            RefreshPlacement()
        end,
    })
    pickerDropdown:SetPoint("TOPLEFT", indent, y)
    y = y - 56

    local pointOptions = {}
    for _, point in ipairs(Square.WIDGET_POINTS) do
        pointOptions[#pointOptions + 1] = { value = point.key, label = point.label }
    end

    pointDropdown = W:CreateDropdown(parentFrame, "Anchor", {
        options = pointOptions,
        selected = Square:GetLayout(selected).point,
        width = width,
        onChange = function(value)
            if updatingUI then return end
            Square:SetLayout(selected, "point", value)
            Refresh()
        end,
    })
    pointDropdown:SetPoint("TOPLEFT", indent, y)
    y = y - 56

    offsetXSlider = W:CreateSlider(parentFrame, "Horizontal offset", {
        min = 0, max = Square.WIDGET_OFFSET_MAX, step = 1,
        value = Square:GetLayout(selected).x,
        width = width,
        onChange = function(value)
            if updatingUI then return end
            Square:SetLayout(selected, "x", value)
            Refresh()
        end,
    })
    offsetXSlider:SetPoint("TOPLEFT", indent, y)
    y = y - 56

    offsetYSlider = W:CreateSlider(parentFrame, "Vertical offset", {
        min = 0, max = Square.WIDGET_OFFSET_MAX, step = 1,
        value = Square:GetLayout(selected).y,
        width = width,
        onChange = function(value)
            if updatingUI then return end
            Square:SetLayout(selected, "y", value)
            Refresh()
        end,
    })
    offsetYSlider:SetPoint("TOPLEFT", indent, y)
    y = y - 56

    scaleSlider = W:CreateSlider(parentFrame, "Icon size", {
        min = Square.WIDGET_SCALE_MIN, max = Square.WIDGET_SCALE_MAX, step = 0.05,
        value = Square:GetLayout(selected).scale,
        width = width,
        format = function(v) return string.format("%.2f", v) end,
        onChange = function(value)
            if updatingUI then return end
            Square:SetLayout(selected, "scale", value)
            Refresh()
        end,
    })
    scaleSlider:SetPoint("TOPLEFT", indent, y)
    y = y - 58

    local resetButton = W:CreateButton(parentFrame, "Reset this one", {
        width = width,
        onClick = function()
            Square:ResetLayout(selected)
            RefreshPlacement()
            Refresh()
        end,
    })
    resetButton:SetPoint("TOPLEFT", indent, y)
    y = y - 34

    local placeNote = W:CreateLabel(parentFrame,
        "The difficulty flag, mail icon and group finder eye only appear when " ..
            "they have something to say, so you may need to be in an instance " ..
            "or queue to see a change.",
        { font = "GameFontNormalSmall", color = { 0.5, 0.5, 0.5 } })
    placeNote:SetPoint("TOPLEFT", indent, y)
    placeNote:SetWidth(width)
    y = y - 50

    local _, trackerY = W:CreateSectionHeader(parentFrame, "Objective tracker", indent, y)
    y = trackerY - 8

    local trackerDropdown = W:CreateDropdown(parentFrame, "Quest tracker position", {
        options = {
            { value = "detach", label = "Leave it where it is" },
            { value = "leave", label = "Let it follow the minimap" },
        },
        selected = PMM.Config.objectiveTracker or "detach",
        width = width,
        onChange = function(value)
            PMM.Config.objectiveTracker = value
            PMM.Config:Save()
            Refresh()
        end,
    })
    trackerDropdown:SetPoint("TOPLEFT", indent, y)
    y = y - 56

    local trackerHint = W:CreateLabel(parentFrame,
        "Blizzard anchors the quest tracker to the minimap, so moving the map " ..
            "drags the tracker across the screen with it. Detaching gives the " ..
            "tracker an anchor of its own; you can still move it in Edit Mode.",
        { font = "GameFontNormalSmall", color = { 0.5, 0.5, 0.5 } })
    trackerHint:SetPoint("TOPLEFT", indent, y)
    trackerHint:SetWidth(width)
    y = y - 50

    parentFrame:SetHeight(math.abs(y) + 30)
end

--------------------------------------------------------------------------------
-- Buttons page
--------------------------------------------------------------------------------

function ConfigUI:BuildButtonsPage(parentFrame)
    local y = -10
    local indent = 25
    local width = ResolveWidth(parentFrame, indent)

    local _, newY = W:CreateSectionHeader(parentFrame, "Addon buttons", indent, y)
    y = newY - 8

    local intro = W:CreateLabel(parentFrame,
        "Addon buttons that place themselves around the minimap are collected " ..
            "into one grid. Buttons you exclude are left exactly where their " ..
            "addon put them.",
        { font = "GameFontNormalSmall", color = { 0.7, 0.7, 0.7 } })
    intro:SetPoint("TOPLEFT", indent, y)
    intro:SetWidth(width)
    y = y - 40

    local collectToggle = W:CreateCheckbox(parentFrame, "Collect addon buttons", {
        checked = PMM.Config.collectButtons ~= false,
        width = width,
        onChange = function(checked)
            PMM.Config.collectButtons = checked
            PMM.Config:Save()
            if checked then PMM.Buttons:Enable() else PMM.Buttons:Disable() end
            -- Blizzard's widgets need re-placing either way: into the grid when
            -- collection comes back, onto their corners when it goes away.
            Refresh()
        end,
    })
    collectToggle:SetPoint("TOPLEFT", indent, y)
    y = y - 38

    local visibilityDropdown = W:CreateDropdown(parentFrame, "Show the grid", {
        options = {
            { value = "always", label = "Always" },
            { value = "hover", label = "While the pointer is over the minimap" },
            { value = "toggle", label = "Only when I click the button" },
        },
        selected = PMM.Config.visibility or "always",
        width = width,
        onChange = function(value)
            PMM.Config.visibility = value
            PMM.Config:Save()
            PMM.Buttons:Layout()
        end,
    })
    visibilityDropdown:SetPoint("TOPLEFT", indent, y)
    y = y - 56

    local growDropdown = W:CreateDropdown(parentFrame, "Grid position", {
        options = {
            { value = "BOTTOM", label = "Below the minimap" },
            { value = "TOP", label = "Above the minimap" },
            { value = "LEFT", label = "Left of the minimap" },
            { value = "RIGHT", label = "Right of the minimap" },
        },
        selected = PMM.Config.growDirection or "BOTTOM",
        width = width,
        onChange = function(value)
            PMM.Config.growDirection = value
            PMM.Config:Save()
            PMM.Buttons:Layout()
        end,
    })
    growDropdown:SetPoint("TOPLEFT", indent, y)
    y = y - 56

    local perRowSlider = W:CreateSlider(parentFrame, "Buttons per row", {
        min = 1, max = 12, step = 1,
        value = PMM.Config.buttonsPerRow or 6,
        width = width,
        onChange = function(value)
            PMM.Config.buttonsPerRow = value
            PMM.Config:Save()
            PMM.Buttons:Layout()
        end,
    })
    perRowSlider:SetPoint("TOPLEFT", indent, y)
    y = y - 56

    local buttonSizeSlider = W:CreateSlider(parentFrame, "Button size", {
        min = 16, max = 40, step = 1,
        value = PMM.Config.buttonSize or 26,
        width = width,
        onChange = function(value)
            PMM.Config.buttonSize = value
            PMM.Config:Save()
            PMM.Buttons:Layout()
        end,
    })
    buttonSizeSlider:SetPoint("TOPLEFT", indent, y)
    y = y - 56

    local backgroundToggle = W:CreateCheckbox(parentFrame, "Background behind the grid", {
        checked = PMM.Config.barBackground ~= false,
        width = width,
        onChange = function(checked)
            PMM.Config.barBackground = checked
            PMM.Config:Save()
            PMM.Buttons:Layout()
        end,
    })
    backgroundToggle:SetPoint("TOPLEFT", indent, y)
    y = y - 42

    local _, listY = W:CreateSectionHeader(parentFrame, "Collected buttons", indent, y)
    y = listY - 8

    local names = PMM.Buttons:GetNames()
    if #names == 0 then
        local empty = W:CreateLabel(parentFrame,
            "Nothing collected yet. Buttons appear here once their addon creates " ..
                "them; /pmm scan looks again.",
            { font = "GameFontNormalSmall", color = { 0.5, 0.5, 0.5 } })
        empty:SetPoint("TOPLEFT", indent, y)
        empty:SetWidth(width)
        y = y - 40
    else
        for _, name in ipairs(names) do
            local row = W:CreateCheckbox(parentFrame, name, {
                checked = not PMM.Config.excluded[name],
                width = width,
                onChange = function(checked)
                    PMM.Buttons:SetExcluded(name, not checked)
                end,
            })
            row:SetPoint("TOPLEFT", indent, y)
            y = y - 26
        end
        y = y - 10
    end

    local rescan = W:CreateButton(parentFrame, "Scan for new buttons", {
        width = width,
        variant = "primary",
        onClick = function()
            PMM.Buttons:Scan()
            PMM.Buttons:Layout()
        end,
    })
    rescan:SetPoint("TOPLEFT", indent, y)
    y = y - 40

    parentFrame:SetHeight(math.abs(y) + 30)
end

--------------------------------------------------------------------------------
-- Information page
--------------------------------------------------------------------------------

function ConfigUI:BuildInfoPage(parentFrame)
    PeaversCommons.ConfigUIUtils.BuildInfoPage(parentFrame, "MiniMap", {
        "Squares the minimap, pins it to a corner of the screen, and gathers " ..
            "the addon buttons that scatter themselves around its edge into a " ..
            "single grid.",
        { command = "/pmm", desc = "open the settings" },
        { command = "/pmm size N", desc = "set the square's edge length" },
        { command = "/pmm scan", desc = "look for buttons that appeared late" },
        { command = "/pmm buttons", desc = "list every collected button" },
        { command = "/pmm disable", desc = "restore Blizzard's minimap exactly as it was" },

        { header = "Everything is reversible" },
        "Every value the addon overwrites is captured before the first change. " ..
            "Turning it off puts the minimap, its widgets and every collected " ..
            "button back where Blizzard and their own addons had them - no " ..
            "reload required.",

        { header = "About the button grid" },
        "Buttons are identified by exclusion rather than by a list of known " ..
            "addons, so a button from an addon released tomorrow is still " ..
            "collected. Once collected, a button cannot move itself again: the " ..
            "grid owns its position until you exclude it or disable collection.",

        { header = "Performance" },
        "The addon runs nothing per frame and nothing on a timer. Layout happens " ..
            "when something actually changes, and repeated changes in the same " ..
            "frame are coalesced into one pass. It also strips the drag handlers " ..
            "from collected buttons, which removes the per-frame work those run " ..
            "while you hold one.",
    })
end

function ConfigUI:GetPages()
    return {
        { key = "info", label = "Information", builder = function(f) ConfigUI:BuildInfoPage(f) end },
        { key = "minimap", label = "Minimap", builder = function(f) ConfigUI:BuildMinimapPage(f) end },
        { key = "buttons", label = "Buttons", builder = function(f) ConfigUI:BuildButtonsPage(f) end },
        { key = "blizzard", label = "Blizzard", builder = function(f) ConfigUI:BuildBlizzardPage(f) end },
    }
end

function ConfigUI:BuildIntoFrame(parentFrame)
    self:BuildMinimapPage(parentFrame)
    return parentFrame
end

function ConfigUI:OpenOptions()
    if _G.PeaversConfig and _G.PeaversConfig.MainFrame then
        _G.PeaversConfig.MainFrame:Show()
        _G.PeaversConfig.MainFrame:SelectAddon("PeaversMiniMap")
        return
    end

    if Settings and Settings.OpenToCategory then
        if PMM.directSettingsCategoryID then
            local success = pcall(Settings.OpenToCategory, PMM.directSettingsCategoryID)
            if success then return end
        end
        if PMM.directCategoryID then
            local success = pcall(Settings.OpenToCategory, PMM.directCategoryID)
            if success then return end
        end
    end

    if SettingsPanel then
        SettingsPanel:Open()
    end
end

function ConfigUI:Initialize()
end

return ConfigUI
