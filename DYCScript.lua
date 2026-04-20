--[[
    DEFEND YOUR CASTLE - Auto Script
    GitHub: Minhtam-cr21/DefenseYourCastle

    Remotes (confirmed từ scan):
    - BuyDefense       : ReplicatedStorage.Events.Functions.BuyDefense
    - UpdateCurrentShop: ReplicatedStorage.Events.Functions.UpdateCurrentShop
    - ToggleAutoBuy    : ReplicatedStorage.Events.Functions.ToggleAutoBuy
    - StartChallenge   : ReplicatedStorage.Events.Functions.StartChallenge
    - GetLimStock      : ReplicatedStorage.Events.Functions.GetLimStock
    - BuyLimStock      : ReplicatedStorage.Events.Functions.BuyLimStock
--]]

-- ============================================================
-- SERVICES
-- ============================================================
local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LP = Players.LocalPlayer

-- ============================================================
-- XÓA GUI CŨ (khi re-execute)
-- ============================================================
for _, loc in ipairs({game:GetService("CoreGui"), LP.PlayerGui}) do
    local old = loc:FindFirstChild("DYC_UI")
    if old then old:Destroy() end
end

-- ============================================================
-- REMOTES (đúng tên từ scan)
-- ============================================================
local Functions = ReplicatedStorage:WaitForChild("Events"):WaitForChild("Functions")

local RF = {
    BuyDefense        = Functions:WaitForChild("BuyDefense"),
    UpdateCurrentShop = Functions:WaitForChild("UpdateCurrentShop"),
    ToggleAutoBuy     = Functions:WaitForChild("ToggleAutoBuy"),
    StartChallenge    = Functions:WaitForChild("StartChallenge"),
    EndChallenge      = Functions:WaitForChild("EndChallenge"),
    GetLimStock       = Functions:WaitForChild("GetLimStock"),
    BuyLimStock       = Functions:WaitForChild("BuyLimStock"),
    GetChallengeLeaderboard = Functions:WaitForChild("GetChallengeLeaderboard"),
}

print("[DYC] Remotes loaded OK")

-- ============================================================
-- STATE
-- ============================================================
local T = {
    AutoBuy       = false,
    AutoChallenge = false,
    AntiAFK       = false,
}

local Stats = {
    Bought     = 0,
    Challenges = 0,
}

-- ============================================================
-- CORE: AUTO BUY DEFENSE (Prints/Blueprints)
-- ============================================================
-- BuyDefense nhận tham số: defenseName (string), quantity (number)
-- Game dùng "LimStock" cho shop limited => BuyLimStock
-- Ta dùng UpdateCurrentShop để lấy danh sách hàng có sẵn
-- rồi mua từng cái còn hàng

local function GetShopStock()
    -- UpdateCurrentShop trả về danh sách items trong shop hiện tại
    local ok, result = pcall(function()
        return RF.UpdateCurrentShop:InvokeServer()
    end)
    if ok and result then
        return result
    end
    return nil
end

local function TryBuyAll()
    -- Cách 1: dùng BuyLimStock để mua tất cả limited stock
    local ok1, stock = pcall(function()
        return RF.GetLimStock:InvokeServer()
    end)

    if ok1 and stock and type(stock) == "table" then
        for itemName, qty in pairs(stock) do
            if type(qty) == "number" and qty > 0 then
                for i = 1, qty do
                    pcall(function()
                        RF.BuyLimStock:InvokeServer(itemName)
                    end)
                    task.wait(0.1)
                    Stats.Bought = Stats.Bought + 1
                    print("[DYC] Bought LimStock: " .. tostring(itemName))
                end
            end
        end
        return
    end

    -- Cách 2: BuyDefense trực tiếp (fallback)
    -- Thử fire với các tham số phổ biến của game
    local ok2 = pcall(function()
        RF.BuyDefense:InvokeServer()
    end)
    if ok2 then
        Stats.Bought = Stats.Bought + 1
        print("[DYC] BuyDefense fired (no args)")
    end
end

-- Loop Auto Buy
task.spawn(function()
    while true do
        task.wait(3)
        if T.AutoBuy then
            local ok, err = pcall(TryBuyAll)
            if not ok then
                print("[DYC] AutoBuy error: " .. tostring(err))
            end
        end
    end
end)

