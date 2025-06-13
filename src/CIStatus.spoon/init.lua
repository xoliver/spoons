--- === CIStatus ===
---
--- A Hammerspoon Spoon to monitor CI pipelines via Buildkite and display the status in the macOS menu bar.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "CIStatus"
obj.version = "1.0"
obj.author = "Your Name"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- Default values
obj.bkOrganization = nil
obj.bkPipeline = nil
obj.bkToken = nil
obj.branches = { "master", "production" } -- Default branches
obj.logoPath = nil -- Path to the logo image
obj.menubar = nil
obj.refreshSeconds = 180 -- Seconds

-- Maps for emojis
obj.statusToEmoji = {
    Success = "✅",
    Failure = "❌",
    Exception = "⚠️",
    Unknown = "❓"
}
obj.activityToEmoji = {
    Sleeping = "💤",
    Building = "🏗️"
}

--- CIStatus:init()
--- Method
--- Initializes the spoon.
function obj:init()
    self.menubar = hs.menubar.new()
    if self.logoPath then
        self:_setMenubarIcon(self.logoPath)
    end
    self.menubar:setTitle("⏳")
end

--- CIStatus:start()
--- Method
--- Starts monitoring the CI pipeline.
function obj:start()
    hs.timer.doAfter(3, function() self:_updateMenu() end)
    -- Refresh every 5 minutes
    self.timer = hs.timer.doEvery(self.refreshSeconds, function() self:_updateMenu() end)
end

--- CIStatus:stop()
--- Method
--- Stops monitoring the CI pipeline.
function obj:stop()
    if self.timer then
        self.timer:stop()
        self.timer = nil
    end
    self.menubar:delete()
end

-- Helper: Set a processed menubar icon
function obj:_setMenubarIcon(logoPath)
    local image = hs.image.imageFromPath(logoPath)
    if image then
        -- Resize image to standard menubar size
        self.menubar:setIcon(image:setSize({ w = 16, h = 16 }))
    end
end

-- Helper: Update the menu bar icon and menu items
function obj:_updateMenu()
    local projects = {}
    local hasFailures = false
    local isBuilding = false
    local pendingCalls = #self.branches

    -- Helper function to process the HTTP response
    local function processResponse(status, body)
        if status == 200 then
            for name, activity, lastBuildStatus, lastBuildTime, webUrl in string.gmatch(
                body,
                '<Project.-name="(.-)".-activity="(.-)".-lastBuildStatus="(.-)".-lastBuildTime="(.-)".-webUrl="(.-)".->'
            ) do
                -- Determine the emoji
                local emoji
                if activity == "Sleeping" then
                    emoji = obj.statusToEmoji[lastBuildStatus] or "❓"
                else
                    emoji = obj.activityToEmoji[activity] or "❓"
                end

                -- Check for statuses
                if lastBuildStatus == "Failure" or lastBuildStatus == "Exception" then
                    hasFailures = true
                elseif activity == "Building" then
                    isBuilding = true
                end

                -- Parse lastBuildTime (assumes ISO 8601 format)
                local buildTime = obj:_parseISO8601(lastBuildTime)
                local now = os.time()
                local diff = os.difftime(now, buildTime)
                local timeDiff = obj:_formatTimeDiff(diff)

                -- Add to menu
                table.insert(projects, {
                    title = string.format("%s %s (%s)", emoji, name, timeDiff),
                    fn = function() hs.urlevent.openURL(webUrl) end
                })
            end
        else
            table.insert(projects, {
                title = "Error fetching projects",
                disabled = true
            })
        end

        -- Decrement pending calls and update menu bar icon
        pendingCalls = pendingCalls - 1
        if pendingCalls == 0 then
            self:_updateMenuBar(hasFailures, isBuilding, projects)
        end
    end

    -- Helper function to make an HTTP call
    local function makeCall(branch)
        -- https://buildkite.com/docs/pipelines/integrations/other/cc-menu
        local url = string.format(
            "https://cc.buildkite.com/%s/%s.xml?access_token=%s&branch=%s",
            hs.http.encodeForQuery(self.bkOrganization),
            hs.http.encodeForQuery(self.bkPipeline),
            hs.http.encodeForQuery(self.bkToken),
            hs.http.encodeForQuery(branch)
        )
        hs.http.asyncGet(url, nil, processResponse)
    end

    -- Make calls for each branch
    for _, branch in ipairs(self.branches) do
        makeCall(branch)
    end
end

-- Helper: Update the menubar emoji and menu
function obj:_updateMenuBar(hasFailures, isBuilding, projects)
    local emoji
    if hasFailures then
        emoji = "🔴"
    elseif isBuilding then
        emoji = "🟠"
    else
        emoji = "🟢"
    end
    self.menubar:setTitle(emoji)
    self.menubar:setMenu(projects)
end

-- Helper: Parse ISO 8601 timestamp
function obj:_parseISO8601(timestamp)
    local pattern = "(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)"
    local year, month, day, hour, min, sec = timestamp:match(pattern)
    return os.time({
        year = year,
        month = month,
        day = day,
        hour = hour,
        min = min,
        sec = sec
    })
end

-- Helper: Format time difference
function obj:_formatTimeDiff(diff)
    local days = math.floor(diff / (60 * 60 * 24))
    local hours = math.floor((diff % (60 * 60 * 24)) / (60 * 60))
    if days > 0 then
        return string.format("%d%dh", days, hours)
    elseif hours > 0 then
        return string.format("%dh", hours)
    else
        return string.format("%dm", math.floor(diff / 60))
    end
end

return obj