local obj = {}
obj.__index = obj

obj.name = "ThisIsFine"
obj.apiKey = nil
obj.menubar = nil
obj.incidents = {}
obj.timer = nil
obj.refreshInterval = 300 -- seconds
obj.apiError = false
obj.apiErrorMessage = nil
obj.serviceIds = nil
obj.incidentAgeThresholdHours = 24

function obj:init()
    if self.menubar then return end -- Prevent multiple menubars
    self.menubar = hs.menubar.new()
    self:updateMenu()
    if not self.timer then
        self.timer = hs.timer.doEvery(self.refreshInterval, function() self:refresh() end)
    end
end

function obj:refresh()
    if not self.apiKey then
        self.incidents = {}
        self.apiError = false
        self.apiErrorMessage = nil
        self:updateMenu()
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
                        local pattern = "^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)"
                        local y, m, d, H, M, S = started:match(pattern)
                        if y then
                            local incident_time = os.time({year=tonumber(y), month=tonumber(m), day=tonumber(d), hour=tonumber(H), min=tonumber(M), sec=tonumber(S)})
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
            self:updateMenu()
        end
    )
end

function obj:updateMenu()
    if not self.menubar then return end
    if self.apiError then
        self.menubar:setTitle("❓")
        self.menubar:setMenu({{ title = self.apiErrorMessage or "API error", disabled = true }})
        return
    end
    local hasIncidents = self.incidents and #self.incidents > 0
    local showFire = false
    local threshold = (self.incidentAgeThresholdHours or 24) * 3600
    if hasIncidents then
        for _, incident in ipairs(self.incidents) do
            if incident._how_long_ago and incident._how_long_ago < threshold then
                showFire = true
                break
            end
        end
    end
    self.menubar:setTitle(showFire and "🔥" or "✅")
    if not hasIncidents then
        self.menubar:setMenu({{ title = "No open incidents", disabled = true }})
        return
    end
    local menu = {}
    local function how_long_ago_string(diff)
        if not diff then return "(N/A)" end
        if diff < 60 then
            return string.format("(%ds)", diff)
        elseif diff < 3600 then
            return string.format("(%dm)", math.floor(diff/60))
        elseif diff < 86400 then
            return string.format("(%dh)", math.floor(diff/3600))
        else
            return string.format("(%dd)", math.floor(diff/86400))
        end
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
                    title = string.format("%s %s", name, ago),
                    fn = function() hs.urlevent.openURL(incident.html_url or ("https://pagerduty.com/incidents/" .. id)) end
                })
            end
        end
    end
    -- Separate incidents into recent and old
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

    self.menubar:setMenu(menu)
end

function obj:configure(cfg)
    self.apiKey = cfg.apiKey
    self.serviceIds = cfg.serviceIds
    self.incidentAgeThresholdHours = cfg.incidentAgeThresholdHours or 24
end

function obj:start()
    self:init()
    self.menubar:setTitle("⏳")
    hs.timer.doAfter(3, function() self:refresh() end)
end

function obj:stop()
    if self.timer then self.timer:stop() self.timer = nil end
    if self.menubar then self.menubar:delete() self.menubar = nil end
end

return obj
