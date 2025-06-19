-- Utility functions for AllTheThingsspoon
local utils = {}

function utils.parseISO8601(timestamp)
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

function utils.formatTimeDiff(diff)
    if not diff then return "N/A" end
    if diff < 60 then
        return string.format("%ds", diff)
    elseif diff < 3600 then
        return string.format("%dm", math.floor(diff/60))
    elseif diff < 86400 then
        return string.format("%dh", math.floor(diff/3600))
    else
        return string.format("%dd", math.floor(diff/86400))
    end
end

return utils

