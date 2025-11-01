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
    PathAgent = {
        AgentHeight = 6,
        AgentRadius = 2,
        AgentCanJump = false,
    },
    RecomputeDelay = 0.75,
    WaypointTolerance = 1.5,
    Visualization = {
        Enabled = true,
        SegmentThickness = 0.2,
        WaypointSize = Vector3.new(0.6, 0.6, 0.6),
        Color = Color3.fromRGB(0, 255, 170),
    },
}

CONFIG.PathAgent.AgentCanJump = CONFIG.AllowJump

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
local pendingRecomputeTime = 0
local lastTarget: Player? = nil
local lastTargetPosition: Vector3? = nil

local function clearActivePath()
    activeWaypoints = nil
    currentWaypointIndex = 0
    lastTargetPosition = nil
    clearVisualization()
end

local function moveToWaypoint(index: number)
    if not activeWaypoints then
        return false
    end

    local waypoint = activeWaypoints[index]
    if not waypoint then
        return false
    end

    if waypoint.Action == Enum.PathWaypointAction.Jump and CONFIG.AllowJump then
        local floorMaterial = humanoid.FloorMaterial
        if floorMaterial and floorMaterial ~= Enum.Material.Air then
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end

    humanoid:MoveTo(waypoint.Position)
    currentWaypointIndex = index
    return true
end

humanoid.MoveToFinished:Connect(function(reached)
    if not activeWaypoints then
        return
    end

    if not reached then
        clearActivePath()
        pendingRecomputeTime = time() + 0.25
        return
    end

    local nextIndex = currentWaypointIndex + 1
    if not moveToWaypoint(nextIndex) then
        clearActivePath()
        pendingRecomputeTime = time() -- reached end, refresh soon
    end
end)

RunService.Heartbeat:Connect(function()
    if not root or not root.Parent then
        return
    end

    local targetPlayer = getNearestPlayer()
    if not targetPlayer then
        clearActivePath()
        lastTarget = nil
        return
    end

    if targetPlayer ~= lastTarget then
        pendingRecomputeTime = 0
        lastTarget = targetPlayer
    end

    local targetCharacter = targetPlayer.Character
    local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
    if not targetRoot then
        clearActivePath()
        return
    end

    local now = time()
    if now < pendingRecomputeTime then
        return
    end

    local targetPosition = targetRoot.Position
    if lastTargetPosition then
        local drift = (targetPosition - lastTargetPosition).Magnitude
        if drift < CONFIG.WaypointTolerance and activeWaypoints then
            return
        end
    end

    local path = computePath(targetRoot.Position)
    if not path then
        pendingRecomputeTime = now + 0.5
        return
    end
    activeWaypoints = path:GetWaypoints()
    lastTargetPosition = targetPosition
    renderPath(activeWaypoints)

    if not moveToWaypoint(math.min(#activeWaypoints, 2)) then
        clearActivePath()
    else
        pendingRecomputeTime = now + CONFIG.RecomputeDelay
    end
end)
