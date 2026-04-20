--[[
    DEFEND YOUR CASTLE - Auto Script v2.0
    GitHub: Minhtam-cr21/DefenseYourCastle

    Confirmed remotes:
    - UpdateCurrentShop -> returns {itemName = qty, ...}
    - BuyDefense(itemName, qty) -> mua item
    - StartChallenge() -> bắt đầu challenge (result=false = đang trong raid, cần EndChallenge trước)
    - EndChallenge() -> kết thúc challenge hiện tại
    - Remotes.ChallengeEnd -> event khi challenge xong
--]]

-- ============================================================
-- SERVICES
-- ============================================================
local Players            = game:GetService("Players")
local TweenService       = game:GetService("TweenService")
local UserInputService   = game:GetService("UserInputService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local LP = Players.LocalPlayer

-- ============================================================
-- CLEANUP khi re-execute
-- ============================================================
for _, loc in ipairs({game:GetService("CoreGui"), LP.PlayerGui}) do
    local old = loc:FindFirstChild("DYC_UI")
    if old then old:Destroy() end
end

-- ============================================================
-- REMOTES
-- ============================================================
local Events    = ReplicatedStorage:WaitForChild("Events")
local Functions = Events:WaitForChild("Functions")
local Remotes   = Events:WaitForChild("Remotes")

local RF_UpdateShop      = Functions:WaitForChild("UpdateCurrentShop")
local RF_BuyDefense      = Functions:WaitForChild("BuyDefense")
local RF_StartChallenge  = Functions:WaitForChild("StartChallenge")
local RF_EndChallenge    = Functions:WaitForChild("EndChallenge")
local RE_ChallengeEnd    = Remotes:FindFirstChild("ChallengeEnd")

print("[DYC] Remotes loaded OK")

-- ============================================================
-- CONFIG (save/load bằng writefile/readfile)
-- ============================================================
local CONFIG_PATH = "DYC_Config.json"

local DEFAULT_CONFIG = {
    AntiAFK           = false,
    AutoBuy           = false,
    AutoChallenge     = false,
    ChallengeDifficulty = "Easy",  -- Easy | Medium | Pro
    BuyDelay          = 3,         -- giây giữa mỗi lần mua
    SelectedItems     = {},        -- {"Crossbow", "Cannon", ...} rỗng = mua tất cả
}

local function SaveConfig(cfg)
    pcall(function()
        local ok, enc = pcall(function()
            -- encode JSON thủ công (không có thư viện)
            local parts = {}
            for k, v in pairs(cfg) do
                local val
                if type(v) == "boolean" then
                    val = v and "true" or "false"
                elseif type(v) == "number" then
                    val = tostring(v)
                elseif type(v) == "string" then
                    val = '"' .. v .. '"'
                elseif type(v) == "table" then
                    local arr = {}
                    for _, item in ipairs(v) do
                        table.insert(arr, '"' .. tostring(item) .. '"')
                    end
                    val = "[" .. table.concat(arr, ",") .. "]"
                end
                if val then
                    table.insert(parts, '"' .. k .. '":' .. val)
                end
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end)
        if ok then writefile(CONFIG_PATH, enc) end
    end)
end

local function LoadConfig()
    local cfg = {}
    -- copy defaults
    for k, v in pairs(DEFAULT_CONFIG) do
        if type(v) == "table" then
            cfg[k] = {}
            for _, item in ipairs(v) do table.insert(cfg[k], item) end
        else
            cfg[k] = v
        end
    end

    pcall(function()
        if not isfile(CONFIG_PATH) then return end
        local raw = readfile(CONFIG_PATH)
        if not raw or raw == "" then return end

        -- parse JSON thủ công
        -- booleans
        for k in pairs(DEFAULT_CONFIG) do
            if type(DEFAULT_CONFIG[k]) == "boolean" then
                local val = raw:match('"' .. k .. '"%s*:%s*(true|false)')
                if val then cfg[k] = (val == "true") end
            elseif type(DEFAULT_CONFIG[k]) == "number" then
                local val = raw:match('"' .. k .. '"%s*:%s*([%d%.]+)')
                if val then cfg[k] = tonumber(val) end
            elseif type(DEFAULT_CONFIG[k]) == "string" then
                local val = raw:match('"' .. k .. '"%s*:%s*"([^"]*)"')
                if val then cfg[k] = val end
            elseif type(DEFAULT_CONFIG[k]) == "table" then
                local arr = raw:match('"' .. k .. '"%s*:%s*%[([^%]]*)%]')
                if arr then
                    cfg[k] = {}
                    for item in arr:gmatch('"([^"]*)"') do
                        table.insert(cfg[k], item)
                    end
                end
            end
        end
    end)

    return cfg
end

-- Load config ngay khi khởi động
local Config = LoadConfig()

-- ============================================================
-- STATE
-- ============================================================
local Stats = { Bought = 0, Challenges = 0 }
local challengeActive = false
local allShopItems = {}  -- được cập nhật từ UpdateCurrentShop

-- ============================================================
-- REMOTE: LẤY DANH SÁCH SHOP
-- ============================================================
local function FetchShop()
    local ok, result = pcall(function()
        return RF_UpdateShop:InvokeServer()
    end)
    if ok and type(result) == "table" then
        allShopItems = result
        return result
    end
    return {}
end

-- ============================================================
-- CORE: AUTO BUY
-- ============================================================
-- BuyDefense nhận: (defenseName: string, quantity: number)
-- UpdateCurrentShop trả về {defenseName = qty}
-- Chỉ mua những item có qty > 0 VÀ nằm trong SelectedItems (nếu có chọn)

local function IsItemSelected(name)
    if #Config.SelectedItems == 0 then
        return true -- không filter = mua tất
    end
    for _, sel in ipairs(Config.SelectedItems) do
        if sel == name then return true end
    end
    return false
end

local function DoBuyAll()
    local shop = FetchShop()
    local bought = 0

    for itemName, qty in pairs(shop) do
        if type(qty) == "number" and qty > 0 and IsItemSelected(itemName) then
            local ok, result = pcall(function()
                return RF_BuyDefense:InvokeServer(itemName, qty)
            end)
            if ok then
                bought = bought + qty
                Stats.Bought = Stats.Bought + qty
                print("[DYC] Bought: " .. itemName .. " x" .. qty)
            else
                print("[DYC] BuyDefense error: " .. tostring(result))
            end
            task.wait(0.2)
        end
    end

    return bought
end

task.spawn(function()
    while true do
        task.wait(Config.BuyDelay)
        if Config.AutoBuy then
            local n = DoBuyAll()
            if n > 0 then
                print("[DYC] AutoBuy cycle: bought " .. n .. " items")
            end
        end
    end
end)

-- ============================================================
-- CORE: AUTO CHALLENGE
-- ============================================================
-- StartChallenge result=false khi đang trong raid → cần EndChallenge trước
-- Difficulty: game không nhận string → thử fire không tham số

if RE_ChallengeEnd then
    RE_ChallengeEnd.OnClientEvent:Connect(function()
        challengeActive = false
        print("[DYC] ChallengeEnd event received")
    end)
end

local function TryStartChallenge()
    if challengeActive then return end

    -- Bước 1: End challenge hiện tại (nếu có) để clear state
    pcall(function() RF_EndChallenge:InvokeServer() end)
    task.wait(1)

    -- Bước 2: Start challenge
    -- Difficulty map (từ scan: tất cả string đều return false → thử không args)
    local diffMap = {
        Easy   = 1,
        Medium = 2,
        Pro    = 3,
    }
    local diffNum = diffMap[Config.ChallengeDifficulty] or 1

    -- Thử với số
    local ok1, r1 = pcall(function()
        return RF_StartChallenge:InvokeServer(diffNum)
    end)
    print("[DYC] StartChallenge(" .. diffNum .. ") -> " .. tostring(ok1) .. " / " .. tostring(r1))

    -- Nếu số không work, thử không args
    if not ok1 or r1 == false then
        local ok2, r2 = pcall(function()
            return RF_StartChallenge:InvokeServer()
        end)
        print("[DYC] StartChallenge() -> " .. tostring(ok2) .. " / " .. tostring(r2))
        if ok2 and r2 ~= false then
            challengeActive = true
        end
    else
        if r1 ~= false then
            challengeActive = true
        end
    end

    if challengeActive then
        Stats.Challenges = Stats.Challenges + 1
        print("[DYC] Challenge started! Total: " .. Stats.Challenges)
        task.delay(300, function() challengeActive = false end)
    end
end

task.spawn(function()
    while true do
        task.wait(8)
        if Config.AutoChallenge then
            TryStartChallenge()
        end
    end
end)

-- ============================================================
-- CORE: ANTI-AFK
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
                local VU = game:GetService("VirtualUser")
                VU:Button1Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
                task.wait(0.1)
                VU:Button1Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
            end)
            print("[DYC] Anti-AFK fired")
        end
    end
