-- Simple enemy AI that follows the nearest player and visualizes its computed path.
-- Place this Script inside the NPC model you want to control.

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")

local npc = script.Parent
if not npc or not npc:IsA("Model") then
    error("EnemyAI.lua must be parented to an NPC Model")
end

local humanoid = npc:FindFirstChildOfClass("Humanoid")
if not humanoid then
    error("NPC requires a Humanoid for movement")
end

local root = npc.PrimaryPart or npc:FindFirstChild("HumanoidRootPart")
if not root then
    error("NPC requires a PrimaryPart or HumanoidRootPart for navigation")
end

local CONFIG = {
    RepathInterval = 1.0, -- Seconds between path recomputations.
    AllowJump = false, -- Set true if the enemy should obey jump waypoints.
    Animations = {
        TransitionTime = 0.2,
        Idle = nil, -- Accepts animation ids (string/number) or Animation instances.
        Move = nil,
    },
    PathAgent = {
        AgentHeight = 6,
        AgentRadius = 2,
        AgentCanJump = false,
    },
    Visualization = {
        Enabled = true,
        SegmentThickness = 0.2,
        WaypointSize = Vector3.new(0.6, 0.6, 0.6),
        Color = Color3.fromRGB(0, 255, 170),
    },
}

CONFIG.PathAgent.AgentCanJump = CONFIG.AllowJump

local function syncJumpCapability()
    if humanoid.SetStateEnabled then
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, CONFIG.AllowJump)
    end
    if humanoid.UseJumpPower ~= nil then
        humanoid.UseJumpPower = CONFIG.AllowJump
    end
end

syncJumpCapability()

local animator = humanoid:FindFirstChildOfClass("Animator")
if not animator then
    animator = Instance.new("Animator")
    animator.Parent = humanoid
end

local function normalizeAssetId(raw)
    if not raw or raw == "" then
        return nil
    end

    local valueType = typeof(raw)
    if valueType == "number" then
        return "rbxassetid://" .. raw
    elseif valueType == "string" then
        if raw:match("^rbxassetid://") then
            return raw
        end
        if tonumber(raw) then
            return "rbxassetid://" .. raw
        end
        return raw
    elseif valueType == "Instance" and raw:IsA("Animation") then
        return raw.AnimationId
    end

    return nil
end

local function loadAnimation(entry)
    if not entry then
        return nil
    end

    local animationInstance
    local priority
    local looped = true

    if typeof(entry) == "Instance" and entry:IsA("Animation") then
        animationInstance = entry
    elseif typeof(entry) == "table" then
        priority = entry.Priority
        if entry.Looped ~= nil then
            looped = entry.Looped
        end
        if entry.Animation and typeof(entry.Animation) == "Instance" and entry.Animation:IsA("Animation") then
            animationInstance = entry.Animation
        else
            local id = normalizeAssetId(entry.Id or entry.AnimationId or entry.AssetId)
            if not id then
                return nil
            end
            animationInstance = Instance.new("Animation")
            animationInstance.AnimationId = id
            animationInstance.Name = entry.Name or "EnemyAnimation"
            animationInstance.Parent = script
        end
    else
        local id = normalizeAssetId(entry)
        if not id then
            return nil
        end
        animationInstance = Instance.new("Animation")
        animationInstance.AnimationId = id
        animationInstance.Name = "EnemyAnimation"
        animationInstance.Parent = script
    end

    if priority then
        pcall(function()
            animationInstance.Priority = priority
        end)
    end

    local success, trackOrError = pcall(function()
        return animator:LoadAnimation(animationInstance)
    end)

    if not success then
        warn("Enemy failed to load animation", trackOrError)
        return nil
    end

    local track = trackOrError
    track.Looped = looped

    if priority then
        pcall(function()
            track.Priority = priority
        end)
    end

    return track
end

local animationTracks = {
    Idle = loadAnimation(CONFIG.Animations and CONFIG.Animations.Idle),
    Move = loadAnimation(CONFIG.Animations and CONFIG.Animations.Move),
}

local currentAnimation

