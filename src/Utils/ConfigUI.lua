local _, PMM = ...

local ConfigUI = {}
PMM.ConfigUI = ConfigUI

local PeaversCommons = _G.PeaversCommons
if not PeaversCommons then
    print("|cffff0000Error:|r PeaversCommons not found.")
    return
end

local ConfigUIUtils = PeaversCommons.ConfigUIUtils

function ConfigUI:BuildInfoPage(parentFrame)
    ConfigUIUtils.BuildInfoPageWithEditMode(parentFrame, "MiniMap", {
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
    }, {
        title = "the minimap",
        select = "the minimap",
        reset = function()
            PMM.Config:Reset()
            if PMM.ApplySetting then PMM.ApplySetting() end
            if PeaversCommons.EditModePanel then
                PeaversCommons.EditModePanel:Refresh()
            end
        end,
    })
end

function ConfigUI:GetPages()
    return {
        { key = "info", label = "Information", builder = function(f) ConfigUI:BuildInfoPage(f) end },
    }
end

function ConfigUI:BuildIntoFrame(parentFrame)
    self:BuildInfoPage(parentFrame)
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
