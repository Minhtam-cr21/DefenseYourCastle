--[[
    DEFEND YOUR CASTLE - v5.0
    CONFIRMED:
    - StartChallenge("Easy"/"Medium"/"Hard"/"Insane"/"Godly") -> true=ok / false=cooldown
    - RaidEnd + RaidStop (RemoteEvent:FireServer()) để end raid
    - RaidStart (RemoteFunction:InvokeServer()) để restart raid
    - Cooldown GUI: Framework.Raid.Top.Buttons.Challenge.Timer = "MM:SS:mmm"
    - ChallengeEnd (RemoteEvent) -> server fires khi xong
--]]

local Players  = game:GetService("Players")
local TweenSvc = game:GetService("TweenService")
local UIS      = game:GetService("UserInputService")
local RS       = game:GetService("ReplicatedStorage")
local VU       = game:GetService("VirtualUser")
local LP       = Players.LocalPlayer
local CoreGui  = game:GetService("CoreGui")

local UI_NAME  = "DYC_UI"
local CFG_PATH = "DYC_Config.json"

-- ── CLEANUP ──────────────────────────────────────────────────
for _, p in ipairs({CoreGui, LP:FindFirstChild("PlayerGui")}) do
    if p then local o = p:FindFirstChild(UI_NAME) if o then o:Destroy() end end
end

-- ── REMOTES ──────────────────────────────────────────────────
local Events    = RS:WaitForChild("Events")
local Functions = Events:WaitForChild("Functions")
local Remotes   = Events:WaitForChild("Remotes")

local RF_UpdateShop     = Functions:WaitForChild("UpdateCurrentShop")
local RF_BuyDefense     = Functions:WaitForChild("BuyDefense")
local RF_StartChallenge = Functions:WaitForChild("StartChallenge")
local RF_EndChallenge   = Functions:WaitForChild("EndChallenge")
local RF_RaidStart      = Functions:WaitForChild("RaidStart")
local RE_RaidEnd        = Remotes:WaitForChild("RaidEnd")
local RE_RaidStop       = Remotes:WaitForChild("RaidStop")
local RE_ChallengeEnd   = Remotes:FindFirstChild("ChallengeEnd")

-- ── CHALLENGE DEFINITIONS ────────────────────────────────────
-- key=config flag, diff=server arg, label=UI, color
local CHALLDEFS = {
    { key="ChallNovice",   diff="Easy",   label="Novice",   waves=25, col=Color3.fromRGB(64,189,115)  },
    { key="ChallAdvanced", diff="Medium", label="Advanced", waves=25, col=Color3.fromRGB(225,180,62)  },
    { key="ChallPro",      diff="Hard",   label="Pro",      waves=25, col=Color3.fromRGB(214,140,60)  },
    { key="ChallInsane",   diff="Insane", label="Insane",   waves=20, col=Color3.fromRGB(190,70,220)  },
    { key="ChallGodly",    diff="Godly",  label="Godly",    waves=25, col=Color3.fromRGB(220,60,60)   },
}

-- ── FILE API ─────────────────────────────────────────────────
local CAN_FILE = type(readfile)=="function" and type(writefile)=="function" and type(isfile)=="function"

-- ── CONFIG ───────────────────────────────────────────────────
local Config = {
    AntiAFK      = false,
    AutoBuy      = false,
    AutoChallenge= false,
    BuyDelay     = 3,
    BuyAllItems  = true,
    SelectedItems= {},
    -- per-challenge toggles
    ChallNovice  = false,
    ChallAdvanced= false,
    ChallPro     = false,
    ChallInsane  = false,
    ChallGodly   = false,
}

-- ── STATE ────────────────────────────────────────────────────
local State = {
    Bought          = 0,
    Challenges      = 0,
    LastBuy         = "None",
    LastSave        = "—",
    LastError       = "None",
    ChallengeActive = false,  -- đang trong 1 challenge
    ChallRunning    = false,  -- queue đang chạy
    ChallCurrent    = "—",
    ShopItems       = {},
    Logs            = {},
}

-- ── LOG ──────────────────────────────────────────────────────
local function log(t)
    local s="[DYC] "..tostring(t)
    print(s)
    table.insert(State.Logs,1,s)
    while #State.Logs>24 do table.remove(State.Logs) end
end

-- ── SAVE/LOAD ────────────────────────────────────────────────
local function saveConfig()
    if not CAN_FILE then State.LastSave="No file API" return end
    local p={}
    for k,v in pairs(Config) do
        if type(v)=="boolean" then table.insert(p,'"'..k..'":'.. (v and"true"or"false"))
        elseif type(v)=="number" then table.insert(p,'"'..k..'":'..v)
        elseif type(v)=="string" then table.insert(p,'"'..k..'":"'..v..'"')
        elseif type(v)=="table" then
            local a={} for _,i in ipairs(v) do table.insert(a,'"'..i..'"') end
            table.insert(p,'"'..k..'":[' ..table.concat(a,",").."]")
        end
    end
    local ok,e=pcall(writefile,CFG_PATH,"{"..table.concat(p,",").."}")
    State.LastSave=ok and "✅ saved" or "❌ "..tostring(e)
