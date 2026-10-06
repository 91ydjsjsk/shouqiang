--[[
    ============================================
           🔪 Blade Hub  |  Combat Script
    ============================================
    Features: Combat / Movement / Player / Visuals / Misc
    UI: WindUI (Mobile Friendly)
    ============================================
]]

-- // Services \\ --
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

-- // Locals \\ --
local LocalPlayer = Players.LocalPlayer
local cloneref = (cloneref or clonereference or function(i) return i end)
local gethui = (gethui or function() return game:GetService("CoreGui") end)
local getgenv = (getgenv or function() return _G end)
local firesignal = (firesignal or function(signal, ...) return signal:Fire(...) end)
local hookfunction = (hookfunction or hookfunc or function(f, n) return f end)
local hookmetamethod = (hookmetamethod or function() end)

local getrenv = (getrenv or function() return getfenv(0) end)

-- // Globals \\ --
getgenv().BladeHubSettings = getgenv().BladeHubSettings or {}
local Settings = getgenv().BladeHubSettings

-- // Remote Cache \\ --
local function GetRemote(path)
    local parts = string.split(path, ".")
    local obj = game
    for _, part in ipairs(parts) do
        if part == "game" then continue end
        local ok, result = pcall(function()
            return obj[part]
        end)
        if not ok or not result then return nil end
        obj = result
    end
    return cloneref(obj)
end

local Remotes = {
    SwitchSlot    = GetRemote("ReplicatedStorage.Remote.CombatService.SwitchSlot"),
    Confirm       = GetRemote("ReplicatedStorage.Remote.CombatService.Confirm"),
    SetWeapon     = GetRemote("ReplicatedStorage.Remote.CombatService.SetSimpleWeapon"),
    Jump          = GetRemote("ReplicatedStorage.Remote.EntityService.Jump"),
    SetInAir      = GetRemote("ReplicatedStorage.Remote.EntityService.SetInAir"),
    WalkSpeed     = GetRemote("ReplicatedStorage.Remote.EntityService.WalkSpeed"),
    Teleport      = GetRemote("ReplicatedStorage.Remote.ReplicateService.Teleport"),
    Respawn       = GetRemote("ReplicatedStorage.Remote.GameService.Respawn"),
    ClientTP      = GetRemote("ReplicatedStorage.Remote.Any.ClientTeleported"),
    Killed        = GetRemote("ReplicatedStorage.Remote.GameService.GameClient.Killed"),
    ByteNetReliable = GetRemote("ReplicatedStorage.ByteNetReliable"),
    ByteNetQuery    = GetRemote("ReplicatedStorage.ByteNetQuery"),
    ClientReplicateCFrame = GetRemote("ReplicatedStorage.ClientReplicateCFrame"),
    ServerReplicateCFrame = GetRemote("ReplicatedStorage.ServerReplicateCFrame"),
    CHRONO_BLINK  = GetRemote("ReplicatedStorage.CHRONO_BLINK_RELIABLE_REMOTE"),
}

-- // Utility Functions \\ --
local function GetCharacter(player)
    player = player or LocalPlayer
    return player.Character
end

local function GetHumanoid(player)
    local char = GetCharacter(player)
    if char then return char:FindFirstChildOfClass("Humanoid") end
end

local function GetRoot(player)
    local char = GetCharacter(player)
    if char then return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char.PrimaryPart end
end

local function GetPlayers()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            table.insert(list, p)
        end
    end
    return list
end

local function GetNearestPlayer(range)
    local myRoot = GetRoot()
    if not myRoot then return nil end
    local nearest, dist = nil, range or math.huge
    for _, p in ipairs(GetPlayers()) do
        local root = GetRoot(p)
        if root then
            local d = (root.Position - myRoot.Position).Magnitude
            if d < dist then
                dist = d
                nearest = p
            end
        end
    end
    return nearest, dist
end

local function Notify(title, content, duration)
    if WindUI then
        WindUI:Notify({
            Title = title,
            Content = content,
            Duration = duration or 3,
        })
    end
