-- Simple enemy AI that follows the nearest player and visualizes its computed path.
-- Place this Script inside the NPC model you want to control.

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local npc = script.Parent
if not npc or not npc:IsA("Model") then
    error("EnemyAI.lua must be parented to an NPC Model")
end

local humanoid = npc:FindFirstChildOfClass("Humanoid")
if not humanoid then
    error("NPC requires a Humanoid for movement")
end
local root = npc.PrimaryPart
if not root then
    root = npc:FindFirstChild("HumanoidRootPart")
end
if not root then
    error("NPC requires a PrimaryPart or HumanoidRootPart for navigation")
end

local CONFIG = {
    AllowJump = false,
    JumpToleranceMultiplier = 1.8,
    PathAgent = {
        AgentHeight = 6,
        AgentRadius = 2,
        AgentCanJump = false,
    },
    RecomputeDelay = 0.75,
    WaypointTolerance = 1.5,
    TargetDriftRepathDistance = 6,
    TargetDriftRepathHeight = 4,
    StuckTime = 2,
    StuckDistance = 0.5,
    Animations = {
        TransitionTime = 0.2,
        Idle = nil, -- Accepts an asset id (string/number) or table with Id/Looped/Priority fields
        Move = nil,
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
    if humanoid then
        if humanoid.SetStateEnabled then
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, CONFIG.AllowJump)
        end
        if CONFIG.AllowJump and humanoid.UseJumpPower ~= nil then
            humanoid.UseJumpPower = true
        elseif not CONFIG.AllowJump and humanoid.UseJumpPower ~= nil then
            humanoid.UseJumpPower = false
        end
    end
end

syncJumpCapability()

local animator = humanoid:FindFirstChildOfClass("Animator")
if not animator then
    animator = Instance.new("Animator")
    animator.Parent = humanoid
end

local function normalizeAssetId(raw)
    if raw == nil then
        return nil
    end

    local valueType = typeof(raw)
    if valueType == "number" then
        return "rbxassetid://" .. raw
    elseif valueType == "string" then
        if raw == "" then
            return nil
        end
        if raw:match("^rbxassetid://") then
            return raw
        end
        if tonumber(raw) then
            return "rbxassetid://" .. raw
        end
        return raw
    end

    return nil
end

local function loadAnimationFromConfig(entry)
    if not entry then
        return nil
    end

    local entryType = typeof(entry)
    local animationInstance
    local priority
    local looped

    if entryType == "Instance" and entry:IsA("Animation") then
        animationInstance = entry
    elseif entryType == "table" then
        priority = entry.Priority
        looped = entry.Looped

        if entry.Animation and typeof(entry.Animation) == "Instance" and entry.Animation:IsA("Animation") then
            animationInstance = entry.Animation
        else
            local id = normalizeAssetId(entry.Id or entry.AnimationId or entry.AssetId)
            if not id then
                return nil
            end
            animationInstance = Instance.new("Animation")
            animationInstance.AnimationId = id
            animationInstance.Name = entry.Name or "EnemyConfiguredAnimation"
            animationInstance.Parent = script
        end
    else
        local id = normalizeAssetId(entry)
        if not id then
            return nil
        end
        animationInstance = Instance.new("Animation")
        animationInstance.AnimationId = id
        animationInstance.Name = "EnemyConfiguredAnimation"
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
    if looped ~= nil then
        track.Looped = looped
    else
        track.Looped = true
    end

    if priority then
        pcall(function()
            track.Priority = priority
        end)
    end

    return track
end

local animationTracks = {
    Idle = loadAnimationFromConfig(CONFIG.Animations and CONFIG.Animations.Idle),
    Move = loadAnimationFromConfig(CONFIG.Animations and CONFIG.Animations.Move),
}

local currentAnimationName = nil

local function animationTransitionTime()
    if CONFIG.Animations and CONFIG.Animations.TransitionTime then
        return CONFIG.Animations.TransitionTime
    end
    return 0.2
end

local function playAnimation(name)
    if currentAnimationName == name then
        return
    end

    local fadeTime = animationTransitionTime()
    for trackName, track in pairs(animationTracks) do
        if track and track.IsPlaying and trackName ~= name then
            track:Stop(fadeTime)
        end
    end

    currentAnimationName = name
    local track = animationTracks[name]
    if track then
        track:Play(fadeTime)
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

local function drawSegment(startPos: Vector3, endPos: Vector3)
    local part = Instance.new("Part")
    part.Anchored = true
    part.CanCollide = false
    part.Material = Enum.Material.Neon
    part.Color = CONFIG.Visualization.Color
    part.Size = Vector3.new(CONFIG.Visualization.SegmentThickness, CONFIG.Visualization.SegmentThickness, (endPos - startPos).Magnitude)
    part.CFrame = CFrame.new(startPos, endPos) * CFrame.new(0, 0, -part.Size.Z / 2)
    part.Parent = visualizationFolder
end

local function drawWaypoint(position: Vector3)
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

local function renderPath(waypoints: { PathWaypoint })
    clearVisualization()
    if not CONFIG.Visualization.Enabled then
        return
    end
    for index = 1, #waypoints do
        drawWaypoint(waypoints[index].Position)
        if index > 1 then
            drawSegment(waypoints[index - 1].Position, waypoints[index].Position)
        end
    end
end

local function getNearestPlayer(): Player?
    local nearestPlayer = nil
    local nearestDistance = math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        local humanoidTarget = character and character:FindFirstChildOfClass("Humanoid")
        if character and hrp and humanoidTarget and humanoidTarget.Health > 0 then
            local distance = (hrp.Position - root.Position).Magnitude
            if distance < nearestDistance then
                nearestDistance = distance
                nearestPlayer = player
            end
        end
    end
    return nearestPlayer
end

local function computePath(targetPosition: Vector3)
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

local activeWaypoints: { PathWaypoint }? = nil
local currentWaypointIndex = 0
local currentMoveGoal: Vector3? = nil
local currentWaypointStartTime = 0
local currentWaypointStartDistance: number? = nil
local pendingRecomputeTime = 0
local lastTarget: Player? = nil
local lastTargetPosition: Vector3? = nil

local function clearActivePath(shouldIdle: boolean)
    activeWaypoints = nil
    currentWaypointIndex = 0
    currentMoveGoal = nil
    currentWaypointStartTime = 0
    currentWaypointStartDistance = nil
    clearVisualization()
    if shouldIdle then
        playAnimation("Idle")
    end
end

local function applyJumpIfNeeded(waypoint: PathWaypoint)
    if waypoint.Action == Enum.PathWaypointAction.Jump and CONFIG.AllowJump then
        local floorMaterial = humanoid.FloorMaterial
        if floorMaterial and floorMaterial ~= Enum.Material.Air then
            if humanoid.ChangeState then
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end
            humanoid.Jump = true
        end
    end
end

local function moveToWaypoint(index: number)
    if not activeWaypoints then
        return false
    end

    local waypoint = activeWaypoints[index]
    if not waypoint then
        return false
    end

    applyJumpIfNeeded(waypoint)
    humanoid:MoveTo(waypoint.Position)
    currentWaypointIndex = index
    currentMoveGoal = waypoint.Position
    currentWaypointStartTime = time()
    currentWaypointStartDistance = (root.Position - waypoint.Position).Magnitude
    playAnimation("Move")
    return true
end

local function ensureMovementTowardsWaypoint(now: number)
    if not activeWaypoints or currentWaypointIndex == 0 then
        return
    end

    local waypoint = activeWaypoints[currentWaypointIndex]
    if not waypoint then
        clearActivePath(false)
        pendingRecomputeTime = now
        return
    end

    local tolerance = CONFIG.WaypointTolerance
    if waypoint.Action == Enum.PathWaypointAction.Jump then
        tolerance = tolerance * CONFIG.JumpToleranceMultiplier
    end

    local distance = (root.Position - waypoint.Position).Magnitude
    if distance <= tolerance then
        if not moveToWaypoint(currentWaypointIndex + 1) then
            clearActivePath(false)
            pendingRecomputeTime = now
        end
        return
    end

    if not currentMoveGoal or (currentMoveGoal - waypoint.Position).Magnitude > 0.05 then
        moveToWaypoint(currentWaypointIndex)
        return
    end

    if currentWaypointStartTime > 0 and now - currentWaypointStartTime >= CONFIG.StuckTime then
        if not currentWaypointStartDistance or distance > math.max(tolerance, currentWaypointStartDistance - CONFIG.StuckDistance) then
            clearActivePath(false)
            pendingRecomputeTime = now
        else
            currentWaypointStartTime = now
            currentWaypointStartDistance = distance
        end
    end
end

RunService.Heartbeat:Connect(function()
    if not root or not root.Parent then
        return
    end

    local targetPlayer = getNearestPlayer()
    if not targetPlayer then
        if activeWaypoints then
            clearActivePath(true)
        else
            playAnimation("Idle")
        end
        lastTarget = nil
        lastTargetPosition = nil
        return
    end

    if targetPlayer ~= lastTarget then
        pendingRecomputeTime = 0
        lastTarget = targetPlayer
        lastTargetPosition = nil
    end

    local targetCharacter = targetPlayer.Character
    local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
    if not targetRoot then
        if activeWaypoints then
            clearActivePath(true)
        else
            playAnimation("Idle")
        end
        return
    end

    local now = time()
    local targetPosition = targetRoot.Position

    if lastTargetPosition then
        local horizontalDelta = Vector3.new(targetPosition.X, 0, targetPosition.Z) - Vector3.new(lastTargetPosition.X, 0, lastTargetPosition.Z)
        if horizontalDelta.Magnitude >= CONFIG.TargetDriftRepathDistance or math.abs(targetPosition.Y - lastTargetPosition.Y) >= CONFIG.TargetDriftRepathHeight then
            pendingRecomputeTime = 0
        end
    end

    if now < pendingRecomputeTime then
        ensureMovementTowardsWaypoint(now)
        return
    end

    local path = computePath(targetPosition)
    if not path then
        pendingRecomputeTime = now + 0.5
        if not activeWaypoints then
            playAnimation("Idle")
        else
            clearActivePath(true)
        end
        return
    end

    activeWaypoints = path:GetWaypoints()
    renderPath(activeWaypoints)

    local startingIndex = 1
    if activeWaypoints[1] and (activeWaypoints[1].Position - root.Position).Magnitude <= CONFIG.WaypointTolerance then
        startingIndex = math.min(2, #activeWaypoints)
    end

    if startingIndex == 0 or #activeWaypoints == 0 then
        clearActivePath(false)
        pendingRecomputeTime = now + CONFIG.RecomputeDelay
        lastTargetPosition = targetPosition
        return
    end

    if moveToWaypoint(startingIndex) then
        pendingRecomputeTime = now + CONFIG.RecomputeDelay
        lastTargetPosition = targetPosition
        ensureMovementTowardsWaypoint(now)
    else
        clearActivePath(true)
    end
end)