-- ============================================================
-- CORE: AUTO CHALLENGE
-- ============================================================
-- StartChallenge: bắt đầu challenge
-- Game có ChallengeEnd remote event (server→client) khi kết thúc

local challengeActive = false

-- Lắng nghe khi challenge kết thúc
local Remotes = ReplicatedStorage:WaitForChild("Events"):WaitForChild("Remotes")
local challengeEndEvent = Remotes:FindFirstChild("ChallengeEnd")

if challengeEndEvent then
    challengeEndEvent.OnClientEvent:Connect(function()
        challengeActive = false
        print("[DYC] Challenge ended (event received)")
    end)
end

local function TryStartChallenge()
    if challengeActive then return end
    local ok, result = pcall(function()
        return RF.StartChallenge:InvokeServer()
    end)
    if ok then
        challengeActive = true
        Stats.Challenges = Stats.Challenges + 1
        print("[DYC] Challenge started! Total: " .. Stats.Challenges)
        -- Reset sau 5 phút phòng trường hợp event không fire
        task.delay(300, function()
            challengeActive = false
        end)
    else
        print("[DYC] StartChallenge error: " .. tostring(result))
    end
end

task.spawn(function()
    while true do
        task.wait(5)
        if T.AutoChallenge then
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
        if T.AntiAFK then
            local char = LP.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    hum.Jump = true
                end
            end
            pcall(function()
                local VU = game:GetService("VirtualUser")
                VU:Button1Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
                task.wait(0.1)
                VU:Button1Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
            end)
            print("[DYC] Anti-AFK triggered")
        end
    end
end)

-- ============================================================
-- UI: THEME
-- ============================================================
local BG     = Color3.fromRGB(16, 16, 24)
local PANEL  = Color3.fromRGB(24, 24, 36)
local HDR    = Color3.fromRGB(26, 26, 44)
local ACCENT = Color3.fromRGB(75, 115, 255)
local GREEN  = Color3.fromRGB(55, 195, 110)
local RED    = Color3.fromRGB(205, 55, 55)
local TEXT   = Color3.fromRGB(225, 225, 245)
local SUBTEXT= Color3.fromRGB(115, 115, 145)
local BORDER = Color3.fromRGB(45, 45, 72)
local TOGOFF = Color3.fromRGB(50, 50, 72)