local function playAnimation(name)
    if currentAnimation == name then
        return
    end

    local transition = (CONFIG.Animations and CONFIG.Animations.TransitionTime) or 0.2

    for trackName, track in pairs(animationTracks) do
        if track and track.IsPlaying and trackName ~= name then
            track:Stop(transition)
        end
    end

    currentAnimation = name
    local track = animationTracks[name]
    if track then
        track:Play(transition)
    end
end

playAnimation("Idle")

local visualizationFolder = Instance.new("Folder")
visualizationFolder.Name = "EnemyPathVisualization"
visualizationFolder.Parent = npc

local function clearVisualization()
    for _, child in ipairs(visualizationFolder:GetChildren()) do
        child:Destroy()
    end
end

local function drawSegment(startPos, endPos)
    local part = Instance.new("Part")
    part.Anchored = true
    part.CanCollide = false
    part.Material = Enum.Material.Neon
    part.Color = CONFIG.Visualization.Color
    part.Size = Vector3.new(CONFIG.Visualization.SegmentThickness, CONFIG.Visualization.SegmentThickness, (endPos - startPos).Magnitude)
    part.CFrame = CFrame.new(startPos, endPos) * CFrame.new(0, 0, -part.Size.Z / 2)
    part.Parent = visualizationFolder
end

local function drawWaypoint(position)
    local part = Instance.new("Part")
    part.Anchored = true
    part.CanCollide = false
    part.Shape = Enum.PartType.Ball
    part.Material = Enum.Material.Neon
    part.Color = CONFIG.Visualization.Color
    part.Size = CONFIG.Visualization.WaypointSize
    part.CFrame = CFrame.new(position)
    part.Parent = visualizationFolder
end

local function renderPath(waypoints)
    clearVisualization()

    if not CONFIG.Visualization.Enabled then
        return
    end

    for index = 1, #waypoints do
        local waypoint = waypoints[index]
        drawWaypoint(waypoint.Position)
        if index > 1 then
            drawSegment(waypoints[index - 1].Position, waypoint.Position)
        end
    end
end

local function getNearestPlayer()
    local nearestPlayer
    local nearestDistance = math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local targetRoot = character and character:FindFirstChild("HumanoidRootPart")
        local targetHumanoid = character and character:FindFirstChildOfClass("Humanoid")
        if targetRoot and targetHumanoid and targetHumanoid.Health > 0 then
            local distance = (targetRoot.Position - root.Position).Magnitude
            if distance < nearestDistance then
                nearestDistance = distance
                nearestPlayer = player
            end
        end
    end

    return nearestPlayer
end

local function computePath(targetPosition)
    local path = PathfindingService:CreatePath(CONFIG.PathAgent)
    local success, errorMessage = pcall(function()
        path:ComputeAsync(root.Position, targetPosition)
    end)

    if not success or path.Status ~= Enum.PathStatus.Success then
        warn("Enemy path computation failed", errorMessage)
        return nil
    end

    return path
end

local function followPath(targetRoot, path)
    local waypoints = path:GetWaypoints()
    if #waypoints == 0 then
        clearVisualization()
        return false
    end

    renderPath(waypoints)
    playAnimation("Move")

    for _, waypoint in ipairs(waypoints) do
        if not targetRoot.Parent then
            return false
        end

        if waypoint.Action == Enum.PathWaypointAction.Jump and CONFIG.AllowJump then
            humanoid.Jump = true
        end

        humanoid:MoveTo(waypoint.Position)
        local reached = humanoid.MoveToFinished:Wait()
        if not reached then
            return false
        end
    end

    return true
end

while true do
    local targetPlayer = getNearestPlayer()
    if not targetPlayer then
        clearVisualization()
        playAnimation("Idle")
        task.wait(CONFIG.RepathInterval)
        continue
    end

    local character = targetPlayer.Character
    local targetRoot = character and character:FindFirstChild("HumanoidRootPart")
    if not targetRoot then
        clearVisualization()
        playAnimation("Idle")
        task.wait(CONFIG.RepathInterval)
        continue
    end

    local path = computePath(targetRoot.Position)
    local success = false
    if path then
        success = followPath(targetRoot, path)
    else
        clearVisualization()
    end

    if path and not success then
        clearVisualization()
    end

    playAnimation("Idle")

    task.wait(CONFIG.RepathInterval)
end
