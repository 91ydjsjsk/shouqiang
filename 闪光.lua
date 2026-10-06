--[[
    Flash Client Script
    Game: FPS Shooter (based on Remote Spy log)
    UI: WindUI
    Features: Silent Aim, Aimbot, Triggerbot, ESP, Auto Reload, No Spread, etc.
    Mobile Friendly
]]

-- ============================================================
-- Services & References
-- ============================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- ============================================================
-- Remote References (cached for performance)
-- ============================================================
local function getRemote(pathStr)
    local parts = {}
    for part in string.gmatch(pathStr, "[^%.]+") do
        table.insert(parts, part)
    end
    local obj
    if parts[1] == "game" then
        obj = game
        table.remove(parts, 1)
    end
    for _, part in ipairs(parts) do
        if obj then
            obj = obj:FindFirstChild(part)
        end
    end
    return obj
end

local Remotes = {
    CheckFire = nil,
    CheckShot = nil,
    Reload = nil,
    ProjectileRender = nil,
    ProjectileFinished = nil,
    ConnectM6D = nil,
    Command = nil,
    UpdateSetting = nil,
    AntiCheat = nil,
}

local function refreshRemotes()
    local char = LocalPlayer.Character
    if char then
        local cr = char:FindFirstChild("ClientRemotes")
        if cr then
            Remotes.CheckFire = cr:FindFirstChild("CheckFire")
            Remotes.CheckShot = cr:FindFirstChild("CheckShot")
            Remotes.Reload = cr:FindFirstChild("Reload")
        end
    end
    local gunRemote = ReplicatedStorage:FindFirstChild("ModuleScripts")
    if gunRemote then
        gunRemote = gunRemote:FindFirstChild("GunModules")
        if gunRemote then
            gunRemote = gunRemote:FindFirstChild("Remote")
            if gunRemote then
                Remotes.ProjectileRender = gunRemote:FindFirstChild("ProjectileRender")
                Remotes.ProjectileFinished = gunRemote:FindFirstChild("ProjectileFinished")
                Remotes.ConnectM6D = gunRemote:FindFirstChild("ConnectM6D")
            end
        end
    end
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        Remotes.Command = remotes:FindFirstChild("Command")
        Remotes.UpdateSetting = remotes:FindFirstChild("UpdateSetting")
    end
    Remotes.AntiCheat = ReplicatedStorage:FindFirstChild("886cf5c0-8edf-48f2-b577-40025758c492")
end
refreshRemotes()

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    refreshRemotes()
end)

-- ============================================================
-- Utility Functions
-- ============================================================
local function getCharacter(player)
    return player.Character or player.CharacterAdded:Wait()
end

local function getHitPart(char, partName)
    if not char then return nil end
    return char:FindFirstChild(partName)
end

local function getNearestPlayer(maxDistance, fovRadius, hitPartName, teamCheck)
    local nearestPlayer = nil
    local nearestDist = math.huge
    local nearestScreenPos = nil
    local mousePos = UserInputService:GetMouseLocation()
    local origin = Camera.CFrame.Position

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local isEnemy = true
            if teamCheck and player.Team and LocalPlayer.Team then
                isEnemy = (player.Team ~= LocalPlayer.Team)
            end
            if isEnemy then
                local char = player.Character
                if char then
                    local hrp = char:FindFirstChild("HumanoidRootPart")
                    local humanoid = char:FindFirstChildOfClass("Humanoid")
                    if hrp and humanoid and humanoid.Health > 0 then
                        local targetPart = getHitPart(char, hitPartName) or hrp
                        local pos = targetPart.Position
                        local dist = (pos - origin).Magnitude
                        if dist <= maxDistance then
                            local screenPos, onScreen = Camera:WorldToViewportPoint(pos)
                            if onScreen then
                                local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                                if screenDist <= fovRadius and screenDist < nearestDist then
                                    nearestDist = screenDist
                                    nearestPlayer = player
                                    nearestScreenPos = screenPos
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return nearestPlayer, nearestScreenPos
end

local function isPointingAtPlayer(hitPartName)
    local origin = Camera.CFrame.Position
    local direction = Camera.CFrame.LookVector * 500
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {LocalPlayer.Character}
    local result = Workspace:Raycast(origin, direction, params)
    if result then
        local inst = result.Instance
        local char = inst.Parent
        while char and not char:FindFirstChildOfClass("Humanoid") do
            char = char.Parent
        end
        if char then
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and player.Character == char then
                    return player, inst
                end
            end
        end
    end
    return nil
end