end)

-- ============================================================
-- UI THEME
-- ============================================================
local CLR = {
    BG      = Color3.fromRGB(14, 14, 22),
    PANEL   = Color3.fromRGB(22, 22, 34),
    HDR     = Color3.fromRGB(24, 24, 42),
    ACCENT  = Color3.fromRGB(72, 110, 255),
    GREEN   = Color3.fromRGB(50, 190, 105),
    RED     = Color3.fromRGB(200, 52, 52),
    YELLOW  = Color3.fromRGB(240, 185, 40),
    TEXT    = Color3.fromRGB(222, 222, 242),
    SUB     = Color3.fromRGB(108, 108, 140),
    BORDER  = Color3.fromRGB(40, 40, 68),
    TOGOFF  = Color3.fromRGB(46, 46, 68),
    ITEMSEL = Color3.fromRGB(35, 70, 35),
    ITEMDEF = Color3.fromRGB(26, 26, 40),
}

local function Rnd(i, r) local c = Instance.new("UICorner") c.CornerRadius=UDim.new(0,r or 8) c.Parent=i end
local function Strk(i,c,t) local s=Instance.new("UIStroke") s.Color=c or CLR.BORDER s.Thickness=t or 1 s.Parent=i end

local function Frm(p,sz,pos,col)
    local f=Instance.new("Frame") f.Size=sz f.Position=pos or UDim2.new(0,0,0,0)
    f.BackgroundColor3=col or CLR.PANEL f.BorderSizePixel=0 f.Parent=p return f
