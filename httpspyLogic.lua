--// HttpSpy Core | Cannedsoup (Inspired from IEnes HttpSpy for normal executors)
--//loaded remotely - do not run this directly

local _origGet     = game.HttpGet
local _origPost    = game.HttpPost
local _origLoadstr = loadstring
local HttpService  = game:GetService("HttpService")

--//logger
local function log(tag, msg)
    print(("[HttpSpy][%s] %s"):format(tag, tostring(msg):sub(1, 400)))
end

local UrlIntercepts = {
    ["http://127.0.0.1:6463/rpc"] = {
        Callback = function()
            warn("[HttpSpy] Blocked Discord RPC!")
            return ""
        end,
    },
}

local function findIntercept(url)
    for pattern, data in next, UrlIntercepts do
        if url:match(pattern) then return data end
    end
end

--//scan URLs
local function scanForUrls(src)
    local found = {}
    local seen  = {}
    for url in src:gmatch('["\']+(https?://[^"\'%s]+)["\']') do
        if not seen[url] then
            seen[url] = true
            found[#found+1] = url
        end
    end
    return found
end

--core HTTP handler
local function handleRequest(method, origFunc, url, body, headers, ...)
    --// Log request
    log(method, url)
    if body    then log("BODY",    tostring(body):sub(1, 300)) end
    if headers then
        local ok, enc = pcall(HttpService.JSONEncode, HttpService, headers)
        if ok then log("HEADERS", enc:sub(1, 300)) end
    end

    local intercept = findIntercept(url)
    local response

    if not intercept or intercept.PassResponse then
        local ok, res = pcall(origFunc, game, url, body or nil, ...)
        response = ok and res or nil
        if response then log("RES", tostring(response):sub(1, 200)) end
    end

    if not intercept then return response end

    local spoofed = intercept.Callback
    if type(spoofed) == "function" then
        spoofed = intercept.PassResponse and spoofed(response, url) or spoofed(url)
    end

    log("INTERCEPTED", url)
    return spoofed
end

--//spy wrappers
local function spyGet(self, url, ...)
    return handleRequest("GET", _origGet, url, nil, nil, ...)
end

local function spyPost(self, url, body, ...)
    return handleRequest("POST", _origPost, url, body, nil, ...)
end

--//globals
HttpGet  = spyGet
HttpPost = spyPost
_G.HttpGet  = spyGet
_G.HttpPost = spyPost

local spyMeta = {
    __index = function(t, k)
        if k == "HttpGet"  then return spyGet  end
        if k == "HttpPost" then return spyPost end
        return _G[k]
    end,
    __newindex = function(t, k, v) _G[k] = v end,
}

loadstring = function(src, chunkname)
    local fn, err = _origLoadstr(src, chunkname)
    if not fn then return nil, err end
    pcall(setfenv, fn, setmetatable({}, spyMeta))
    return fn, err
end

--//spy logic
game_HttpGet_spy = function(url, ...)
    log("FETCH", url)

    local ok, src = pcall(_origGet, game, url, ...)
    if not ok then
        log("ERR", tostring(src))
        return
    end
    log("BYTES", #src .. " bytes")

    local urls = scanForUrls(src)
    if #urls > 0 then
        log("SCAN", #urls .. " URL(s) found in source:")
        for _, u in ipairs(urls) do log("URL", u) end
    else
        log("SCAN", "No hardcoded URLs found")
    end

    local fn, err = _origLoadstr(src)
    if not fn then
        log("ERR", "Compile failed: " .. tostring(err))
        return
    end

    pcall(setfenv, fn, setmetatable({}, spyMeta))

    --// Run it
    log("RUN", "Executing: " .. url)
    local runOk, runErr = pcall(fn)
    if not runOk then
        log("ERR", "Script error: " .. tostring(runErr))
    else
        log("RUN", "Done: " .. url)
    end
end

log("LOADED", "HttpSpy active | game_HttpGet_spy(url) to spy on loadstrings")
