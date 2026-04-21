--[[
    DEFEND YOUR CASTLE - v4.0
    GitHub: Minhtam-cr21/DefenseYourCastle

    CONFIRMED REMOTES (from scan):
    Functions:
        UpdateCurrentShop() -> {itemName=qty}
        BuyDefense(name, qty) -> mua item
        StartChallenge() -> true=ok, false=in raid or cooldown
        EndChallenge() -> kết thúc challenge
        RaidStart() -> true/nil
    RemoteEvents:
        RaidEnd, RaidStop -> fire để end raid
        ChallengeEnd -> server fires khi challenge xong

    CHALLENGE LOGIC:
        - StartChallenge trả false nếu:
            1) Đang trong Raid -> cần fire RaidEnd/RaidStop trước
            2) Còn cooldown -> cần đợi EndTime
        - Detect: GUI Framework.Raid.Top.Buttons.Stop.Button = "End" -> đang raid
        - Detect cooldown: GUI Challenges frame có cooldown label
        - Challenge names: Novice, Advanced, Pro, Insane, Godly
--]]

-- ============================================================
-- SERVICES
-- ============================================================
local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local UIS               = game:GetService("UserInputService")
local RS                = game:GetService("ReplicatedStorage")
local VU                = game:GetService("VirtualUser")

local LP       = Players.LocalPlayer
local CoreGui  = game:GetService("CoreGui")
local UI_NAME  = "DYC_UI"
local CFG_PATH = "DYC_Config.json"

-- ============================================================
-- CLEANUP
-- ============================================================
for _, parent in ipairs({CoreGui, LP:FindFirstChild("PlayerGui")}) do
    if parent and parent:FindFirstChild(UI_NAME) then
        parent[UI_NAME]:Destroy()
    end
end

-- ============================================================
-- REMOTES
-- ============================================================
local Events    = RS:WaitForChild("Events")
local Functions = Events:WaitForChild("Functions")
local Remotes   = Events:WaitForChild("Remotes")

local RF_UpdateShop     = Functions:FindFirstChild("UpdateCurrentShop")
local RF_BuyDefense     = Functions:FindFirstChild("BuyDefense")
local RF_StartChallenge = Functions:FindFirstChild("StartChallenge")
local RF_EndChallenge   = Functions:FindFirstChild("EndChallenge")
local RF_RaidStart      = Functions:FindFirstChild("RaidStart")
local RE_RaidEnd        = Remotes:FindFirstChild("RaidEnd")
local RE_RaidStop       = Remotes:FindFirstChild("RaidStop")
local RE_ChallengeEnd   = Remotes:FindFirstChild("ChallengeEnd")

-- ============================================================
-- FILE API CHECK
-- ============================================================
local CAN_FILE = type(readfile)=="function" and type(writefile)=="function" and type(isfile)=="function"

-- ============================================================
-- CONFIG
-- ============================================================
local Config = {
    AntiAFK          = false,
    AutoBuy          = false,
    AutoChallenge    = false,
    BuyDelay         = 3,
    -- Challenge queue: bật/tắt từng difficulty
    ChallEasy        = false,
    ChallAdvanced    = false,
    ChallPro         = false,
    ChallInsane      = false,
    ChallGodly       = false,
    BuyAllItems      = true,
    SelectedItems    = {},
}

-- Challenge name map (GUI name -> server nhận gì)
-- Từ scan: StartChallenge() không args bị lỗi EndTime
-- -> game cần biết difficulty qua internal state
-- -> Ta dùng GetChallengeLeaderboard để detect, hoặc thử tên GUI
local CHALL_DEFS = {
    { key="ChallEasy",     label="Novice",   waves=25, color=Color3.fromRGB(64,189,115) },
    { key="ChallAdvanced", label="Advanced", waves=25, color=Color3.fromRGB(225,180,62) },
    { key="ChallPro",      label="Pro",      waves=25, color=Color3.fromRGB(214,140,60) },
    { key="ChallInsane",   label="Insane",   waves=20, color=Color3.fromRGB(190,70,220) },
    { key="ChallGodly",    label="Godly",    waves=25, color=Color3.fromRGB(220,60,60)  },
}

-- ============================================================
-- STATE
-- ============================================================
local State = {
    Bought          = 0,
    Challenges      = 0,
    LastBuy         = "None",
    LastStatus      = "Ready",
    LastError       = "None",
    LastSave        = "Not saved",
    ChallengeActive = false,
    ChallQueue      = {},    -- queue các difficulty cần chạy
    ChallRunning    = false, -- đang chạy queue
    ChallCurrent    = "",    -- difficulty đang chạy
    ShopItems       = {},
    Logs            = {},
}

-- ============================================================
-- LOGGING
-- ============================================================
local function log(text)
    local line = "[DYC] " .. tostring(text)
    print(line)
    table.insert(State.Logs, 1, line)
    while #State.Logs > 20 do table.remove(State.Logs) end
