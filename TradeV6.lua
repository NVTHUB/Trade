-- Cho game tai xong thi chay script
repeat task.wait(1) until game:IsLoaded()
-- Khai bao cac dich vu va Module noi bo cua Adopt Me
local RS = game:GetService("ReplicatedStorage")
local API = RS:WaitForChild("API")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local ClientData = require(RS.ClientModules.Core.ClientData)
local Router = require(RS.ClientModules.Core.RouterClient.RouterClient)
-- Doc Config, ho tro ca chu hoa va chu thuong
local function cfg(key, default)
    local c = getgenv().Config or {}
    local v = c[key]
    if v ~= nil then
        return v
    end
    local lower = string.lower(key)
    if c[lower] ~= nil then
        return c[lower]
    end
    return default
end

local function listToLookup(list)
    local map = {}
    if type(list) ~= "table" then
        return map
    end
    for _, v in ipairs(list) do
        if type(v) == "string" and v ~= "" then
            map[string.lower(v)] = true
        end
    end
    return map
end

local function listContainsInsensitive(list, value)
    if type(list) ~= "table" then
        return false
    end
    if type(value) ~= "string" then
        return false
    end
    local needle = string.lower(value)
    for _, v in ipairs(list) do
        if type(v) == "string" and string.lower(v) == needle then
            return true
        end
    end
    return false
end

local function normalizeItemKhac(raw)
    if type(raw) == "table" then
        local out = {}
        for _, v in ipairs(raw) do
            if type(v) == "string" and v ~= "" then
                table.insert(out, v)
            end
        end
        return out
    end
    if type(raw) == "string" then
        if raw == "" then
            return {}
        end
        local out = {}
        for token in string.gmatch(raw, "[^,]+") do
            local cleaned = string.gsub(token, "^%s+", "")
            cleaned = string.gsub(cleaned, "%s+$", "")
            if cleaned ~= "" then
                table.insert(out, cleaned)
            end
        end
        return out
    end
    return {}
end

local function getPetRarity(info)
    return string.lower((info and info.rarity) or (info and info.pet_rarity) or "common")
end

local rarityRank = {
    common = 1,
    uncommon = 2,
    rare = 3,
    ultra_rare = 4,
    legendary = 5
}

local function petState(info)
    local props = (info and info.properties) or {}
    local isMega = props.mega_neon == true
    local isNeon = props.neon == true
    local age = tonumber(props.age or 1) or 1
    return isMega, isNeon, age
end
-- Ham giai ma (dehash) cac RemoteEvent de script co the goi truc tiep API
local function dehash()
    pcall(function()
        local mapping = debug.getupvalue(Router.init, 7)
        for name, remote in pairs(mapping) do
            if typeof(remote) == "Instance" then
                remote.Name = name
            end
        end
    end)
end
dehash()
-- Tu dong vao game, chon phe (Parents) va tat cac bang thong bao
local function enterGame()
    pcall(function()
        API:WaitForChild("TeamAPI/ChooseTeam"):InvokeServer("Parents", { source_for_logging = "intro_sequence" })
        task.wait(1)
        local Fsys = require(RS.Fsys)
        local ui = Fsys.load("UIManager")
        ui.set_app_visibility("MainMenuApp", false)
        ui.set_app_visibility("NewsApp", false)
        ui.set_app_visibility("DialogApp", false)
        API:WaitForChild("DailyLoginAPI/ClaimDailyReward"):InvokeServer()
    end)
end
enterGame()
-- Anti AFK
local function keepAliveAntiAfk()
    task.spawn(function()
        local vu = game:GetService("VirtualUser")
        LocalPlayer.Idled:Connect(function()
            vu:CaptureController()
            vu:ClickButton2(Vector2.new())
        end)
    end)
end
keepAliveAntiAfk()
-- Tu dong lay bang giao dich (Trade License) neu chua co
local function checkTradeLicense()
    if ClientData.get("has_trade_license") == true then
        return
    end
    pcall(function()
        API:WaitForChild("SettingsAPI/SetBooleanFlag"):FireServer("has_talked_to_trade_quest_npc", true)
        task.wait(0.5)
        API:WaitForChild("TradeAPI/BeginQuiz"):FireServer()
        task.wait(1)
        local quiz = ClientData.get("trade_license_quiz_manager").quiz
        for _, qdata in pairs(quiz or {}) do
            API:WaitForChild("TradeAPI/AnswerQuizQuestion"):FireServer(qdata.answer)
            task.wait(0.5)
        end
    end)
