--[[ 
    MODULES.LUA
    File ini berisi fungsi-fungsi dasar untuk farm, movement, dan chat logger.
    Jalankan dengan: loadfile("modules.lua")()
]]

-- CONFIG
local player = game.Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local root = char:WaitForChild("HumanoidRootPart")
local humanoid = char:WaitForChild("Humanoid")

-- REMOTES
local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
local fist = remotes:WaitForChild("PlayerFist")
local place = remotes:WaitForChild("PlayerPlaceItem")
local movement = remotes:WaitForChild("PlayerMovementPackets"):WaitForChild(player.Name)
local drop = remotes:WaitForChild("PlayerDrop")

local TILE_SIZE = 4.5
local SHOW_LOG = true

function printLogToConsole(text, type, ...)
    if SHOW_LOG then
        local message = string.format(text, ...)

        if type == "error" then
            error("[ERROR] " .. message)
        elseif type == "info" then
            warn("[INFO] " .. message)
        elseif type == "basic" then
            print(message)
        else
            error("[ERROR] Invalid log type: " .. type)
        end
    else
        return nil
    end
end
-- Helper
--[[ 
    get tile untuk mengecek tile player berada convert dari real position to tile position
]]
function getTile() 
    local pos = root.Position
    local tileX = math.floor(pos.X / TILE_SIZE + 0.5)
    local tileY = math.floor(pos.Y / TILE_SIZE + 0.5)
    printLogToConsole("BOT IN TILE: %d, %d REAL POS: %f, %f", "info", tileX, tileY, pos.X, pos.Y)
    return {X = tileX, Y = tileY}
end
--[[ 
    getitemsmanager untuk mendapatkan itemsmanager
]]
local function getItemsManager()
    local success, manager = pcall(function()
        return require(game:GetService("ReplicatedStorage"):WaitForChild("Managers"):WaitForChild("ItemsManager"))
    end)
    return success and manager or nil
end

--[[ 
    getblockname untuk mendapatkan nama block dari id block
]]
function getBlockName(blockId)
    if not blockId then return "None" end
    local itemsManager = getItemsManager()
    if itemsManager and itemsManager.NumberToStringMap then
        return itemsManager.NumberToStringMap[blockId] or tostring(blockId)
    end
    return tostring(blockId)
end

--[[ 
    getinventoryfromserver untuk mendapatkan inventory dari server
]]
function getInventoryFromServer()
    local success, inv = pcall(function()
        return require(game:GetService("ReplicatedStorage").Modules.Inventory)
    end)
    return success and inv or nil
end

--[[ 
    getinventory untuk mendapatkan inventory dari player
    jika block_name diisi, maka akan mencari item dengan nama block_name
    jika block_name tidak diisi, maka akan mencari semua item
]]
function getInventory(block_name)
    local inv = getInventoryFromServer()
    if not inv or not inv.Stacks then return nil, 0 end

    local itemsManager = getItemsManager()

    if not block_name or block_name == "" then
        printLogToConsole("SEARCHING ALL ITEMS", "info")
        local found = false
        for i, v in pairs(inv.Stacks) do
            local itemName = tostring(v.Id)
            if itemsManager and itemsManager.NumberToStringMap then
                itemName = itemsManager.NumberToStringMap[v.Id] or itemName
            end
            printLogToConsole("SLOT %-3d: %-25s | AMOUNT: %d", "basic", i, itemName, v.Amount or 0)
            found = true
        end
        if not found then printLogToConsole("INVENTORY IS EMPTY.", "info") end
        return nil, 0
    end

    -- If block_name is provided, search and print matching items
    printLogToConsole("SEARCHING FOR: %s", "info", tostring(block_name))
    local searchPattern = tostring(block_name):lower()
    local isSearchingForSapling = searchPattern:find("sapling") or searchPattern:find("seed")

    -- Pass 1: Look for Exact Match (ID or Name)
    for i, v in pairs(inv.Stacks) do
        local itemName = tostring(v.Id)
        local rawId = v.Id
        if itemsManager and itemsManager.NumberToStringMap then
            itemName = itemsManager.NumberToStringMap[v.Id] or itemName
        end
        
        if tostring(rawId) == tostring(block_name) or itemName:lower() == searchPattern then
            printLogToConsole("[EXACT MATCH] SLOT %-3d: %-25s | AMOUNT: %d", "basic", i, itemName, v.Amount or 0)
            return i, v.Amount or 0
        end
    end

    -- Pass 2: Look for Smart Match (Block vs Sapling)
    local partialMatches = {}
    for i, v in pairs(inv.Stacks) do
        local itemName = tostring(v.Id)
        if itemsManager and itemsManager.NumberToStringMap then
            itemName = itemsManager.NumberToStringMap[v.Id] or itemName
        end
        
        local itemNameLower = itemName:lower()
        if itemNameLower:find(searchPattern, 1, true) then
            local isItemSapling = itemNameLower:find("sapling") or itemNameLower:find("seed")
            
            -- If we are NOT searching for a sapling, prioritize non-sapling items
            if not isSearchingForSapling and not isItemSapling then
                printLogToConsole("[BLOCK MATCH] SLOT %-3d: %-25s | AMOUNT: %d", "basic", i, itemName, v.Amount or 0)
                return i, v.Amount or 0
            end
            
            -- If we ARE searching for a sapling, prioritize sapling items
            if isSearchingForSapling and isItemSapling then
                printLogToConsole("[SEED MATCH] SLOT %-3d: %-25s | AMOUNT: %d", "basic", i, itemName, v.Amount or 0)
                return i, v.Amount or 0
            end

            table.insert(partialMatches, {slot = i, name = itemName, amount = v.Amount or 0})
        end
    end

    -- Final fallback: Use the first partial match found if no prioritized match
    if #partialMatches > 0 then
        local match = partialMatches[1]
        printLogToConsole("[PARTIAL MATCH] SLOT %-3d: %-25s | AMOUNT: %d", "basic", match.slot, match.name, match.amount)
        return match.slot, match.amount
    end
    
    printLogToConsole("NO ITEMS FOUND MATCHING: %s", "info", tostring(block_name))
    return nil, 0