end

local function Lbl(p,txt,sz,pos,col,fs,fn,xa)
    local l=Instance.new("TextLabel") l.Text=txt l.Size=sz l.Position=pos or UDim2.new(0,0,0,0)
    l.BackgroundTransparency=1 l.TextColor3=col or CLR.TEXT l.TextSize=fs or 13
    l.Font=fn or Enum.Font.GothamMedium l.TextXAlignment=xa or Enum.TextXAlignment.Left
    l.TextWrapped=true l.Parent=p return l
end

local function Btn(p,txt,sz,pos,col,cb)
    local b=Instance.new("TextButton") b.Text=txt b.Size=sz b.Position=pos or UDim2.new(0,0,0,0)
    b.BackgroundColor3=col or CLR.ACCENT b.TextColor3=CLR.TEXT b.TextSize=12
    b.Font=Enum.Font.GothamBold b.BorderSizePixel=0 b.AutoButtonColor=false b.Parent=p
    Rnd(b,7)
    b.MouseEnter:Connect(function()
        TweenService:Create(b,TweenInfo.new(0.15),{BackgroundColor3=Color3.new(
            math.min((col or CLR.ACCENT).R+0.08,1),
            math.min((col or CLR.ACCENT).G+0.08,1),
            math.min((col or CLR.ACCENT).B+0.08,1)
        )}):Play()
    end)
    b.MouseLeave:Connect(function()
        TweenService:Create(b,TweenInfo.new(0.15),{BackgroundColor3=col or CLR.ACCENT}):Play()
    end)
    if cb then b.MouseButton1Click:Connect(cb) end
    return b
end

