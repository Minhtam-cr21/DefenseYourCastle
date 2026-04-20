local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local VU = game:GetService("VirtualUser")

local LP = Players.LocalPlayer
local CoreGui = game:GetService("CoreGui")
local UI_NAME = "DYC_UI"
local CFG_PATH = "DYC_Config.json"

for _, parent in ipairs({CoreGui, LP:FindFirstChild("PlayerGui")}) do
    if parent and parent:FindFirstChild(UI_NAME) then
        parent[UI_NAME]:Destroy()
    end
end

local Events = RS:WaitForChild("Events")
local Functions = Events:WaitForChild("Functions")
local Remotes = Events:WaitForChild("Remotes")

local RF_UpdateShop = Functions:FindFirstChild("UpdateCurrentShop")
local RF_BuyDefense = Functions:FindFirstChild("BuyDefense")
local RF_StartChallenge = Functions:FindFirstChild("StartChallenge")
local RF_EndChallenge = Functions:FindFirstChild("EndChallenge")
local RE_ChallengeEnd = Remotes:FindFirstChild("ChallengeEnd")

local CAN_FILE = type(readfile) == "function" and type(writefile) == "function" and type(isfile) == "function"

local Config = {
    AntiAFK = false,
    AutoBuy = false,
    AutoChallenge = false,
    BuyDelay = 3,
    ChallengeDelay = 10,
    ChallengeDifficulty = "Easy",
    BuyAllItems = false,
    SelectedItems = {},
}

local State = {
    Bought = 0,
    Challenges = 0,
    LastStatus = "Ready",
    LastError = "None",
    LastSave = "Not saved yet",
    LastBuy = "None",
    LastChallenge = "Idle",
    ChallengeActive = false,
    ShopItems = {},
    Logs = {},
}

local function log(text)
    local line = "[DYC] " .. tostring(text)
    print(line)
    table.insert(State.Logs, 1, line)
    while #State.Logs > 14 do
        table.remove(State.Logs)
    end
end

local function saveConfig()
    if not CAN_FILE then
        State.LastSave = "Executor has no file API"
        return
    end
    local parts = {}
    for k, v in pairs(Config) do
        if type(v) == "boolean" then
            table.insert(parts, '"' .. k .. '":' .. (v and "true" or "false"))
        elseif type(v) == "number" then
            table.insert(parts, '"' .. k .. '":' .. tostring(v))
        elseif type(v) == "string" then
            table.insert(parts, '"' .. k .. '":"' .. v .. '"')
        elseif type(v) == "table" then
            local arr = {}
            for _, item in ipairs(v) do
                table.insert(arr, '"' .. tostring(item) .. '"')
            end
            table.insert(parts, '"' .. k .. '":[' .. table.concat(arr, ",") .. ']')
        end
    end
    local ok, err = pcall(function()
        writefile(CFG_PATH, "{" .. table.concat(parts, ",") .. "}")
    end)
    State.LastSave = ok and ("Saved " .. CFG_PATH) or ("Save failed: " .. tostring(err))
end

local function loadConfig()
    if not CAN_FILE or not isfile(CFG_PATH) then
        State.LastSave = CAN_FILE and "No config file yet" or "Executor has no file API"
        return
    end
    local ok, raw = pcall(readfile, CFG_PATH)
    if not ok or type(raw) ~= "string" then
        State.LastSave = "Load failed"
        return
    end
    for key, default in pairs(Config) do
        if type(default) == "boolean" then
            local v = raw:match('"' .. key .. '"%s*:%s*(true|false)')
            if v then Config[key] = v == "true" end
        elseif type(default) == "number" then
            local v = raw:match('"' .. key .. '"%s*:%s*([%d%.]+)')
            if v then Config[key] = tonumber(v) end
        elseif type(default) == "string" then
            local v = raw:match('"' .. key .. '"%s*:%s*"([^"]*)"')
            if v then Config[key] = v end
        elseif type(default) == "table" then
            local arr = raw:match('"' .. key .. '"%s*:%s*%[([^%]]*)%]')
            Config[key] = {}
            if arr then
                for item in arr:gmatch('"([^"]*)"') do
                    table.insert(Config[key], item)
                end
            end
        end
    end
    State.LastSave = "Loaded " .. CFG_PATH