end

-- // Fire Helpers \\ --
local function FireAttack()
    if Remotes.Confirm then
        pcall(function() Remotes.Confirm:FireServer({}) end)
    end
    -- ByteNet attack payload {7, 7}
    if Remotes.ByteNetReliable then
        pcall(function()
            local buf = buffer.create(2)
            buffer.writeu8(buf, 0, 7)
            buffer.writeu8(buf, 1, 7)
            Remotes.ByteNetReliable:FireServer(buf, nil)
        end)
    end
end

local function FireSwitchSlot(slot)
    if Remotes.SwitchSlot then
        pcall(function() Remotes.SwitchSlot:FireServer(os.clock(), slot or "Primary", {}) end)
    end
end

local function FireJump()
    if Remotes.Jump then
        pcall(function() Remotes.Jump:FireServer() end)
    end
end

local function FireSetInAir(state)
    if Remotes.SetInAir then
        pcall(function() Remotes.SetInAir:FireServer(state) end)
    end
end

local function FireRespawn()
    if Remotes.Respawn then
        pcall(function() Remotes.Respawn:FireServer() end)
    end
end

-- // State \\ --
local State = {
    AutoAttack = false,
    AutoBlock = false,
    KillAura = false,
    Reach = false,
    ReachValue = 10,
    InfiniteJump = false,
    Fly = false,
    FlySpeed = 100,
    Noclip = false,
    GodMode = false,
    AntiRagdoll = false,
    AutoRespawn = false,
    NoCooldown = false,
    WalkSpeedEnabled = false,
    WalkSpeedValue = 24,
    JumpPowerEnabled = false,
    JumpPowerValue = 60,
    ESP = false,
    Tracers = false,
    FOV = false,
    Fullbright = false,
    AntiAFK = false,
}

-- // ============== COMBAT ============== \\ --

-- Auto Attack loop
task.spawn(function()
    while true do
        if State.AutoAttack then
            FireAttack()
            task.wait(Settings.AttackDelay or 0.05)
        else
            task.wait(0.1)
        end
    end
end)

-- Kill Aura loop
task.spawn(function()
    while true do
        if State.KillAura then
            local target = GetNearestPlayer(State.Reach and State.ReachValue or 8)
            if target then
                local myRoot = GetRoot()
                local theirRoot = GetRoot(target)
                if myRoot and theirRoot then
                    -- Face target
                    local lookPos = Vector3.new(theirRoot.Position.X, myRoot.Position.Y, theirRoot.Position.Z)
                    myRoot.CFrame = CFrame.new(myRoot.Position, lookPos)
                    FireAttack()
                end
            end
            task.wait(Settings.AuraDelay or 0.08)
        else
            task.wait(0.1)
        end
    end
end)