end

local function loadConfig()
    if not CAN_FILE or not isfile(CFG_PATH) then
        State.LastSave=CAN_FILE and "No file yet" or "No file API" return
    end
    local ok,raw=pcall(readfile,CFG_PATH)
    if not ok then State.LastSave="Load failed" return end
    for k,def in pairs(Config) do
        if type(def)=="boolean" then
            local v=raw:match('"'..k..'":%s*(true|false)') if v then Config[k]=(v=="true") end
        elseif type(def)=="number" then
            local v=raw:match('"'..k..'":%s*([%d%.]+)') if v then Config[k]=tonumber(v) end
        elseif type(def)=="string" then
            local v=raw:match('"'..k..'":%s*"([^"]*)"') if v then Config[k]=v end
        elseif type(def)=="table" then
            local a=raw:match('"'..k..'":%s*%[([^%]]*)%]')
            Config[k]={} if a then for i in a:gmatch('"([^"]*)"') do table.insert(Config[k],i) end end
        end
    end
    State.LastSave="✅ loaded"
end
loadConfig()

-- ═══════════════════════════════════════════════════════════════
-- ── GUI HELPERS ──────────────────────────────────────────────
-- ═══════════════════════════════════════════════════════════════

-- Lấy Framework GUI
local function GetFramework()
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then return nil end
    return pg:FindFirstChild("Framework", true)
end

-- Đọc cooldown timer từ GUI: "MM:SS:mmm" -> seconds
-- Path: Framework.Raid.Top.Buttons.Challenge.Timer
local function GetCooldownSeconds()
    local fw = GetFramework()
    if not fw then return 0 end
    -- Tìm Timer label trong Challenge button của Raid Top
    local timerLabel = nil
    pcall(function()
        timerLabel = fw
            :FindFirstChild("Raid",true)
            :FindFirstChild("Top",true)
            :FindFirstChild("Buttons",true)
            :FindFirstChild("Challenge",true)
            :FindFirstChild("Timer",true)
    end)
    if not timerLabel then
        -- Fallback: scan tất cả TextLabel tên "Timer" trong Challenge area
        for _, v in ipairs(fw:GetDescendants()) do
            if v.Name == "Timer" and v:IsA("TextLabel") then
                timerLabel = v
                break
            end
        end
    end
    if not timerLabel then return 0 end
    local txt = timerLabel.Text or ""
    -- Format "MM:SS:mmm" hoặc "MM:SS"
    local m,s = txt:match("^(%d+):(%d+)")
    if m and s then
        local total = tonumber(m)*60 + tonumber(s)
        return total > 0 and total or 0
    end
    return 0
end

-- Check đang trong raid: Raid.Top.Buttons.Stop button visible = "End"
local function IsInRaid()
    local fw = GetFramework()
    if not fw then return false end
    -- Check: Raid frame visible
    pcall(function()
        local raidFrame = fw:FindFirstChild("Raid", true)
        if raidFrame and raidFrame:IsA("Frame") and raidFrame.Visible then
            -- Có frame "Raid" visible = đang raid
        end
    end)
    -- Reliable method: coi Wave label trong Raid.Top
    for _, v in ipairs(fw:GetDescendants()) do
        if v:IsA("TextLabel") and v.Name == "Wave" then
            -- Check parents visible
            local vis = true
            local p = v.Parent
            local depth = 0
            while p and p ~= fw and depth < 6 do
                if not p.Visible then vis=false break end
                p = p.Parent depth=depth+1
            end
            if vis and v.Text and v.Text:match("Wave %d+") then
                return true
            end
        end
    end
    return false
end

-- ═══════════════════════════════════════════════════════════════
-- ── CORE CHALLENGE ENGINE ────────────────────────────────────
-- ═══════════════════════════════════════════════════════════════

-- Listen ChallengeEnd event
if RE_ChallengeEnd then
    RE_ChallengeEnd.OnClientEvent:Connect(function()
        State.ChallengeActive = false
        log("◀ ChallengeEnd event received")
    end)
end

-- End raid hiện tại
local function DoEndRaid()
    log("🔴 Ending raid...")
    pcall(function() RE_RaidEnd:FireServer() end)
    task.wait(0.3)
    pcall(function() RE_RaidStop:FireServer() end)
    task.wait(1)
    -- Đợi raid thực sự kết thúc (max 8s)
    for i = 1, 8 do
        task.wait(1)
        if not IsInRaid() then
            log("✅ Raid ended after "..i.."s")
            return true
        end
    end
    log("⚠️ Raid may still be active, proceeding...")
    return false