local function Rnd(inst, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = inst
end

local function Strk(inst, col, t)
    local s = Instance.new("UIStroke")
    s.Color = col or BORDER
    s.Thickness = t or 1
    s.Parent = inst
end

local function Frm(parent, sz, pos, col)
    local f = Instance.new("Frame")
    f.Size = sz
    f.Position = pos or UDim2.new(0,0,0,0)
    f.BackgroundColor3 = col or PANEL
    f.BorderSizePixel = 0
    f.Parent = parent
    return f
end

local function Lbl(parent, txt, sz, pos, col, fs, fn, xa)
    local l = Instance.new("TextLabel")
    l.Text = txt
    l.Size = sz
    l.Position = pos or UDim2.new(0,0,0,0)
    l.BackgroundTransparency = 1
    l.TextColor3 = col or TEXT
    l.TextSize = fs or 13
    l.Font = fn or Enum.Font.GothamMedium
    l.TextXAlignment = xa or Enum.TextXAlignment.Left
    l.TextWrapped = true
    l.Parent = parent
    return l
end

-- ============================================================
-- UI: SCREENGUI
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
-- UI: MAIN WINDOW
-- ============================================================
local Win = Frm(SG, UDim2.new(0,310,0,0), UDim2.new(0.5,-155,0.5,-200), BG)
Win.AutomaticSize = Enum.AutomaticSize.Y
Rnd(Win, 12)
Strk(Win, BORDER, 1)

-- HEADER
local Hdr = Frm(Win, UDim2.new(1,0,0,46), UDim2.new(0,0,0,0), HDR)
Rnd(Hdr, 12)
Frm(Hdr, UDim2.new(1,0,0,12), UDim2.new(0,0,1,-12), HDR) -- patch corners

Lbl(Hdr, "🏰  Defend Your Castle", UDim2.new(1,-90,0,26), UDim2.new(0,14,0,5), TEXT, 14, Enum.Font.GothamBold)
Lbl(Hdr, "Auto Script  •  RightShift = ẩn/hiện", UDim2.new(1,-90,0,14), UDim2.new(0,14,0,30), SUBTEXT, 10, Enum.Font.Gotham)

-- Close btn
local XBtn = Instance.new("TextButton")
XBtn.Text = "✕"
XBtn.Size = UDim2.new(0,26,0,26)
XBtn.Position = UDim2.new(1,-32,0.5,-13)
XBtn.BackgroundColor3 = RED
XBtn.TextColor3 = Color3.new(1,1,1)
XBtn.TextSize = 13
XBtn.Font = Enum.Font.GothamBold
XBtn.BorderSizePixel = 0
XBtn.Parent = Hdr
Rnd(XBtn, 6)
XBtn.MouseButton1Click:Connect(function() Win.Visible = false end)

-- Minimize btn
local MinBtn = Instance.new("TextButton")
MinBtn.Text = "−"
MinBtn.Size = UDim2.new(0,26,0,26)
MinBtn.Position = UDim2.new(1,-62,0.5,-13)
MinBtn.BackgroundColor3 = TOGOFF
MinBtn.TextColor3 = TEXT
MinBtn.TextSize = 15
MinBtn.Font = Enum.Font.GothamBold
MinBtn.BorderSizePixel = 0
MinBtn.Parent = Hdr
Rnd(MinBtn, 6)

-- BODY
local Body = Frm(Win, UDim2.new(1,-20,0,0), UDim2.new(0,10,0,54), Color3.new(0,0,0))
Body.BackgroundTransparency = 1
Body.AutomaticSize = Enum.AutomaticSize.Y

local BodyLayout = Instance.new("UIListLayout")
BodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
BodyLayout.Padding = UDim.new(0,7)
BodyLayout.Parent = Body

local UIPad = Instance.new("UIPadding")
UIPad.PaddingBottom = UDim.new(0,12)
UIPad.Parent = Body

-- Minimize logic
local bodyVisible = true
MinBtn.MouseButton1Click:Connect(function()
    bodyVisible = not bodyVisible
    Body.Visible = bodyVisible
end)

-- ============================================================
-- UI: SECTION LABEL
-- ============================================================
local secOrder = 0
local function Section(txt)
    secOrder = secOrder + 1
    local l = Lbl(Body, txt:upper(), UDim2.new(1,0,0,16), nil, SUBTEXT, 10, Enum.Font.GothamBold)
    l.LayoutOrder = secOrder
    return l
end

-- ============================================================
-- UI: TOGGLE ROW
-- ============================================================
local StatusLbl -- forward ref

local function ToggleRow(title, desc, flag, onToggle)
    secOrder = secOrder + 1
    local row = Frm(Body, UDim2.new(1,0,0,66), nil, PANEL)
    row.LayoutOrder = secOrder
    Rnd(row, 9)
    Strk(row, BORDER, 1)

    Lbl(row, title, UDim2.new(1,-68,0,22), UDim2.new(0,12,0,10), TEXT, 13, Enum.Font.GothamBold)
    Lbl(row, desc,  UDim2.new(1,-68,0,18), UDim2.new(0,12,0,34), SUBTEXT, 11, Enum.Font.Gotham)

    -- Pill
    local pill = Instance.new("TextButton")
    pill.Text = ""
    pill.Size = UDim2.new(0,44,0,22)
    pill.Position = UDim2.new(1,-54,0.5,-11)
    pill.BackgroundColor3 = TOGOFF
    pill.BorderSizePixel = 0
    pill.Parent = row
    Rnd(pill, 11)

    -- Knob
    local knob = Frm(pill, UDim2.new(0,16,0,16), UDim2.new(0,3,0.5,-8), Color3.fromRGB(200,200,220))
    Rnd(knob, 8)

    local isOn = false
    pill.MouseButton1Click:Connect(function()
        isOn = not isOn
        T[flag] = isOn
        local targetBG  = isOn and GREEN or TOGOFF
        local targetPos = isOn and UDim2.new(0,25,0.5,-8) or UDim2.new(0,3,0.5,-8)
        TweenService:Create(pill, TweenInfo.new(0.18,Enum.EasingStyle.Quad), {BackgroundColor3=targetBG}):Play()
        TweenService:Create(knob, TweenInfo.new(0.18,Enum.EasingStyle.Quad), {Position=targetPos}):Play()
        if onToggle then onToggle(isOn) end
    end)

    return row
end

-- ============================================================
-- UI: STATS CARD
-- ============================================================
local function StatsCard()
    secOrder = secOrder + 1
    local card = Frm(Body, UDim2.new(1,0,0,44), nil, PANEL)
    card.LayoutOrder = secOrder
    Rnd(card, 9)
    Strk(card, BORDER, 1)

    local bLbl = Lbl(card, "📄 Prints: 0",      UDim2.new(0.5,0,1,0), UDim2.new(0,12,0,0),   GREEN, 12)
    local cLbl = Lbl(card, "⚡ Challenges: 0",  UDim2.new(0.5,0,1,0), UDim2.new(0.5,0,0,0),  GREEN, 12)

    task.spawn(function()
        while true do
            task.wait(2)
            pcall(function()
                bLbl.Text = "📄 Prints: "     .. Stats.Bought
                cLbl.Text = "⚡ Challenges: " .. Stats.Challenges
            end)
        end
    end)

    return card
end

-- ============================================================
-- UI: STATUS BAR
-- ============================================================
local function StatusBar()
    secOrder = secOrder + 1
    local bar = Frm(Body, UDim2.new(1,0,0,28), nil, Color3.fromRGB(18,18,28))
    bar.LayoutOrder = secOrder
    Rnd(bar, 8)

    StatusLbl = Lbl(bar, "● Ready", UDim2.new(1,-12,1,0), UDim2.new(0,10,0,0), SUBTEXT, 11, Enum.Font.GothamMedium)
    return bar
end

local function SetStatus(msg, col)
    if StatusLbl then
        StatusLbl.Text = "● " .. msg
        StatusLbl.TextColor3 = col or SUBTEXT
    end
end

-- ============================================================
-- BUILD UI
-- ============================================================

Section("Auto Features")

ToggleRow(
    "Anti-AFK",
    "Tự động hành động mỗi 50s để không bị kick",
    "AntiAFK",
    function(on)
        if on then
            SetStatus("Anti-AFK đang chạy", GREEN)
            -- fire ngay 1 lần
            local char = LP.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then hum.Jump = true end
            end
        else
            SetStatus("Anti-AFK tắt", RED)
            task.delay(2, function() SetStatus("Ready") end)
        end
    end
)

ToggleRow(
    "Auto Buy Prints",
    "Tự động mua Blueprint có sẵn trong shop",
    "AutoBuy",
    function(on)
        if on then
            SetStatus("Auto Buy đang chạy...", GREEN)
        else
            SetStatus("Auto Buy tắt", RED)
            task.delay(2, function() SetStatus("Ready") end)
        end
    end
)

ToggleRow(
    "Auto Challenges",
    "Tự động bắt đầu Challenge khi rảnh",
    "AutoChallenge",
    function(on)
        if on then
            SetStatus("Auto Challenge đang chạy...", GREEN)
        else
            SetStatus("Auto Challenge tắt", RED)
            task.delay(2, function() SetStatus("Ready") end)
        end
    end
)

Section("Stats")
StatsCard()

Section("Status")
StatusBar()

-- ============================================================
-- DRAG WINDOW
-- ============================================================
local dragging, dragStart, frameStart = false, nil, nil

Hdr.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1
    or inp.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = inp.Position
        frameStart = Win.Position
    end
end)

UserInputService.InputChanged:Connect(function(inp)
    if not dragging then return end
    if inp.UserInputType == Enum.UserInputType.MouseMovement
    or inp.UserInputType == Enum.UserInputType.Touch then
        local d = inp.Position - dragStart
        Win.Position = UDim2.new(
            frameStart.X.Scale, frameStart.X.Offset + d.X,
            frameStart.Y.Scale, frameStart.Y.Offset + d.Y
        )
    end
end)

UserInputService.InputEnded:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1
    or inp.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

-- ============================================================
-- KEYBIND: RightShift
-- ============================================================
UserInputService.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.KeyCode == Enum.KeyCode.RightShift then
        Win.Visible = not Win.Visible
    end
end)

-- ============================================================
-- DONE
-- ============================================================
print("[DYC] ✅ Script loaded! UI ready. RightShift = ẩn/hiện.")
SetStatus("Script loaded ✅", GREEN)
task.delay(3, function() SetStatus("Ready") end)