-- Auto Slot switch for combos
task.spawn(function()
    local slots = {"Primary", "Secondary", "Special"}
    local idx = 1
    while true do
        if State.NoCooldown then
            FireSwitchSlot(slots[idx])
            idx = (idx % #slots) + 1
            task.wait(0.15)
        else
            task.wait(0.2)
        end
    end
end)

-- // ============== MOVEMENT ============== \\ --

-- Infinite Jump
local jumpConn
jumpConn = UserInputService.JumpRequest:Connect(function()
    if State.InfiniteJump then
        local hum = GetHumanoid()
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
            FireJump()
        end
    end
end)

-- Fly
local flyConn, flyGyro, flyVel
local function StartFly()
    local hum = GetHumanoid()
    local root = GetRoot()
    if not hum or not root then return end
    hum.PlatformStand = true
    flyGyro = Instance.new("BodyGyro")
    flyGyro.P = 10000
    flyGyro.MaxTorque = Vector3.new(10^9, 10^9, 10^9)
    flyGyro.CFrame = root.CFrame
    flyGyro.Parent = root
    flyVel = Instance.new("BodyVelocity")
    flyVel.MaxForce = Vector3.new(10^9, 10^9, 10^9)
    flyVel.Velocity = Vector3.zero
    flyVel.Parent = root
end

local function StopFly()
    local hum = GetHumanoid()
    if hum then hum.PlatformStand = false end
    if flyGyro then flyGyro:Destroy() flyGyro = nil end
    if flyVel then flyVel:Destroy() flyVel = nil end
end

flyConn = RunService.RenderStepped:Connect(function()
    if not State.Fly then return end
    local root = GetRoot()
    if not root then return end
    local cam = Workspace.CurrentCamera
    local speed = State.FlySpeed
    local moveDir = Vector3.zero
    local keys = UserInputService:GetKeysPressed()
    for _, k in ipairs(keys) do
        if k.KeyCode == Enum.KeyCode.W then moveDir += cam.CFrame.LookVector end
        if k.KeyCode == Enum.KeyCode.S then moveDir -= cam.CFrame.LookVector end
        if k.KeyCode == Enum.KeyCode.A then moveDir -= cam.CFrame.RightVector end
        if k.KeyCode == Enum.KeyCode.D then moveDir += cam.CFrame.RightVector end
        if k.KeyCode == Enum.KeyCode.Space then moveDir += Vector3.new(0,1,0) end
        if k.KeyCode == Enum.KeyCode.LeftShift then moveDir -= Vector3.new(0,1,0) end
    end
    -- Mobile: use camera look direction + touch
    if UserInputService.TouchEnabled then
        if #keys == 0 then
            moveDir = cam.CFrame.LookVector * 0.5
        end
    end
    if flyGyro then flyGyro.CFrame = cam.CFrame end
    if flyVel then
        flyVel.Velocity = moveDir * speed
    end
end)

-- WalkSpeed / JumpPower loop
RunService.Heartbeat:Connect(function()
    local hum = GetHumanoid()
    if not hum then return end
    if State.WalkSpeedEnabled then
        hum.WalkSpeed = State.WalkSpeedValue
    end
    if State.JumpPowerEnabled then
        if hum.UseJumpPower then
            hum.JumpPower = State.JumpPowerValue
        else
            hum.JumpHeight = State.JumpPowerValue / 7.2
        end
    end
end)

-- Noclip
local noclipConn
noclipConn = RunService.Stepped:Connect(function()
    if not State.Noclip then return end
    local char = GetCharacter()
    if not char then return end
    for _, v in ipairs(char:GetDescendants()) do
        if v:IsA("BasePart") then
            v.CanCollide = false
        end
    end
end)

-- // ============== PLAYER ============== \\ --

-- God Mode: block Killed remote connections
local killedConnections = {}
if Remotes.Killed and getconnections then
    pcall(function()
        for _, conn in ipairs(getconnections(Remotes.Killed.OnClientEvent)) do
            table.insert(killedConnections, conn)
        end
    end)
end

local function SetKilledBlocked(blocked)
    for _, conn in ipairs(killedConnections) do
        pcall(function()
            if blocked then
                conn:Disable()
            else
                conn:Enable()
            end
        end)
    end
end

-- God Mode via Humanoid.Health protection
task.spawn(function()
    while true do
        if State.GodMode then
            SetKilledBlocked(true)
            local hum = GetHumanoid()
            if hum and hum.Health < hum.MaxHealth then
                hum.Health = hum.MaxHealth
            end
        else
            SetKilledBlocked(false)
        end
        task.wait(0.1)
    end
end)

-- Anti Ragdoll
task.spawn(function()
    while true do
        if State.AntiRagdoll then
            local hum = GetHumanoid()
            if hum then
                hum.BreakJointsOnDeath = false
                for _, part in ipairs(hum.Parent:GetDescendants()) do
                    if part:IsA("Motor6D") then
                        part.Enabled = true
                    end
                end
            end
        end
        task.wait(0.2)
    end
end)

-- Auto Respawn
if Remotes.Killed then
    Remotes.Killed.OnClientEvent:Connect(function(victim, killer)
        if State.AutoRespawn then
            task.delay(0.5, function()
                FireRespawn()
            end)
        end
    end)
end

-- // ============== VISUALS (ESP) ============== \\ --
local ESPObjects = {}

local function CreateESP(player)
    local char = player.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not root or not hum then return end

    local holder = Drawing and Drawing.new or nil
    if not holder then return end

    local box = Drawing.new("Square")
    box.Visible = false
    box.Thickness = 1.5
    box.Color = Color3.fromRGB(255, 50, 50)
    box.Filled = false
    box.Transparency = 1

    local name = Drawing.new("Text")
    name.Visible = false
    name.Size = 14
    name.Color = Color3.fromRGB(255, 255, 255)
    name.Center = true
    name.Outline = true
    name.Text = player.Name

    local health = Drawing.new("Text")
    health.Visible = false
    health.Size = 12
    health.Color = Color3.fromRGB(0, 255, 0)
    health.Center = true
    health.Outline = true

    local tracer = Drawing.new("Line")
    tracer.Visible = false
    tracer.Thickness = 1
    tracer.Color = Color3.fromRGB(255, 50, 50)
    tracer.Transparency = 0.8

    ESPObjects[player] = {box = box, name = name, health = health, tracer = tracer, root = root, hum = hum}
end

local function RemoveESP(player)
    local esp = ESPObjects[player]
    if esp then
        for _, obj in pairs(esp) do
            if typeof(obj) == "table" then continue end
            pcall(function() obj:Remove() end)
        end
        ESPObjects[player] = nil
    end
end

RunService.RenderStepped:Connect(function()
    if not State.ESP and not State.Tracers then
        for _, esp in pairs(ESPObjects) do
            pcall(function()
                esp.box.Visible = false
                esp.name.Visible = false
                esp.health.Visible = false
                esp.tracer.Visible = false
            end)
        end
        return
    end

    local cam = Workspace.CurrentCamera
    local vpX, vpY = cam.ViewportSize.X, cam.ViewportSize.Y

    for _, player in ipairs(GetPlayers()) do
        if not ESPObjects[player] or ESPObjects[player].root.Parent ~= player.Character then
            RemoveESP(player)
            CreateESP(player)
        end
        local esp = ESPObjects[player]
        if not esp then continue end
        local root = esp.root
        local hum = esp.hum
        if not root or not hum or not root.Parent then
            RemoveESP(player)
            continue
        end

        local pos, onScreen = cam:WorldToViewportPoint(root.Position)
        if onScreen then
            local headPos = cam:WorldToViewportPoint((root.Position + Vector3.new(0, 2, 0)))
            local legPos = cam:WorldToViewportPoint((root.Position - Vector3.new(0, 2, 0)))
            local height = math.abs(headPos.Y - legPos.Y)
            local width = height * 0.5

            if State.ESP then
                esp.box.Visible = true
                esp.box.Size = Vector2.new(width, height)
                esp.box.Position = Vector2.new(pos.X - width/2, pos.Y - height/2)

                esp.name.Visible = true
                esp.name.Position = Vector2.new(pos.X, pos.Y - height/2 - 16)

                esp.health.Visible = true
                local hp = math.floor(hum.Health)
                esp.health.Text = hp .. " HP"
                esp.health.Color = hp > 50 and Color3.fromRGB(0,255,0) or hp > 25 and Color3.fromRGB(255,200,0) or Color3.fromRGB(255,0,0)
                esp.health.Position = Vector2.new(pos.X, pos.Y + height/2 + 2)
            else
                esp.box.Visible = false
                esp.name.Visible = false
                esp.health.Visible = false
            end

            if State.Tracers then
                esp.tracer.Visible = true
                esp.tracer.From = Vector2.new(vpX/2, vpY)
                esp.tracer.To = Vector2.new(pos.X, pos.Y)
            else
                esp.tracer.Visible = false
            end
        else
            esp.box.Visible = false
            esp.name.Visible = false
            esp.health.Visible = false
            esp.tracer.Visible = false
        end
    end

    -- Clean up dead
    for player, _ in pairs(ESPObjects) do
        if not Players:FindFirstChild(player.Name) or not player.Character then
            RemoveESP(player)
        end
    end
end)

-- FOV Circle
local FOVCircle
if Drawing then
    FOVCircle = Drawing.new("Circle")
    FOVCircle.Visible = false
    FOVCircle.Color = Color3.fromRGB(0, 200, 255)
    FOVCircle.Thickness = 1.5
    FOVCircle.NumSides = 64
    FOVCircle.Radius = 150
    FOVCircle.Transparency = 0.8
end

RunService.RenderStepped:Connect(function()
    if FOVCircle then
        FOVCircle.Visible = State.FOV
        if State.FOV then
            local cam = Workspace.CurrentCamera
            FOVCircle.Position = Vector2.new(cam.ViewportSize.X/2, cam.ViewportSize.Y/2)
        end
    end
end)

-- Fullbright
local function ApplyFullbright()
    Lighting.Brightness = 3
    Lighting.ClockTime = 14
    Lighting.FogEnd = 100000
    Lighting.GlobalShadows = false
    Lighting.Ambient = Color3.fromRGB(178, 178, 178)
    Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
end

-- // ============== MISC ============== \\ --

-- Anti AFK
local afkConn
local function StartAntiAFK()
    if afkConn then return end
    local VirtualUser = (VirtualUser or nil)
    afkConn = LocalPlayer.Idled:Connect(function()
        pcall(function()
            if VirtualUser then
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end
        end)
    end)
end

local function StopAntiAFK()
    if afkConn then afkConn:Disconnect() afkConn = nil end
end

-- Teleport to player
local function TeleportToPlayer(targetName)
    local target = Players:FindFirstChild(targetName)
    if not target or not target.Character then return false end
    local theirRoot = GetRoot(target)
    local myRoot = GetRoot()
    if not theirRoot or not myRoot then return false end
    myRoot.CFrame = theirRoot.CFrame + Vector3.new(0, 3, 0)
    -- Tell server we teleported
    if Remotes.ClientTP then
        pcall(function() Remotes.ClientTP:FireServer(myRoot.CFrame) end)
    end
    return true
end

-- Rejoin
local function Rejoin()
    local ts = game:GetService("TeleportService")
    ts:Teleport(game.PlaceId, LocalPlayer)
end

-- Server Hop
local function ServerHop()
    local HttpService = game:GetService("HttpService")
    local servers = {}
    pcall(function()
        servers = HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100"))
    end)
    if servers and servers.data then
        for _, srv in ipairs(servers.data) do
            if srv.playing < srv.maxPlayers then
                pcall(function()
                    game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, srv.id, LocalPlayer)
                end)
                break
            end
        end
    end
