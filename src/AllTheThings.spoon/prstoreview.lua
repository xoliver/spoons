-- PRsToReview module for AllTheThingsspoon
local obj = {}
obj.__index = obj

function obj.new(cfg)
    local self = setmetatable({}, obj)
    self.sectionName = cfg.sectionName or "PRs to review"
    self.token = cfg.token
    self.username = cfg.username
    self.prs = {}
    self.timer = nil
    self.refreshInterval = cfg.refreshInterval or 300
    self.apiError = false
    self.apiErrorMessage = nil
    return self
end

function obj:refresh()
    if not self.token or not self.username then
        self.prs = {}
        self.apiError = false
        self.apiErrorMessage = nil
        return
    end
    hs.http.asyncGet(
        string.format(
            "https://api.github.com/search/issues?q=type:pr+review-requested:%s+state:open&sort=created&order=desc",
            self.username
        ),
        {
            ["Authorization"] = "token " .. self.token,
            ["User-Agent"] = "Hammerspoon-PRsToReview"
        },
        function(status, body, _)
            if status == 200 then
                local ok, result = pcall(hs.json.decode, body)
                if ok and result and result.items then
                    self.prs = result.items
                    self.apiError = false
                    self.apiErrorMessage = nil
                else
                    self.prs = {}
                    self.apiError = true
                    self.apiErrorMessage = (result and result.message) or "Failed to parse response"
                end
            else
                self.prs = {}
                self.apiError = true
                local ok, result = pcall(hs.json.decode, body)
                if ok and result and result.message then
                    self.apiErrorMessage = result.message
                else
                    self.apiErrorMessage = body or ("HTTP error: " .. tostring(status))
                end
            end
        end
    )
end

function obj:getStatusIcon()
    if self.apiError then return "❓" end
    if self.prs and #self.prs > 0 then return "👀" end
    return "🙈"
end

function obj:getMenuItems()
    if self.apiError then
        return {{ title = self.apiErrorMessage or "API error", disabled = true }}
    end
    local hasPRs = self.prs and #self.prs > 0
    if not hasPRs then
        return {
            {
                title = "No PRs to review",
                fn = function() hs.urlevent.openURL(string.format("https://github.com/curative/covid19lab/pulls/review-requested/%s", self.username)) end
            },
        }
    end
    local menu = {}
    for _, pr in ipairs(self.prs) do
        table.insert(menu, {
            title = string.format("[#%d] %s", pr.number, pr.title),
            fn = function() hs.urlevent.openURL(pr.html_url) end
        })
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