end


--[[ 
    getworld untuk mendapatkan world dari server
    radius adalah radius dari world yang akan diambil
    jika radius tidak diisi, maka akan mengambil world dengan radius 1
]]
local function checkIsSolid(blockId)
    if not blockId then return false end
    local itemsManager = getItemsManager()
    local idStr = tonumber(blockId) and "" or tostring(blockId):lower()
    local nonSolidKeywords = {"sapling", "frame", "door", "platform", "ladder", "climb", "gate", "bridge", "sign"}
    for _, kw in ipairs(nonSolidKeywords) do
        if idStr:find(kw, 1, true) then return false end
    end
    if itemsManager then
        local itemData = nil
        pcall(function() itemData = itemsManager.RequestItemData(blockId) end)
        if itemData then
            if itemData.Background or itemData.IsBackground then return false end
            local name = (itemData.Name or ""):lower()
            for _, kw in ipairs(nonSolidKeywords) do
                if name:find(kw, 1, true) then return false end
            end
        end
    end
    return true
end

local worldTilesCached = nil
function isTilePassable(x, y)
    if not worldTilesCached then
        local success, worldTiles = pcall(function()
            return require(game:GetService("ReplicatedStorage"):WaitForChild("WorldTiles"))
        end)
        if success then worldTilesCached = worldTiles end
    end
    
    local worldTiles = worldTilesCached
    if not worldTiles then return true end -- Asumsi bisa dilewati jika gagal load

    local tileData = worldTiles[x] and worldTiles[x][y]
    if not tileData then return true end

    -- Cek layer 1 (Foreground)
    local fGround = tileData[1]
    if type(fGround) == "table" and fGround[1] then fGround = fGround[1] end
    
    if fGround and checkIsSolid(fGround) then
        return false
    end
    
    return true
end