end

loadConfig()

local function isSelected(name)
    if Config.BuyAllItems then
        return true
    end
    for _, item in ipairs(Config.SelectedItems) do
        if item == name then
            return true
        end
    end
    return false
end

local function toggleItem(name)
    for i, item in ipairs(Config.SelectedItems) do
        if item == name then
            table.remove(Config.SelectedItems, i)
            saveConfig()
            return
        end
    end
    table.insert(Config.SelectedItems, name)
    saveConfig()
end

local function sortedShop()
    local items = {}
    for name, qty in pairs(State.ShopItems) do
        table.insert(items, {name = tostring(name), qty = tonumber(qty) or 0})
    end
    table.sort(items, function(a, b) return a.name < b.name end)
    return items
end

local function fetchShop()
    if not RF_UpdateShop then
        State.LastError = "UpdateCurrentShop missing"
        return
    end
    local ok, result = pcall(function()
        return RF_UpdateShop:InvokeServer()
    end)
    if ok and type(result) == "table" then
        State.ShopItems = result
    else
        State.LastError = "Shop fetch failed: " .. tostring(result)
        log(State.LastError)
    end
end

local function autoBuyOnce()
    if not RF_BuyDefense then
        State.LastError = "BuyDefense missing"
        return
    end
    fetchShop()
    local boughtAny = false
    for _, entry in ipairs(sortedShop()) do
        if entry.qty > 0 and isSelected(entry.name) then
            local ok, result = pcall(function()
                return RF_BuyDefense:InvokeServer(entry.name, entry.qty)
            end)
            if ok then
                boughtAny = true
                State.Bought = State.Bought + entry.qty
                State.LastBuy = entry.name .. " x" .. entry.qty
                log("Bought " .. State.LastBuy)
            else
                State.LastError = "Buy failed for " .. entry.name .. ": " .. tostring(result)
                log(State.LastError)
            end
            task.wait(0.2)
        end
    end
    if not boughtAny then
        State.LastBuy = "No matching stock"
    end
end

local DIFF_ARGS = {
    Easy = {"Easy", "easy", 1, "1"},
    Medium = {"Medium", "medium", 2, "2"},
    Pro = {"Pro", "pro", 3, "3"},
}

local function autoChallengeOnce()
    if not RF_StartChallenge then
        State.LastError = "StartChallenge missing"
        return
    end
    if RF_EndChallenge then
        pcall(function() RF_EndChallenge:InvokeServer() end)
        task.wait(0.7)
    end
    local success = false
    local tries = DIFF_ARGS[Config.ChallengeDifficulty] or DIFF_ARGS.Easy
    for _, arg in ipairs(tries) do
        local ok, result = pcall(function()
            return RF_StartChallenge:InvokeServer(arg)
        end)
        log("StartChallenge(" .. tostring(arg) .. ") => " .. tostring(ok) .. " / " .. tostring(result))
        if ok and result ~= false then
            success = true
            break
        end
        task.wait(0.25)
    end
    if not success then
        local ok, result = pcall(function()
            return RF_StartChallenge:InvokeServer()
        end)
        log("StartChallenge() => " .. tostring(ok) .. " / " .. tostring(result))
        success = ok and result ~= false
    end
    State.ChallengeActive = success
    State.LastChallenge = success and ("Started " .. Config.ChallengeDifficulty) or "Start failed"
    if success then
        State.Challenges = State.Challenges + 1
    else
        State.LastError = "Challenge start failed"
    end
end