-- ============================================================
-- SCREENGUI
-- ============================================================
local SG = Instance.new("ScreenGui")
SG.Name = "DYC_UI"
SG.ResetOnSpawn = false
SG.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
SG.DisplayOrder = 100
local ok = pcall(function() SG.Parent = game:GetService("CoreGui") end)
if not ok or not SG.Parent then SG.Parent = LP.PlayerGui end
print("[DYC] ScreenGui in: " .. SG.Parent.Name)

-- ============================================================
-- MAIN WINDOW
-- ============================================================
local Win = Frm(SG, UDim2.new(0,320,0,0), UDim2.new(0.04,0,0.08,0), CLR.BG)
Win.AutomaticSize = Enum.AutomaticSize.Y
Rnd(Win, 12)
Strk(Win, CLR.BORDER, 1)

-- HEADER
local Hdr = Frm(Win, UDim2.new(1,0,0,48), UDim2.new(0,0,0,0), CLR.HDR)
Rnd(Hdr, 12)
Frm(Hdr, UDim2.new(1,0,0,12), UDim2.new(0,0,1,-12), CLR.HDR)

Lbl(Hdr,"🏰  Defend Your Castle",UDim2.new(1,-96,0,26),UDim2.new(0,14,0,5),CLR.TEXT,14,Enum.Font.GothamBold)
Lbl(Hdr,"v2.0  •  RightShift = ẩn/hiện",UDim2.new(1,-96,0,14),UDim2.new(0,14,0,30),CLR.SUB,10,Enum.Font.Gotham)

local function HdrBtn(txt, xOff, col, cb)
    local b = Btn(Hdr, txt, UDim2.new(0,26,0,26), UDim2.new(1,xOff,0.5,-13), col, cb)
    return b
end
HdrBtn("✕", -32, CLR.RED, function() Win.Visible = false end)
local minBtn = HdrBtn("−", -62, CLR.TOGOFF, nil)

-- BODY
local Body = Frm(Win, UDim2.new(1,-20,0,0), UDim2.new(0,10,0,56), Color3.new(0,0,0))
Body.BackgroundTransparency = 1
Body.AutomaticSize = Enum.AutomaticSize.Y

local bodyLayout = Instance.new("UIListLayout")
bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
bodyLayout.Padding = UDim.new(0,6)
bodyLayout.Parent = Body

local bodyPad = Instance.new("UIPadding")
bodyPad.PaddingBottom = UDim.new(0,12)
bodyPad.Parent = Body

local bodyVisible = true
minBtn.MouseButton1Click:Connect(function()
    bodyVisible = not bodyVisible
    Body.Visible = bodyVisible
end)

-- ============================================================
-- TAB SYSTEM
-- ============================================================
local tabOrder = 0
local tabs = {}
local pages = {}
local activeTab = nil

-- Tab bar
local TabBar = Frm(Body, UDim2.new(1,0,0,30), nil, CLR.PANEL)
TabBar.LayoutOrder = 0
Rnd(TabBar, 8)

local tbLayout = Instance.new("UIListLayout")
tbLayout.FillDirection = Enum.FillDirection.Horizontal
tbLayout.SortOrder = Enum.SortOrder.LayoutOrder
tbLayout.Padding = UDim.new(0,3)
tbLayout.VerticalAlignment = Enum.VerticalAlignment.Center
tbLayout.Parent = TabBar

local tbPad = Instance.new("UIPadding")
tbPad.PaddingLeft = UDim.new(0,4)
tbPad.Parent = TabBar

local function SetActiveTab(name)
    for tname, page in pairs(pages) do
        page.Visible = (tname == name)
    end
    for tname, tbtn in pairs(tabs) do
        TweenService:Create(tbtn, TweenInfo.new(0.15), {
            BackgroundColor3 = tname == name and CLR.ACCENT or CLR.TOGOFF,
            TextColor3 = tname == name and CLR.TEXT or CLR.SUB,
        }):Play()
    end
    activeTab = name
end

