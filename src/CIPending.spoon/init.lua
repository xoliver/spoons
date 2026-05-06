--- === CIPending ===
---
--- A Hammerspoon Spoon that lists every non-finished Buildkite build on the
--- configured branches (running, scheduled, blocked, canceling, failing) and
--- surfaces their status in the macOS menu bar.
---
--- Unlike CIStatus, which uses the CCMenu XML feed and only reports the *last*
--- build per branch, CIPending talks to the Buildkite REST API and can report
--- multiple in-flight builds — including builds paused on a manual/block step
--- (state = "blocked").
---
--- Token note: `bkToken` must be a Buildkite *API* personal access token with
--- the `read_builds` scope. This is NOT the same as the CCMenu access token
--- used by CIStatus.

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "CIPending"
obj.version = "1.0"
obj.author = "xoliver"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- Configuration (set these before calling :start())
obj.bkOrganization = nil
obj.bkPipeline = nil
obj.bkToken = nil
obj.branches = { "master" }
obj.states = { "running", "scheduled", "blocked", "canceling", "failing" }
-- States to also fetch across *all* branches (deduped against per-branch results).
-- Defaults to surfacing any blocked build anywhere — those need human input.
-- Set to {} to disable.
obj.extraStatesAllBranches = { "blocked" }
obj.refreshSeconds = 60
obj.logoPath = nil

-- Internal state
obj.menubar = nil
obj.timer = nil

-- Per-build state -> emoji
obj.stateToEmoji = {
    running   = "🏗️",
    scheduled = "⏳",
    blocked   = "⏸️",
    canceling = "🛑",
    failing   = "💥"
}

-- Aggregate menubar emoji priority (lower = higher priority)
obj.aggregatePriority = {
    ["❓"]  = 1, -- API error or missing config
    ["⏸️"]  = 2, -- something is waiting on input
    ["💥"]  = 3,
    ["🛑"]  = 4,
    ["🏗️"]  = 5,
    ["⏳"]  = 6,
    ["✅"]  = 7  -- nothing in flight
}

--- CIPending:init()
--- Method
--- Initializes the spoon. Creates the menubar with a placeholder title.
function obj:init()
    self.menubar = hs.menubar.new()
    if self.logoPath then
        self:_setMenubarIcon(self.logoPath)
    end
    self.menubar:setTitle("⏳")
end

--- CIPending:start()
--- Method
--- Starts polling Buildkite for non-finished builds.
function obj:start()
    print("[CIPending] starting; refresh every " .. tostring(self.refreshSeconds) .. "s")
    self:_updateMenu()
    self.timer = hs.timer.doEvery(self.refreshSeconds, function() self:_updateMenu() end)
end

--- CIPending:stop()
--- Method
--- Stops polling and removes the menubar item.
function obj:stop()
    if self.timer then
        self.timer:stop()
        self.timer = nil
    end
    if self.menubar then
        self.menubar:delete()
        self.menubar = nil
    end
end

-- Helper: apply an icon to the menubar item
function obj:_setMenubarIcon(logoPath)
    local image = hs.image.imageFromPath(logoPath)
    if image then
        self.menubar:setIcon(image:setSize({ w = 16, h = 16 }))
    end
end

-- Helper: build the Buildkite REST API URL. `branch` is optional (omit to query
-- across all branches). `states` is the list of state filters to include.
function obj:_buildUrl(branch, states)
    local base = string.format(
        "https://api.buildkite.com/v2/organizations/%s/pipelines/%s/builds?per_page=100",
        hs.http.encodeForQuery(self.bkOrganization),
        hs.http.encodeForQuery(self.bkPipeline)
    )
    if branch then
        base = base .. "&branch=" .. hs.http.encodeForQuery(branch)
    end
    for _, state in ipairs(states or {}) do
        base = base .. "&state[]=" .. hs.http.encodeForQuery(state)
    end
    return base
end

