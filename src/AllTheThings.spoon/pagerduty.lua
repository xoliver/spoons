-- PagerDuty module for AllTheThingsspoon
local utils = require("utils")
local obj = {}
obj.__index = obj

function obj.new(cfg)
    local self = setmetatable({}, obj)
    self.sectionName = cfg.sectionName or "PagerDuty incidents"
    self.apiKey = cfg.apiKey
    self.serviceIds = cfg.serviceIds
    self.incidentAgeThresholdHours = cfg.incidentAgeThresholdHours or 24
    self.incidents = {}
    self.timer = nil
    self.refreshInterval = cfg.refreshInterval or 300
    self.apiError = false
    self.apiErrorMessage = nil
    return self
end

function obj:refresh()
    if not self.apiKey then
        self.incidents = {}
        self.apiError = false
        self.apiErrorMessage = nil
        return
    end
    local url = "https://api.pagerduty.com/incidents?statuses[]=triggered&statuses[]=acknowledged&sort_by=created_at:desc"
    if self.serviceIds and type(self.serviceIds) == "table" and #self.serviceIds > 0 then
        for _, id in ipairs(self.serviceIds) do
            url = url .. "&service_ids[]=" .. hs.http.encodeForQuery(id)
        end
    end
    hs.http.asyncGet(
        url,
        {
            ["Authorization"] = "Token token=" .. self.apiKey,
            ["Accept"] = "application/json",
            ["Content-Type"] = "application/json",
        },
        function(status, body, _)
            if status == 200 then
                local ok, result = pcall(hs.json.decode, body)
                if ok and result and result.incidents then
                    local now = os.time()
                    for _, incident in ipairs(result.incidents) do
                        local started = incident.created_at or ""
                        local incident_time = utils.parseISO8601(started)
                        if incident_time then
                            local diff = now - incident_time
                            incident._how_long_ago = diff
                        else
                            incident._how_long_ago = nil
                        end
                    end
                    self.incidents = result.incidents
                    self.apiError = false
                    self.apiErrorMessage = nil
                else
                    self.incidents = {}
                    self.apiError = true
                    self.apiErrorMessage = (result and result.error and result.error.message) or "Failed to parse response"
                end
            else
                self.incidents = {}
                self.apiError = true
                local ok, result = pcall(hs.json.decode, body)
                if ok and result and result.error and result.error.message then
                    self.apiErrorMessage = result.error.message
                else
                    self.apiErrorMessage = body or ("HTTP error: " .. tostring(status))
                end
            end
        end
    )
end

function obj:getStatusIcon()
    if self.apiError then return "❓" end
    local threshold = (self.incidentAgeThresholdHours or 24) * 3600
    for _, incident in ipairs(self.incidents or {}) do
        if incident._how_long_ago and incident._how_long_ago < threshold then
            return "🔥"
        end
    end
    return "✅"
end

function obj:getMenuItems()
    if self.apiError then
        return {{ title = self.apiErrorMessage or "API error", disabled = true }}
    end
    local hasIncidents = self.incidents and #self.incidents > 0
    if not hasIncidents then
        return {{ title = "No open incidents", disabled = true }}
    end
    local menu = {}
    local function how_long_ago_string(diff)
        return utils.formatTimeDiff(diff)
    end
    local function add_incident_group_to_menu(group)
        if #group == 0 then
            table.insert(menu, { title = "This is fine", disabled = true })
        else
            for _, incident in ipairs(group) do
                local name = incident.summary or incident.title or "(no summary)"
                local ago = how_long_ago_string(incident._how_long_ago)
                local id = incident.id or "?"
                table.insert(menu, {
                    title = string.format("%s (%s)", name, ago),
                    fn = function() hs.urlevent.openURL(incident.html_url or ("https://pagerduty.com/incidents/" .. id)) end
                })
            end
        end
    end
    -- Separate incidents into recent and old
    local threshold = (self.incidentAgeThresholdHours or 24) * 3600
    local recent = {}
    local old = {}
    for _, incident in ipairs(self.incidents) do
        if incident._how_long_ago and incident._how_long_ago < threshold then
            table.insert(recent, incident)
        else
            table.insert(old, incident)
        end
    end
    if #recent > 0 then
        add_incident_group_to_menu(recent)
    end
    if #old > 0 then
        table.insert(menu, { title = "Older", disabled = true })
        add_incident_group_to_menu(old)
    end
    if #menu == 0 then
        table.insert(menu, { title = "This is actually fine!", disabled = true })
    end
    return menu
end

function obj:start()
    if self.timer then return end
    self:refresh()
    self.timer = hs.timer.doEvery(self.refreshInterval, function() self:refresh() end)
end

function obj:stop()
    if self.timer then self.timer:stop() self.timer = nil end
end

return obj