local pageOrder = 1
local function MakeTab(name, icon)
    tabOrder = tabOrder + 1
    local tbtn = Instance.new("TextButton")
    tbtn.Text = (icon and icon.." " or "") .. name
    tbtn.Size = UDim2.new(0,88,1,-6)
    tbtn.BackgroundColor3 = CLR.TOGOFF
    tbtn.TextColor3 = CLR.SUB
    tbtn.TextSize = 12
    tbtn.Font = Enum.Font.GothamMedium
    tbtn.BorderSizePixel = 0
    tbtn.LayoutOrder = tabOrder
    tbtn.Parent = TabBar
    Rnd(tbtn, 6)

    pageOrder = pageOrder + 1
    local page = Frm(Body, UDim2.new(1,0,0,0), nil, Color3.new(0,0,0))
    page.BackgroundTransparency = 1
    page.AutomaticSize = Enum.AutomaticSize.Y
    page.LayoutOrder = pageOrder
    page.Visible = false

    local pl = Instance.new("UIListLayout")
    pl.SortOrder = Enum.SortOrder.LayoutOrder
    pl.Padding = UDim.new(0,6)
    pl.Parent = page

    tabs[name] = tbtn
    pages[name] = page
    tbtn.MouseButton1Click:Connect(function() SetActiveTab(name) end)
    return page
end

-- ============================================================
-- WIDGET HELPERS
-- ============================================================
local function Section(page, txt, order)
    local l = Lbl(page, txt:upper(), UDim2.new(1,0,0,16), nil, CLR.SUB, 10, Enum.Font.GothamBold)
    l.LayoutOrder = order
end

local StatusLbl
local function SetStatus(msg, col)
    if StatusLbl then
        StatusLbl.Text = "● " .. msg
        StatusLbl.TextColor3 = col or CLR.SUB
    end
end

-- Toggle row
local function MakeToggle(page, order, title, desc, flag, onToggle)
    local row = Frm(page, UDim2.new(1,0,0,66), nil, CLR.PANEL)
    row.LayoutOrder = order
    Rnd(row, 9) Strk(row, CLR.BORDER, 1)
    Lbl(row, title, UDim2.new(1,-68,0,22), UDim2.new(0,12,0,10), CLR.TEXT, 13, Enum.Font.GothamBold)
    Lbl(row, desc,  UDim2.new(1,-68,0,18), UDim2.new(0,12,0,34), CLR.SUB, 11, Enum.Font.Gotham)

    local pill = Instance.new("TextButton")
    pill.Text="" pill.Size=UDim2.new(0,44,0,22) pill.Position=UDim2.new(1,-54,0.5,-11)
    pill.BackgroundColor3 = Config[flag] and CLR.GREEN or CLR.TOGOFF
    pill.BorderSizePixel=0 pill.Parent=row
    Rnd(pill,11)

    local knob = Frm(pill, UDim2.new(0,16,0,16),
        Config[flag] and UDim2.new(0,25,0.5,-8) or UDim2.new(0,3,0.5,-8),
        Color3.fromRGB(200,200,220))
    Rnd(knob,8)

    local function Refresh(on)
        TweenService:Create(pill,TweenInfo.new(0.18,Enum.EasingStyle.Quad),{BackgroundColor3=on and CLR.GREEN or CLR.TOGOFF}):Play()
        TweenService:Create(knob,TweenInfo.new(0.18,Enum.EasingStyle.Quad),{Position=on and UDim2.new(0,25,0.5,-8) or UDim2.new(0,3,0.5,-8)}):Play()
    end

    pill.MouseButton1Click:Connect(function()
        Config[flag] = not Config[flag]
        Refresh(Config[flag])
        SaveConfig(Config)
        if onToggle then onToggle(Config[flag]) end
    end)

    return row
end

-- ============================================================
-- PAGE: MAIN
-- ============================================================
local pageMain = MakeTab("Main", "⚡")
SetActiveTab("Main")

Section(pageMain, "Auto Features", 1)

MakeToggle(pageMain, 2, "Anti-AFK", "Tự động hành động mỗi 50s để không bị kick", "AntiAFK",
    function(on) SetStatus(on and "Anti-AFK đang chạy" or "Anti-AFK tắt", on and CLR.GREEN or CLR.RED) end)

MakeToggle(pageMain, 3, "Auto Buy Prints", "Mua Blueprint có stock → xem tab 'Buy' để chọn item", "AutoBuy",
    function(on) SetStatus(on and "Auto Buy đang chạy..." or "Auto Buy tắt", on and CLR.GREEN or CLR.RED) end)