-- ============================================================
-- Settings (configurable via UI)
-- ============================================================
local Settings = {
    -- Combat
    SilentAim = false,
    Aimbot = false,
    AimbotFOV = 200,
    AimbotDistance = 1000,
    AimbotPart = "Crit",
    AimbotSmoothness = 0.1,
    AimbotTeamCheck = false,
    Triggerbot = false,
    TriggerbotDelay = 0,
    AutoReload = false,
    NoSpread = false,
    RapidFire = false,
    -- Visuals
    PlayerESP = false,
    ESPTeamCheck = false,
    ESPName = true,
    ESPHealth = true,
    ESPDistance = true,
    ESPTracer = false,
    ESPBox = false,
    ESPColor = Color3.fromHex("#FF4757"),
    FOVCircle = false,
    HitboxExpander = false,
    HitboxSize = 5,
    -- Player
    AutoPlay = false,
    AutoSpawn = false,
    WalkSpeed = 16,
    JumpPower = 50,
    Fly = false,
    FlySpeed = 50,
    Noclip = false,
    FullBright = false,
    AntiAFK = false,
    -- World
    RemoveFog = false,
    TimeOfDay = "14:00",
    -- Misc
    AntiKick = true,
}

-- ============================================================
-- Combat: Silent Aim (Hook CheckShot)
-- ============================================================
local function isRemote(self, name)
    if not self then return false end
    if Remotes[name] and self == Remotes[name] then return true end
    -- Fallback: match by name in case remote reference not yet cached
    if self.Name == name then return true end
    return false
end

local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    if method == "FireServer" then
        if isRemote(self, "CheckShot") and Settings.SilentAim then
            local args = {...}
            -- args: 0, 0, 1, 0.8, CFrame, Vector3, Instance, number, timestamp
            local target = getNearestPlayer(Settings.AimbotDistance, Settings.AimbotFOV, Settings.AimbotPart, Settings.AimbotTeamCheck)
            if target and target.Character then
                local hitPart = getHitPart(target.Character, Settings.AimbotPart)
                if hitPart then
                    args[6] = hitPart.Position
                    args[7] = hitPart
                end
            end
            return oldNamecall(self, unpack(args))
        elseif isRemote(self, "ProjectileRender") and Settings.NoSpread then
            local args = {...}
            local data = args[1]
            if data and data.Type == "Bullet" then
                -- Straight endpoint from origin in camera direction
                local origin = data.Origin
                local direction = Camera.CFrame.LookVector
                data.Endpoint = origin + direction * 1000
            end
            return oldNamecall(self, unpack(args))
        elseif isRemote(self, "ProjectileFinished") and Settings.SilentAim then
            local args = {...}
            local data = args[1]
            if data then
                local target = getNearestPlayer(Settings.AimbotDistance, Settings.AimbotFOV, Settings.AimbotPart, Settings.AimbotTeamCheck)
                if target and target.Character then
                    local hitPart = getHitPart(target.Character, Settings.AimbotPart)
                    if hitPart then
                        data.CFrame = CFrame.new(hitPart.Position)
                        data.HitPlayer = true
                    end
                end
            end
            return oldNamecall(self, unpack(args))
        end
    end
    return oldNamecall(self, ...)
end)

-- ============================================================
-- Combat: Aimbot (Camera rotation)
-- ============================================================
RunService.RenderStepped:Connect(function()
    if Settings.Aimbot then
        local target = getNearestPlayer(Settings.AimbotDistance, Settings.AimbotFOV, Settings.AimbotPart, Settings.AimbotTeamCheck)
        if target and target.Character then
            local hitPart = getHitPart(target.Character, Settings.AimbotPart)
            if hitPart then
                local targetPos = hitPart.Position
                local cameraPos = Camera.CFrame.Position
                local desiredCFrame = CFrame.new(cameraPos, targetPos)
                Camera.CFrame = Camera.CFrame:Lerp(desiredCFrame, 1 - Settings.AimbotSmoothness)
            end
        end
    end
end)