end

-- Restart raid
local function DoStartRaid()
    log("🟢 Starting raid...")
    local ok, r = pcall(function() return RF_RaidStart:InvokeServer() end)
    log("RaidStart -> "..tostring(ok).."/"..tostring(r))
    return ok
end

-- Chạy 1 challenge theo difficulty string
-- Returns: "done" | "cooldown" | "failed"
local function RunOneChallenge(def)
    State.ChallCurrent = def.label
    log("⚔️ Trying challenge: "..def.label.." (diff="..def.diff..")")

    -- Step 1: Đợi nếu còn cooldown
    local cooldown = GetCooldownSeconds()
    if cooldown > 0 then
        log(string.format("⏳ Cooldown: %ds, waiting...", cooldown))
        State.ChallCurrent = def.label.." ⏳"..cooldown.."s"
        task.wait(cooldown + 3)
    end

    -- Step 2: End raid nếu đang trong raid
    if IsInRaid() then
        DoEndRaid()
        task.wait(1)
    end

    -- Step 3: EndChallenge để clear state cũ
    pcall(function() RF_EndChallenge:InvokeServer() end)
    task.wait(0.5)

    -- Step 4: StartChallenge với đúng difficulty string
    -- Confirmed: StartChallenge("Easy"/"Medium"/"Hard"/"Insane"/"Godly")
    local started = false
    for attempt = 1, 6 do
        local ok, result = pcall(function()
            return RF_StartChallenge:InvokeServer(def.diff)
        end)
        log(string.format("  StartChallenge(%s) attempt %d -> ok=%s result=%s",
            def.diff, attempt, tostring(ok), tostring(result)))

        if ok and result ~= false then
            started = true
            break
        end

        -- result=false = còn cooldown hoặc state issue
        if attempt == 1 then
            -- Thử lại sau khi đợi thêm
            local cd = GetCooldownSeconds()
            if cd > 0 then
                log("⏳ Still cooldown: "..cd.."s")
                State.ChallCurrent = def.label.." ⏳"..cd.."s"
                task.wait(cd + 3)
            else
                task.wait(2)
            end
        else
            task.wait(2)
        end
    end

    if not started then
        log("❌ "..def.label.." could not start, skip")
        return "failed"
    end

    -- Step 5: Đợi challenge kết thúc
    State.ChallengeActive = true
    State.ChallCurrent = "⚔️ "..def.label.." running..."
    log("✅ "..def.label.." started! Waiting for end...")

    local timeout = def.waves * 10 + 90
    local elapsed = 0
    while State.ChallengeActive and elapsed < timeout do
        task.wait(1)
        elapsed = elapsed + 1
        -- Update label với elapsed time
        if elapsed % 5 == 0 then
            State.ChallCurrent = string.format("⚔️ %s (%ds)", def.label, elapsed)
        end
    end

    State.ChallengeActive = false
    State.Challenges = State.Challenges + 1
    log(string.format("✅ %s done in %ds! Total: %d", def.label, elapsed, State.Challenges))
    return "done"
end

-- ── MAIN CHALLENGE LOOP ──────────────────────────────────────
-- Chạy liên tục: kiểm tra queue -> chạy từng challenge -> restart raid -> lặp lại
local challLoopRunning = false

local function ChallengeLoop()
    if challLoopRunning then return end
    challLoopRunning = true
    log("=== Challenge loop started ===")

    while Config.AutoChallenge do
        -- Build queue từ config theo thứ tự
        local queue = {}
        for _, def in ipairs(CHALLDEFS) do
            if Config[def.key] then
                table.insert(queue, def)
            end
        end

        if #queue == 0 then
            State.ChallCurrent = "No difficulty selected"
            task.wait(3)
            -- eslint
        else
            local anyDone = false

            -- Chạy từng challenge trong queue
            for _, def in ipairs(queue) do
                if not Config.AutoChallenge then break end
                local result = RunOneChallenge(def)
                if result == "done" then
                    anyDone = true
                end
                task.wait(2)
            end

            -- Sau khi xong tất cả -> check cooldown tổng
            if Config.AutoChallenge then
                local cd = GetCooldownSeconds()
                if cd > 0 then
                    -- Còn cooldown -> restart raid trong lúc chờ
                    log("All challenges done. Cooldown: "..cd.."s -> Restarting raid...")
                    State.ChallCurrent = "⏳ All done, restarting raid"
                    DoStartRaid()
                    -- Đợi cooldown hết rồi vòng lặp tiếp theo sẽ tự xử lý
                    task.wait(cd + 3)
                else
                    -- Không còn cooldown -> restart raid và chạy lại ngay
                    log("All done, restarting raid...")
                    State.ChallCurrent = "✅ Queue done"
                    DoStartRaid()
                    task.wait(5)
                end
            end
        end
    end

    -- AutoChallenge tắt -> restart raid
    log("=== Challenge loop stopped, restarting raid ===")
    DoStartRaid()
    State.ChallCurrent = "—"
    challLoopRunning = false