end

-- ============================================================
-- CONFIG SAVE/LOAD
-- ============================================================
local function saveConfig()
    if not CAN_FILE then State.LastSave="No file API" return end
    local parts = {}
    for k, v in pairs(Config) do
        if type(v)=="boolean" then
            table.insert(parts, '"'..k..'":'.. (v and "true" or "false"))
        elseif type(v)=="number" then
            table.insert(parts, '"'..k..'":'..tostring(v))
        elseif type(v)=="string" then
            table.insert(parts, '"'..k..'":"'..v..'"')
        elseif type(v)=="table" then
            local arr={}
            for _,item in ipairs(v) do table.insert(arr,'"'..tostring(item)..'"') end
            table.insert(parts, '"'..k..'":[' ..table.concat(arr,",")..']')
        end
    end
    local ok,err = pcall(writefile, CFG_PATH, "{"..table.concat(parts,",").."}")
    State.LastSave = ok and ("✅ "..CFG_PATH) or ("❌ "..tostring(err))
end

local function loadConfig()
    if not CAN_FILE or not isfile(CFG_PATH) then
        State.LastSave = CAN_FILE and "No file yet" or "No file API"
        return
    end
    local ok, raw = pcall(readfile, CFG_PATH)
    if not ok or type(raw)~="string" then State.LastSave="Load failed" return end
    for key, default in pairs(Config) do
        if type(default)=="boolean" then
            local v=raw:match('"'..key..'":%s*(true|false)')
            if v then Config[key]=(v=="true") end
        elseif type(default)=="number" then
            local v=raw:match('"'..key..'":%s*([%d%.]+)')
            if v then Config[key]=tonumber(v) end
        elseif type(default)=="string" then
            local v=raw:match('"'..key..'":%s*"([^"]*)"')
            if v then Config[key]=v end
        elseif type(default)=="table" then
            local arr=raw:match('"'..key..'":%s*%[([^%]]*)%]')
            Config[key]={}
            if arr then for item in arr:gmatch('"([^"]*)"') do table.insert(Config[key],item) end end
        end
    end
    State.LastSave = "✅ Loaded"
end
loadConfig()

-- ============================================================
-- RAID STATE DETECTION
-- ============================================================
-- Detect đang trong raid qua GUI
local function IsInRaid()
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then return false end
    -- Path: Framework.Raid.Top.Buttons.Stop.Button.TextLabel = "End"
    local fw = pg:FindFirstChild("Framework", true)
    if not fw then return false end
    -- Tìm button "End" trong Raid UI
    local raidTop = fw:FindFirstChild("Raid", true)
    if raidTop then
        local stopBtn = raidTop:FindFirstChild("Stop", true)
        if stopBtn then
            local lbl = stopBtn:FindFirstChildOfClass("TextLabel")
            if lbl and lbl.Text == "End" then return true end
            -- Hoặc tìm TextButton
            for _, c in ipairs(stopBtn:GetDescendants()) do
                if (c:IsA("TextLabel") or c:IsA("TextButton")) and c.Text == "End" then
                    return true
                end
            end
        end
    end
    -- Fallback: tìm Wave label đang active
    for _, v in ipairs(pg:GetDescendants()) do
        if v:IsA("TextLabel") then
            local t = v.Text
            if t and t:match("^Wave %d+$") and v.Visible then
                -- kiểm tra parent visible
                local visible = true
                local p = v.Parent
                while p and p ~= pg do
                    if not p.Visible then visible=false break end
                    p = p.Parent
                end
                if visible then return true end
            end
        end
    end
    return false
end

-- Detect cooldown từ GUI Challenges frame
local function GetChallengeCooldown()
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then return 0 end
    for _, v in ipairs(pg:GetDescendants()) do
        if v:IsA("TextLabel") then
            -- Tìm pattern "Xm Xs" hoặc "X:XX" trong Challenges frame
            local m,s = v.Text:match("(%d+)m%s*(%d+)s")
            if m then return tonumber(m)*60 + tonumber(s) end
            local m2,s2 = v.Text:match("(%d+):(%d+)")
            if m2 then
                -- Chỉ lấy nếu parent frame tên liên quan challenge
                local inChall = false
                local p = v.Parent
                while p do
                    if p.Name:lower():find("chall") or p.Name:lower():find("cooldown") then
                        inChall = true break
                    end
                    p = p.Parent
                end
                if inChall then return tonumber(m2)*60 + tonumber(s2) end
            end
        end
    end
    return 0
end

-- ============================================================
-- END RAID
-- ============================================================
local function EndRaid()
    log("Ending raid...")
    -- Fire cả hai event để chắc chắn
    if RE_RaidEnd then
        pcall(function() RE_RaidEnd:FireServer() end)
    end
    task.wait(0.5)
    if RE_RaidStop then
        pcall(function() RE_RaidStop:FireServer() end)
    end
    task.wait(1.5)
    log("Raid end fired, waiting...")