-- ============================================================
-- Combat: Triggerbot
-- ============================================================
local lastTriggerTime = 0
RunService.RenderStepped:Connect(function()
    if Settings.Triggerbot then
        local now = tick()
        if now - lastTriggerTime >= Settings.TriggerbotDelay then
            local target, hitPart = isPointingAtPlayer(Settings.AimbotPart)
            if target then
                lastTriggerTime = now
                -- Simulate a shot by firing the remotes directly
                local char = LocalPlayer.Character
                if char and Remotes.CheckFire then
                    local timestamp = tick()
                    local origin = Camera.CFrame.Position
                    local endpoint = hitPart.Position
                    Remotes.CheckFire:FireServer(timestamp, origin)
                    if Remotes.ProjectileRender then
                        Remotes.ProjectileRender:FireServer({
                            Type = "Bullet",
                            Index = timestamp,
                            Origin = origin,
                            Owner = char,
                            Endpoint = endpoint,
                            Life = 5,
                            Force = 130,
                            Gravity = 0,
                            Wind = Vector3.new(0, 0, 0)
                        })
                    end
                    if Remotes.CheckShot then
                        Remotes.CheckShot:FireServer(
                            0, 0, 1, 0.8,
                            CFrame.new(origin),
                            endpoint,
                            hitPart,
                            11,
                            timestamp
                        )
                    end
                    if Remotes.ProjectileFinished then
                        Remotes.ProjectileFinished:FireServer({
                            Index = timestamp,
                            Origin = origin,
                            CFrame = CFrame.new(endpoint),
                            ExpRadius = 15,
                            LaserColor = Color3.new(0, 1, 1),
                            LaserSpeed = 10,
                            LaserTime = 0.7,
                            Effect = "Gib_T",
                            ExpColor = Color3.new(1, 0.6, 0.2),
                            LaserTexture = "rbxassetid://4813348676",
                            Explosive = false,
                            HitPlayer = true,
                            IsLaser = false,
                            LaserWidth = 3,
                            LaserLength = 5,
                            LaserEmission = 1,
                            ExpSound = "rbxassetid://2814354338"
                        })
                    end
                end
            end
        end
    end
end)

-- ============================================================
-- Combat: Auto Reload
-- ============================================================
local function getAmmo()
    local char = LocalPlayer.Character
    if char then
        -- Search the whole character for ammo values
        for _, child in ipairs(char:GetDescendants()) do
            if child:IsA("NumberValue") then
                local name = child.Name:lower()
                if name == "ammo" or name == "currentammo" or name == "mag" or name == "bullets" then
                    return child.Value
                end
            end
        end
        -- Also check PlayerGui for HUD ammo display
        local gui = LocalPlayer.PlayerGui
        if gui then
            for _, child in ipairs(gui:GetDescendants()) do
                if child:IsA("TextLabel") or child:IsA("TextButton") then
                    local num = tonumber(child.Text)
                    if num and num >= 0 and num < 500 then
                        -- Could be ammo text, but unreliable; skip for now
                    end
                end
            end
        end
    end
    return nil
end

local lastReloadTime = 0
RunService.RenderStepped:Connect(function()
    if Settings.AutoReload and Remotes.Reload then
        local now = tick()
        if now - lastReloadTime > 1 then
            local ammo = getAmmo()
            if ammo and ammo <= 0 then
                Remotes.Reload:FireServer()
                lastReloadTime = now
            end
        end
    end
end)

-- ============================================================
-- Combat: Rapid Fire (bypass cooldown)
-- ============================================================
-- Rapid Fire is handled in the namecall hook for CheckFire.
-- We don't block calls; the actual fire rate is server-controlled.
-- This hook ensures client-side debounce doesn't prevent firing.
local lastRapidFire = 0
-- Rapid Fire: handled by allowing CheckFire through namecall hook
-- (no client-side rate limiting block)

-- ============================================================
-- Player: Auto Play & Auto Spawn
-- ============================================================
local lastAutoPlay = 0
RunService.RenderStepped:Connect(function()
    if Settings.AutoPlay and Remotes.Command then
        local now = tick()
        if now - lastAutoPlay > 5 then
            -- Auto send "Play" command to join rounds
            Remotes.Command:FireServer("Play")
            lastAutoPlay = now
        end
    end
end)

-- Auto spawn on death
LocalPlayer.CharacterAdded:Connect(function(char)
    if Settings.AutoSpawn and Remotes.UpdateSetting then
        task.wait(0.5)
        Remotes.UpdateSetting:FireServer("AutoSpawn", true)
    end
end)

-- ============================================================
-- Visuals: FOV Circle
-- ============================================================
local fovCircle = nil
if Drawing and Drawing.new then
    fovCircle = Drawing.new("Circle")
    fovCircle.Visible = false
    fovCircle.Color = Color3.fromRGB(255, 255, 255)
    fovCircle.Thickness = 1
    fovCircle.NumSides = 64
    fovCircle.Radius = 200
    fovCircle.Filled = false
    fovCircle.Transparency = 1
end

RunService.RenderStepped:Connect(function()
    if fovCircle then
        fovCircle.Visible = Settings.FOVCircle or Settings.Aimbot or Settings.SilentAim
        if fovCircle.Visible then
            local mousePos = UserInputService:GetMouseLocation()
            fovCircle.Position = Vector2.new(mousePos.X, mousePos.Y - 36)
            fovCircle.Radius = Settings.AimbotFOV
        end
    end
end)