end

-- // ============== WINDUI SETUP ============== \\ --
local WindUI
do
    local ok, result = pcall(function()
        return require(ReplicatedStorage:WaitForChild("WindUI"):WaitForChild("Init"))
    end)
    if ok then
        WindUI = result
    else
        ok, result = pcall(function()
            return loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
        end)
        if ok then
            WindUI = result
        else
            warn("Failed to load WindUI:", result)
        end
    end
end

if not WindUI then
    warn("Blade Hub: WindUI failed to load!")
    return
end

-- Colors
local C = {
    Red    = Color3.fromHex("#FF4757"),
    Orange = Color3.fromHex("#FF7A45"),
    Yellow = Color3.fromHex("#FFA502"),
    Green  = Color3.fromHex("#2ED573"),
    Cyan   = Color3.fromHex("#1E90FF"),
    Blue   = Color3.fromHex("#3742FA"),
    Purple = Color3.fromHex("#A55EEA"),
    Pink   = Color3.fromHex("#FF6B81"),
    Grey   = Color3.fromHex("#A4B0BE"),
}

-- Create Window
local Window = WindUI:CreateWindow({
    Title = "🔪 Blade Hub",
    Author = "Powered by WindUI",
    Folder = "BladeHub",
    Icon = "solar:knife-bold",
    NewElements = true,
    OpenButton = {
        Title = "🔪 Blade",
        CornerRadius = UDim.new(1, 0),
        StrokeThickness = 3,
        Enabled = true,
        Draggable = true,
        OnlyMobile = false,
        Scale = 0.6,
        Color = ColorSequence.new(
            Color3.fromHex("#FF4757"),
            Color3.fromHex("#A55EEA")
        ),
    },
    Topbar = {
        Height = 44,
        ButtonsType = "Mac",
    },
})

