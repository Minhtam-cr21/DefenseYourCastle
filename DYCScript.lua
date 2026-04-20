-- // Defend Your Castle - Auto Script
-- // Load từ GitHub: loadstring(game:HttpGet("https://raw.githubusercontent.com/USERNAME/REPO/main/DYCScript.lua"))()

-- ============================================
-- LOAD RAYFIELD (cách an toàn cho medium executor)
-- ============================================
local RayfieldLoaded = false
local Rayfield

local ok1 = pcall(function()
    Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield", true))()
    RayfieldLoaded = true
end)

if not ok1 then
    local ok2 = pcall(function()
        Rayfield = loadstring(game:HttpGet("https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/main/source.lua", true))()
        RayfieldLoaded = true
    end)
end

if not RayfieldLoaded then
    -- Fallback: dùng ScreenGui tự tạo nếu Rayfield fail
    warn("[DYC] Rayfield load fail - dùng UI fallback")
end

-- ============================================
-- SERVICES
-- ============================================
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local TeleportService   = game:GetService("TeleportService")

local LP = Players.LocalPlayer

-- ============================================
-- STATE
-- ============================================
local Toggles = {
    AutoBuy        = false,
    AutoChallenge  = false,
    AntiAFK        = false,
}

local Stats = {
    Bought     = 0,
    Challenges = 0,
}

-- ============================================
-- SCAN REMOTES (debug helper)
-- ============================================
local function ScanRemotes()
    local found = {}
    for _, v in ipairs(ReplicatedStorage:GetDescendants()) do
        if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
            table.insert(found, v:GetFullName() .. " [" .. v.ClassName .. "]")
        end
    end
    return table.concat(found, "\n")
end

-- ============================================
-- FIND REMOTE (tìm theo keyword)
-- ============================================
local function FindRemote(keyword)
    keyword = string.lower(keyword)
    for _, v in ipairs(ReplicatedStorage:GetDescendants()) do
        if (v:IsA("RemoteEvent") or v:IsA("RemoteFunction")) then
            if string.lower(v.Name):find(keyword) or string.lower(v:GetFullName()):find(keyword) then
                return v
            end
        end
    end
    return nil
end

-- ============================================
-- FIRE REMOTE SAFELY
-- ============================================
local function Fire(remote, ...)
    if not remote then return false end
    local args = {...}
    if remote:IsA("RemoteEvent") then
        pcall(function() remote:FireServer(table.unpack(args)) end)
        return true
    elseif remote:IsA("RemoteFunction") then
        local ok, res = pcall(function() return remote:InvokeServer(table.unpack(args)) end)
        return ok, res
    end
    return false
end

-- ============================================
-- AUTO BUY PRINTS
-- ============================================
local function DoBuyPrint()
    -- Thử các tên remote có thể có trong game này
    local candidates = {
        "BuyPrint", "BuyBlueprint", "BuyDefense", "Purchase",
        "Shop", "Buy", "Print", "Blueprint"
    }
    for _, name in ipairs(candidates) do
        local r = FindRemote(name)
        if r then
            Fire(r, "Print")
            Fire(r, "Blueprint")
            Fire(r)
            Stats.Bought += 1
            return true
        end
    end
    return false
end

task.spawn(function()
    while true do
        task.wait(2)
        if Toggles.AutoBuy then
            DoBuyPrint()
        end
    end
end)

-- ============================================
-- AUTO CHALLENGE
-- ============================================
local function DoChallenge()
    local candidates = {
        "Challenge", "StartChallenge", "JoinChallenge",
        "ClaimChallenge", "CompleteChallenge"
    }
    for _, name in ipairs(candidates) do
        local r = FindRemote(name)
        if r then
            Fire(r)
            Stats.Challenges += 1
            return true
        end
    end
    return false
end

task.spawn(function()
    while true do
        task.wait(5)
        if Toggles.AutoChallenge then
            DoChallenge()
        end
    end
end)

-- ============================================
-- ANTI AFK
-- ============================================
task.spawn(function()
    while true do
        task.wait(55)
        if Toggles.AntiAFK then
            local char = LP.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then
                    hum.Jump = true
                end
            end
            -- Fake input
            pcall(function()
                local fakeEvent = Instance.new("BindableEvent")
                fakeEvent:Fire()
                fakeEvent:Destroy()
            end)
        end
    end
end)

