-- AllTheThingsspoon: Unified menubar for incidents, CI, and PRs
local obj = {}
obj.__index = obj

-- Add current folder to package.path so we can require local modules
local script_dir = debug.getinfo(1, "S").source:match("@(.*/)")
package.path = script_dir .. "?.lua;" .. package.path

-- Import feature modules
local PagerDuty = require("pagerduty")
local CIStatus = require("cistatus")
local PRsToReview = require("prstoreview")

obj.menubar = nil
obj.modules = {}
obj.refreshTimer = nil
obj.refreshInterval = 10 -- seconds for unified menubar refresh

obj.ciStatus = nil
obj.prsToReview = nil
obj.thisIsFine = nil

function obj:init()
    -- This method is required for SpoonInstall:andUse compatibility
    return self
end

function obj:start()
    if self.menubar then return end
    self.menubar = hs.menubar.new()

    -- Initialize configured modules
    self.modules = {}
    if self.thisIsFine then
        self.modules.PagerDuty = PagerDuty.new(self.thisIsFine)
    end
    if self.ciStatus then
        self.modules.CIStatus = CIStatus.new(self.ciStatus)
    end
    if self.prsToReview then
        self.modules.PRsToReview = PRsToReview.new(self.prsToReview)
    end

    -- Set up periodic refresh for all modules
    for _, mod in pairs(self.modules) do
        if mod.start then mod:start() end
    end
    self:updateMenu()
    if not self.refreshTimer then
        self.refreshTimer = hs.timer.doEvery(self.refreshInterval, function() self:updateMenu() end)
    end
end

function obj:chooseIcon(icons)
    -- Default priority: 🔥 > ❌ > 👀 > 🏗️ > ✅ > 🙈 > ❓
    local priority = { ["🔥"] = 1, ["❌"] = 2, ["👀"] = 3, ["🏗️"] = 4, ["✅"] = 5, ["🙈"] = 6, ["❓"] = 7 }
    local best = "✅"
    local bestScore = 99
    for _, icon in ipairs(icons) do
        local score = priority[icon] or 99
        if score < bestScore then
            best = icon
            bestScore = score
        end
    end
    return best
end

function obj:updateMenu()
    -- Gather status from all modules
    local icons = {}
    local menu = {}
    for name, mod in pairs(self.modules) do
        if mod.getStatusIcon then
            table.insert(icons, mod:getStatusIcon())
        end
        if mod.getMenuItems then
            local section = mod:getMenuItems()
            if section and #section > 0 then
                table.insert(menu, { title = mod.sectionName, disabled = true })
                for _, item in ipairs(section) do table.insert(menu, item) end
                table.insert(menu, { title = "-", disabled = true })
            end
        end
    end
    if #menu > 0 and menu[#menu].title == "-" then table.remove(menu, #menu) end
    -- Pick the "worst" icon (fire > X > eyes > check)
    local icon = self:chooseIcon(icons)
    self.menubar:setTitle(icon)
    self.menubar:setMenu(menu)
end

function obj:refresh()
    for _, mod in pairs(self.modules) do
        if mod.refresh then mod:refresh() end
    end
    self:updateMenu()
end

function obj:stop()
    for _, mod in pairs(self.modules) do
        if mod.stop then mod:stop() end
    end
    if self.refreshTimer then self.refreshTimer:stop() self.refreshTimer = nil end
    if self.menubar then self.menubar:delete() self.menubar = nil end
end

return obj