-- Version Tag
Window:Tag({
    Title = "v1.0.0",
    Icon = "solar:info-circle-bold",
    Color = Color3.fromHex("#2c2c2c"),
    Border = true,
})

-- // ============== COMBAT TAB ============== \\ --
do
    local CombatTab = Window:Tab({
        Title = "Combat",
        Icon = "solar:knife-bold",
        IconColor = C.Red,
        IconShape = "Square",
        Border = true,
    })

    local Sec = CombatTab:Section({Title = "⚔️  Attack"})

    Sec:Toggle({
        Title = "Auto Attack",
        Desc = "自动连续攻击",
        Callback = function(v)
            State.AutoAttack = v
            Notify("Combat", "Auto Attack: " .. (v and "ON" or "OFF"))
        end,
    })
    Sec:Slider({
        Title = "Attack Delay",
        Desc = "攻击间隔 (秒)",
        Step = 0.01,
        Value = {Min = 0.01, Max = 0.5, Default = 0.05},
        Callback = function(v) Settings.AttackDelay = v end,
    })
    Sec:Space()

    Sec:Toggle({
        Title = "Kill Aura",
        Desc = "自动锁定并攻击附近玩家",
        Callback = function(v)
            State.KillAura = v
            Notify("Combat", "Kill Aura: " .. (v and "ON" or "OFF"))
        end,
    })
    Sec:Slider({
        Title = "Aura Range",
        Desc = "光环范围 (studs)",
        Step = 1,
        Value = {Min = 3, Max = 50, Default = 10},
        Callback = function(v) State.ReachValue = v end,
    })
    Sec:Space()

    Sec:Toggle({
        Title = "Reach",
        Desc = "扩展攻击距离",
        Callback = function(v)
            State.Reach = v
        end,
    })
    Sec:Space()

    Sec:Toggle({
        Title = "No Cooldown",
        Desc = "快速切换武器槽消除冷却",
        Callback = function(v)
            State.NoCooldown = v
            Notify("Combat", "No Cooldown: " .. (v and "ON" or "OFF"))
        end,
    })
    Sec:Space()

    Sec:Toggle({
        Title = "Auto Block",
        Desc = "自动格挡 (占位)",
        Callback = function(v)
            State.AutoBlock = v
        end,
    })
    Sec:Space()

    CombatTab:Button({
        Title = "🔄  Switch to Primary",
        Color = C.Blue,
        Justify = "Center",
        Icon = "solar:repeat-bold",
        Callback = function()
            FireSwitchSlot("Primary")
            Notify("Combat", "Switched to Primary")
        end,
    })
    CombatTab:Button({
        Title = "🔄  Switch to Secondary",
        Color = C.Blue,
        Justify = "Center",
        Icon = "solar:repeat-bold",
        Callback = function()
            FireSwitchSlot("Secondary")
            Notify("Combat", "Switched to Secondary")
        end,
    })