-- ============================================
-- RAYFIELD UI
-- ============================================
if RayfieldLoaded and Rayfield then

    local Window = Rayfield:CreateWindow({
        Name = "🏰 Defend Your Castle",
        LoadingTitle = "DYC Script",
        LoadingSubtitle = "Đang tải...",
        ConfigurationSaving = {
            Enabled = false,
        },
        KeySystem = false,
    })

    -- TAB 1: MAIN
    local Main = Window:CreateTab("Main", "zap")

    Main:CreateSection("Auto Features")

    Main:CreateToggle({
        Name = "Auto Buy Prints",
        CurrentValue = false,
        Flag = "AutoBuy",
        Callback = function(v)
            Toggles.AutoBuy = v
        end,
    })

    Main:CreateToggle({
        Name = "Auto Challenges",
        CurrentValue = false,
        Flag = "AutoChallenge",
        Callback = function(v)
            Toggles.AutoChallenge = v
        end,
    })

    Main:CreateToggle({
        Name = "Anti-AFK",
        CurrentValue = false,
        Flag = "AntiAFK",
        Callback = function(v)
            Toggles.AntiAFK = v
        end,
    })

    -- TAB 2: DEBUG (quan trọng để tìm remote)
    local Debug = Window:CreateTab("Debug", "terminal")

    Debug:CreateSection("Remote Scanner")

    Debug:CreateButton({
        Name = "Scan Remotes (copy to output)",
        Callback = function()
            local result = ScanRemotes()
            print("=== REMOTES FOUND ===")
            print(result)
            print("=== END ===")
            Rayfield:Notify({
                Title = "Scan Done!",
                Content = "Xem Output (F9) để thấy danh sách remotes",
                Duration = 5,
                Image = "rbxassetid://4483345998",
            })
        end,
    })

    Debug:CreateButton({
        Name = "Test Buy Remote",
        Callback = function()
            local r = FindRemote("buy") or FindRemote("print") or FindRemote("shop")
            if r then
                Rayfield:Notify({
                    Title = "Tìm thấy!",
                    Content = "Remote: " .. r:GetFullName(),
                    Duration = 5,
                    Image = "rbxassetid://4483345998",
                })
            else
                Rayfield:Notify({
                    Title = "Không tìm thấy",
                    Content = "Hãy Scan Remotes để xem tên thật",
                    Duration = 5,
                    Image = "rbxassetid://4483345998",
                })
            end
        end,
    })

    Debug:CreateSection("Stats")

    local statsLabel = Debug:CreateLabel("Prints Bought: 0 | Challenges: 0")

    task.spawn(function()
        while true do
            task.wait(3)
            pcall(function()
                statsLabel:Set("Prints Bought: " .. Stats.Bought .. " | Challenges: " .. Stats.Challenges)
            end)
        end
    end)

    -- TAB 3: MISC
    local Misc = Window:CreateTab("Misc", "settings")

    Misc:CreateSection("Utilities")

    Misc:CreateButton({
        Name = "Rejoin",
        Callback = function()
            TeleportService:Teleport(game.PlaceId, LP)
        end,
    })

    -- Thông báo load xong
    Rayfield:Notify({
        Title = "🏰 DYC Script Ready!",
        Content = "Bật toggle để dùng tính năng. Dùng Debug tab để scan remotes nếu auto buy chưa hoạt động.",
        Duration = 6,
        Image = "rbxassetid://4483345998",
    })

else
    -- FALLBACK UI nếu Rayfield không load được
    warn("[DYC] Chạy không có Rayfield UI")

    local sg = Instance.new("ScreenGui")
    sg.Name = "DYCFallback"
    sg.ResetOnSpawn = false
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    pcall(function() sg.Parent = game:GetService("CoreGui") end)
    if not sg.Parent then sg.Parent = LP.PlayerGui end

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 300, 0, 200)
    frame.Position = UDim2.new(0.5, -150, 0.5, -100)
    frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    frame.BorderSizePixel = 0
    frame.Parent = sg

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame

    local title = Instance.new("TextLabel")
    title.Text = "🏰 DYC Script (No Rayfield)"
    title.Size = UDim2.new(1, 0, 0, 40)
    title.BackgroundColor3 = Color3.fromRGB(50, 50, 200)
    title.TextColor3 = Color3.new(1,1,1)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.Parent = frame

    local info = Instance.new("TextLabel")
    info.Text = "Rayfield failed to load.\nDùng executor hỗ trợ HttpGet.\nCheck output (F9) để debug."
    info.Size = UDim2.new(1, -20, 1, -50)
    info.Position = UDim2.new(0, 10, 0, 45)
    info.BackgroundTransparency = 1
    info.TextColor3 = Color3.new(1,1,1)
    info.Font = Enum.Font.Gotham
    info.TextSize = 13
    info.TextWrapped = true
    info.TextXAlignment = Enum.TextXAlignment.Left
    info.Parent = frame
end

print("[DYC] Script loaded OK!")
print("[DYC] Remotes available:")
print(ScanRemotes())
