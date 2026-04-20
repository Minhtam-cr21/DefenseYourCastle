-- // DYC Loader
-- // Thay USERNAME và REPO bằng thông tin GitHub của bạn
-- // Dùng: loadstring(game:HttpGet("https://raw.githubusercontent.com/USERNAME/REPO/main/Loader.lua"))()

local SCRIPT_URL = "https://raw.githubusercontent.com/MinhTam/REPO/main/DYCScript.lua"

local ok, err = pcall(function()
    loadstring(game:HttpGet(SCRIPT_URL, true))()
end)

if not ok then
    warn("[DYC Loader] Failed: " .. tostring(err))
end