end

-- // ============== MOVEMENT TAB ============== \\ --
do
    local MoveTab = Window:Tab({
        Title = "Movement",
        Icon = "solar:walk-bold",
        IconColor = C.Green,
        IconShape = "Square",
        Border = true,
    })

    local Sec = MoveTab:Section({Title = "🚶  Speed"})

    Sec:Toggle({
        Title = "WalkSpeed",
        Desc = "修改移动速度",
        Callback = function(v)
            State.WalkSpeedEnabled = v
            if not v then
                local hum = GetHumanoid()
                if hum then hum.WalkSpeed = 19.5 end
            end
        end,
    })
    Sec:Slider({
        Title = "WalkSpeed Value",
        Step = 1,
        Value = {Min = 16, Max = 200, Default = 24},
        Callback = function(v) State.WalkSpeedValue = v end,
    })
    Sec:Space()

    Sec:Toggle({
        Title = "Jump Power",
        Desc = "修改跳跃力",
        Callback = function(v) State.JumpPowerEnabled = v end,
    })
    Sec:Slider({
        Title = "Jump Power",
        Step = 1,
        Value = {Min = 50, Max = 300, Default = 60},
        Callback = function(v) State.JumpPowerValue = v end,
    })
    Sec:Space()

    Sec:Toggle({
        Title = "Infinite Jump",
        Desc = "空中可无限跳跃",
        Callback = function(v)
            State.InfiniteJump = v
        end,
    })
    Sec:Space()

    local FlySec = MoveTab:Section({Title = "✈️  Fly"})
    FlySec:Toggle({
        Title = "Fly",
        Desc = "飞行模式 (WASD/方向, Space升, Shift降)",
        Callback = function(v)
            State.Fly = v
            if v then
                StartFly()
                Notify("Movement", "Fly: ON")
            else
                StopFly()
                Notify("Movement", "Fly: OFF")
            end
        end,
    })
    FlySec:Slider({
        Title = "Fly Speed",
        Step = 10,
        Value = {Min = 20, Max = 500, Default = 100},
        Callback = function(v) State.FlySpeed = v end,
    })
    FlySec:Space()

    MoveTab:Toggle({
        Title = "Noclip",
        Desc = "穿墙模式",
        Callback = function(v)
            State.Noclip = v
            Notify("Movement", "Noclip: " .. (v and "ON" or "OFF"))
        end,
    })
    MoveTab:Space()

    -- Teleport
    local TPSec = MoveTab:Section({Title = "📍  Teleport"})
    local playerNames = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            table.insert(playerNames, p.Name)
        end
    end

    TPSec:Dropdown({
        Title = "Teleport to Player",
        Values = playerNames,
        Callback = function(name)
            if TeleportToPlayer(name) then
                Notify("Movement", "Teleported to " .. name)
            else
                Notify("Movement", "Failed to teleport")
            end
        end,
    })
    TPSec:Space()

    TPSec:Button({
        Title = "🔄  Refresh Player List",
        Color = C.Cyan,
        Justify = "Center",
        Callback = function()
            playerNames = {}
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer then
                    table.insert(playerNames, p.Name)
                end
            end
            Notify("Movement", "Player list refreshed")
        end,
    })