end
checkTradeLicense()
-- Logic kiem tra pet so voi bo loc (Age, Rarity, Mode) 
local function itemToTradeFilterPass(kind)
    local whitelist = cfg("Item_To_Trade", cfg("item_to_trade", {}))
    if type(whitelist) ~= "table" or #whitelist == 0 then
        return true
    end
    return listContainsInsensitive(whitelist, kind)
end

local function shouldTradeByAgeFilter(info)
    local filter = cfg("AgeFilter", {})
    local isMega, isNeon, age = petState(info)

    if isMega then
        return filter.Mega == true
    end

    if isNeon then
        if filter.Neon ~= true then
            return false
        end
        local neonAges = filter.AgeNeon or {}
        return #neonAges == 0 or table.find(neonAges, age) ~= nil
    end

    if filter.Normal ~= true then
        return false
    end
    local normalAges = filter.AgeNormal or {}
    return #normalAges == 0 or table.find(normalAges, age) ~= nil
end

local function shouldTradePetByMode(info)
    if not info or not info.kind then
        return false
    end

    if not itemToTradeFilterPass(info.kind) then
        return false
    end

    local tradeMode = string.lower(cfg("Trade_Mode", "AgeFilter"))
    local isMega, isNeon, age = petState(info)

    if tradeMode == "allpet" then
        return true
    end

    if tradeMode == "allmega" then
        return isMega or (isNeon and age == 6)
    end

    if tradeMode == "raritiesfilter" then
        local allowed = listToLookup(cfg("RaritiesFilter", {}))
        if next(allowed) == nil then
            return false
        end
        return allowed[getPetRarity(info)] == true
    end

    return shouldTradeByAgeFilter(info)
end

local function collectTradePets(inventory)
    local candidates = {}
    for id, info in pairs((inventory and inventory.pets) or {}) do
        if shouldTradePetByMode(info) then
            table.insert(candidates, {
                id = id,
                info = info,
                rank = rarityRank[getPetRarity(info)] or 999
            })
        end
    end

    local tradeMode = string.lower(cfg("Trade_Mode", "AgeFilter"))
    if tradeMode == "allpet" and #candidates > 0 then
        local keepIndex = 1
        local minRank = candidates[1].rank
        for i = 2, #candidates do
            if candidates[i].rank < minRank then
                keepIndex = i
                minRank = candidates[i].rank
            end
        end
        table.remove(candidates, keepIndex)
    end

    local ids = {}
    for _, entry in ipairs(candidates) do
        table.insert(ids, entry.id)
    end
    return ids
end

local alwaysItemCategories = {
    "roleplay",
    "food",
    "pet_accessories",
    "pet_accessoris",
    "toys",
    "transport",
    "gifts",
    "strollers",
    "pets",
    "stickers"
}

local function collectAlwaysItemIds(inventory, alreadyAdded)
    local out = {}
    local itemKhac = normalizeItemKhac(cfg("Item_Khac", ""))
    if #itemKhac == 0 then
        return out
    end

    local wanted = listToLookup(itemKhac)
    for _, category in ipairs(alwaysItemCategories) do
        local bag = (inventory and inventory[category]) or {}
        for id, info in pairs(bag) do
            local kind = info and info.kind
            if type(kind) == "string" and wanted[string.lower(kind)] == true and not alreadyAdded[id] then
                table.insert(out, id)
                alreadyAdded[id] = true
            end
        end
    end

    return out
end
-- Tu dong up pet len neon, mega
local function runAutoNeonPass()
    local autoNeon = cfg("Auto_Neon", {})
    if type(autoNeon) ~= "table" or #autoNeon == 0 then
        return
    end

    local modeMap = listToLookup(autoNeon)
    if modeMap[""] then
        modeMap[""] = nil
    end
    if modeMap.meon then
        modeMap.mega = true
    end
    if not modeMap.neon and not modeMap.mega then
        return
    end

    local inventory = ClientData.get("inventory")
    if not inventory or not inventory.pets then
        return
    end

    local groups = {}
    for id, info in pairs(inventory.pets) do
        local isMega, isNeon, age = petState(info)
        if age == 6 and not isMega then
            if modeMap.neon and not isNeon then
                local key = (info.kind or "unknown") .. "|normal"
                groups[key] = groups[key] or {}
                table.insert(groups[key], id)
            elseif modeMap.mega and isNeon then
                local key = (info.kind or "unknown") .. "|neon"
                groups[key] = groups[key] or {}
                table.insert(groups[key], id)
            end
        end
    end

    for groupKey, ids in pairs(groups) do
        local i = 1
        while i + 3 <= #ids do
            local materials = { ids[i], ids[i + 1], ids[i + 2], ids[i + 3] }
            pcall(function()
                API:WaitForChild("PetAPI/DoNeonFusion"):InvokeServer(materials)
            end)
            i = i + 4
            task.wait(1)
        end
    end