end

-- ============================================================
-- START RAID
-- ============================================================
local function StartRaid()
    if not RF_RaidStart then
        log("RaidStart remote missing!")
        return false
    end
    local ok, r = pcall(function() return RF_RaidStart:InvokeServer() end)
    log("RaidStart -> " .. tostring(ok) .. "/" .. tostring(r))
    return ok
end

-- ============================================================
-- CHALLENGE ENGINE
-- ============================================================
-- ChallengeEnd event
if RE_ChallengeEnd then
    RE_ChallengeEnd.OnClientEvent:Connect(function()
        State.ChallengeActive = false
        log("ChallengeEnd event received")
    end)
end

-- Thử start challenge, retry nhiều lần
local function TryStartChallenge(maxRetry, retryDelay)
    maxRetry = maxRetry or 5
    retryDelay = retryDelay or 2

    for attempt = 1, maxRetry do
        local ok, result = pcall(function()
            return RF_StartChallenge:InvokeServer()
        end)
        log(string.format("StartChallenge attempt %d -> ok=%s result=%s", attempt, tostring(ok), tostring(result)))

        if ok and result ~= false then
            return true  -- thành công
        end

        -- result=false: có thể vẫn trong raid hoặc cooldown
        if attempt < maxRetry then
            task.wait(retryDelay)
        end
    end
    return false
end

-- Đợi challenge kết thúc (lắng nghe event hoặc timeout)
local function WaitForChallengeEnd(timeoutSeconds)
    timeoutSeconds = timeoutSeconds or 300  -- 5 phút max
    State.ChallengeActive = true
    local elapsed = 0
    local interval = 1

    while State.ChallengeActive and elapsed < timeoutSeconds do
        task.wait(interval)
        elapsed = elapsed + interval
        State.ChallCurrent = State.ChallCurrent .. string.format(" (%ds)", elapsed)
    end

    State.ChallengeActive = false
    if elapsed >= timeoutSeconds then
        log("Challenge timeout after " .. timeoutSeconds .. "s")
    end
end

-- Đợi cooldown từ GUI
local function WaitForCooldown()
    local cooldown = GetChallengeCooldown()
    if cooldown > 0 then
        log(string.format("Challenge cooldown: %ds, waiting...", cooldown))
        State.LastStatus = string.format("⏳ Cooldown %ds", cooldown)
        task.wait(cooldown + 2)  -- +2s buffer
    end
end

-- MAIN CHALLENGE RUNNER: chạy 1 difficulty
local function RunChallenge(challDef)
    State.ChallCurrent = challDef.label
    State.LastStatus = "🔄 " .. challDef.label .. ": checking raid..."
    log("--- Starting challenge: " .. challDef.label .. " ---")

    -- Bước 1: End raid nếu đang trong raid
    if IsInRaid() then
        log("In raid, ending first...")
        State.LastStatus = "🔄 " .. challDef.label .. ": ending raid..."
        EndRaid()
        -- Đợi raid thực sự kết thúc
        local waited = 0
        while IsInRaid() and waited < 10 do
            task.wait(1)
            waited = waited + 1
        end
        if IsInRaid() then
            log("⚠️ Raid still active after 10s, proceeding anyway...")
        end
    end

    -- Bước 2: Đợi cooldown nếu có
    WaitForCooldown()

    -- Bước 3: End challenge cũ (nếu có)
    if RF_EndChallenge then
        pcall(function() RF_EndChallenge:InvokeServer() end)
        task.wait(0.5)
    end

    -- Bước 4: Start challenge
    State.LastStatus = "⚔️ Starting " .. challDef.label .. "..."
    local success = TryStartChallenge(5, 2)

    if not success then
        log("❌ Failed to start " .. challDef.label)
        State.LastStatus = "❌ " .. challDef.label .. " failed"
        State.LastError = challDef.label .. " start failed"
        return false
    end

    -- Bước 5: Đợi challenge kết thúc
    log("✅ " .. challDef.label .. " started! Waiting for end...")
    State.LastStatus = "⚔️ Running: " .. challDef.label
    State.Challenges = State.Challenges + 1

    -- timeout = waves * ~8s (estimate) + 60s buffer
    local timeout = challDef.waves * 8 + 60
    WaitForChallengeEnd(timeout)

    log("✅ " .. challDef.label .. " finished!")
    State.LastStatus = "✅ " .. challDef.label .. " done"
    task.wait(2)
    return true
end