end

-- ═══════════════════════════════════════════════════════════════
-- ── AUTO BUY ─────────────────────────────────────────────────
-- ═══════════════════════════════════════════════════════════════
local function isSelected(n)
    if Config.BuyAllItems then return true end
    for _,i in ipairs(Config.SelectedItems) do if i==n then return true end end
    return false
end
local function toggleItem(n)
    for i,item in ipairs(Config.SelectedItems) do
        if item==n then table.remove(Config.SelectedItems,i) saveConfig() return end
    end
    table.insert(Config.SelectedItems,n) saveConfig()
end
local function sortedShop()
    local t={}
    for n,q in pairs(State.ShopItems) do table.insert(t,{name=tostring(n),qty=tonumber(q)or 0}) end
    table.sort(t,function(a,b) return a.name<b.name end)
    return t
end
local function fetchShop()
    local ok,r=pcall(function() return RF_UpdateShop:InvokeServer() end)
    if ok and type(r)=="table" then State.ShopItems=r
    else State.LastError="Shop:"..tostring(r) end
end
local function autoBuyOnce()
    fetchShop()
    for _,entry in ipairs(sortedShop()) do
        if entry.qty>0 and isSelected(entry.name) then
            local ok,r=pcall(function() return RF_BuyDefense:InvokeServer(entry.name,entry.qty) end)
            if ok then
                State.Bought=State.Bought+entry.qty
                State.LastBuy=entry.name.." x"..entry.qty
                log("Bought "..State.LastBuy)
            else
                State.LastError="Buy:"..entry.name.."->"..tostring(r)
            end
            task.wait(0.15)
        end
    end
end

task.spawn(function()
    while true do
        task.wait(Config.BuyDelay)
        if Config.AutoBuy then autoBuyOnce() end
    end
end)