MakeToggle(pageMain, 4, "Auto Challenges", "Tự động bắt đầu Challenge → xem tab 'Chall'", "AutoChallenge",
    function(on) SetStatus(on and "Auto Challenge đang chạy..." or "Auto Challenge tắt", on and CLR.GREEN or CLR.RED) end)

Section(pageMain, "Stats", 5)
local statsRow = Frm(pageMain, UDim2.new(1,0,0,36), nil, CLR.PANEL)
statsRow.LayoutOrder = 6
Rnd(statsRow,9) Strk(statsRow,CLR.BORDER,1)
local bLbl = Lbl(statsRow,"📄 Prints: 0",UDim2.new(0.5,0,1,0),UDim2.new(0,12,0,0),CLR.GREEN,12)
local cLbl = Lbl(statsRow,"⚡ Challenges: 0",UDim2.new(0.5,0,1,0),UDim2.new(0.5,0,0,0),CLR.GREEN,12)
task.spawn(function()
    while true do task.wait(2) pcall(function()
        bLbl.Text="📄 Prints: "..Stats.Bought
        cLbl.Text="⚡ Challenges: "..Stats.Challenges
    end) end
end)

Section(pageMain, "Status", 7)
local statusBar = Frm(pageMain, UDim2.new(1,0,0,28), nil, Color3.fromRGB(16,16,26))
statusBar.LayoutOrder = 8
Rnd(statusBar,8)
StatusLbl = Lbl(statusBar,"● Ready",UDim2.new(1,-12,1,0),UDim2.new(0,10,0,0),CLR.SUB,11,Enum.Font.GothamMedium)

-- ============================================================
-- PAGE: BUY (chọn item)
-- ============================================================
local pageBuy = MakeTab("Buy", "🛒")

-- Danh sách item đầy đủ từ scan
local ALL_ITEMS = {
    "Crossbow","The Shocker","Archer Tower","Flamethrower","Mortar",
    "Mystic Artillery","Cannon","Double Cannon","Mega Tesla","Wizard Tower",
    "Wall","Inferno Beam","Mega Cannon","Railgun","Tesla","Mega Mortar",
    "Double Magma Cannon","Bomb Tower","Magma Cannon","Mega Crossbow",
    "Minigun","Flamespitter","Triple Mortar","Rocket Artillery",
    "Hidden Tesla","Catapult","The Crusher","Volcanic Artillery",
}

local itemOrder = 0
local function BuySection(txt, ord)
    local l = Lbl(pageBuy, txt:upper(), UDim2.new(1,0,0,16), nil, CLR.SUB, 10, Enum.Font.GothamBold)
    l.LayoutOrder = ord
end

itemOrder = itemOrder + 1
BuySection("Chọn item để Auto Buy (rỗng = mua tất)", itemOrder)

itemOrder = itemOrder + 1
local selectHint = Lbl(pageBuy,
    "Bật toggle = chọn mua item đó | Tắt = bỏ qua\nRỗng tất cả = mua mọi item có stock",
    UDim2.new(1,0,0,32), nil, CLR.SUB, 11, Enum.Font.Gotham)
selectHint.LayoutOrder = itemOrder

-- Nút Select All / Clear All
itemOrder = itemOrder + 1
local btnRow = Frm(pageBuy, UDim2.new(1,0,0,30), nil, Color3.new(0,0,0))
btnRow.BackgroundTransparency = 1
btnRow.LayoutOrder = itemOrder
local btnLayout = Instance.new("UIListLayout")
btnLayout.FillDirection = Enum.FillDirection.Horizontal
btnLayout.Padding = UDim.new(0,6)
btnLayout.Parent = btnRow

local itemToggleBtns = {} -- name -> {btn, selected}

local function RefreshItemUI()
    for name, data in pairs(itemToggleBtns) do
        local isSelected = IsItemSelected(name)
        data.selected = isSelected
        TweenService:Create(data.btn, TweenInfo.new(0.15), {
            BackgroundColor3 = isSelected and CLR.ITEMSEL or CLR.ITEMDEF,
            TextColor3 = isSelected and CLR.GREEN or CLR.SUB,
        }):Play()
    end
