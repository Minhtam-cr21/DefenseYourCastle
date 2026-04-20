--[[
    DEFEND YOUR CASTLE - Script
    GitHub: Minhtam-cr21/DefenseYourCastle
    
    STEP 1: UI chạy OK
    STEP 2: Anti-AFK
    (Buy & Challenge sẽ thêm sau khi biết tên Remote)
--]]

-- ============================================================
-- SERVICES (chỉ lấy những cái chắc chắn có)
-- ============================================================
local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LP = Players.LocalPlayer

-- ============================================================
-- XÓA GUI CŨ nếu re-execute
-- ============================================================
pcall(function()
    local old = game:GetService("CoreGui"):FindFirstChild("DYC_UI")
    if old then old:Destroy() end
end)
pcall(function()
    local old = LP.PlayerGui:FindFirstChild("DYC_UI")
    if old then old:Destroy() end
end)

-- ============================================================
-- TẠO SCREENGUI
-- ============================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "DYC_UI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 100

-- Thử CoreGui trước (executor hỗ trợ), fallback về PlayerGui
local ok = pcall(function()
    ScreenGui.Parent = game:GetService("CoreGui")
end)
if not ok or not ScreenGui.Parent then
    ScreenGui.Parent = LP.PlayerGui
end

print("[DYC] ScreenGui created in: " .. ScreenGui.Parent.Name)

-- ============================================================
-- MAIN FRAME (cửa sổ chính)
-- ============================================================
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 300, 0, 320)
MainFrame.Position = UDim2.new(0.5, -150, 0.5, -160)
MainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
MainFrame.BorderSizePixel = 0
MainFrame.Parent = ScreenGui

local corner1 = Instance.new("UICorner")
corner1.CornerRadius = UDim.new(0, 10)
corner1.Parent = MainFrame

local stroke1 = Instance.new("UIStroke")
stroke1.Color = Color3.fromRGB(60, 60, 100)
stroke1.Thickness = 1
stroke1.Parent = MainFrame

-- ============================================================
-- HEADER
-- ============================================================
local Header = Instance.new("Frame")
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0, 44)
Header.Position = UDim2.new(0, 0, 0, 0)
Header.BackgroundColor3 = Color3.fromRGB(28, 28, 50)
Header.BorderSizePixel = 0
Header.Parent = MainFrame

local hCorner = Instance.new("UICorner")
hCorner.CornerRadius = UDim.new(0, 10)
hCorner.Parent = Header

-- patch corners bị tròn phía dưới header
local hPatch = Instance.new("Frame")
hPatch.Size = UDim2.new(1, 0, 0, 10)
hPatch.Position = UDim2.new(0, 0, 1, -10)
hPatch.BackgroundColor3 = Color3.fromRGB(28, 28, 50)
hPatch.BorderSizePixel = 0
hPatch.Parent = Header

-- Title
local Title = Instance.new("TextLabel")
Title.Text = "🏰 Defend Your Castle"
Title.Size = UDim2.new(1, -80, 1, 0)
Title.Position = UDim2.new(0, 12, 0, 0)
Title.BackgroundTransparency = 1
Title.TextColor3 = Color3.fromRGB(230, 230, 255)
Title.TextSize = 14
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

-- Close button
local CloseBtn = Instance.new("TextButton")
CloseBtn.Text = "✕"
CloseBtn.Size = UDim2.new(0, 26, 0, 26)
CloseBtn.Position = UDim2.new(1, -32, 0.5, -13)
CloseBtn.BackgroundColor3 = Color3.fromRGB(200, 55, 55)
CloseBtn.TextColor3 = Color3.new(1, 1, 1)
CloseBtn.TextSize = 13
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.BorderSizePixel = 0
CloseBtn.Parent = Header

local cCorner = Instance.new("UICorner")
cCorner.CornerRadius = UDim.new(0, 6)
cCorner.Parent = CloseBtn

CloseBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = false
end)

-- ============================================================
-- BODY (nội dung bên dưới header)
-- ============================================================
local Body = Instance.new("Frame")
Body.Name = "Body"
Body.Size = UDim2.new(1, -20, 1, -54)
Body.Position = UDim2.new(0, 10, 0, 54)
Body.BackgroundTransparency = 1
Body.BorderSizePixel = 0
Body.Parent = MainFrame

local bodyLayout = Instance.new("UIListLayout")
bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
bodyLayout.Padding = UDim.new(0, 8)
bodyLayout.Parent = Body

