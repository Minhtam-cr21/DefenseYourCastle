-- Loader - Defend Your Castle Script
-- loadstring(game:HttpGet("https://raw.githubusercontent.com/Minhtam-cr21/DefenseYourCastle/main/Loader.lua"))()

local URL = "https://raw.githubusercontent.com/Minhtam-cr21/DefenseYourCastle/main/DYCScript.lua"

local content = game:HttpGet(URL, true)
if not content or content == "" then
    warn("[DYC] Không tải được script!")
    return
end

local fn, err = loadstring(content)
if not fn then
    warn("[DYC] loadstring lỗi: " .. tostring(err))
    return
end

fn()