function getWorld(radius)
    local success, worldTiles = pcall(function()
        return require(game:GetService("ReplicatedStorage"):WaitForChild("WorldTiles"))
    end)
    if not success or not worldTiles then return end

    local itemsManager = getItemsManager()

    local function getLayerData(x, y, layer)
        local tileData = worldTiles[x] and worldTiles[x][y]
        if not tileData then return nil end
        local lData = tileData[layer]
        if lData then
            if type(lData) == "table" and lData[1] then return lData[1]
            elseif type(lData) ~= "table" then return lData end
        end
        return nil
    end

    local function getAllFloatingItems()
        local detectedItems = {} -- [x][y] = { [itemId] = amount }
        
        local targetFolders = {
            workspace:FindFirstChild("Drops"),
            workspace:FindFirstChild("Gems"),
            workspace:FindFirstChild("DroppedItems")
        }
        
        local function scanItem(item)
            local descendants = item:GetDescendants()
            table.insert(descendants, 1, item)

            for _, obj in ipairs(descendants) do
                if obj:IsA("BasePart") or obj:IsA("Model") then
                    local name = obj.Name:lower()
                    if name:find("effect", 1, true) or name:find("shadow", 1, true) or name:find("highlight", 1, true) or name:find("particle", 1, true) then continue end

                    local pos = obj:IsA("Model") and (obj.PrimaryPart and obj.PrimaryPart.Position or obj:GetPivot().Position) or obj.Position
                    if pos then
                        local tx = math.floor(pos.X / TILE_SIZE + 0.5)
                        local ty = math.floor(pos.Y / TILE_SIZE + 0.5)
                        
                        local itemId = obj:GetAttribute("id")
                        local itemAmount = obj:GetAttribute("amount") or 1
                        
                        if itemId then
                            if not detectedItems[tx] then detectedItems[tx] = {} end
                            if not detectedItems[tx][ty] then detectedItems[tx][ty] = {} end
                            
                            detectedItems[tx][ty][itemId] = (detectedItems[tx][ty][itemId] or 0) + itemAmount
                            return true -- Stop scanning this item once processed
                        end
                    end
                end
            end
            return false
        end

        for _, folder in ipairs(targetFolders) do
            if folder then
                for _, child in ipairs(folder:GetChildren()) do
                    scanItem(child)
                end
            end
        end
        return detectedItems
    end

    if type(radius) ~= "number" or radius < 0 then
        error("[ERROR] radius must be a non-negative number")
    end

    local tile = getTile()
    printLogToConsole("CALLING FUNCTION getWorld WITH RADIUS: %d", "info", radius)
    local floatLogs = {} -- Tabel untuk menampung log float sementara
    local floatingMap = getAllFloatingItems()

    for dy = radius, -radius, -1 do
        for dx = -radius, radius do
            local absX, absY = tile.X + dx, tile.Y + dy
            local fGround = getLayerData(absX, absY, 1)
            local bGround = getLayerData(absX, absY, 2)
            local floats = floatingMap[absX] and floatingMap[absX][absY]
            
            -- Print blok FG/BG langsung
            if fGround or bGround then
                local fName = fGround and getBlockName(fGround) or "EMPTY"
                local bName = bGround and getBlockName(bGround) or "EMPTY"
                local status = checkIsSolid(fGround) and "SOLID" or "PASSABLE"
                printLogToConsole("[ GROUND ] CORD: [%d, %d] | FG: %-15s | BG: %-15s | STATUS: %-8s", "basic", absX, absY, fName, bName, status)
            end

            -- Simpan info float untuk di-print paling akhir
            if floats then
                for id, amt in pairs(floats) do
                    table.insert(floatLogs, string.format("[ FLOATING ] CORD: [%d, %d] | ITEM: %-20s | COUNT: %-5d | STATUS: PASSABLE", absX, absY, id, amt))
                end
            end
        end
    end

    -- Print semua floating items di bagian paling bawah
    if #floatLogs > 0 then
        for _, log in ipairs(floatLogs) do
            printLogToConsole("%s", "basic", log)
        end
    end
end

--[[ 
    moveToTile (Internal) - VERSI ANTI-STUCK TOTAL
    Mengembalikan status apakah bot BENERAN pindah posisi atau macet
]]
local function moveToTile(tileX, tileY)
    local char = player.Character or player.CharacterAdded:Wait()
    local root = char:WaitForChild("HumanoidRootPart")
    
    local worldX = tileX * TILE_SIZE
    local worldY = tileY * TILE_SIZE
    local startPos = root.Position
    local targetPos = Vector3.new(worldX, worldY, startPos.Z)
    
    local distance = (targetPos - startPos).Magnitude
    if distance < 0.1 then return true end 
    
    local steps = math.ceil(distance / 1.5)
    local lastCheckPos = root.Position
    
    for i = 1, steps do
        if not root or not root.Parent then return false end
        
        local alpha = i / steps
        local intermediatePos = startPos:Lerp(targetPos, alpha)
        
        root.Velocity = Vector3.new(0, 0, 0)
        root.RotVelocity = Vector3.new(0, 0, 0)
        root.CFrame = CFrame.new(intermediatePos) * (root.CFrame - root.CFrame.Position)
        
        pcall(function()
            movement:FireServer(Vector2.new(intermediatePos.X, intermediatePos.Y))
        end)
        
        task.wait(0.01)
    end
    
    -- Snap akhir & Verifikasi Fisik
    if root and root.Parent then
        root.CFrame = CFrame.new(targetPos) * (root.CFrame - root.CFrame.Position)
        pcall(function()
            movement:FireServer(Vector2.new(worldX, worldY))
        end)
        
        -- CEK APAKAH POSISI BENERAN BERUBAH DARI START
        local finalDist = (root.Position - targetPos).Magnitude
        if finalDist > 1 then -- Jika masih jauh dari target setelah lerp selesai
            return false -- Terdeteksi STUCK secara fisik
        end
    end
    
    return true
end