-- QUEUE RUNNER: chạy tất cả difficulty được chọn
local function RunChallengeQueue()
    if State.ChallRunning then
        log("Queue already running!")
        return
    end
    State.ChallRunning = true
    log("=== Challenge queue started ===")

    -- Build queue từ config
    local queue = {}
    for _, def in ipairs(CHALL_DEFS) do
        if Config[def.key] then
            table.insert(queue, def)
        end
    end

    if #queue == 0 then
        log("No challenges selected!")
        State.LastStatus = "⚠️ No challenges selected"
        State.ChallRunning = false
        return
    end

    log(string.format("Queue: %d challenges", #queue))

    -- Chạy từng challenge
    for i, challDef in ipairs(queue) do
        if not Config.AutoChallenge then
            log("AutoChallenge disabled, stopping queue")
            break
        end

        State.LastStatus = string.format("⚔️ [%d/%d] %s", i, #queue, challDef.label)
        local ok = RunChallenge(challDef)

        if not ok then
            log("⚠️ Skipping " .. challDef.label .. " due to failure")
        end

        -- Nhỏ delay giữa các challenge
        task.wait(3)
    end

    -- Restart raid sau khi xong tất cả
    log("=== Queue complete, restarting raid... ===")
    State.LastStatus = "🔄 Restarting raid..."
    task.wait(2)
    StartRaid()
    task.wait(2)

    State.ChallRunning = false
    State.ChallCurrent = ""
    State.LastStatus = "✅ Queue done, raid restarted"
    log("=== Queue finished, raid restarted ===")
end

-- Auto challenge loop: đợi queue xong rồi đợi cooldown rồi chạy lại
task.spawn(function()
    while true do
        task.wait(5)
        if Config.AutoChallenge and not State.ChallRunning then
            -- Check có difficulty nào được chọn không
            local hasSelected = false
            for _, def in ipairs(CHALL_DEFS) do
                if Config[def.key] then hasSelected=true break end
            end
            if hasSelected then
                task.spawn(RunChallengeQueue)
            end
        end
    end
end)

-- ============================================================
-- AUTO BUY
-- ============================================================
local function isSelected(name)
    if Config.BuyAllItems then return true end
    for _, item in ipairs(Config.SelectedItems) do
        if item == name then return true end
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
        table.insert(items, {name=tostring(name), qty=tonumber(qty) or 0})
    end
    table.sort(items, function(a,b) return a.name < b.name end)
    return items
end

local function fetchShop()
    if not RF_UpdateShop then State.LastError="UpdateCurrentShop missing" return end
    local ok, result = pcall(function() return RF_UpdateShop:InvokeServer() end)
    if ok and type(result)=="table" then
        State.ShopItems = result
    else
        State.LastError = "Shop failed: "..tostring(result)
    end
end

local function autoBuyOnce()
    if not RF_BuyDefense then State.LastError="BuyDefense missing" return end
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
                State.LastBuy = entry.name.." x"..entry.qty
                log("Bought "..State.LastBuy)
            else
                State.LastError = "Buy failed: "..entry.name.." -> "..tostring(result)
            end
            task.wait(0.2)
        end
    end
    if not boughtAny then State.LastBuy = "No stock" end
end

task.spawn(function()
    while true do
        task.wait(Config.BuyDelay)
        if Config.AutoBuy then autoBuyOnce() end
    end
end)

-- ============================================================
-- ANTI-AFK
-- ============================================================
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
                VU:Button1Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
                task.wait(0.1)
                VU:Button1Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
            end)
        end
    end
end)

-- ============================================================
-- UI THEME
-- ============================================================
local C = {
    bg     = Color3.fromRGB(16,18,26),
    panel  = Color3.fromRGB(25,28,40),
    head   = Color3.fromRGB(35,39,56),
    soft   = Color3.fromRGB(45,50,70),
    accent = Color3.fromRGB(78,132,255),
    green  = Color3.fromRGB(64,189,115),
    red    = Color3.fromRGB(214,78,78),
    gold   = Color3.fromRGB(225,180,62),
    purple = Color3.fromRGB(190,70,220),
    text   = Color3.fromRGB(235,239,248),
    sub    = Color3.fromRGB(145,150,170),
    stroke = Color3.fromRGB(50,55,76),
    active = Color3.fromRGB(42,83,55),
}

-- ============================================================
-- UI HELPERS
-- ============================================================
local function corner(i,r) local c=Instance.new("UICorner") c.CornerRadius=UDim.new(0,r or 8) c.Parent=i end
local function border(i) local s=Instance.new("UIStroke") s.Color=C.stroke s.Parent=i end
local function frame(p,size,pos,col)
    local f=Instance.new("Frame") f.Size=size f.Position=pos or UDim2.new()
    f.BackgroundColor3=col or C.panel f.BorderSizePixel=0 f.Parent=p return f
end
local function label(p,txt,size,pos,col,ts,font)
    local l=Instance.new("TextLabel") l.Size=size l.Position=pos or UDim2.new()
    l.BackgroundTransparency=1 l.Text=txt l.TextColor3=col or C.text l.TextSize=ts or 12
    l.Font=font or Enum.Font.GothamMedium l.TextWrapped=true l.TextXAlignment=Enum.TextXAlignment.Left
    l.Parent=p return l
end
local function button(p,txt,size,pos,col,fn)
    local b=Instance.new("TextButton") b.Size=size b.Position=pos or UDim2.new()
    b.BackgroundColor3=col or C.accent b.BorderSizePixel=0 b.Text=txt
    b.TextColor3=C.text b.TextSize=12 b.Font=Enum.Font.GothamBold b.Parent=p
    corner(b,7) if fn then b.MouseButton1Click:Connect(fn) end return b
end
local function section(p,t)
    label(p,string.upper(t),UDim2.new(1,0,0,16),nil,C.sub,10,Enum.Font.GothamBold)
end
local function toggleRow(p,title,desc,key,onToggle)
    local r=frame(p,UDim2.new(1,0,0,66),nil,C.panel) corner(r,9) border(r)
    label(r,title,UDim2.new(1,-74,0,22),UDim2.new(0,12,0,10),C.text,13,Enum.Font.GothamBold)
    label(r,desc,UDim2.new(1,-74,0,18),UDim2.new(0,12,0,34),C.sub,11,Enum.Font.Gotham)
    local pill=Instance.new("TextButton") pill.Size=UDim2.new(0,44,0,22)
    pill.Position=UDim2.new(1,-56,0.5,-11) pill.BorderSizePixel=0 pill.Text=""
    pill.BackgroundColor3=Config[key] and C.green or C.soft pill.Parent=r corner(pill,11)
    local knob=frame(pill,UDim2.new(0,16,0,16),Config[key] and UDim2.new(0,25,0.5,-8) or UDim2.new(0,3,0.5,-8),Color3.fromRGB(236,238,245)) corner(knob,8)
    pill.MouseButton1Click:Connect(function()
        Config[key]=not Config[key]
        pill.BackgroundColor3=Config[key] and C.green or C.soft
        knob.Position=Config[key] and UDim2.new(0,25,0.5,-8) or UDim2.new(0,3,0.5,-8)
        saveConfig()
        if onToggle then onToggle(Config[key]) end
    end)
    return r
end

-- ============================================================
-- SCREENGUI
-- ============================================================
local SG=Instance.new("ScreenGui") SG.Name=UI_NAME SG.ResetOnSpawn=false
SG.ZIndexBehavior=Enum.ZIndexBehavior.Sibling SG.DisplayOrder=100
local ok=pcall(function() SG.Parent=CoreGui end)
if not ok or not SG.Parent then SG.Parent=LP:WaitForChild("PlayerGui") end

local Win=frame(SG,UDim2.new(0,360,0,0),UDim2.new(0.04,0,0.08,0),C.bg)
Win.AutomaticSize=Enum.AutomaticSize.Y corner(Win,12) border(Win)

-- HEAD
local Head=frame(Win,UDim2.new(1,0,0,50),nil,C.head) corner(Head,12)
frame(Head,UDim2.new(1,0,0,12),UDim2.new(0,0,1,-12),C.head)
label(Head,"Defend Your Castle",UDim2.new(1,-100,0,22),UDim2.new(0,14,0,6),C.text,14,Enum.Font.GothamBold)
label(Head,"v4.0 | RightShift toggle",UDim2.new(1,-100,0,14),UDim2.new(0,14,0,30),C.sub,10,Enum.Font.Gotham)
button(Head,"X",UDim2.new(0,26,0,26),UDim2.new(1,-34,0.5,-13),C.red,function() Win.Visible=false end)

-- BODY
local Body=frame(Win,UDim2.new(1,-20,0,0),UDim2.new(0,10,0,58),Color3.new())
Body.BackgroundTransparency=1 Body.AutomaticSize=Enum.AutomaticSize.Y
local BL=Instance.new("UIListLayout") BL.Padding=UDim.new(0,6) BL.Parent=Body

-- TABBAR
local TabBar=frame(Body,UDim2.new(1,0,0,30),nil,C.panel) corner(TabBar,8)
local TL=Instance.new("UIListLayout") TL.FillDirection=Enum.FillDirection.Horizontal
TL.Padding=UDim.new(0,3) TL.Parent=TabBar
local TP=Instance.new("UIPadding") TP.PaddingLeft=UDim.new(0,3) TP.Parent=TabBar

local pages,tabs={},{}
local function activate(name)
    for n,p in pairs(pages) do p.Visible=n==name end
    for n,b in pairs(tabs) do
        b.BackgroundColor3=(n==name) and C.accent or C.soft
        b.TextColor3=(n==name) and C.text or C.sub
    end
end
local function makePage(name,icon)
    local tb=Instance.new("TextButton") tb.Size=UDim2.new(0,82,1,-6)
    tb.BackgroundColor3=C.soft tb.TextColor3=C.sub tb.BorderSizePixel=0
    tb.Text=(icon and icon.." " or "")..name tb.TextSize=11 tb.Font=Enum.Font.GothamMedium
    tb.Parent=TabBar corner(tb,6)
    local p=frame(Body,UDim2.new(1,0,0,0),nil,Color3.new())
    p.BackgroundTransparency=1 p.AutomaticSize=Enum.AutomaticSize.Y
    local pl=Instance.new("UIListLayout") pl.Padding=UDim.new(0,6) pl.Parent=p
    pages[name]=p tabs[name]=tb
    tb.MouseButton1Click:Connect(function() activate(name) end)
    return p
end

local Main   = makePage("Main","⚡")
local Buy    = makePage("Buy","🛒")
local Chall  = makePage("Chall","⚔️")
local Debug  = makePage("Debug","🔍")
activate("Main")

local StatusLabel

-- ============================================================
-- PAGE: MAIN
-- ============================================================
section(Main,"Core")
toggleRow(Main,"Anti-AFK","Tự động jump/click mỗi 50s","AntiAFK")
toggleRow(Main,"Auto Buy","Tự động mua Blueprint có stock","AutoBuy")
toggleRow(Main,"Auto Challenge","Tự động chạy challenge queue","AutoChallenge",
    function(on)
        if on then
            -- Kick off queue immediately
            if not State.ChallRunning then
                task.spawn(RunChallengeQueue)
            end
        else
            log("AutoChallenge disabled")
        end
    end
)

section(Main,"Stats")
local StatBox=frame(Main,UDim2.new(1,0,0,80),nil,C.panel) corner(StatBox,9) border(StatBox)
local BoughtLabel   = label(StatBox,"📄 Bought: 0",       UDim2.new(1,-12,0,18),UDim2.new(0,12,0,6), C.green,12)
local LastBuyLabel  = label(StatBox,"Last: None",          UDim2.new(1,-12,0,16),UDim2.new(0,12,0,26),C.sub,11)
local ChallLabel    = label(StatBox,"⚔️ Challenges: 0",   UDim2.new(0.6,0,0,18),UDim2.new(0,12,0,46),C.gold,12)
local ChallCurLabel = label(StatBox,"Current: —",          UDim2.new(0.5,0,0,18),UDim2.new(0.45,0,0,46),C.sub,11)

section(Main,"Status")
local StatusBox=frame(Main,UDim2.new(1,0,0,28),nil,C.panel) corner(StatusBox,8)
StatusLabel=label(StatusBox,"● Ready",UDim2.new(1,-12,1,0),UDim2.new(0,10,0,0),C.sub,11,Enum.Font.GothamMedium)

-- ============================================================
-- PAGE: BUY
-- ============================================================
section(Buy,"Mode")
local ModeBox=frame(Buy,UDim2.new(1,0,0,66),nil,C.panel) corner(ModeBox,9) border(ModeBox)
label(ModeBox,"Buy All Items",UDim2.new(1,-74,0,22),UDim2.new(0,12,0,8),C.text,13,Enum.Font.GothamBold)
label(ModeBox,"ON=mua tất cả | OFF=chỉ mua item đã chọn",UDim2.new(1,-74,0,26),UDim2.new(0,12,0,30),C.sub,11,Enum.Font.Gotham)
local BAP=Instance.new("TextButton") BAP.Size=UDim2.new(0,44,0,22) BAP.Position=UDim2.new(1,-56,0.5,-11)
BAP.BorderSizePixel=0 BAP.Text="" BAP.BackgroundColor3=Config.BuyAllItems and C.green or C.soft BAP.Parent=ModeBox corner(BAP,11)
local BAK=frame(BAP,UDim2.new(0,16,0,16),Config.BuyAllItems and UDim2.new(0,25,0.5,-8) or UDim2.new(0,3,0.5,-8),Color3.fromRGB(236,238,245)) corner(BAK,8)
BAP.MouseButton1Click:Connect(function()
    Config.BuyAllItems=not Config.BuyAllItems
    BAP.BackgroundColor3=Config.BuyAllItems and C.green or C.soft
    BAK.Position=Config.BuyAllItems and UDim2.new(0,25,0.5,-8) or UDim2.new(0,3,0.5,-8)
    saveConfig()
end)

section(Buy,"Shop Items")
local BuyBtns=frame(Buy,UDim2.new(1,0,0,30),nil,Color3.new()) BuyBtns.BackgroundTransparency=1
local BBL=Instance.new("UIListLayout") BBL.FillDirection=Enum.FillDirection.Horizontal BBL.Padding=UDim.new(0,6) BBL.Parent=BuyBtns
local ShopInfo=label(Buy,"Load shop để xem items.",UDim2.new(1,0,0,18),nil,C.sub,11)
local Grid=frame(Buy,UDim2.new(1,0,0,0),nil,Color3.new()) Grid.BackgroundTransparency=1 Grid.AutomaticSize=Enum.AutomaticSize.Y
local GL=Instance.new("UIGridLayout") GL.CellSize=UDim2.new(0.5,-4,0,32) GL.CellPadding=UDim2.new(0,4,0,4) GL.Parent=Grid

local function rebuildShop()
    for _,child in ipairs(Grid:GetChildren()) do
        if child:IsA("TextButton") or child:IsA("Frame") then child:Destroy() end
    end
    local items=sortedShop()
    ShopInfo.Text=(#items==0) and "No shop data." or ("Items: "..#items)
    for _,entry in ipairs(items) do
        local sel=isSelected(entry.name)
        local b=Instance.new("TextButton") b.Size=UDim2.new(1,0,0,32) b.BorderSizePixel=0
        b.Text=entry.name..(entry.qty>0 and " ["..entry.qty.."]" or " [0]")
        b.TextSize=11 b.Font=Enum.Font.GothamMedium
        b.BackgroundColor3=sel and C.active or C.soft
        b.TextColor3=sel and C.green or C.sub b.Parent=Grid corner(b,6) border(b)
        b.MouseButton1Click:Connect(function() toggleItem(entry.name) rebuildShop() end)
    end
end

button(BuyBtns,"Refresh",UDim2.new(0.5,-3,1,0),nil,C.accent,function() fetchShop() rebuildShop() end)
button(BuyBtns,"Buy Once",UDim2.new(0.5,-3,1,0),UDim2.new(0.5,3,0,0),C.green,function() autoBuyOnce() fetchShop() rebuildShop() end)

-- ============================================================
-- PAGE: CHALLENGE
-- ============================================================
section(Chall,"Chọn Difficulty (Queue)")

-- Info box
local challInfo=frame(Chall,UDim2.new(1,0,0,46),nil,C.panel) corner(challInfo,9) border(challInfo)
label(challInfo,"Bật các difficulty muốn chạy. Script sẽ:",UDim2.new(1,-12,0,16),UDim2.new(0,10,0,4),C.sub,11)
label(challInfo,"End Raid → Chạy từng challenge → Restart Raid",UDim2.new(1,-12,0,16),UDim2.new(0,10,0,24),C.gold,11)

-- Difficulty toggles
local challToggles = {} -- key -> pill,knob
for _, def in ipairs(CHALL_DEFS) do
    local r=frame(Chall,UDim2.new(1,0,0,52),nil,C.panel) corner(r,9) border(r)
    -- Color indicator
    local indicator=frame(r,UDim2.new(0,4,1,-16),UDim2.new(0,0,0.5,-0),def.color)
    indicator.Position=UDim2.new(0,0,0.5,-18) corner(indicator,2)
    label(r,def.label,UDim2.new(0,120,0,20),UDim2.new(0,14,0,8),C.text,13,Enum.Font.GothamBold)
    label(r,def.waves.." Waves",UDim2.new(0,120,0,16),UDim2.new(0,14,0,30),C.sub,11,Enum.Font.Gotham)
    -- Status badge
    local badge=label(r,"—",UDim2.new(0,80,1,0),UDim2.new(0,140,0,0),C.sub,11,Enum.Font.GothamMedium)
    -- Toggle pill
    local pill=Instance.new("TextButton") pill.Size=UDim2.new(0,44,0,22)
    pill.Position=UDim2.new(1,-54,0.5,-11) pill.BorderSizePixel=0 pill.Text=""
    pill.BackgroundColor3=Config[def.key] and C.green or C.soft pill.Parent=r corner(pill,11)
    local knob=frame(pill,UDim2.new(0,16,0,16),Config[def.key] and UDim2.new(0,25,0.5,-8) or UDim2.new(0,3,0.5,-8),Color3.fromRGB(236,238,245)) corner(knob,8)
    local function refreshPill()
        pill.BackgroundColor3=Config[def.key] and C.green or C.soft
        knob.Position=Config[def.key] and UDim2.new(0,25,0.5,-8) or UDim2.new(0,3,0.5,-8)
    end
    pill.MouseButton1Click:Connect(function()
        Config[def.key]=not Config[def.key]
        refreshPill()
        saveConfig()
    end)
    challToggles[def.key] = {pill=pill,knob=knob,badge=badge,refreshPill=refreshPill}
end

section(Chall,"Manual Control")
local CBtns=frame(Chall,UDim2.new(1,0,0,30),nil,Color3.new()) CBtns.BackgroundTransparency=1
local CBL=Instance.new("UIListLayout") CBL.FillDirection=Enum.FillDirection.Horizontal CBL.Padding=UDim.new(0,6) CBL.Parent=CBtns

button(CBtns,"▶ Run Queue",UDim2.new(0.5,-3,1,0),nil,C.green,function()
    if State.ChallRunning then
        log("Already running!")
        return
    end
    task.spawn(RunChallengeQueue)
end)
button(CBtns,"⏹ Stop",UDim2.new(0.5,-3,1,0),UDim2.new(0.5,3,0,0),C.red,function()
    Config.AutoChallenge=false
    State.ChallRunning=false
    State.ChallengeActive=false
    if RF_EndChallenge then pcall(function() RF_EndChallenge:InvokeServer() end) end
    log("Challenge stopped manually")
end)

-- Queue status
local QueueBox=frame(Chall,UDim2.new(1,0,0,40),nil,C.panel) corner(QueueBox,8)
local QueueLbl=label(QueueBox,"Queue: idle",UDim2.new(1,-12,0,18),UDim2.new(0,10,0,4),C.sub,11,Enum.Font.GothamMedium)
local QueueLbl2=label(QueueBox,"Current: —",UDim2.new(1,-12,0,16),UDim2.new(0,10,0,24),C.sub,11)

-- ============================================================
-- PAGE: DEBUG
-- ============================================================
section(Debug,"Runtime Info")
local DBox=frame(Debug,UDim2.new(1,0,0,110),nil,C.panel) corner(DBox,9) border(DBox)
local DL1=label(DBox,"",UDim2.new(1,-12,0,16),UDim2.new(0,10,0,6),C.sub,11)
local DL2=label(DBox,"",UDim2.new(1,-12,0,16),UDim2.new(0,10,0,26),C.sub,11)
local DL3=label(DBox,"",UDim2.new(1,-12,0,16),UDim2.new(0,10,0,46),C.sub,11)
local DL4=label(DBox,"",UDim2.new(1,-12,0,16),UDim2.new(0,10,0,66),C.sub,11)
local DL5=label(DBox,"",UDim2.new(1,-12,0,16),UDim2.new(0,10,0,86),C.sub,11)

section(Debug,"Actions")
local DBA=frame(Debug,UDim2.new(1,0,0,30),nil,Color3.new()) DBA.BackgroundTransparency=1
local DBL=Instance.new("UIListLayout") DBL.FillDirection=Enum.FillDirection.Horizontal DBL.Padding=UDim.new(0,6) DBL.Parent=DBA
button(DBA,"Save Config",UDim2.new(0.5,-3,1,0),nil,C.accent,saveConfig)
button(DBA,"Refresh Shop",UDim2.new(0.5,-3,1,0),UDim2.new(0.5,3,0,0),C.gold,function() fetchShop() rebuildShop() end)

section(Debug,"Logs")
local LogBox=frame(Debug,UDim2.new(1,0,0,180),nil,C.panel) corner(LogBox,9) border(LogBox)
local LogLbl=label(LogBox,"",UDim2.new(1,-12,1,-12),UDim2.new(0,10,0,6),C.sub,11,Enum.Font.Code)
LogLbl.TextYAlignment=Enum.TextYAlignment.Top

-- ============================================================
-- UPDATE LOOP
-- ============================================================
task.spawn(function()
    while true do
        task.wait(0.5)
        pcall(function()
            -- Main stats
            BoughtLabel.Text   = "📄 Bought: "..State.Bought
            LastBuyLabel.Text  = "Last: "..State.LastBuy
            ChallLabel.Text    = "⚔️ Challenges: "..State.Challenges
            ChallCurLabel.Text = "Current: "..(State.ChallCurrent~="" and State.ChallCurrent or "—")
            StatusLabel.Text   = "● "..State.LastStatus

            -- Challenge queue status
            if State.ChallRunning then
                QueueLbl.Text = "⚔️ Queue: RUNNING"
                QueueLbl.TextColor3 = C.green
            else
                QueueLbl.Text = "Queue: idle"
                QueueLbl.TextColor3 = C.sub
            end
            QueueLbl2.Text = "Current: "..(State.ChallCurrent~="" and State.ChallCurrent or "—")

            -- Debug info
            local inRaid = IsInRaid()
            DL1.Text = "InRaid: "..tostring(inRaid).." | ChallActive: "..tostring(State.ChallengeActive)
            DL2.Text = "Config: "..State.LastSave
            DL3.Text = "LastError: "..State.LastError
            DL4.Text = "Remotes: Shop="..tostring(RF_UpdateShop~=nil).." Buy="..tostring(RF_BuyDefense~=nil).." Chall="..tostring(RF_StartChallenge~=nil)
            DL5.Text = "RaidEnd="..tostring(RE_RaidEnd~=nil).." RaidStart="..tostring(RF_RaidStart~=nil)

            LogLbl.Text = table.concat(State.Logs,"\n")
        end)
    end
end)

-- ============================================================
-- DRAG
-- ============================================================
local dragging,dragStart,startPos=false,nil,nil
Head.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        dragging=true dragStart=i.Position startPos=Win.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
        local d=i.Position-dragStart
        Win.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=false end
end)
UIS.InputBegan:Connect(function(i,gp)
    if not gp and i.KeyCode==Enum.KeyCode.RightShift then Win.Visible=not Win.Visible end
end)

-- ============================================================
-- INIT
-- ============================================================
task.spawn(function() fetchShop() rebuildShop() end)
log("UI ready - v4.0")
log("Challenge system: End Raid -> Queue -> Restart Raid")