-- ============================================================
-- HELPER: Tạo Toggle Row
-- ============================================================
local function CreateToggle(parent, title, description, order, onToggle)
    local row = Instance.new("Frame")
    row.Name = "Row_" .. title
    row.Size = UDim2.new(1, 0, 0, 64)
    row.BackgroundColor3 = Color3.fromRGB(26, 26, 38)
    row.BorderSizePixel = 0
    row.LayoutOrder = order
    row.Parent = parent

    local rCorner = Instance.new("UICorner")
    rCorner.CornerRadius = UDim.new(0, 8)
    rCorner.Parent = row

    local rStroke = Instance.new("UIStroke")
    rStroke.Color = Color3.fromRGB(50, 50, 80)
    rStroke.Thickness = 1
    rStroke.Parent = row

    -- Title
    local tLbl = Instance.new("TextLabel")
    tLbl.Text = title
    tLbl.Size = UDim2.new(1, -70, 0, 22)
    tLbl.Position = UDim2.new(0, 12, 0, 10)
    tLbl.BackgroundTransparency = 1
    tLbl.TextColor3 = Color3.fromRGB(225, 225, 245)
    tLbl.TextSize = 13
    tLbl.Font = Enum.Font.GothamBold
    tLbl.TextXAlignment = Enum.TextXAlignment.Left
    tLbl.Parent = row

    -- Description
    local dLbl = Instance.new("TextLabel")
    dLbl.Text = description
    dLbl.Size = UDim2.new(1, -70, 0, 18)
    dLbl.Position = UDim2.new(0, 12, 0, 34)
    dLbl.BackgroundTransparency = 1
    dLbl.TextColor3 = Color3.fromRGB(120, 120, 150)
    dLbl.TextSize = 11
    dLbl.Font = Enum.Font.Gotham
    dLbl.TextXAlignment = Enum.TextXAlignment.Left
    dLbl.Parent = row

    -- Toggle Pill
    local pill = Instance.new("TextButton")
    pill.Text = ""
    pill.Size = UDim2.new(0, 44, 0, 22)
    pill.Position = UDim2.new(1, -54, 0.5, -11)
    pill.BackgroundColor3 = Color3.fromRGB(55, 55, 80)
    pill.BorderSizePixel = 0
    pill.Parent = row

    local pCorner = Instance.new("UICorner")
    pCorner.CornerRadius = UDim.new(0, 11)
    pCorner.Parent = pill

    -- Knob
    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 16, 0, 16)
    knob.Position = UDim2.new(0, 3, 0.5, -8)
    knob.BackgroundColor3 = Color3.fromRGB(200, 200, 220)
    knob.BorderSizePixel = 0
    knob.Parent = pill

    local kCorner = Instance.new("UICorner")
    kCorner.CornerRadius = UDim.new(0, 8)
    kCorner.Parent = knob

    -- State
    local isOn = false
    pill.MouseButton1Click:Connect(function()
        isOn = not isOn

        if isOn then
            TweenService:Create(pill, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
                BackgroundColor3 = Color3.fromRGB(60, 200, 120)
            }):Play()
            TweenService:Create(knob, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
                Position = UDim2.new(0, 25, 0.5, -8)
            }):Play()
        else
            TweenService:Create(pill, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
                BackgroundColor3 = Color3.fromRGB(55, 55, 80)
            }):Play()
            TweenService:Create(knob, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
                Position = UDim2.new(0, 3, 0.5, -8)
            }):Play()
        end

        if onToggle then onToggle(isOn) end
    end)

    return row
end

-- ============================================================
-- SECTION LABEL
-- ============================================================
local function CreateSection(parent, text, order)
    local lbl = Instance.new("TextLabel")
    lbl.Text = text:upper()
    lbl.Size = UDim2.new(1, 0, 0, 16)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3 = Color3.fromRGB(100, 100, 140)
    lbl.TextSize = 10
    lbl.Font = Enum.Font.GothamBold
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.LayoutOrder = order
    lbl.Parent = parent
    return lbl
end

-- ============================================================
-- STATUS BAR
-- ============================================================
local StatusBar = Instance.new("Frame")
StatusBar.Size = UDim2.new(1, 0, 0, 28)
StatusBar.BackgroundColor3 = Color3.fromRGB(22, 22, 35)
StatusBar.BorderSizePixel = 0
StatusBar.LayoutOrder = 99
StatusBar.Parent = Body

local sbCorner = Instance.new("UICorner")
sbCorner.CornerRadius = UDim.new(0, 8)
sbCorner.Parent = StatusBar

local StatusLbl = Instance.new("TextLabel")
StatusLbl.Text = "● Idle"
StatusLbl.Size = UDim2.new(1, -12, 1, 0)
StatusLbl.Position = UDim2.new(0, 10, 0, 0)
StatusLbl.BackgroundTransparency = 1
StatusLbl.TextColor3 = Color3.fromRGB(100, 100, 140)
StatusLbl.TextSize = 11
StatusLbl.Font = Enum.Font.GothamMedium
StatusLbl.TextXAlignment = Enum.TextXAlignment.Left
StatusLbl.Parent = StatusBar