function movePosition(targetX, targetY)
    if not targetX or not targetY then 
        printLogToConsole("INVALID COORDINATES FOR movePosition", "error")
        return 
    end

    local arrivedAtFinal = false
    local mainLoopRetries = 0
    local maxMainLoops = 20 -- Lebih banyak kesempatan untuk world jauh

    while not arrivedAtFinal and mainLoopRetries < maxMainLoops do
        mainLoopRetries = mainLoopRetries + 1
        local current = getTile()
        
        -- 1. SMART TARGET
        local finalTargetX, finalTargetY = targetX, targetY
        if not isTilePassable(targetX, targetY) then
            local offsets = {{X=1, Y=0}, {X=-1, Y=0}, {X=0, Y=1}, {X=0, Y=-1}, {X=1, Y=1}, {X=-1, Y=1}, {X=1, Y=-1}, {X=-1, Y=-1}}
            for _, off in ipairs(offsets) do
                if isTilePassable(targetX + off.X, targetY + off.Y) then
                    finalTargetX = targetX + off.X
                    finalTargetY = targetY + off.Y
                    break
                end
            end
        end

        if current.X == finalTargetX and current.Y == finalTargetY then
            arrivedAtFinal = true
            break
        end

        -- 2. BFS Pathfinding
        local startNode = {X = current.X, Y = current.Y, Parent = nil, Dir = nil}
        local queue = {startNode}
        local head = 1 
        local visited = {}
        visited[current.X .. "," .. current.Y] = true
        local endNode = nil
        local directions = {{X=1, Y=0, Name="RIGHT"}, {X=-1, Y=0, Name="LEFT"}, {X=0, Y=1, Name="UP"}, {X=0, Y=-1, Name="DOWN"}}

        local limit = 50000 
        local count = 0
        while head <= #queue and count < limit do
            count = count + 1
            local node = queue[head]
            head = head + 1
            if node.X == finalTargetX and node.Y == finalTargetY then
                endNode = node
                break
            end
            for _, dir in ipairs(directions) do
                local nextX, nextY = node.X + dir.X, node.Y + dir.Y
                if not visited[nextX .. "," .. nextY] and isTilePassable(nextX, nextY) then
                    visited[nextX .. "," .. nextY] = true
                    table.insert(queue, {X = nextX, Y = nextY, Parent = node, Dir = dir.Name})
                end
            end
        end

        if not endNode then break end

        -- 3. Rekonstruksi rute
        local foundPath = {}
        local curr = endNode
        while curr.Parent do
            table.insert(foundPath, 1, curr)
            curr = curr.Parent
        end

        -- 4. Execute REALTIME Movement dengan DETEKSI STUCK PAKSA
        local pathAborted = false
        for i, step in ipairs(foundPath) do
            local stepSuccess = false
            
            -- COBA PINDAH (Verifikasi di dalam moveToTile)
            if moveToTile(step.X, step.Y) then
                -- Cek lagi jarak stud di sini untuk double check
                local currentPos = root.Position
                local targetWorldPos = Vector3.new(step.X * TILE_SIZE, step.Y * TILE_SIZE, currentPos.Z)
                local dist = (Vector3.new(currentPos.X, currentPos.Y, targetWorldPos.Z) - targetWorldPos).Magnitude
                
                if dist < 1.2 then
                    stepSuccess = true
                end
            end
            
            if not stepSuccess then
                -- JIKA MACET, LANGSUNG FORCE SNAP TANPA AMPUN
                printLogToConsole("!!! STUCK DETECTED AT [%d, %d] !!! FORCE SNAPPING...", "info", step.X, step.Y)
                
                root.Velocity = Vector3.new(0, 0, 0)
                root.CFrame = CFrame.new(step.X * TILE_SIZE, step.Y * TILE_SIZE, root.Position.Z) * (root.CFrame - root.CFrame.Position)
                
                -- Kirim packet paksa ke server
                pcall(function()
                    movement:FireServer(Vector2.new(step.X * TILE_SIZE, step.Y * TILE_SIZE))
                end)
                
                task.wait(0.1) -- Jeda biar physics Roblox nyadar posisi baru
                
                -- Cek lagi, kalau masih gagal juga setelah snap, baru abort rute
                local finalCheckDist = (root.Position - Vector3.new(step.X * TILE_SIZE, step.Y * TILE_SIZE, root.Position.Z)).Magnitude
                if finalCheckDist > 1.5 then
                    pathAborted = true
                    break
                end
            end
            
            if i % 10 == 0 then printLogToConsole("MOVING... (%d/%d)", "basic", i, #foundPath) end
        end

        -- Verifikasi posisi akhir
        local finalCheck = getTile()
        if finalCheck.X == finalTargetX and finalCheck.Y == finalTargetY then
            arrivedAtFinal = true
            break
        else
            printLogToConsole("RE-CALCULATING PATH... [%d/%d]", "warn", mainLoopRetries, maxMainLoops)
            task.wait(0.2)
        end
    end

    if arrivedAtFinal then
        printLogToConsole("ARRIVED AT DESTINATION: (%d, %d)", "info", targetX, targetY)
    else
        printLogToConsole("FAILED TO REACH DESTINATION.", "error")
    end
end

movePosition(1, 0)