end
-- Change foder YUMMY
local function doChangeFolderOrYummy()
    if cfg("Auto_Change", false) ~= true then
        return false
    end

    local mode = string.lower(tostring(cfg("Change_Mode", "Farmsyn")))
    if mode == "yummy" then
        if writefile then
            local fileName = LocalPlayer.Name .. ".txt"
            writefile(fileName, "Yummytool")
        else
            warn("Executor khong ho tro writefile")
        end
        return true
    end

    local fromFolder = (cfg("Folder_From", cfg("folder_from", {})) or {})[1]
    local toFolder = (cfg("Folder_To", cfg("folder_to", {})) or {})[1]
    if fromFolder and toFolder and getgenv().client then
        pcall(function()
            getgenv().client:ChangeToFolder(fromFolder, toFolder, false, nil)
        end)
        return true
    end

    warn("Khong doi duoc folder: thieu Folder_From/Folder_To hoac getgenv().client")
    return false
end
-- ACC NHAN
local function functionA()
    API:WaitForChild("TradeAPI/TradeRequestReceived").OnClientEvent:Connect(function(sender)
        if not sender then
            return
        end
        pcall(function()
            API["PlayerProfileAPI/RefreshProfile"]:InvokeServer(sender)
            task.wait(0.2)
            API["TradeAPI/AcceptOrDeclineTradeRequest"]:InvokeServer(sender, true)
        end)
    end)

    task.spawn(function()
        while task.wait(0.5) do
            pcall(function()
                API["TradeAPI/AcceptNegotiation"]:FireServer()
                API["TradeAPI/ConfirmTrade"]:FireServer()
            end)
        end
    end)

    task.spawn(function()
        while task.wait(8) do
            pcall(runAutoNeonPass)
        end
    end)
end
-- ACC GUI
local function functionB()
    local folderChanged = false

    task.spawn(function()
        task.wait(300)
        if LocalPlayer then
            LocalPlayer:Kick("He thong: Da het 5 phut treo may, tu dong thoat de bao mat!")
        end
    end)

    task.spawn(function()
        while not folderChanged do
            local inventory = ClientData.get("inventory")
            local petIds = collectTradePets(inventory)

            if #petIds > 0 then
                local sendTrade = API:WaitForChild("TradeAPI/SendTradeRequest", 5)
                local userList = cfg("Username", cfg("username", {}))
                if sendTrade and type(userList) == "table" and #userList > 0 then
                    local targetName = userList[math.random(1, #userList)]
                    local target = Players:FindFirstChild(targetName)
                    if target and target ~= LocalPlayer then
                        pcall(function()
                            sendTrade:FireServer(target)
                        end)
                    end
                end
                task.wait(10)
            else
                local changed = doChangeFolderOrYummy()
                if changed then
                    folderChanged = true
                    break
                end
            end
            task.wait(2)
        end
    end)

    task.spawn(function()
        while not folderChanged do
            local inventory = ClientData.get("inventory")
            local addItem = API:WaitForChild("TradeAPI/AddItemToOffer", 5)
            local acceptNeg = API:WaitForChild("TradeAPI/AcceptNegotiation", 5)
            local confirmTrade = API:WaitForChild("TradeAPI/ConfirmTrade", 5)

            if addItem and inventory then
                local count = 0
                local added = {}

                local petIds = collectTradePets(inventory)
                for _, id in ipairs(petIds) do
                    if count >= 18 then
                        break
                    end
                    if not added[id] then
                        pcall(function()
                            addItem:FireServer(id)
                        end)
                        added[id] = true
                        count = count + 1
                    end
                end

                if count < 18 then
                    local alwaysIds = collectAlwaysItemIds(inventory, added)
                    for _, id in ipairs(alwaysIds) do
                        if count >= 18 then
                            break
                        end
                        pcall(function()
                            addItem:FireServer(id)
                        end)
                        count = count + 1
                    end
                end

                if count > 0 then
                    pcall(function()
                        acceptNeg:FireServer()
                        confirmTrade:FireServer()
                    end)
                end
            end

            task.wait(0.8)
        end
    end)
end

-- KHỞI CHẠY

local targetUsers = cfg("Username", cfg("username", {}))
local isTarget = type(targetUsers) == "table" and table.find(targetUsers, LocalPlayer.Name) ~= nil

if isTarget then
    functionA()
else
    functionB()
end
