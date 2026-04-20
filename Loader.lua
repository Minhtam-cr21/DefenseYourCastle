-- Loader cho Defend Your Castle Script
-- Dùng lệnh này trong executor:
-- loadstring(game:HttpGet("https://raw.githubusercontent.com/Minhtam-cr21/DefenseYourCastle/main/Loader.lua"))()

local URL = "https://raw.githubusercontent.com/Minhtam-cr21/DefenseYourCastle/main/DYCScript.lua"

local content = game:HttpGet(URL, true)

if not content or content == "" then
    warn("[DYC Loader] Không tải được script từ GitHub!")
    return
end

local fn, err = loadstring(content)
if not fn then
    warn("[DYC Loader] loadstring lỗi: " .. tostring(err))
    return
end

fn()