end

-- // ============== PLAYER TAB ============== \\ --
do
    local PlayerTab = Window:Tab({
        Title = "Player",
        Icon = "solar:user-bold",
        IconColor = C.Purple,
        IconShape = "Square",
        Border = true,
    })

    local Sec = PlayerTab:Section({Title = "🛡️  Survival"})

    Sec:Toggle({
        Title = "God Mode",
        Desc = "免疫死亡 (恢复血量 + 拦截死亡事件)",
        Callback = function(v)
            State.GodMode = v
            Notify("Player", "God Mode: " .. (v and "ON" or "OFF"))
        end,
    })
    Sec:Space()

    Sec:Toggle({
        Title = "Auto Respawn",
        Desc = "死亡后自动重生",
        Callback = function(v)
            State.AutoRespawn = v
        end,
    })
    Sec:Space()

    Sec:Toggle({
        Title = "Anti Ragdoll",
        Desc = "防止被击倒/布娃娃",
        Callback = function(v)
            State.AntiRagdoll = v
        end,
    })
    Sec:Space()

    PlayerTab:Button({
        Title = "💀  Respawn Now",
        Color = C.Red,
        Justify = "Center",
        Icon = "solar:refresh-bold",
        Callback = function()
            FireRespawn()
            Notify("Player", "Respawning...")
        end,
    })
    PlayerTab:Space()

    PlayerTab:Button({
        Title = "⚡  Force Jump",
        Color = C.Green,
        Justify = "Center",
        Icon = "solar:arrow-up-bold",
        Callback = function()
            FireJump()
            local hum = GetHumanoid()
            if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
        end,
    })
