local addonName, PMM = ...

-- Access the PeaversCommons library
local PeaversCommons = _G.PeaversCommons
local Utils = PeaversCommons.Utils

-- Initialize addon namespace
PMM.name = addonName
PMM.version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "1.0.0"

-- Register slash commands
PeaversCommons.SlashCommands:Register(addonName, "pmm", {
    default = function()
        PMM.ConfigUI:OpenOptions()
    end,
    enable = function()
        PMM.Square:Enable()
        Utils.Print(PMM, "Square minimap enabled.")
    end,
    disable = function()
        PMM.Square:Disable()
        Utils.Print(PMM, "Restored Blizzard's minimap.")
    end,
    size = function(rest)
        local value = tonumber(rest)
        if not value then
            Utils.Print(PMM, string.format("Usage: /pmm size 220 (%d-%d)",
                PMM.Square.SIZE_MIN, PMM.Square.SIZE_MAX))
            return
        end
        PMM.Config.size = math.max(PMM.Square.SIZE_MIN, math.min(PMM.Square.SIZE_MAX, value))
        PMM.Config:Save()
        PMM.Square:Apply()
        Utils.Print(PMM, "Minimap size set to " .. PMM.Config.size .. ".")
    end,
    scan = function()
        local found = PMM.Buttons:Scan()
        PMM.Buttons:Layout()
        Utils.Print(PMM, string.format("Scanned: %d new, %d button(s) collected.",
            found, PMM.Buttons:Count()))
    end,
    buttons = function()
        local names = PMM.Buttons:GetNames()
        if #names == 0 then
            Utils.Print(PMM, "No addon buttons collected.")
            return
        end
        Utils.Print(PMM, #names .. " button(s) collected:")
        for _, name in ipairs(names) do
            print("  " .. name .. (PMM.Config.excluded[name] and " |cffff8800(excluded)|r" or ""))
        end
    end,
    info = function()
        PMM.Square:PrintInfo()
        Utils.Print(PMM, PMM.Buttons:Count() .. " addon button(s) in the grid.")
    end,
    debug = function()
        PMM.Config.debugMode = not PMM.Config.debugMode
        PMM.Config.DEBUG_ENABLED = PMM.Config.debugMode
        PMM.Config:Save()
        Utils.Print(PMM, "Debug mode " .. (PMM.Config.debugMode and "enabled" or "disabled"))
    end,
    help = function()
        Utils.Print(PMM, "Commands:")
        print("  /pmm - Open settings")
        print("  /pmm enable - Square the minimap and collect addon buttons")
        print("  /pmm disable - Restore Blizzard's minimap exactly as it was")
        print("  /pmm size N - Set the square's edge length in pixels")
        print("  /pmm scan - Look for addon buttons that appeared late")
        print("  /pmm buttons - List the collected buttons")
        print("  /pmm info - Print minimap diagnostics")
    end
})

-- Initialize the addon
PeaversCommons.Events:Init(addonName, function()
    PMM.Config:Initialize()

    -- Buttons first: Square hands Blizzard's calendar, group-finder eye and
    -- expansion button straight into the grid as it applies, so the grid has to
    -- be live by then. Square:Apply finishes by laying the grid out against the
    -- minimap's final geometry, so nothing is lost by starting this way round.
    PMM.Buttons:Initialize()
    PMM.Square:Initialize()

    if PMM.ConfigUI and PMM.ConfigUI.Initialize then
        PMM.ConfigUI:Initialize()
    end

    if PMM.Patrons and PMM.Patrons.Initialize then
        PMM.Patrons:Initialize()
    end

    -- Edit Mode restores the minimap's own anchor during login, after our first
    -- Apply. Reapplying here is what makes the square survive a cold start.
    PeaversCommons.Events:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        if PMM.Config.enabled then
            PMM.Square:Apply()
            PMM.Buttons:Scan()
        end
    end)

    -- Leaving Edit Mode, or switching layout, rewrites the cluster anchor.
    PeaversCommons.Events:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", function()
        if PMM.Config.enabled then
            C_Timer.After(0, function() PMM.Square:Apply() end)
        end
    end)

    -- A protected frame can refuse to be reparented during combat, which leaves
    -- a Blizzard widget sitting in a corner instead of the grid. Retry once the
    -- fight is over. Registering the event costs nothing while out of combat.
    PeaversCommons.Events:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if PMM.Config.enabled then PMM.Square:Apply() end
    end)

    -- Use the centralized SettingsUI system from PeaversCommons
    C_Timer.After(0.5, function()
        PeaversCommons.SettingsUI:CreateRedirectPage(PMM, "PeaversMiniMap", "Peavers MiniMap")
    end)

    -- Register with PeaversConfig registry
    if PeaversCommons.ConfigRegistry then
        PeaversCommons.ConfigRegistry:Register({
            name = "PeaversMiniMap",
            displayName = "MiniMap",
            description = "Square minimap with a tidy addon button grid",
            addonRef = PMM,
            config = PMM.Config,
            pages = PMM.ConfigUI:GetPages(),
            order = 13,
        })
    end
end, {
    suppressAnnouncement = true
})

_G.PeaversMiniMap = PMM