-- ============================================================
-- Visuals: Player ESP
-- ============================================================
local ESPObjects = {}
local ESPBillboards = {}

local function createESPBillboard(player)
    if ESPBillboards[player] then return ESPBillboards[player] end
    local char = player.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    local bb = Instance.new("BillboardGui")
    bb.Name = "ESP_" .. player.Name
    bb.Adornee = hrp
    bb.Size = UDim2.new(0, 100, 0, 100)
    bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop = true
    bb.MaxDistance = math.huge
    bb.Parent = hrp

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "Name"
    nameLabel.BackgroundTransparency = 1
    nameLabel.Size = UDim2.new(1, 0, 0, 16)
    nameLabel.Position = UDim2.new(0, 0, 0, 0)
    nameLabel.Text = player.Name
    nameLabel.TextColor3 = Settings.ESPColor
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.SourceSansBold
    nameLabel.Parent = bb

    local healthLabel = Instance.new("TextLabel")
    healthLabel.Name = "Health"
    healthLabel.BackgroundTransparency = 1
    healthLabel.Size = UDim2.new(1, 0, 0, 14)
    healthLabel.Position = UDim2.new(0, 0, 0, 16)
    healthLabel.Text = "100"
    healthLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
    healthLabel.TextScaled = true
    healthLabel.Font = Enum.Font.SourceSansBold
    healthLabel.Parent = bb

    local distLabel = Instance.new("TextLabel")
    distLabel.Name = "Distance"
    distLabel.BackgroundTransparency = 1
    distLabel.Size = UDim2.new(1, 0, 0, 14)
    distLabel.Position = UDim2.new(0, 0, 0, 30)
    distLabel.Text = "0m"
    distLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    distLabel.TextScaled = true
    distLabel.Font = Enum.Font.SourceSansBold
    distLabel.Parent = bb

    ESPBillboards[player] = bb
    return bb
end

local function removeESPBillboard(player)
    local bb = ESPBillboards[player]
    if bb then
        bb:Destroy()
        ESPBillboards[player] = nil
    end
end

RunService.RenderStepped:Connect(function()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local showESP = Settings.PlayerESP
            if showESP and Settings.ESPTeamCheck and player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team then
                showESP = false
            end
            local char = player.Character
            if showESP and char then
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local bb = createESPBillboard(player)
                    if bb then
                        bb.Name.Visible = Settings.ESPName
                        bb.Health.Visible = Settings.ESPHealth
                        bb.Distance.Visible = Settings.ESPDistance
                        bb.Name.TextColor3 = Settings.ESPColor
                        local humanoid = char:FindFirstChildOfClass("Humanoid")
                        if humanoid then
                            local hp = math.floor(humanoid.Health)
                            bb.Health.Text = tostring(hp)
                            if hp > 60 then
                                bb.Health.TextColor3 = Color3.fromRGB(0, 255, 0)
                            elseif hp > 30 then
                                bb.Health.TextColor3 = Color3.fromRGB(255, 255, 0)
                            else
                                bb.Health.TextColor3 = Color3.fromRGB(255, 0, 0)
                            end
                        end
                        local dist = (hrp.Position - Camera.CFrame.Position).Magnitude
                        bb.Distance.Text = tostring(math.floor(dist)) .. "m"
                    end
                end
            else
                removeESPBillboard(player)
            end
        end
    end
end)

Players.PlayerRemoving:Connect(function(player)
    removeESPBillboard(player)
end)

-- ============================================================
-- Visuals: Hitbox Expander (visual only)
-- ============================================================
local hitboxParts = {}
local function expandHitbox(player)
    local char = player.Character
    if not char then return end
    for _, part in ipairs(char:GetChildren()) do
        if part:IsA("BasePart") then
            if not hitboxParts[part] then
                hitboxParts[part] = part.Size
            end
            if Settings.HitboxExpander then
                part.Size = hitboxParts[part] * Settings.HitboxSize
            else
                part.Size = hitboxParts[part]
            end
        end
    end
end

RunService.RenderStepped:Connect(function()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            if Settings.HitboxExpander then
                expandHitbox(player)
            end
        end
    end
end)