if RE_ChallengeEnd then
    RE_ChallengeEnd.OnClientEvent:Connect(function(...)
        State.ChallengeActive = false
        State.LastChallenge = "Challenge ended"
        log("ChallengeEnd => " .. tostring(select(1, ...)))
    end)
end

task.spawn(function()
    while true do
        task.wait(50)
        if Config.AntiAFK then
            local char = LP.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then hum.Jump = true end
            end
            pcall(function()
                VU:Button1Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
                task.wait(0.1)
                VU:Button1Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
            end)
            State.LastStatus = "Anti-AFK pulse"
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(Config.BuyDelay)
        if Config.AutoBuy then autoBuyOnce() end
    end
end)

task.spawn(function()
    while true do
        task.wait(Config.ChallengeDelay)
        if Config.AutoChallenge then autoChallengeOnce() end
    end
end)

local C = {
    bg = Color3.fromRGB(16, 18, 26),
    panel = Color3.fromRGB(25, 28, 40),
    head = Color3.fromRGB(35, 39, 56),
    soft = Color3.fromRGB(45, 50, 70),
    accent = Color3.fromRGB(78, 132, 255),
    green = Color3.fromRGB(64, 189, 115),
    red = Color3.fromRGB(214, 78, 78),
    gold = Color3.fromRGB(225, 180, 62),
    text = Color3.fromRGB(235, 239, 248),
    sub = Color3.fromRGB(145, 150, 170),
    stroke = Color3.fromRGB(50, 55, 76),
    active = Color3.fromRGB(42, 83, 55),
}

local function corner(i, r) local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, r or 8) c.Parent = i end
local function border(i) local s = Instance.new("UIStroke") s.Color = C.stroke s.Parent = i end
local function frame(p, size, pos, col) local f = Instance.new("Frame") f.Size = size f.Position = pos or UDim2.new() f.BackgroundColor3 = col or C.panel f.BorderSizePixel = 0 f.Parent = p return f end
local function label(p, txt, size, pos, col, ts, font)
    local l = Instance.new("TextLabel") l.Size = size l.Position = pos or UDim2.new() l.BackgroundTransparency = 1 l.Text = txt l.TextColor3 = col or C.text l.TextSize = ts or 12 l.Font = font or Enum.Font.GothamMedium l.TextWrapped = true l.TextXAlignment = Enum.TextXAlignment.Left l.Parent = p return l
end
local function button(p, txt, size, pos, col, fn)
    local b = Instance.new("TextButton") b.Size = size b.Position = pos or UDim2.new() b.BackgroundColor3 = col or C.accent b.BorderSizePixel = 0 b.Text = txt b.TextColor3 = C.text b.TextSize = 12 b.Font = Enum.Font.GothamBold b.Parent = p corner(b, 7) if fn then b.MouseButton1Click:Connect(fn) end return b
end

local SG = Instance.new("ScreenGui")
SG.Name = UI_NAME
SG.ResetOnSpawn = false
SG.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
SG.DisplayOrder = 100
local ok = pcall(function() SG.Parent = CoreGui end)
if not ok or not SG.Parent then SG.Parent = LP:WaitForChild("PlayerGui") end

local Win = frame(SG, UDim2.new(0, 360, 0, 0), UDim2.new(0.04, 0, 0.08, 0), C.bg)
Win.AutomaticSize = Enum.AutomaticSize.Y
corner(Win, 12)
border(Win)

local Head = frame(Win, UDim2.new(1, 0, 0, 50), nil, C.head)
corner(Head, 12)
frame(Head, UDim2.new(1, 0, 0, 12), UDim2.new(0, 0, 1, -12), C.head)
label(Head, "Defend Your Castle", UDim2.new(1, -100, 0, 22), UDim2.new(0, 14, 0, 6), C.text, 14, Enum.Font.GothamBold)
label(Head, "v3.0 | RightShift toggle", UDim2.new(1, -100, 0, 14), UDim2.new(0, 14, 0, 30), C.sub, 10, Enum.Font.Gotham)
button(Head, "X", UDim2.new(0, 26, 0, 26), UDim2.new(1, -34, 0.5, -13), C.red, function() Win.Visible = false end)