local function SetStatus(msg, color)
    StatusLbl.Text = "● " .. msg
    StatusLbl.TextColor3 = color or Color3.fromRGB(100, 100, 140)
end

-- ============================================================
-- ANTI-AFK LOGIC
-- ============================================================
local antiAFKEnabled = false
local antiAFKCount = 0

-- Method 1: nhảy nhân vật
-- Method 2: simulate click giả để reset idle timer
local function DoAntiAFK()
    antiAFKCount = antiAFKCount + 1

    -- Jump character
    local char = LP.Character or LP.CharacterAdded:Wait()
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health > 0 then
        hum.Jump = true
    end

    -- Fake VirtualUser click để bypass Roblox AFK detection
    pcall(function()
        local VU = game:GetService("VirtualUser")
        VU:Button1Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        task.wait(0.1)
        VU:Button1Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    end)

    print("[DYC] Anti-AFK #" .. antiAFKCount .. " triggered")
    SetStatus("Anti-AFK active (#" .. antiAFKCount .. ")", Color3.fromRGB(60, 200, 120))
end

-- Loop chạy ngầm
task.spawn(function()
    while true do
        task.wait(50) -- mỗi 50 giây (Roblox kick sau ~60s)
        if antiAFKEnabled then
            DoAntiAFK()
        end
    end
end)

-- ============================================================
-- BUILD UI CONTENT
-- ============================================================

CreateSection(Body, "Auto Features", 1)

CreateToggle(Body,
    "Anti-AFK",
    "Tự động hành động mỗi 50s để không bị kick",
    2,
    function(state)
        antiAFKEnabled = state
        if state then
            SetStatus("Anti-AFK đang chạy...", Color3.fromRGB(60, 200, 120))
            DoAntiAFK() -- fire ngay lập tức 1 lần
        else
            SetStatus("Anti-AFK đã tắt", Color3.fromRGB(180, 80, 80))
            task.delay(2, function()
                SetStatus("Idle")
            end)
        end
    end
)

CreateSection(Body, "Coming Soon", 3)

-- Placeholder rows (chưa hoạt động - cần biết Remote)
local placeholderRow1 = Instance.new("Frame")
placeholderRow1.Size = UDim2.new(1, 0, 0, 40)
placeholderRow1.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
placeholderRow1.BorderSizePixel = 0
placeholderRow1.LayoutOrder = 4
placeholderRow1.Parent = Body

local pc1 = Instance.new("UICorner")
pc1.CornerRadius = UDim.new(0, 8)
pc1.Parent = placeholderRow1

local UIStroke2 = Instance.new("UIStroke")
UIStroke2.Color = Color3.fromRGB(40, 40, 60)
UIStroke2.Thickness = 1
UIStroke2.Parent = placeholderRow1

local pLbl1 = Instance.new("TextLabel")
pLbl1.Text = "🔒  Auto Buy Prints  (coming soon)"
pLbl1.Size = UDim2.new(1, -12, 1, 0)
pLbl1.Position = UDim2.new(0, 12, 0, 0)
pLbl1.BackgroundTransparency = 1
pLbl1.TextColor3 = Color3.fromRGB(70, 70, 100)
pLbl1.TextSize = 12
pLbl1.Font = Enum.Font.GothamMedium
pLbl1.TextXAlignment = Enum.TextXAlignment.Left
pLbl1.Parent = placeholderRow1

local placeholderRow2 = placeholderRow1:Clone()
placeholderRow2.LayoutOrder = 5
placeholderRow2.Parent = Body
placeholderRow2.TextLabel.Text = "🔒  Auto Challenges  (coming soon)"

-- ============================================================
-- DRAG TO MOVE
-- ============================================================
local dragging = false
local dragStart = nil
local frameStart = nil

Header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        frameStart = MainFrame.Position
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement
    or input.UserInputType == Enum.UserInputType.Touch then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(
            frameStart.X.Scale, frameStart.X.Offset + delta.X,
            frameStart.Y.Scale, frameStart.Y.Offset + delta.Y
        )
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

-- ============================================================
-- KEYBIND: RightShift = ẩn/hiện UI
-- ============================================================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        MainFrame.Visible = not MainFrame.Visible
    end
end)

-- ============================================================
-- DONE
-- ============================================================
print("[DYC] ✅ Script loaded! UI đang hiện. Nhấn RightShift để ẩn/hiện.")
SetStatus("Script loaded ✅", Color3.fromRGB(60, 200, 120))
task.delay(3, function()
    SetStatus("Idle")
end)

-- ============================================================
task.wait(3)
print("=== ALL REMOTES ===")
for _, v in ipairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
    if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
        print(v.ClassName .. " >> " .. v:GetFullName())
    end
end
print("=== END ===")
-- ============================================================