-- Helper: fan out one async GET per branch (and one across all branches for
-- `extraStatesAllBranches`), dedupe by build id, then update the menubar.
function obj:_updateMenu()
    if not self.bkOrganization or not self.bkPipeline or not self.bkToken then
        print("[CIPending] missing config (org/pipeline/token)")
        self:_renderError("Missing Buildkite config")
        return
    end

    local buildsById = {}
    local apiError = nil
    local startedAt = hs.timer.secondsSinceEpoch()

    local extraStates = self.extraStatesAllBranches or {}
    local hasGlobal = #extraStates > 0
    local pendingCalls = #self.branches + (hasGlobal and 1 or 0)

    local headers = { Authorization = "Bearer " .. self.bkToken }

    local function onDone(label, status, body)
        local elapsed = hs.timer.secondsSinceEpoch() - startedAt
        if status == 200 then
            local ok, decoded = pcall(hs.json.decode, body)
            if ok and type(decoded) == "table" then
                local added = 0
                for _, build in ipairs(decoded) do
                    local id = build.id or tostring(build.number)
                    if not buildsById[id] then
                        buildsById[id] = build
                        added = added + 1
                    end
                end
                print(string.format("[CIPending] %s: %d build(s) (+%d new) in %.2fs",
                    label, #decoded, added, elapsed))
            else
                apiError = apiError or ("Could not parse response for " .. label)
                print(string.format("[CIPending] %s: parse error after %.2fs", label, elapsed))
            end
        else
            apiError = apiError or string.format("HTTP %s for %s", tostring(status), label)
            print(string.format("[CIPending] %s: HTTP %s after %.2fs; body=%s",
                label, tostring(status), elapsed, tostring(body):sub(1, 200)))
        end

        pendingCalls = pendingCalls - 1
        if pendingCalls == 0 then
            if apiError then
                self:_renderError(apiError)
            else
                self:_renderResults(buildsById)
            end
        end
    end

    for _, branch in ipairs(self.branches) do
        local url = self:_buildUrl(branch, self.states)
        print("[CIPending] GET " .. url)
        hs.http.asyncGet(url, headers, function(status, body)
            onDone(branch, status, body)
        end)
    end

    if hasGlobal then
        local url = self:_buildUrl(nil, extraStates)
        print("[CIPending] GET " .. url)
        hs.http.asyncGet(url, headers, function(status, body)
            onDone("(any branch)", status, body)
        end)
    end
end

-- Helper: render an error state in the menubar
function obj:_renderError(message)
    self.menubar:setTitle("❓")
    self.menubar:setMenu({
        { title = message, disabled = true }
    })
end

-- Helper: render successful results in the menubar
function obj:_renderResults(buildsById)
    local now = os.time()
    local seenStates = {}
    local byBranch = {}
    local totalBuilds = 0

    for _, build in pairs(buildsById) do
        local branch = build.branch or "(unknown)"
        byBranch[branch] = byBranch[branch] or {}
        table.insert(byBranch[branch], build)
        totalBuilds = totalBuilds + 1
    end

    if totalBuilds == 0 then
        self.menubar:setTitle("✅")
        self.menubar:setMenu({{ title = "No non-finished builds", disabled = true }})
        return
    end

    -- Display configured branches first (in declared order), then any other
    -- branches surfaced via extraStatesAllBranches (alphabetical).
    local seen, order = {}, {}
    for _, branch in ipairs(self.branches) do
        if not seen[branch] then
            table.insert(order, branch)
            seen[branch] = true
        end
    end
    local extras = {}
    for branch, _ in pairs(byBranch) do
        if not seen[branch] then table.insert(extras, branch) end
    end
    table.sort(extras)
    for _, b in ipairs(extras) do table.insert(order, b) end

    local menu = {}
    for _, branch in ipairs(order) do
        local builds = byBranch[branch] or {}
        if #builds > 0 then
            table.sort(builds, function(a, b)
                return (a.number or 0) > (b.number or 0)
            end)
            table.insert(menu, { title = branch, disabled = true })
            for _, build in ipairs(builds) do
                local state = build.state or "unknown"
                if build.blocked == true then state = "blocked" end
                seenStates[state] = true
                local emoji = self.stateToEmoji[state]
                if not emoji then
                    print(string.format("[CIPending] unknown state %q on build #%s (%s)",
                        tostring(state), tostring(build.number), branch))
                    emoji = "❓"
                end

                local timestamp = build.started_at or build.created_at
                local age = "?"
                if timestamp then
                    local t = self:_parseISO8601(timestamp)
                    if t then age = self:_formatTimeDiff(os.difftime(now, t)) end
                end

                local message = build.message or ""
                local firstLine = message:match("([^\r\n]*)") or ""
                if #firstLine > 60 then firstLine = firstLine:sub(1, 57) .. "..." end

                local title = string.format("%s #%s — %s (%s)",
                    emoji, tostring(build.number or "?"), firstLine, age)

                local webUrl = build.web_url
                table.insert(menu, {
                    title = title,
                    fn = function()
                        if webUrl then hs.urlevent.openURL(webUrl) end
                    end
                })
            end
            table.insert(menu, { title = "-", disabled = true })
        end
    end

    if #menu > 0 and menu[#menu].title == "-" then
        table.remove(menu, #menu)
    end

    self.menubar:setTitle(self:_aggregateEmoji(seenStates, totalBuilds))
    self.menubar:setMenu(menu)
end

-- Helper: pick the highest-priority emoji from the set of seen states
function obj:_aggregateEmoji(seenStates, totalBuilds)
    if totalBuilds == 0 then return "✅" end
    local best = "✅"
    local bestScore = self.aggregatePriority[best]
    for state, _ in pairs(seenStates) do
        local emoji = self.stateToEmoji[state] or "❓"
        local score = self.aggregatePriority[emoji] or 99
        if score < bestScore then
            best = emoji
            bestScore = score
        end
    end
    return best
end

-- Helper: parse an ISO 8601 timestamp into a unix epoch
function obj:_parseISO8601(timestamp)
    local pattern = "(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)"
    local year, month, day, hour, min, sec = timestamp:match(pattern)
    if not year then return nil end
    return os.time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(min),
        sec = tonumber(sec)
    })
end

-- Helper: format a duration in seconds as a short human string
function obj:_formatTimeDiff(diff)
    if not diff then return "N/A" end
    if diff < 60 then
        return string.format("%ds", diff)
    elseif diff < 3600 then
        return string.format("%dm", math.floor(diff / 60))
    elseif diff < 86400 then
        return string.format("%dh", math.floor(diff / 3600))
    else
        return string.format("%dd", math.floor(diff / 86400))
    end
end

return obj
