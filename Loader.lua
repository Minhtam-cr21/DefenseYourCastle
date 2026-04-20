local SCRIPT_URL = "https://raw.githubusercontent.com/Minhtam-cr21/DefenseYourCastle/main/DYCScript.lua"
local ok, content = pcall(function()
    return game:HttpGet(SCRIPT_URL, true)
end)
if not ok or type(content) ~= "string" or content == "" then
    warn("[DYC] Failed to download script")
    return
end
local fn, err = loadstring(content)
if not fn then
    warn("[DYC] loadstring error: " .. tostring(err))
    return
end
local runOk, runErr = pcall(fn)
if not runOk then
    warn("[DYC] runtime error: " .. tostring(runErr))
end