end

Btn(btnRow, "✅ Chọn tất", UDim2.new(0.5,-3,1,0), nil, CLR.ITEMSEL, function()
    Config.SelectedItems = {}
    for _, name in ipairs(ALL_ITEMS) do
        table.insert(Config.SelectedItems, name)
    end
    SaveConfig(Config)
    RefreshItemUI()
end)

Btn(btnRow, "❌ Bỏ tất", UDim2.new(0.5,-3,1,0), UDim2.new(0.5,3,0,0), CLR.ITEMDEF, function()
    Config.SelectedItems = {}
    SaveConfig(Config)
    RefreshItemUI()
end)

-- Grid items
itemOrder = itemOrder + 1
local grid = Frm(pageBuy, UDim2.new(1,0,0,0), nil, Color3.new(0,0,0))
grid.BackgroundTransparency = 1
grid.AutomaticSize = Enum.AutomaticSize.Y
grid.LayoutOrder = itemOrder

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0.5,-4,0,28)
gridLayout.CellPadding = UDim2.new(0,4,0,4)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = grid

for i, itemName in ipairs(ALL_ITEMS) do
    local isSelected = IsItemSelected(itemName)
    local ibtn = Instance.new("TextButton")
    ibtn.Text = itemName
    ibtn.Size = UDim2.new(1,0,0,28)
    ibtn.BackgroundColor3 = isSelected and CLR.ITEMSEL or CLR.ITEMDEF
    ibtn.TextColor3 = isSelected and CLR.GREEN or CLR.SUB
    ibtn.TextSize = 11
    ibtn.Font = Enum.Font.GothamMedium
    ibtn.BorderSizePixel = 0
    ibtn.LayoutOrder = i
    ibtn.TextTruncate = Enum.TextTruncate.AtEnd
    ibtn.Parent = grid
    Rnd(ibtn, 6)
    Strk(ibtn, CLR.BORDER, 1)

    itemToggleBtns[itemName] = {btn=ibtn, selected=isSelected}

    ibtn.MouseButton1Click:Connect(function()
        -- toggle selection
        local found = false
        for idx, sel in ipairs(Config.SelectedItems) do
            if sel == itemName then
                table.remove(Config.SelectedItems, idx)
                found = true
                break
            end
        end
        if not found then
            table.insert(Config.SelectedItems, itemName)
        end
        SaveConfig(Config)
        RefreshItemUI()
    end)
end

-- ============================================================
-- PAGE: CHALLENGE
-- ============================================================
local pageChall = MakeTab("Chall", "⚔️")

local challOrder = 0
local function ChallSection(txt)
    challOrder = challOrder + 1
    local l = Lbl(pageChall, txt:upper(), UDim2.new(1,0,0,16), nil, CLR.SUB, 10, Enum.Font.GothamBold)
    l.LayoutOrder = challOrder
end

ChallSection("Chọn Difficulty")

challOrder = challOrder + 1
local diffHint = Lbl(pageChall,
    "Script sẽ EndChallenge hiện tại rồi StartChallenge với difficulty đã chọn.",
    UDim2.new(1,0,0,32), nil, CLR.SUB, 11, Enum.Font.Gotham)
diffHint.LayoutOrder = challOrder

local DIFFICULTIES = {"Easy","Medium","Pro"}
local diffBtns = {}

challOrder = challOrder + 1
local diffRow = Frm(pageChall, UDim2.new(1,0,0,36), nil, Color3.new(0,0,0))
diffRow.BackgroundTransparency = 1
diffRow.LayoutOrder = challOrder
local diffLayout = Instance.new("UIListLayout")
diffLayout.FillDirection = Enum.FillDirection.Horizontal
diffLayout.Padding = UDim.new(0,6)
diffLayout.Parent = diffRow

local DIFF_COLORS = {Easy=CLR.GREEN, Medium=CLR.YELLOW, Pro=CLR.RED}

