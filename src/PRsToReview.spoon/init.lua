local obj = {}
obj.__index = obj

obj.name = "PRsToReview"
obj.token = nil
obj.username = nil
obj.menubar = nil
obj.prs = {}
obj.timer = nil
obj.refreshInterval = 300 -- seconds
obj.apiError = false
obj.apiErrorMessage = nil

function obj:init()
    if self.menubar then return end -- Prevent multiple menubars
    self.menubar = hs.menubar.new()
    self:updateMenu()
    if not self.timer then
        self.timer = hs.timer.doEvery(self.refreshInterval, function() self:refresh() end)
    end
end

function obj:refresh()
    if not self.token or not self.username then
        self.prs = {}
        self.apiError = false
        self.apiErrorMessage = nil
        self:updateMenu()
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
    local hasPRs = self.prs and #self.prs > 0
    self.menubar:setTitle(hasPRs and "👀" or "🙈")
    if not hasPRs then
        self.menubar:setMenu({{ title = "No PRs to review", disabled = true }})
        return
    end
    local menu = {}
    for _, pr in ipairs(self.prs) do
        table.insert(menu, {
            title = string.format("[#%d] %s", pr.number, pr.title),
            fn = function() hs.urlevent.openURL(pr.html_url) end
        })
    end
    self.menubar:setMenu(menu)
end

function obj:configure(cfg)
    self.token = cfg.token
    self.username = cfg.username
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