local Body = frame(Win, UDim2.new(1, -20, 0, 0), UDim2.new(0, 10, 0, 58), Color3.new())
Body.BackgroundTransparency = 1
Body.AutomaticSize = Enum.AutomaticSize.Y
local BL = Instance.new("UIListLayout") BL.Padding = UDim.new(0, 6) BL.Parent = Body

local TabBar = frame(Body, UDim2.new(1, 0, 0, 30), nil, C.panel)
corner(TabBar, 8)
local TL = Instance.new("UIListLayout") TL.FillDirection = Enum.FillDirection.Horizontal TL.Padding = UDim.new(0, 4) TL.Parent = TabBar

local pages, tabs = {}, {}
local function activate(name)
    for n, p in pairs(pages) do p.Visible = n == name end
    for n, b in pairs(tabs) do b.BackgroundColor3 = (n == name) and C.accent or C.soft b.TextColor3 = (n == name) and C.text or C.sub end
end

local function makePage(name)
    local tb = Instance.new("TextButton")
    tb.Size = UDim2.new(0, 84, 1, -6)
    tb.BackgroundColor3 = C.soft
    tb.TextColor3 = C.sub
    tb.BorderSizePixel = 0
    tb.Text = name
    tb.TextSize = 12
    tb.Font = Enum.Font.GothamMedium
    tb.Parent = TabBar
    corner(tb, 6)
    local p = frame(Body, UDim2.new(1, 0, 0, 0), nil, Color3.new())
    p.BackgroundTransparency = 1
    p.AutomaticSize = Enum.AutomaticSize.Y
    local pl = Instance.new("UIListLayout") pl.Padding = UDim.new(0, 6) pl.Parent = p
    pages[name] = p
    tabs[name] = tb
    tb.MouseButton1Click:Connect(function() activate(name) end)
    return p
end

local Main = makePage("Main")
local Buy = makePage("Buy")
local Chall = makePage("Challenge")
local Debug = makePage("Debug")
activate("Main")

local function section(p, t) label(p, string.upper(t), UDim2.new(1, 0, 0, 16), nil, C.sub, 10, Enum.Font.GothamBold) end
local StatusLabel

