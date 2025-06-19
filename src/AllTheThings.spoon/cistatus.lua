-- CIStatus module for AllTheThingsspoon
local utils = require("utils")
local obj = {}
obj.__index = obj

function obj.new(cfg)
    local self = setmetatable({}, obj)
    self.sectionName = cfg.sectionName or "CI status"
    self.bkOrganization = cfg.bkOrganization
    self.bkPipeline = cfg.bkPipeline
    self.bkToken = cfg.bkToken
    self.branches = cfg.branches or { "master", "production" }
    self.refreshSeconds = cfg.refreshSeconds or 180
    self.projects = {}
    self.timer = nil
    self.hasFailures = false
    self.isBuilding = false
    self.apiError = false
    self.apiErrorMessage = nil
    return self
end

function obj:refresh()
    self.projects = {}
    self.hasFailures = false
    self.isBuilding = false
    self.apiError = false
    self.apiErrorMessage = nil
    local pendingCalls = #self.branches
    if not self.bkOrganization or not self.bkPipeline or not self.bkToken then
        self.apiError = true
        self.apiErrorMessage = "Missing Buildkite config"
        return
    end
    local function processResponse(status, body)
        if status == 200 then
            for name, activity, lastBuildStatus, lastBuildTime, webUrl in string.gmatch(
                body,
                '<Project.-name="(.-)".-activity="(.-)".-lastBuildStatus="(.-)".-lastBuildTime="(.-)".-webUrl="(.-)".->'
            ) do
                local emoji
                if activity == "Sleeping" then
                    emoji = obj.statusToEmoji[lastBuildStatus] or "❓"
                else
                    emoji = obj.activityToEmoji[activity] or "❓"
                end
                if lastBuildStatus == "Failure" or lastBuildStatus == "Exception" then
                    self.hasFailures = true
                elseif activity == "Building" then
                    self.isBuilding = true
                end
                local buildTime = utils.parseISO8601(lastBuildTime)
                local now = os.time()
                local diff = os.difftime(now, buildTime)
                local timeDiff = utils.formatTimeDiff(diff)
                table.insert(self.projects, {
                    title = string.format("%s %s (%s)", emoji, name, timeDiff),
                    fn = function() hs.urlevent.openURL(webUrl) end
                })
            end
        else
            table.insert(self.projects, {
                title = "Error fetching projects",
                disabled = true
            })
            self.apiError = true
            self.apiErrorMessage = "Error fetching projects"
        end
        pendingCalls = pendingCalls - 1
    end
    local function makeCall(branch)
        local url = string.format(
            "https://cc.buildkite.com/%s/%s.xml?access_token=%s&branch=%s",
            hs.http.encodeForQuery(self.bkOrganization),
            hs.http.encodeForQuery(self.bkPipeline),
            hs.http.encodeForQuery(self.bkToken),
            hs.http.encodeForQuery(branch)
        )
        hs.http.asyncGet(url, nil, processResponse)
    end
    for _, branch in ipairs(self.branches) do
        makeCall(branch)
    end
end

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

function obj:getStatusIcon()
    if self.apiError then return "❓" end
    if self.hasFailures then return "❌" end
    if self.isBuilding then return "🏗️" end
    return "✅"
end

function obj:getMenuItems()
    if self.apiError then
        return {{ title = self.apiErrorMessage or "API error", disabled = true }}
    end
    if not self.projects or #self.projects == 0 then
        return {{ title = "No CI data", disabled = true }}
    end
    return self.projects
end

function obj:start()
    if self.timer then return end
    self:refresh()
    self.timer = hs.timer.doEvery(self.refreshSeconds, function() self:refresh() end)
end

function obj:stop()
    if self.timer then self.timer:stop() self.timer = nil end
end

return obj