-- ── ANTI-AFK ─────────────────────────────────────────────────
task.spawn(function()
    while true do
        task.wait(50)
        if Config.AntiAFK then
            local c=LP.Character
            if c then local h=c:FindFirstChildOfClass("Humanoid") if h and h.Health>0 then h.Jump=true end end
            pcall(function() VU:Button1Down(Vector2.new(0,0),workspace.CurrentCamera.CFrame) task.wait(0.1) VU:Button1Up(Vector2.new(0,0),workspace.CurrentCamera.CFrame) end)
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- ── UI ───────────────────────────────────────────────────────
-- ═══════════════════════════════════════════════════════════════
local C={
    bg=Color3.fromRGB(16,18,26), panel=Color3.fromRGB(25,28,40),
    head=Color3.fromRGB(35,39,56), soft=Color3.fromRGB(45,50,70),
    accent=Color3.fromRGB(78,132,255), green=Color3.fromRGB(64,189,115),
    red=Color3.fromRGB(214,78,78), gold=Color3.fromRGB(225,180,62),
    purple=Color3.fromRGB(190,70,220), text=Color3.fromRGB(235,239,248),
    sub=Color3.fromRGB(145,150,170), stroke=Color3.fromRGB(50,55,76),
    active=Color3.fromRGB(42,83,55),
}
local function rnd(i,r) local c=Instance.new("UICorner") c.CornerRadius=UDim.new(0,r or 8) c.Parent=i end
local function brd(i) local s=Instance.new("UIStroke") s.Color=C.stroke s.Parent=i end
local function frm(p,sz,pos,col)
    local f=Instance.new("Frame") f.Size=sz f.Position=pos or UDim2.new()
    f.BackgroundColor3=col or C.panel f.BorderSizePixel=0 f.Parent=p return f
end
local function lbl(p,txt,sz,pos,col,ts,fn)
    local l=Instance.new("TextLabel") l.Size=sz l.Position=pos or UDim2.new()
    l.BackgroundTransparency=1 l.Text=txt l.TextColor3=col or C.text
    l.TextSize=ts or 12 l.Font=fn or Enum.Font.GothamMedium
    l.TextWrapped=true l.TextXAlignment=Enum.TextXAlignment.Left l.Parent=p return l
end
local function btn(p,txt,sz,pos,col,fn)
    local b=Instance.new("TextButton") b.Size=sz b.Position=pos or UDim2.new()
    b.BackgroundColor3=col or C.accent b.BorderSizePixel=0 b.Text=txt
    b.TextColor3=C.text b.TextSize=12 b.Font=Enum.Font.GothamBold b.Parent=p
    rnd(b,7) if fn then b.MouseButton1Click:Connect(fn) end return b
end
local function sec(p,t) lbl(p,t:upper(),UDim2.new(1,0,0,16),nil,C.sub,10,Enum.Font.GothamBold) end

-- Toggle helper: tạo toggle row, trả về pill để update từ ngoài
local function togRow(p,title,desc,key,onChange)
    local r=frm(p,UDim2.new(1,0,0,62),nil,C.panel) rnd(r,9) brd(r)
    lbl(r,title,UDim2.new(1,-74,0,20),UDim2.new(0,12,0,8),C.text,13,Enum.Font.GothamBold)
    lbl(r,desc,UDim2.new(1,-74,0,16),UDim2.new(0,12,0,30),C.sub,11)
    local pill=Instance.new("TextButton") pill.Size=UDim2.new(0,44,0,22)
    pill.Position=UDim2.new(1,-56,0.5,-11) pill.BorderSizePixel=0 pill.Text=""
    pill.BackgroundColor3=Config[key] and C.green or C.soft pill.Parent=r rnd(pill,11)
    local knob=frm(pill,UDim2.new(0,16,0,16),Config[key] and UDim2.new(0,25,0.5,-8) or UDim2.new(0,3,0.5,-8),Color3.fromRGB(236,238,245)) rnd(knob,8)
    local function refresh()
        TweenSvc:Create(pill,TweenInfo.new(0.15),{BackgroundColor3=Config[key] and C.green or C.soft}):Play()
        TweenSvc:Create(knob,TweenInfo.new(0.15),{Position=Config[key] and UDim2.new(0,25,0.5,-8) or UDim2.new(0,3,0.5,-8)}):Play()
    end
    pill.MouseButton1Click:Connect(function()
        Config[key]=not Config[key]
        refresh() saveConfig()
        if onChange then onChange(Config[key]) end
    end)
    return pill, knob, refresh
end

-- ── SCREENGUI ────────────────────────────────────────────────
local SG=Instance.new("ScreenGui") SG.Name=UI_NAME SG.ResetOnSpawn=false
SG.ZIndexBehavior=Enum.ZIndexBehavior.Sibling SG.DisplayOrder=100
local ok=pcall(function() SG.Parent=CoreGui end)
if not ok or not SG.Parent then SG.Parent=LP:WaitForChild("PlayerGui") end

local Win=frm(SG,UDim2.new(0,360,0,0),UDim2.new(0.03,0,0.07,0),C.bg)
Win.AutomaticSize=Enum.AutomaticSize.Y rnd(Win,12) brd(Win)

local Head=frm(Win,UDim2.new(1,0,0,50),nil,C.head) rnd(Head,12)
frm(Head,UDim2.new(1,0,0,12),UDim2.new(0,0,1,-12),C.head)
lbl(Head,"Defend Your Castle",UDim2.new(1,-100,0,22),UDim2.new(0,14,0,6),C.text,14,Enum.Font.GothamBold)
lbl(Head,"v5.0 | RightShift = toggle",UDim2.new(1,-100,0,14),UDim2.new(0,14,0,30),C.sub,10)
btn(Head,"X",UDim2.new(0,26,0,26),UDim2.new(1,-34,0.5,-13),C.red,function() Win.Visible=false end)

local Body=frm(Win,UDim2.new(1,-20,0,0),UDim2.new(0,10,0,58),Color3.new())
Body.BackgroundTransparency=1 Body.AutomaticSize=Enum.AutomaticSize.Y
local BL=Instance.new("UIListLayout") BL.Padding=UDim.new(0,6) BL.Parent=Body

-- ── TABBAR ───────────────────────────────────────────────────
local TabBar=frm(Body,UDim2.new(1,0,0,30),nil,C.panel) rnd(TabBar,8)
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
    tb.Parent=TabBar rnd(tb,6)
    local p=frm(Body,UDim2.new(1,0,0,0),nil,Color3.new())
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

-- ════════════════════════════════════════════════════════════
-- PAGE: MAIN
-- ════════════════════════════════════════════════════════════
sec(Main,"Core Features")
togRow(Main,"Anti-AFK","Jump + click mỗi 50s để tránh bị kick","AntiAFK")
togRow(Main,"Auto Buy","Tự động mua Blueprint còn hàng trong shop","AutoBuy")

-- Auto Challenge master toggle
togRow(Main,"Auto Challenge",
    "Gạt ON → tự động chạy các challenge đã chọn",
    "AutoChallenge",
    function(on)
        if on then
            if not challLoopRunning then
                task.spawn(ChallengeLoop)
            end
        else
            log("AutoChallenge OFF")
        end
    end
)

sec(Main,"Session Stats")
local StatBox=frm(Main,UDim2.new(1,0,0,72),nil,C.panel) rnd(StatBox,9) brd(StatBox)
local L_Bought  = lbl(StatBox,"📄 Prints bought: 0",   UDim2.new(1,-12,0,16),UDim2.new(0,12,0,6), C.green,12)
local L_LastBuy = lbl(StatBox,"Last: —",               UDim2.new(1,-12,0,14),UDim2.new(0,12,0,24),C.sub,11)
local L_Chall   = lbl(StatBox,"⚔️ Challenges done: 0", UDim2.new(1,-12,0,16),UDim2.new(0,12,0,42),C.gold,12)

sec(Main,"Status")
local StatusBox=frm(Main,UDim2.new(1,0,0,44),nil,C.panel) rnd(StatusBox,8)
local L_Status  = lbl(StatusBox,"● Ready",       UDim2.new(1,-12,0,16),UDim2.new(0,10,0,4), C.sub,11,Enum.Font.GothamMedium)
local L_Current = lbl(StatusBox,"Challenge: —",  UDim2.new(1,-12,0,16),UDim2.new(0,10,0,24),C.sub,11)

-- ════════════════════════════════════════════════════════════
-- PAGE: BUY
-- ════════════════════════════════════════════════════════════
sec(Buy,"Mode")
local ModeBox=frm(Buy,UDim2.new(1,0,0,62),nil,C.panel) rnd(ModeBox,9) brd(ModeBox)
lbl(ModeBox,"Mua tất cả items",UDim2.new(1,-74,0,20),UDim2.new(0,12,0,8),C.text,13,Enum.Font.GothamBold)
lbl(ModeBox,"ON=mua tất cả có stock | OFF=chỉ item đã chọn dưới",UDim2.new(1,-74,0,28),UDim2.new(0,12,0,28),C.sub,11)
local BAP=Instance.new("TextButton") BAP.Size=UDim2.new(0,44,0,22) BAP.Position=UDim2.new(1,-56,0.5,-11)
BAP.BorderSizePixel=0 BAP.Text="" BAP.BackgroundColor3=Config.BuyAllItems and C.green or C.soft BAP.Parent=ModeBox rnd(BAP,11)
local BAK=frm(BAP,UDim2.new(0,16,0,16),Config.BuyAllItems and UDim2.new(0,25,0.5,-8) or UDim2.new(0,3,0.5,-8),Color3.fromRGB(236,238,245)) rnd(BAK,8)
BAP.MouseButton1Click:Connect(function()
    Config.BuyAllItems=not Config.BuyAllItems
    TweenSvc:Create(BAP,TweenInfo.new(0.15),{BackgroundColor3=Config.BuyAllItems and C.green or C.soft}):Play()
    TweenSvc:Create(BAK,TweenInfo.new(0.15),{Position=Config.BuyAllItems and UDim2.new(0,25,0.5,-8) or UDim2.new(0,3,0.5,-8)}):Play()
    saveConfig()
end)

sec(Buy,"Items")
local BuyBtnRow=frm(Buy,UDim2.new(1,0,0,28),nil,Color3.new()) BuyBtnRow.BackgroundTransparency=1
local BBL=Instance.new("UIListLayout") BBL.FillDirection=Enum.FillDirection.Horizontal BBL.Padding=UDim.new(0,6) BBL.Parent=BuyBtnRow
local ShopInfo=lbl(Buy,"Nhấn Refresh để load shop.",UDim2.new(1,0,0,16),nil,C.sub,11)
local Grid=frm(Buy,UDim2.new(1,0,0,0),nil,Color3.new()) Grid.BackgroundTransparency=1 Grid.AutomaticSize=Enum.AutomaticSize.Y
local GL=Instance.new("UIGridLayout") GL.CellSize=UDim2.new(0.5,-4,0,30) GL.CellPadding=UDim2.new(0,4,0,4) GL.Parent=Grid

local function rebuildShop()
    for _,c in ipairs(Grid:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
    local items=sortedShop()
    ShopInfo.Text=(#items==0) and "No shop data." or ("Shop: "..#items.." items")
    for _,e in ipairs(items) do
        local sel=isSelected(e.name)
        local b=Instance.new("TextButton") b.Size=UDim2.new(1,0,0,30) b.BorderSizePixel=0
        b.Text=e.name..(e.qty>0 and " ["..e.qty.."]" or " [0]")
        b.TextSize=11 b.Font=Enum.Font.GothamMedium b.TextTruncate=Enum.TextTruncate.AtEnd
        b.BackgroundColor3=sel and C.active or C.soft
        b.TextColor3=sel and C.green or C.sub b.Parent=Grid rnd(b,6) brd(b)
        b.MouseButton1Click:Connect(function() toggleItem(e.name) rebuildShop() end)
    end
end

btn(BuyBtnRow,"🔄 Refresh",UDim2.new(0.5,-3,1,0),nil,C.accent,function() fetchShop() rebuildShop() end)
btn(BuyBtnRow,"⚡ Buy Once",UDim2.new(0.5,-3,1,0),UDim2.new(0.5,3,0,0),C.green,function() task.spawn(function() autoBuyOnce() fetchShop() rebuildShop() end) end)

-- ════════════════════════════════════════════════════════════
-- PAGE: CHALLENGE
-- ════════════════════════════════════════════════════════════
sec(Chall,"Chọn Difficulties")

-- Info card
local CInfoBox=frm(Chall,UDim2.new(1,0,0,52),nil,C.panel) rnd(CInfoBox,9) brd(CInfoBox)
lbl(CInfoBox,"Gạt ON các difficulty muốn chạy.",UDim2.new(1,-12,0,16),UDim2.new(0,10,0,4),C.text,12,Enum.Font.GothamBold)
lbl(CInfoBox,"Script: kiểm tra cooldown → end raid → challenge → next → restart raid",UDim2.new(1,-12,0,28),UDim2.new(0,10,0,22),C.sub,11)

-- Challenge toggle rows
local challUIData = {} -- key -> {badgeLbl}

for _, def in ipairs(CHALLDEFS) do
    local r=frm(Chall,UDim2.new(1,0,0,56),nil,C.panel) rnd(r,9) brd(r)
    -- Color bar bên trái
    local bar=frm(r,UDim2.new(0,3,0.7,0),UDim2.new(0,0,0.15,0),def.col) rnd(bar,2)
    lbl(r,def.label,UDim2.new(0,130,0,20),UDim2.new(0,14,0,7),C.text,13,Enum.Font.GothamBold)
    lbl(r,def.waves.." Waves  •  Difficulty: "..def.diff,UDim2.new(0,200,0,15),UDim2.new(0,14,0,30),C.sub,10)
    local badgeLbl=lbl(r,"—",UDim2.new(0,70,0,16),UDim2.new(0,190,0,12),C.sub,10,Enum.Font.GothamMedium)

    -- Toggle pill
    local pill=Instance.new("TextButton") pill.Size=UDim2.new(0,44,0,22)
    pill.Position=UDim2.new(1,-54,0.5,-11) pill.BorderSizePixel=0 pill.Text=""
    pill.BackgroundColor3=Config[def.key] and C.green or C.soft pill.Parent=r rnd(pill,11)
    local knob=frm(pill,UDim2.new(0,16,0,16),Config[def.key] and UDim2.new(0,25,0.5,-8) or UDim2.new(0,3,0.5,-8),Color3.fromRGB(236,238,245)) rnd(knob,8)

    pill.MouseButton1Click:Connect(function()
        Config[def.key]=not Config[def.key]
        TweenSvc:Create(pill,TweenInfo.new(0.15),{BackgroundColor3=Config[def.key] and C.green or C.soft}):Play()
        TweenSvc:Create(knob,TweenInfo.new(0.15),{Position=Config[def.key] and UDim2.new(0,25,0.5,-8) or UDim2.new(0,3,0.5,-8)}):Play()
        saveConfig()
        -- Nếu AutoChallenge đang ON và loop chưa chạy -> kick off
        if Config.AutoChallenge and not challLoopRunning then
            task.spawn(ChallengeLoop)
        end
        log((Config[def.key] and "✅ " or "❌ ").."Toggled: "..def.label)
    end)

    challUIData[def.key] = { badge=badgeLbl, pill=pill, knob=knob }
end

-- Status bar challenge
sec(Chall,"Queue Status")
local CStatusBox=frm(Chall,UDim2.new(1,0,0,44),nil,C.panel) rnd(CStatusBox,8)
local L_QueueStatus = lbl(CStatusBox,"Queue: idle",         UDim2.new(1,-12,0,16),UDim2.new(0,10,0,4), C.sub,11,Enum.Font.GothamMedium)
local L_QueueCurrent= lbl(CStatusBox,"Current: —",          UDim2.new(1,-12,0,16),UDim2.new(0,10,0,24),C.sub,11)

-- Manual buttons
sec(Chall,"Manual")
local CBtnRow=frm(Chall,UDim2.new(1,0,0,28),nil,Color3.new()) CBtnRow.BackgroundTransparency=1
local CBRL=Instance.new("UIListLayout") CBRL.FillDirection=Enum.FillDirection.Horizontal CBRL.Padding=UDim.new(0,6) CBRL.Parent=CBtnRow

btn(CBtnRow,"🔴 End Raid",UDim2.new(0.33,-4,1,0),nil,C.red,function()
    task.spawn(DoEndRaid)
end)
btn(CBtnRow,"🟢 Start Raid",UDim2.new(0.33,-4,1,0),UDim2.new(0.33,2,0,0),C.green,function()
    task.spawn(DoStartRaid)
end)
btn(CBtnRow,"⏹ End Chall",UDim2.new(0.34,-2,1,0),UDim2.new(0.66,4,0,0),C.soft,function()
    pcall(function() RF_EndChallenge:InvokeServer() end)
    State.ChallengeActive=false
    log("EndChallenge manual")
end)

-- ════════════════════════════════════════════════════════════
-- PAGE: DEBUG
-- ════════════════════════════════════════════════════════════
sec(Debug,"Runtime")
local DBox=frm(Debug,UDim2.new(1,0,0,100),nil,C.panel) rnd(DBox,9) brd(DBox)
local DL={} for i=0,4 do DL[i+1]=lbl(DBox,"",UDim2.new(1,-12,0,16),UDim2.new(0,10,0,4+i*19),C.sub,11) end

sec(Debug,"Actions")
local DBARow=frm(Debug,UDim2.new(1,0,0,28),nil,Color3.new()) DBARow.BackgroundTransparency=1
local DBAL=Instance.new("UIListLayout") DBAL.FillDirection=Enum.FillDirection.Horizontal DBAL.Padding=UDim.new(0,6) DBAL.Parent=DBARow
btn(DBARow,"💾 Save Config",UDim2.new(0.5,-3,1,0),nil,C.accent,saveConfig)
btn(DBARow,"🔄 Shop",UDim2.new(0.5,-3,1,0),UDim2.new(0.5,3,0,0),C.gold,function() fetchShop() rebuildShop() end)

sec(Debug,"Logs")
local LogBox=frm(Debug,UDim2.new(1,0,0,200),nil,C.panel) rnd(LogBox,9) brd(LogBox)
local LogLbl=lbl(LogBox,"",UDim2.new(1,-12,1,-12),UDim2.new(0,10,0,6),C.sub,11,Enum.Font.Code)
LogLbl.TextYAlignment=Enum.TextYAlignment.Top

-- ═══════════════════════════════════════════════════════════════
-- UPDATE LOOP
-- ═══════════════════════════════════════════════════════════════
task.spawn(function()
    while true do
        task.wait(0.5)
        pcall(function()
            -- Main page
            L_Bought.Text  = "📄 Prints bought: "..State.Bought
            L_LastBuy.Text = "Last: "..State.LastBuy
            L_Chall.Text   = "⚔️ Challenges done: "..State.Challenges
            L_Status.Text  = "● "..(challLoopRunning and "Challenge loop running" or (Config.AutoBuy and "Auto buy active" or "Idle"))
            L_Current.Text = "Challenge: "..State.ChallCurrent

            -- Challenge page
            if challLoopRunning then
                L_QueueStatus.Text = "⚔️ Queue: RUNNING"
                L_QueueStatus.TextColor3 = C.green
            else
                L_QueueStatus.Text = "Queue: idle"
                L_QueueStatus.TextColor3 = C.sub
            end
            L_QueueCurrent.Text = "Current: "..State.ChallCurrent

            -- Per-challenge badge
            local cd = GetCooldownSeconds()
            for _, def in ipairs(CHALLDEFS) do
                local ud = challUIData[def.key]
                if ud then
                    if State.ChallCurrent:find(def.label) and challLoopRunning then
                        ud.badge.Text = "⚔️ running"
                        ud.badge.TextColor3 = C.green
                    elseif cd > 0 then
                        ud.badge.Text = string.format("⏳%ds", cd)
                        ud.badge.TextColor3 = C.gold
                    else
                        ud.badge.Text = Config[def.key] and "✅ queued" or "—"
                        ud.badge.TextColor3 = Config[def.key] and C.green or C.sub
                    end
                end
            end

            -- Debug page
            local inRaid=IsInRaid()
            local cd2=GetCooldownSeconds()
            DL[1].Text="InRaid: "..tostring(inRaid).."  |  Cooldown: "..cd2.."s"
            DL[2].Text="ChallActive: "..tostring(State.ChallengeActive).."  |  Loop: "..tostring(challLoopRunning)
            DL[3].Text="Config save: "..State.LastSave
            DL[4].Text="LastError: "..State.LastError
            DL[5].Text="Remotes: Shop✓ Buy✓ Start✓ RaidEnd✓ RaidStart✓"
            LogLbl.Text=table.concat(State.Logs,"\n")
        end)
    end
end)

-- ── DRAG ─────────────────────────────────────────────────────
local dragging,ds,sp=false,nil,nil
Head.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        dragging=true ds=i.Position sp=Win.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
        local d=i.Position-ds Win.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=false end
end)
UIS.InputBegan:Connect(function(i,gp)
    if not gp and i.KeyCode==Enum.KeyCode.RightShift then Win.Visible=not Win.Visible end
end)

-- ── INIT ─────────────────────────────────────────────────────
task.spawn(function() fetchShop() rebuildShop() end)
log("v5.0 ready")
log("Challenge: RaidEnd → StartChallenge(diff) → wait ChallengeEnd → next → RaidStart")