end

-- // ============== VISUALS TAB ============== \\ --
do
    local VisTab = Window:Tab({
        Title = "Visuals",
        Icon = "solar:eye-bold",
        IconColor = C.Cyan,
        IconShape = "Square",
        Border = true,
    })

    local Sec = VisTab:Section({Title = "👁️  ESP"})

    Sec:Toggle({
        Title = "ESP (Box + Name + HP)",
        Desc = "显示玩家方框、名字和血量",
        Callback = function(v)
            State.ESP = v
            Notify("Visuals", "ESP: " .. (v and "ON" or "OFF"))
        end,
    })
    Sec:Space()

    Sec:Toggle({
        Title = "Tracers",
        Desc = "从屏幕底部画线到玩家",
        Callback = function(v)
            State.Tracers = v
        end,
    })
    Sec:Space()

    Sec:Toggle({
        Title = "FOV Circle",
        Desc = "屏幕中心显示范围圈",
        Callback = function(v)
            State.FOV = v
        end,
    })
    Sec:Space()

    Sec:Toggle({
        Title = "Fullbright",
        Desc = "全屏亮度拉满",
        Callback = function(v)
            State.Fullbright = v
            if v then
                ApplyFullbright()
            else
                Lighting.Brightness = 2
                Lighting.ClockTime = 12
                Lighting.FogEnd = 50000
                Lighting.GlobalShadows = true
            end
        end,
    })
end

-- // ============== MISC TAB ============== \\ --
do
    local MiscTab = Window:Tab({
        Title = "Misc",
        Icon = "solar:settings-bold",
        IconColor = C.Grey,
        IconShape = "Square",
        Border = true,
    })

    local Sec = MiscTab:Section({Title = "⚙️  General"})

    Sec:Toggle({
        Title = "Anti AFK",
        Desc = "防止被踢出挂机",
        Callback = function(v)
            State.AntiAFK = v
            if v then StartAntiAFK() else StopAntiAFK() end
        end,
    })
    Sec:Space()

    MiscTab:Button({
        Title = "🔄  Rejoin",
        Color = C.Blue,
        Justify = "Center",
        Icon = "solar:refresh-bold",
        Callback = function()
            Notify("Misc", "Rejoining...")
            Rejoin()
        end,
    })
    MiscTab:Space()

    MiscTab:Button({
        Title = "🚀  Server Hop",
        Color = C.Purple,
        Justify = "Center",
        Icon = "solar:server-bold",
        Callback = function()
            Notify("Misc", "Server hopping...")
            ServerHop()
        end,
    })
    MiscTab:Space()

    MiscTab:Button({
        Title = "❌  Destroy UI",
        Color = C.Red,
        Justify = "Center",
        Icon = "solar:trash-bold",
        Callback = function()
            Window:Destroy()
        end,
    })
    MiscTab:Space()

    -- Info section
    local InfoSec = MiscTab:Section({Title = "ℹ️  Info"})
    InfoSec:Section({
        Title = "Blade Hub v1.0.0\nBuilt with WindUI\nMobile Friendly\n\nRemotes parsed from spy log.",
        TextSize = 16,
        TextTransparency = 0.3,
    })
end

-- Welcome notification
Notify("🔪 Blade Hub", "Loaded successfully! Tap the 🔪 button to open.", 5)

-- Cleanup on destroy
local oldDestroy = Window.Destroy
Window.Destroy = function(self)
    for _, esp in pairs(ESPObjects) do
        for _, obj in pairs(esp) do
            pcall(function() if typeof(obj) ~= "table" then obj:Remove() end end)
        end
    end
    if FOVCircle then pcall(function() FOVCircle:Remove() end) end
    StopFly()
    StopAntiAFK()
    oldDestroy(self)
end