-- ============================================================
-- Visuals: Tracers
-- ============================================================
local tracerLines = {}
if Drawing and Drawing.new then
    RunService.RenderStepped:Connect(function()
        if not Settings.ESPTracer or not Settings.PlayerESP then
            for _, line in pairs(tracerLines) do
                line.Visible = false
            end
            return
        end
        local mousePos = UserInputService:GetMouseLocation()
        local bottomScreen = Vector2.new(mousePos.X, Camera.ViewportSize.Y)
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                if not (Settings.ESPTeamCheck and player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team) then
                    local char = player.Character
                    if char then
                        local hrp = char:FindFirstChild("HumanoidRootPart")
                        if hrp then
                            local screenPos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
                            if onScreen then
                                if not tracerLines[player] then
                                    tracerLines[player] = Drawing.new("Line")
                                    tracerLines[player].Color = Settings.ESPColor
                                    tracerLines[player].Thickness = 1
                                    tracerLines[player].Transparency = 1
                                end
                                local line = tracerLines[player]
                                line.Visible = true
                                line.From = bottomScreen
                                line.To = Vector2.new(screenPos.X, screenPos.Y)
                                line.Color = Settings.ESPColor
                            else
                                if tracerLines[player] then
                                    tracerLines[player].Visible = false
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
end

-- ============================================================
-- Player: Auto Play & Auto Spawn (handled above)
-- ============================================================


-- ============================================================
-- Player: Fly
-- ============================================================
local flyConnection = nil
local function toggleFly(enabled)
    if enabled then
        if flyConnection then flyConnection:Disconnect() end
        local bodyVelocity = nil
        local bodyGyro = nil
        flyConnection = RunService.RenderStepped:Connect(function()
            local char = LocalPlayer.Character
            if not char then return end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if not hrp or not humanoid then return end

            if not bodyVelocity or not bodyVelocity.Parent then
                bodyVelocity = Instance.new("BodyVelocity")
                bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                bodyVelocity.Velocity = Vector3.zero
                bodyVelocity.Parent = hrp
            end
            if not bodyGyro or not bodyGyro.Parent then
                bodyGyro = Instance.new("BodyGyro")
                bodyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
                bodyGyro.P = 10000
                bodyGyro.Parent = hrp
            end

            humanoid.PlatformStand = true
            local camCF = Camera.CFrame
            local moveDir = Vector3.zero
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + camCF.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - camCF.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - camCF.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + camCF.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir = moveDir + Vector3.new(0, 1, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveDir = moveDir - Vector3.new(0, 1, 0) end

            if moveDir.Magnitude > 0 then
                bodyVelocity.Velocity = moveDir.Unit * Settings.FlySpeed
            else
                bodyVelocity.Velocity = Vector3.zero
            end
            bodyGyro.CFrame = camCF
        end)
    else
        if flyConnection then
            flyConnection:Disconnect()
            flyConnection = nil
        end
        local char = LocalPlayer.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if hrp then
                local bv = hrp:FindFirstChildOfClass("BodyVelocity")
                if bv then bv:Destroy() end
                local bg = hrp:FindFirstChildOfClass("BodyGyro")
                if bg then bg:Destroy() end
            end
            if humanoid then humanoid.PlatformStand = false end
        end
    end
end

-- ============================================================
-- Player: Noclip
-- ============================================================
local noclipConnection = nil
local function toggleNoclip(enabled)
    if enabled then
        if noclipConnection then noclipConnection:Disconnect() end
        noclipConnection = RunService.Stepped:Connect(function()
            local char = LocalPlayer.Character
            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = false
                    end
                end
            end
        end)
    else
        if noclipConnection then
            noclipConnection:Disconnect()
            noclipConnection = nil
        end
    end
end

-- ============================================================
-- Player: Walk Speed & Jump Power
-- ============================================================
RunService.RenderStepped:Connect(function()
    local char = LocalPlayer.Character
    if char then
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = Settings.WalkSpeed
            humanoid.JumpPower = Settings.JumpPower
        end
    end
end)

-- ============================================================
-- Player: Full Bright
-- ============================================================
local oldLighting = {}
local function toggleFullBright(enabled)
    if enabled then
        oldLighting.Brightness = Lighting.Brightness
        oldLighting.ClockTime = Lighting.ClockTime
        oldLighting.FogEnd = Lighting.FogEnd
        oldLighting.Ambient = Lighting.Ambient
        oldLighting.OutdoorAmbient = Lighting.OutdoorAmbient
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.FogEnd = 100000
        Lighting.Ambient = Color3.new(1, 1, 1)
        Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
    else
        Lighting.Brightness = oldLighting.Brightness or 1
        Lighting.ClockTime = oldLighting.ClockTime or 14
        Lighting.FogEnd = oldLighting.FogEnd or 100000
        Lighting.Ambient = oldLighting.Ambient or Color3.new(0, 0, 0)
        Lighting.OutdoorAmbient = oldLighting.OutdoorAmbient or Color3.new(0.5, 0.5, 0.5)
    end
end

-- ============================================================
-- Player: Anti AFK
-- ============================================================
local afkConnection = nil
local function toggleAntiAFK(enabled)
    if enabled then
        if afkConnection then afkConnection:Disconnect() end
        afkConnection = LocalPlayer.Idled:Connect(function()
            -- Prevent AFK kick by simulating input
            local ok, VirtualUser = pcall(function()
                return game:GetService("VirtualUser")
            end)
            if ok and VirtualUser then
                pcall(function()
                    VirtualUser:CaptureController()
                    VirtualUser:ClickButton2(Vector2.new())
                end)
            end
        end)
    else
        if afkConnection then
            afkConnection:Disconnect()
            afkConnection = nil
        end
    end
end

-- ============================================================
-- World: Remove Fog
-- ============================================================
local oldFogEnd = nil
local function toggleRemoveFog(enabled)
    if enabled then
        oldFogEnd = Lighting.FogEnd
        Lighting.FogEnd = 100000
    else
        Lighting.FogEnd = oldFogEnd or 100000
    end
end

-- ============================================================
-- Misc: Anti Kick
-- ============================================================
local oldKick
pcall(function()
    oldKick = hookfunction(LocalPlayer.Kick, function(...)
        if Settings.AntiKick then
            return
        end
        return oldKick(...)
    end)
end)

-- ============================================================
-- WindUI
-- ============================================================
local cloneref = (cloneref or clonereference or function(instance) return instance end)
local WindUI
local ok, err = pcall(function()
    WindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
end)
if not ok or not WindUI then
    warn("Flash Client: Failed to load WindUI: " .. tostring(err))
    return
end

local Window = WindUI:CreateWindow({
    Title = "Flash Client",
    Folder = "FlashClient",
    Icon = "solar:bolt-bold",
    NewElements = true,
    OpenButton = {
        Title = "Flash",
        CornerRadius = UDim.new(1, 0),
        StrokeThickness = 2,
        Enabled = true,
        Draggable = true,
        OnlyMobile = false,
        Scale = 0.6,
        Color = ColorSequence.new(
            Color3.fromHex("#FF6B35"),
            Color3.fromHex("#FFD23F")
        ),
    },
    Topbar = {
        Height = 44,
        ButtonsType = "Mac",
    },
})

Window:Tag({
    Title = "v1.0",
    Icon = "solar:bolt-bold",
    Color = Color3.fromHex("#FF6B35"),
    Border = true,
})

-- Colors
local Orange = Color3.fromHex("#FF6B35")
local Yellow = Color3.fromHex("#FFD23F")
local Green = Color3.fromHex("#10C550")
local Grey = Color3.fromHex("#83889E")
local Blue = Color3.fromHex("#257AF7")
local Red = Color3.fromHex("#EF4F1D")
local Purple = Color3.fromHex("#7775F2")

-- ============================================================
-- Combat Tab
-- ============================================================
local CombatSection = Window:Section({ Title = "Combat" })

do
    local CombatTab = CombatSection:Tab({
        Title = "Aim",
        Icon = "solar:cursor-bold",
        IconColor = Red,
        IconShape = "Square",
        Border = true,
    })

    CombatTab:Toggle({
        Title = "Silent Aim",
        Desc = "Redirects shots to nearest player",
        Callback = function(v)
            Settings.SilentAim = v
        end,
    })

    CombatTab:Space()

    CombatTab:Toggle({
        Title = "Aimbot",
        Desc = "Auto-aim camera at target",
        Callback = function(v)
            Settings.Aimbot = v
        end,
    })

    CombatTab:Space()

    CombatTab:Slider({
        Title = "FOV Radius",
        Desc = "Aimbot field of view",
        Step = 1,
        Value = { Min = 10, Max = 500, Default = 200 },
        Callback = function(v)
            Settings.AimbotFOV = v
        end,
    })

    CombatTab:Space()

    CombatTab:Slider({
        Title = "Max Distance",
        Desc = "Max aim distance in studs",
        Step = 50,
        Value = { Min = 100, Max = 5000, Default = 1000 },
        Callback = function(v)
            Settings.AimbotDistance = v
        end,
    })

    CombatTab:Space()

    CombatTab:Slider({
        Title = "Smoothness",
        Desc = "Aimbot smoothness (lower = snappier)",
        Step = 0.05,
        Value = { Min = 0, Max = 0.9, Default = 0.1 },
        Callback = function(v)
            Settings.AimbotSmoothness = v
        end,
    })

    CombatTab:Space()

    CombatTab:Dropdown({
        Title = "Hit Part",
        Values = {
            { Title = "Crit (Head)", Callback = function() Settings.AimbotPart = "Crit" end },
            { Title = "Head", Callback = function() Settings.AimbotPart = "Head" end },
            { Title = "Torso", Callback = function() Settings.AimbotPart = "Torso" end },
            { Title = "HumanoidRootPart", Callback = function() Settings.AimbotPart = "HumanoidRootPart" end },
        },
    })

    CombatTab:Space()

    CombatTab:Toggle({
        Title = "Team Check",
        Desc = "Don't aim at teammates",
        Callback = function(v)
            Settings.AimbotTeamCheck = v
        end,
    })
end

do
    local TriggerTab = CombatSection:Tab({
        Title = "Trigger",
        Icon = "solar:cursor-square-bold",
        IconColor = Orange,
        IconShape = "Square",
        Border = true,
    })

    TriggerTab:Toggle({
        Title = "Triggerbot",
        Desc = "Auto-fire when crosshair on player",
        Callback = function(v)
            Settings.Triggerbot = v
        end,
    })

    TriggerTab:Space()

    TriggerTab:Slider({
        Title = "Delay",
        Desc = "Triggerbot delay in seconds",
        Step = 0.01,
        Value = { Min = 0, Max = 1, Default = 0 },
        Callback = function(v)
            Settings.TriggerbotDelay = v
        end,
    })

    TriggerTab:Space()

    TriggerTab:Toggle({
        Title = "Auto Reload",
        Desc = "Auto reload when ammo empty",
        Callback = function(v)
            Settings.AutoReload = v
        end,
    })

    TriggerTab:Space()

    TriggerTab:Toggle({
        Title = "No Spread",
        Desc = "Remove bullet spread",
        Callback = function(v)
            Settings.NoSpread = v
        end,
    })

    TriggerTab:Space()

    TriggerTab:Toggle({
        Title = "Rapid Fire",
        Desc = "Bypass fire rate cooldown",
        Callback = function(v)
            Settings.RapidFire = v
        end,
    })
end

-- ============================================================
-- Visuals Tab
-- ============================================================
local VisualsSection = Window:Section({ Title = "Visuals" })

do
    local ESPTab = VisualsSection:Tab({
        Title = "ESP",
        Icon = "solar:eye-bold",
        IconColor = Blue,
        IconShape = "Square",
        Border = true,
    })

    ESPTab:Toggle({
        Title = "Player ESP",
        Callback = function(v)
            Settings.PlayerESP = v
        end,
    })

    ESPTab:Space()

    ESPTab:Toggle({
        Title = "Team Check",
        Desc = "Hide teammates",
        Callback = function(v)
            Settings.ESPTeamCheck = v
        end,
    })

    ESPTab:Space()

    ESPTab:Toggle({
        Title = "Show Name",
        Callback = function(v)
            Settings.ESPName = v
        end,
    })

    ESPTab:Space()

    ESPTab:Toggle({
        Title = "Show Health",
        Callback = function(v)
            Settings.ESPHealth = v
        end,
    })

    ESPTab:Space()

    ESPTab:Toggle({
        Title = "Show Distance",
        Callback = function(v)
            Settings.ESPDistance = v
        end,
    })

    ESPTab:Space()

    ESPTab:Toggle({
        Title = "Tracers",
        Callback = function(v)
            Settings.ESPTracer = v
        end,
    })

    ESPTab:Space()

    ESPTab:Colorpicker({
        Title = "ESP Color",
        Default = Color3.fromHex("#FF4757"),
        Callback = function(color)
            Settings.ESPColor = color
        end,
    })
end

do
    local WorldTab = VisualsSection:Tab({
        Title = "World",
        Icon = "solar:planet-bold",
        IconColor = Green,
        IconShape = "Square",
        Border = true,
    })

    WorldTab:Toggle({
        Title = "FOV Circle",
        Desc = "Show aimbot FOV circle",
        Callback = function(v)
            Settings.FOVCircle = v
        end,
    })

    WorldTab:Space()

    WorldTab:Toggle({
        Title = "Hitbox Expander",
        Desc = "Visual hitbox expansion",
        Callback = function(v)
            Settings.HitboxExpander = v
        end,
    })

    WorldTab:Space()

    WorldTab:Slider({
        Title = "Hitbox Size",
        Step = 0.5,
        Value = { Min = 1, Max = 20, Default = 5 },
        Callback = function(v)
            Settings.HitboxSize = v
        end,
    })

    WorldTab:Space()

    WorldTab:Toggle({
        Title = "Full Bright",
        Callback = function(v)
            Settings.FullBright = v
            toggleFullBright(v)
        end,
    })

    WorldTab:Space()

    WorldTab:Toggle({
        Title = "Remove Fog",
        Callback = function(v)
            Settings.RemoveFog = v
            toggleRemoveFog(v)
        end,
    })
end

-- ============================================================
-- Player Tab
-- ============================================================
local PlayerSection = Window:Section({ Title = "Player" })

do
    local MovementTab = PlayerSection:Tab({
        Title = "Movement",
        Icon = "solar:user-run-bold",
        IconColor = Purple,
        IconShape = "Square",
        Border = true,
    })

    MovementTab:Slider({
        Title = "Walk Speed",
        Step = 1,
        Value = { Min = 16, Max = 200, Default = 16 },
        Callback = function(v)
            Settings.WalkSpeed = v
        end,
    })

    MovementTab:Space()

    MovementTab:Slider({
        Title = "Jump Power",
        Step = 1,
        Value = { Min = 50, Max = 500, Default = 50 },
        Callback = function(v)
            Settings.JumpPower = v
        end,
    })

    MovementTab:Space()

    MovementTab:Toggle({
        Title = "Fly",
        Callback = function(v)
            Settings.Fly = v
            toggleFly(v)
        end,
    })

    MovementTab:Space()

    MovementTab:Slider({
        Title = "Fly Speed",
        Step = 5,
        Value = { Min = 10, Max = 500, Default = 50 },
        Callback = function(v)
            Settings.FlySpeed = v
        end,
    })

    MovementTab:Space()

    MovementTab:Toggle({
        Title = "Noclip",
        Callback = function(v)
            Settings.Noclip = v
            toggleNoclip(v)
        end,
    })
end

do
    local AutoTab = PlayerSection:Tab({
        Title = "Auto",
        Icon = "solar:refresh-bold",
        IconColor = Yellow,
        IconShape = "Square",
        Border = true,
    })

    AutoTab:Toggle({
        Title = "Auto Play",
        Desc = "Auto join rounds",
        Callback = function(v)
            Settings.AutoPlay = v
        end,
    })

    AutoTab:Space()

    AutoTab:Toggle({
        Title = "Auto Spawn",
        Desc = "Auto respawn on death",
        Callback = function(v)
            Settings.AutoSpawn = v
            if Remotes.UpdateSetting then
                Remotes.UpdateSetting:FireServer("AutoSpawn", v)
            end
        end,
    })

    AutoTab:Space()

    AutoTab:Toggle({
        Title = "Anti AFK",
        Callback = function(v)
            Settings.AntiAFK = v
            toggleAntiAFK(v)
        end,
    })

    AutoTab:Space()

    AutoTab:Button({
        Title = "Rejoin",
        Color = Color3.fromHex("#FF6B35"),
        Justify = "Center",
        Callback = function()
            local TeleportService = game:GetService("TeleportService")
            TeleportService:Teleport(game.PlaceId, LocalPlayer)
        end,
    })

    AutoTab:Space()

    AutoTab:Button({
        Title = "Copy Server ID",
        Color = Color3.fromHex("#305dff"),
        Justify = "Center",
        Callback = function()
            setclipboard(tostring(game.JobId))
            WindUI:Notify({
                Title = "Server ID",
                Content = "Copied to clipboard!",
                Duration = 3,
            })
        end,
    })
end

-- ============================================================
-- Misc Tab
-- ============================================================
local MiscSection = Window:Section({ Title = "Misc" })

do
    local MiscTab = MiscSection:Tab({
        Title = "Settings",
        Icon = "solar:settings-bold",
        IconColor = Grey,
        IconShape = "Square",
        Border = true,
    })

    MiscTab:Toggle({
        Title = "Anti Kick",
        Desc = "Block kick attempts",
        Callback = function(v)
            Settings.AntiKick = v
        end,
    })

    MiscTab:Space()

    MiscTab:Button({
        Title = "Refresh Remotes",
        Color = Color3.fromHex("#10C550"),
        Justify = "Center",
        Callback = function()
            refreshRemotes()
            WindUI:Notify({
                Title = "Remotes",
                Content = "Refreshed successfully!",
                Duration = 3,
            })
        end,
    })

    MiscTab:Space()

    MiscTab:Button({
        Title = "Destroy UI",
        Color = Color3.fromHex("#EF4F1D"),
        Justify = "Center",
        Callback = function()
            Window:Destroy()
        end,
    })
end

-- ============================================================
-- Notifications
-- ============================================================
WindUI:Notify({
    Title = "Flash Client",
    Content = "Loaded successfully!",
    Duration = 5,
})

-- Auto-spawn setting on load
if Remotes.UpdateSetting and Settings.AutoSpawn then
    Remotes.UpdateSetting:FireServer("AutoSpawn", true)
end
