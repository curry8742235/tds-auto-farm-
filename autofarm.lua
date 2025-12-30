-- // ========================================================== //
-- //      TDS AUTOSTRAT - STANDALONE VERSION (NO LINKS)         //
-- //      INCLUDES: Ground Targeting, Anti-Road, Auto-Anchor    //
-- // ========================================================== //

-- // 1. CONFIGURATION
getgenv().AutoStrat = true
getgenv().AutoSkip = true 
getgenv().AutoPickups = true
getgenv().Webhook = "" 

-- // 2. INTERNAL LIBRARY (NO LOADSTRING NEEDED)
local TDS = {}
TDS.placed_towers = {}
TDS.Services = {
    Workspace = game:GetService("Workspace"),
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
    Players = game:GetService("Players"),
    RunService = game:GetService("RunService")
}
TDS.LocalPlayer = TDS.Services.Players.LocalPlayer
TDS.Remote = TDS.Services.ReplicatedStorage:WaitForChild("RemoteFunction")

-- // MAP ENGINE
local MapEngine = {}
MapEngine.RecAnchor = Vector3.new(-48.8, 3.8, 14.5) -- Simplicity Spawn
MapEngine.CurrentAnchor = Vector3.zero
MapEngine.Offset = Vector3.zero

function MapEngine:GetPos(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj.Position end
    if obj:IsA("Model") or obj:IsA("Folder") then
        local p = obj:FindFirstChild("0") or obj:FindFirstChild("1") or obj:FindFirstChild("Start") or obj:FindFirstChildWhichIsA("BasePart")
        if p and p:IsA("BasePart") then return p.Position end
        for _, c in ipairs(obj:GetChildren()) do
            if c:IsA("BasePart") then return c.Position end
        end
    end
    return nil
end

function MapEngine:FindAnchor()
    local map = TDS.Services.Workspace:FindFirstChild("Map")
    if not map then return Vector3.zero end

    -- Priority 1: Paths Folder
    if map:FindFirstChild("Paths") then
        local p = map.Paths
        local startNode = p:FindFirstChild("0") or p:FindFirstChild("1") or p:FindFirstChild("Start")
        
        if not startNode and p:FindFirstChild("Path") then
            startNode = p.Path:FindFirstChild("0")
        end
        
        if not startNode then
            local lowest = 9999
            for _, c in ipairs(p:GetChildren()) do
                local n = tonumber(c.Name)
                if n and n < lowest then lowest = n startNode = c end
            end
        end
        local pos = self:GetPos(startNode)
        if pos then return pos end
    end

    -- Priority 2: EnemySpawn
    if map:FindFirstChild("EnemySpawn") then return map.EnemySpawn.Position end
    
    return Vector3.zero
end

-- // RAYCAST: GROUND TARGETING
function MapEngine:FindValidGround(x, z)
    local map = TDS.Services.Workspace:FindFirstChild("Map")
    local origin = Vector3.new(x, self.CurrentAnchor.Y + 300, z)
    local dir = Vector3.new(0, -600, 0)
    
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include 
    
    local whitelist = {}
    
    -- Explicitly add Ground folders
    if TDS.Services.Workspace:FindFirstChild("Ground") then 
        table.insert(whitelist, TDS.Services.Workspace.Ground) 
    end
    
    if map then
        if map:FindFirstChild("Ground") then table.insert(whitelist, map.Ground) end
        if map:FindFirstChild("Environment") then table.insert(whitelist, map.Environment) end
    end
    
    -- Fallback mechanism
    if #whitelist == 0 then
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {
            TDS.LocalPlayer.Character,
            TDS.Services.Workspace.Towers,
            TDS.Services.Workspace.Camera,
            map and map:FindFirstChild("Road"),
            map and map:FindFirstChild("Cliff"),
            map and map:FindFirstChild("Boundaries"),
            map and map:FindFirstChild("Paths")
        }
    else
        params.FilterDescendantsInstances = whitelist
    end

    local res = TDS.Services.Workspace:Raycast(origin, dir, params)
    
    if res and res.Instance then
        return res.Position.Y + 0.1
    end
    
    return nil
end

function MapEngine:Initialize()
    if not TDS.Services.Workspace:FindFirstChild("Map") then
        TDS.Services.Workspace.ChildAdded:Wait()
        task.wait(1)
    end
    self.CurrentAnchor = self:FindAnchor()
    if self.CurrentAnchor ~= Vector3.zero then
        self.Offset = self.CurrentAnchor - self.RecAnchor
        print("[DeepSeek] ✅ Map Adapted. Offset:", self.Offset)
    else
        warn("[DeepSeek] ⚠️ ANCHOR NOT FOUND.")
    end
end

MapEngine:Initialize()

-- // TDS FUNCTIONS
function TDS:Place(name, recX, recY, recZ)
    local baseX = recX + MapEngine.Offset.X
    local baseZ = recZ + MapEngine.Offset.Z
    
    local radius_limit = 45
    local step_size = 3.5
    
    for r = 0, radius_limit, step_size do
        local points = (r == 0) and 1 or math.floor((2 * math.pi * r) / step_size)
        for i = 1, points do
            local angle = (math.pi * 2 / points) * i
            local tryX = baseX + (math.cos(angle) * r)
            local tryZ = baseZ + (math.sin(angle) * r)
            
            local groundY = MapEngine:FindValidGround(tryX, tryZ)
            
            -- Fallback estimation if raycast fails at center
            if not groundY and r == 0 then
               groundY = MapEngine.CurrentAnchor.Y + (recY - MapEngine.RecAnchor.Y)
            end

            if groundY then
                local target = Vector3.new(tryX, groundY, tryZ)
                local s, res = pcall(function()
                    return self.Remote:InvokeServer("Troops", "Place", {
                        Rotation = CFrame.new(),
                        Position = target
                    }, name)
                end)

                if s and (res == true or (type(res)=="table" and res.Success)) then
                    local tOut = tick() + 2
                    repeat task.wait() until tick() > tOut or #TDS.Services.Workspace.Towers:GetChildren() > #self.placed_towers
                    for _, t in ipairs(TDS.Services.Workspace.Towers:GetChildren()) do
                        if t.Name == name and t.Owner.Value == TDS.LocalPlayer.UserId then
                            local known = false
                            for _, k in ipairs(self.placed_towers) do if k==t then known=true end end
                            if not known then
                                table.insert(self.placed_towers, t)
                                print("✅ PLACED:", name, "| R:", r)
                                return 
                            end
                        end
                    end
                end
            end
        end
    end
    print("❌ FAILED:", name, "- Attempting Force Place...")
    pcall(function()
        self.Remote:InvokeServer("Troops", "Place", {
            Rotation = CFrame.new(),
            Position = Vector3.new(baseX, MapEngine.CurrentAnchor.Y, baseZ)
        }, name)
    end)
end

function TDS:Upgrade(idx)
    local t = self.placed_towers[idx]
    if t then pcall(function() self.Remote:InvokeServer("Troops", "Upgrade", "Set", {Troop=t, Path=1}) end) end
end

function TDS:Skip()
    pcall(function() self.Remote:InvokeServer("Voting", "Skip") end)
end

task.spawn(function()
    while task.wait(1) do
        if getgenv().AutoSkip then
            local v = TDS.LocalPlayer.PlayerGui:FindFirstChild("ReactOverridesVote")
            if v and v.Frame.Visible then TDS:Skip() end
        end
    end
end)

-- // ========================================== //
-- //      STRATEGY EXECUTION START              //
-- // ========================================== //

TDS:Place("Scout", -18.16, 1.00, -2.36) -- 1
TDS:Place("Scout", -18.17, 1.00, -5.55) -- 2
TDS:Place("Scout", -18.19, 1.00, -8.74) -- 3
TDS:Place("Scout", -14.89, 1.00, -9.23) -- 4
TDS:Place("Scout", -17.18, 1.00, -11.71) -- 5
TDS:Place("Scout", -19.92, 1.00, -13.37) -- 6
TDS:Place("Scout", -17.09, 1.00, -14.89) -- 7
TDS:Place("Scout", -14.19, 1.00, -12.89) -- 8
TDS:Place("Scout", -11.89, 1.00, -10.53) -- 9
TDS:Place("Scout", -11.78, 1.00, -3.17) -- 10
TDS:Place("Scout", -8.58, 1.00, -2.99) -- 11
TDS:Place("Scout", -11.85, 1.00, 0.04) -- 12
TDS:Place("Scout", -8.53, 1.00, 0.17) -- 13
TDS:Place("Scout", -11.81, 1.00, 3.27) -- 14
TDS:Place("Scout", -8.53, 1.00, 3.45) -- 15
TDS:Place("Scout", -14.97, 1.00, 3.62) -- 16
TDS:Place("Scout", -18.32, 1.00, 3.66) -- 17
TDS:Place("Scout", -21.56, 1.00, 3.69) -- 18
TDS:Place("Scout", -21.55, 1.00, 7.07) -- 19
TDS:Place("Scout", -18.18, 1.00, 7.07) -- 20
TDS:Place("Scout", -14.82, 1.00, 6.91) -- 21
TDS:Place("Scout", -11.70, 1.00, 6.73) -- 22
TDS:Place("Scout", -8.36, 1.00, 6.84) -- 23
TDS:Place("Scout", -5.36, 1.00, -3.08) -- 24
TDS:Place("Scout", -8.55, 1.00, -9.23) -- 25
TDS:Place("Scout", -4.77, 1.00, -9.17) -- 26
TDS:Place("Scout", -2.12, 1.00, -3.02) -- 27
TDS:Place("Scout", -1.53, 1.00, -9.31) -- 28
TDS:Place("Scout", -24.45, 1.00, -5.66) -- 29
TDS:Place("Scout", -24.49, 1.00, -2.38) -- 30
TDS:Place("Scout", -24.47, 1.00, 1.04) -- 31
TDS:Place("Scout", -24.80, 1.00, 4.40) -- 32
TDS:Place("Scout", -27.41, 1.00, -7.94) -- 33
TDS:Place("Scout", -27.25, 1.00, -11.07) -- 34
TDS:Place("Scout", -1.83, 1.00, 3.27) -- 35
TDS:Place("Scout", 1.25, 1.00, -3.35) -- 36
TDS:Place("Scout", 4.46, 1.00, -3.42) -- 37
TDS:Place("Scout", 1.42, 1.00, 3.43) -- 38
TDS:Place("Scout", 5.39, 1.00, 3.24) -- 39
TDS:Place("Scout", 6.56, 1.00, -7.08) -- 40

-- Max Upgrade Loop
for lvl = 1, 4 do
    for i = 1, 40 do TDS:Upgrade(i) end
    task.wait(1.5)
end