local function toggleRow(p, title, desc, key)
    local r = frame(p, UDim2.new(1, 0, 0, 66), nil, C.panel) corner(r, 9) border(r)
    label(r, title, UDim2.new(1, -74, 0, 22), UDim2.new(0, 12, 0, 10), C.text, 13, Enum.Font.GothamBold)
    label(r, desc, UDim2.new(1, -74, 0, 18), UDim2.new(0, 12, 0, 34), C.sub, 11, Enum.Font.Gotham)
    local pill = Instance.new("TextButton") pill.Size = UDim2.new(0, 44, 0, 22) pill.Position = UDim2.new(1, -56, 0.5, -11) pill.BorderSizePixel = 0 pill.Text = "" pill.BackgroundColor3 = Config[key] and C.green or C.soft pill.Parent = r corner(pill, 11)
    local knob = frame(pill, UDim2.new(0, 16, 0, 16), Config[key] and UDim2.new(0, 25, 0.5, -8) or UDim2.new(0, 3, 0.5, -8), Color3.fromRGB(236, 238, 245)) corner(knob, 8)
    pill.MouseButton1Click:Connect(function()
        Config[key] = not Config[key]
        pill.BackgroundColor3 = Config[key] and C.green or C.soft
        knob.Position = Config[key] and UDim2.new(0, 25, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
        State.LastStatus = title .. (Config[key] and " ON" or " OFF")
        saveConfig()
    end)
end

section(Main, "Core")
toggleRow(Main, "Anti-AFK", "Basic anti idle pulse.", "AntiAFK")
toggleRow(Main, "Auto Buy", "Buys by live shop stock.", "AutoBuy")
toggleRow(Main, "Auto Challenge", "Tests multiple challenge args.", "AutoChallenge")

section(Main, "Stats")
local StatBox = frame(Main, UDim2.new(1, 0, 0, 84), nil, C.panel) corner(StatBox, 9) border(StatBox)
local BoughtLabel = label(StatBox, "Bought: 0", UDim2.new(1, -12, 0, 18), UDim2.new(0, 12, 0, 8), C.green, 12)
local LastBuyLabel = label(StatBox, "Last buy: None", UDim2.new(1, -12, 0, 18), UDim2.new(0, 12, 0, 28), C.sub, 11)
local ChallengeLabel = label(StatBox, "Challenges: 0", UDim2.new(1, -12, 0, 18), UDim2.new(0, 12, 0, 48), C.gold, 12)
local LastChallengeLabel = label(StatBox, "Last challenge: Idle", UDim2.new(1, -12, 0, 18), UDim2.new(0, 160, 0, 48), C.sub, 11)

section(Main, "Status")
local StatusBox = frame(Main, UDim2.new(1, 0, 0, 28), nil, C.panel) corner(StatusBox, 8)
StatusLabel = label(StatusBox, "Status: Ready", UDim2.new(1, -12, 1, 0), UDim2.new(0, 10, 0, 0), C.sub, 11, Enum.Font.GothamMedium)

section(Buy, "Mode")
local ModeBox = frame(Buy, UDim2.new(1, 0, 0, 72), nil, C.panel) corner(ModeBox, 9) border(ModeBox)
label(ModeBox, "Buy all stock", UDim2.new(1, -74, 0, 22), UDim2.new(0, 12, 0, 8), C.text, 13, Enum.Font.GothamBold)
label(ModeBox, "OFF = selected items only. ON = all live shop items.", UDim2.new(1, -74, 0, 26), UDim2.new(0, 12, 0, 30), C.sub, 11, Enum.Font.Gotham)
local BuyAll = Instance.new("TextButton") BuyAll.Size = UDim2.new(0, 44, 0, 22) BuyAll.Position = UDim2.new(1, -56, 0.5, -11) BuyAll.BorderSizePixel = 0 BuyAll.Text = "" BuyAll.BackgroundColor3 = Config.BuyAllItems and C.green or C.soft BuyAll.Parent = ModeBox corner(BuyAll, 11)
local BuyAllKnob = frame(BuyAll, UDim2.new(0, 16, 0, 16), Config.BuyAllItems and UDim2.new(0, 25, 0.5, -8) or UDim2.new(0, 3, 0.5, -8), Color3.fromRGB(236, 238, 245)) corner(BuyAllKnob, 8)
BuyAll.MouseButton1Click:Connect(function()
    Config.BuyAllItems = not Config.BuyAllItems
    BuyAll.BackgroundColor3 = Config.BuyAllItems and C.green or C.soft
    BuyAllKnob.Position = Config.BuyAllItems and UDim2.new(0, 25, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
    State.LastStatus = Config.BuyAllItems and "Buy all ON" or "Buy selected only"
    saveConfig()
end)

section(Buy, "Shop")
local BuyBtns = frame(Buy, UDim2.new(1, 0, 0, 30), nil, Color3.new()) BuyBtns.BackgroundTransparency = 1
local BuyBtnsL = Instance.new("UIListLayout") BuyBtnsL.FillDirection = Enum.FillDirection.Horizontal BuyBtnsL.Padding = UDim.new(0, 6) BuyBtnsL.Parent = BuyBtns
local ShopInfo = label(Buy, "Load shop to build item list.", UDim2.new(1, 0, 0, 18), nil, C.sub, 11)
local Grid = frame(Buy, UDim2.new(1, 0, 0, 0), nil, Color3.new()) Grid.BackgroundTransparency = 1 Grid.AutomaticSize = Enum.AutomaticSize.Y
local GL = Instance.new("UIGridLayout") GL.CellSize = UDim2.new(0.5, -4, 0, 32) GL.CellPadding = UDim2.new(0, 4, 0, 4) GL.Parent = Grid

local function rebuildShop()
    for _, child in ipairs(Grid:GetChildren()) do
        if child:IsA("TextButton") or child:IsA("Frame") then child:Destroy() end
    end
    local items = sortedShop()
    ShopInfo.Text = (#items == 0) and "No shop data yet." or ("Live items: " .. #items)
    for _, entry in ipairs(items) do
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, 0, 0, 32)
        b.BorderSizePixel = 0
        b.Text = entry.name .. " [" .. entry.qty .. "]"
        b.TextSize = 11
        b.Font = Enum.Font.GothamMedium
        b.BackgroundColor3 = isSelected(entry.name) and C.active or C.soft
        b.TextColor3 = isSelected(entry.name) and C.green or C.sub
        b.Parent = Grid
        corner(b, 6)
        border(b)
        b.MouseButton1Click:Connect(function()
            toggleItem(entry.name)
            rebuildShop()
            State.LastStatus = "Toggled " .. entry.name
        end)
    end
end

button(BuyBtns, "Refresh Shop", UDim2.new(0.5, -3, 1, 0), nil, C.accent, function() fetchShop() rebuildShop() State.LastStatus = "Shop refreshed" end)
button(BuyBtns, "Buy Once", UDim2.new(0.5, -3, 1, 0), UDim2.new(0.5, 3, 0, 0), C.green, function() autoBuyOnce() fetchShop() rebuildShop() State.LastStatus = "Manual buy done" end)

section(Chall, "Difficulty")
local DiffRow = frame(Chall, UDim2.new(1, 0, 0, 30), nil, Color3.new()) DiffRow.BackgroundTransparency = 1
local DL = Instance.new("UIListLayout") DL.FillDirection = Enum.FillDirection.Horizontal DL.Padding = UDim.new(0, 6) DL.Parent = DiffRow
local DiffButtons = {}
local DiffColors = {Easy = C.green, Medium = C.gold, Pro = C.red}
local function refreshDiff()
    for name, btn in pairs(DiffButtons) do
        btn.BackgroundColor3 = Config.ChallengeDifficulty == name and DiffColors[name] or C.soft
        btn.TextColor3 = Config.ChallengeDifficulty == name and C.text or C.sub
    end
end
for _, diff in ipairs({"Easy", "Medium", "Pro"}) do
    DiffButtons[diff] = button(DiffRow, diff, UDim2.new(0, 94, 1, 0), nil, C.soft, function()
        Config.ChallengeDifficulty = diff
        saveConfig()
        refreshDiff()
        State.LastStatus = "Difficulty " .. diff
    end)
end
refreshDiff()

section(Chall, "Manual")
local CBtns = frame(Chall, UDim2.new(1, 0, 0, 30), nil, Color3.new()) CBtns.BackgroundTransparency = 1
local CBL = Instance.new("UIListLayout") CBL.FillDirection = Enum.FillDirection.Horizontal CBL.Padding = UDim.new(0, 6) CBL.Parent = CBtns
button(CBtns, "Start Now", UDim2.new(0.5, -3, 1, 0), nil, C.green, function() autoChallengeOnce() end)
button(CBtns, "End Now", UDim2.new(0.5, -3, 1, 0), UDim2.new(0.5, 3, 0, 0), C.red, function() if RF_EndChallenge then pcall(function() RF_EndChallenge:InvokeServer() end) end State.ChallengeActive = false State.LastChallenge = "Ended manually" end)
local ChallState = frame(Chall, UDim2.new(1, 0, 0, 28), nil, C.panel) corner(ChallState, 8)
local ChallStateLabel = label(ChallState, "Challenge idle", UDim2.new(1, -12, 1, 0), UDim2.new(0, 10, 0, 0), C.sub, 11, Enum.Font.GothamMedium)

section(Debug, "Runtime")
local DBox = frame(Debug, UDim2.new(1, 0, 0, 126), nil, C.panel) corner(DBox, 9) border(DBox)
local FileLabel = label(DBox, "", UDim2.new(1, -12, 0, 18), UDim2.new(0, 12, 0, 8), C.sub, 11)
local SaveLabel = label(DBox, "", UDim2.new(1, -12, 0, 18), UDim2.new(0, 12, 0, 30), C.sub, 11)
local ErrorLabel = label(DBox, "", UDim2.new(1, -12, 0, 36), UDim2.new(0, 12, 0, 52), C.sub, 11)
local RemoteLabel = label(DBox, "", UDim2.new(1, -12, 0, 36), UDim2.new(0, 12, 0, 86), C.sub, 11)

section(Debug, "Actions")
local DBA = frame(Debug, UDim2.new(1, 0, 0, 30), nil, Color3.new()) DBA.BackgroundTransparency = 1
local DBL = Instance.new("UIListLayout") DBL.FillDirection = Enum.FillDirection.Horizontal DBL.Padding = UDim.new(0, 6) DBL.Parent = DBA
button(DBA, "Save Config", UDim2.new(0.5, -3, 1, 0), nil, C.accent, saveConfig)
button(DBA, "Print Remotes", UDim2.new(0.5, -3, 1, 0), UDim2.new(0.5, 3, 0, 0), C.gold, function()
    log("=== Functions ===")
    for _, c in ipairs(Functions:GetChildren()) do log(c.ClassName .. " | " .. c.Name) end
    log("=== Remotes ===")
    for _, c in ipairs(Remotes:GetChildren()) do log(c.ClassName .. " | " .. c.Name) end
end)

section(Debug, "Recent Logs")
local LogBox = frame(Debug, UDim2.new(1, 0, 0, 170), nil, C.panel) corner(LogBox, 9) border(LogBox)
local LogLabel = label(LogBox, "No logs yet", UDim2.new(1, -12, 1, -12), UDim2.new(0, 10, 0, 6), C.sub, 11, Enum.Font.Code)
LogLabel.TextYAlignment = Enum.TextYAlignment.Top

task.spawn(function() fetchShop() rebuildShop() end)

task.spawn(function()
    while true do
        task.wait(0.5)
        BoughtLabel.Text = "Bought: " .. State.Bought
        LastBuyLabel.Text = "Last buy: " .. State.LastBuy
        ChallengeLabel.Text = "Challenges: " .. State.Challenges
        LastChallengeLabel.Text = "Last challenge: " .. State.LastChallenge
        StatusLabel.Text = "Status: " .. State.LastStatus
        ChallStateLabel.Text = State.ChallengeActive and "Challenge active" or "Challenge idle"
        ChallStateLabel.TextColor3 = State.ChallengeActive and C.green or C.sub
        FileLabel.Text = "File API: " .. tostring(CAN_FILE)
        SaveLabel.Text = "Config: " .. State.LastSave
        ErrorLabel.Text = "Last error: " .. State.LastError
        RemoteLabel.Text = "UpdateShop=" .. tostring(RF_UpdateShop ~= nil) .. " | BuyDefense=" .. tostring(RF_BuyDefense ~= nil) .. " | StartChallenge=" .. tostring(RF_StartChallenge ~= nil) .. " | EndChallenge=" .. tostring(RF_EndChallenge ~= nil)
        LogLabel.Text = table.concat(State.Logs, "\n")
    end
end)

local dragging, dragStart, startPos = false, nil, nil
Head.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = i.Position
        startPos = Win.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - dragStart
        Win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
end)
UIS.InputBegan:Connect(function(i, gp)
    if not gp and i.KeyCode == Enum.KeyCode.RightShift then Win.Visible = not Win.Visible end
end)

log("UI ready")
log("Shop list is dynamic in v3.0")