local function RefreshDiffUI()
    for _, diff in ipairs(DIFFICULTIES) do
        local col = Config.ChallengeDifficulty == diff and DIFF_COLORS[diff] or CLR.TOGOFF
        local tcol = Config.ChallengeDifficulty == diff and CLR.TEXT or CLR.SUB
        if diffBtns[diff] then
            TweenService:Create(diffBtns[diff],TweenInfo.new(0.15),{BackgroundColor3=col,TextColor3=tcol}):Play()
        end
    end
end

for _, diff in ipairs(DIFFICULTIES) do
    local isActive = Config.ChallengeDifficulty == diff
    local db = Btn(diffRow, diff,
        UDim2.new(0,88,1,0), nil,
        isActive and DIFF_COLORS[diff] or CLR.TOGOFF,
        function()
            Config.ChallengeDifficulty = diff
            SaveConfig(Config)
            RefreshDiffUI()
            SetStatus("Difficulty: " .. diff, DIFF_COLORS[diff])
        end
    )
    db.TextColor3 = isActive and CLR.TEXT or CLR.SUB
    diffBtns[diff] = db
end
RefreshDiffUI()

ChallSection("Manual Control")

challOrder = challOrder + 1
local challBtnRow = Frm(pageChall, UDim2.new(1,0,0,34), nil, Color3.new(0,0,0))
challBtnRow.BackgroundTransparency = 1
challBtnRow.LayoutOrder = challOrder
local cbl = Instance.new("UIListLayout")
cbl.FillDirection = Enum.FillDirection.Horizontal
cbl.Padding = UDim.new(0,6)
cbl.Parent = challBtnRow

Btn(challBtnRow, "▶ Start Now", UDim2.new(0.5,-3,1,0), nil, CLR.GREEN, function()
    challengeActive = false
    TryStartChallenge()
    SetStatus("Đã thử start challenge!", CLR.GREEN)
end)
Btn(challBtnRow, "⏹ End", UDim2.new(0.5,-3,1,0), UDim2.new(0.5,3,0,0), CLR.RED, function()
    pcall(function() RF_EndChallenge:InvokeServer() end)
    challengeActive = false
    SetStatus("Đã end challenge", CLR.RED)
end)

ChallSection("Status")
challOrder = challOrder + 1
local challStatusBar = Frm(pageChall, UDim2.new(1,0,0,28), nil, Color3.fromRGB(16,16,26))
challStatusBar.LayoutOrder = challOrder
Rnd(challStatusBar,8)
local challLbl = Lbl(challStatusBar, "● Chưa chạy", UDim2.new(1,-12,1,0), UDim2.new(0,10,0,0), CLR.SUB, 11, Enum.Font.GothamMedium)

task.spawn(function()
    while true do task.wait(1) pcall(function()
        challLbl.Text = "● " .. (challengeActive and "Challenge đang chạy..." or "Không có challenge")
        challLbl.TextColor3 = challengeActive and CLR.GREEN or CLR.SUB
    end) end
end)

-- ============================================================
-- DRAG
-- ============================================================
local dragging, dragStart, frameStart = false, nil, nil
Hdr.InputBegan:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then
        dragging=true dragStart=inp.Position frameStart=Win.Position
    end
end)
UserInputService.InputChanged:Connect(function(inp)
    if not dragging then return end
    if inp.UserInputType==Enum.UserInputType.MouseMovement or inp.UserInputType==Enum.UserInputType.Touch then
        local d=inp.Position-dragStart
        Win.Position=UDim2.new(frameStart.X.Scale,frameStart.X.Offset+d.X,frameStart.Y.Scale,frameStart.Y.Offset+d.Y)
    end
end)
UserInputService.InputEnded:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then dragging=false end
end)

-- ============================================================
-- KEYBIND
-- ============================================================
UserInputService.InputBegan:Connect(function(inp,gp)
    if gp then return end
    if inp.KeyCode==Enum.KeyCode.RightShift then Win.Visible=not Win.Visible end
end)

-- ============================================================
-- INIT
-- ============================================================
SetStatus("Script loaded ✅", CLR.GREEN)
task.delay(3, function() SetStatus("Ready") end)
print("[DYC] ✅ v2.0 loaded! Tabs: Main | Buy | Chall")
