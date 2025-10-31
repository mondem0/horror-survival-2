--!strict
--[[
Simple enemy AI script for Roblox Studio.
Place this Script inside the enemy NPC model.
The model no longer requires a Humanoid object; a PrimaryPart or any BasePart
will be used for movement when a Humanoid is absent.

Optionally configure custom animation ids in the AnimationConfig table below
and add either a Humanoid (with an Animator) or an AnimationController.
]]

local Config = {
    MovementSpeed = 10,
    WaypointReachThreshold = 2.5,
    PathRecalculateDistance = 10,
    LookThresholdDegrees = 45,
    PathAgentParameters = {
        AgentRadius = 3,
        AgentHeight = 6,
        AgentCanJump = true,
    },
    PathVisualization = {
        Enabled = true,
        Parent = nil,
        SegmentColor = Color3.fromRGB(255, 0, 0),
        SegmentMaterial = Enum.Material.Neon,
        SegmentTransparency = 0.25,
        SegmentThickness = 0.35,
        WaypointColor = Color3.fromRGB(255, 170, 0),
        WaypointTransparency = 0.1,
        WaypointSize = 0.85,
        RefreshDistance = 1,
    },
    AnimationConfig = {
        Enabled = false,
        AnimationIds = {
            Idle = nil, -- e.g. "rbxassetid://123456789"
            Moving = nil,
            Watched = nil,
        },
    },
}

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")

local npc = script.Parent
if not npc or not npc:IsA("Model") then
    error("EnemyAI script must be parented to a Model.")
end

local humanoid: Humanoid? = npc:FindFirstChildOfClass("Humanoid")

type PathWaypointLike = {
    Position: Vector3,
    Action: Enum.PathWaypointAction?,
}

local function waitForRootPart(model: Model, hum: Humanoid?): BasePart
    if hum then
        local rootPart = hum.RootPart
        if rootPart then
            return rootPart
        end
        hum:GetPropertyChangedSignal("RootPart"):Wait()
        rootPart = hum.RootPart
        if rootPart then
            return rootPart
        end
    end

    local rootPart = model.PrimaryPart
    while not rootPart do
        local candidate = model:FindFirstChild("HumanoidRootPart")
        if candidate and candidate:IsA("BasePart") then
            rootPart = candidate
            break
        end

        candidate = model:FindFirstChildWhichIsA("BasePart")
        if candidate then
            rootPart = candidate
            break
        end

        model.ChildAdded:Wait()
        rootPart = model.PrimaryPart
    end

    assert(rootPart, "Enemy model requires at least one BasePart to act as a root.")
    return rootPart
end

local root: BasePart = waitForRootPart(npc, humanoid)

if not npc.PrimaryPart then
    pcall(function()
        npc.PrimaryPart = root
    end)
end

local LOOK_THRESHOLD = math.rad(Config.LookThresholdDegrees)
local path: Path = PathfindingService:CreatePath(Config.PathAgentParameters)

local currentWaypointIndex = 0
local waypoints: {PathWaypointLike} = {}
local currentTargetPosition: Vector3? = nil
local isPaused = false
local lastPauseActivity: string? = nil

local currentActivity = "Idle"
local animator: Animator? = nil
local animationTracks: {[string]: AnimationTrack} = {}
local currentAnimationTrack: AnimationTrack? = nil

local pathVisualizationFolder: Folder? = nil
local pathVisualizationItems: {Instance} = {}
local lastVisualizationRootPosition: Vector3? = nil
local lastVisualizationWaypointIndex = 0

local function ensurePathVisualizationFolder(): Folder?
    if not Config.PathVisualization.Enabled then
        return nil
    end

    if pathVisualizationFolder and pathVisualizationFolder.Parent then
        return pathVisualizationFolder
    end

    local parent = Config.PathVisualization.Parent
    if typeof(parent) ~= "Instance" or not parent:IsDescendantOf(game) then
        parent = workspace
    end

    local folder = Instance.new("Folder")
    folder.Name = string.format("%s_PathVisualization", npc.Name)
    folder.Parent = parent
    pathVisualizationFolder = folder

    return folder
end

local function clearPathVisualization()
    for index = #pathVisualizationItems, 1, -1 do
        local item = pathVisualizationItems[index]
        if item and item.Parent then
            item:Destroy()
        end
        pathVisualizationItems[index] = nil
    end

    if pathVisualizationFolder then
        pathVisualizationFolder:ClearAllChildren()
    end

    lastVisualizationRootPosition = nil
    lastVisualizationWaypointIndex = 0
end

local function addPathSegment(folder: Folder, fromPos: Vector3, toPos: Vector3)
    local length = (toPos - fromPos).Magnitude
    if length <= 0.01 then
        return
    end

    local part = Instance.new("Part")
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.Material = Config.PathVisualization.SegmentMaterial
    part.Color = Config.PathVisualization.SegmentColor
    part.Transparency = Config.PathVisualization.SegmentTransparency
    part.Size = Vector3.new(Config.PathVisualization.SegmentThickness, Config.PathVisualization.SegmentThickness, length)
    part.CFrame = CFrame.lookAt((fromPos + toPos) * 0.5, toPos)
    part.Name = "PathSegment"
    part.Parent = folder
    table.insert(pathVisualizationItems, part)
end

local function addWaypointMarker(folder: Folder, position: Vector3)
    local marker = Instance.new("Part")
    marker.Anchored = true
    marker.Shape = Enum.PartType.Ball
    marker.CanCollide = false
    marker.CanQuery = false
    marker.CanTouch = false
    marker.Material = Config.PathVisualization.SegmentMaterial
    marker.Color = Config.PathVisualization.WaypointColor
    marker.Transparency = Config.PathVisualization.WaypointTransparency
    marker.Size = Vector3.new(Config.PathVisualization.WaypointSize, Config.PathVisualization.WaypointSize, Config.PathVisualization.WaypointSize)
    marker.CFrame = CFrame.new(position)
    marker.Name = "WaypointMarker"
    marker.Parent = folder
    table.insert(pathVisualizationItems, marker)
end

local function rebuildPathVisualization()
    if not Config.PathVisualization.Enabled then
        return
    end

    clearPathVisualization()

    local folder = ensurePathVisualizationFolder()
    if not folder then
        return
    end

    if currentWaypointIndex == 0 or #waypoints == 0 then
        return
    end

    local previousPosition = root.Position
    for index = math.max(currentWaypointIndex, 1), #waypoints do
        local waypoint = waypoints[index]
        addPathSegment(folder, previousPosition, waypoint.Position)
        addWaypointMarker(folder, waypoint.Position)
        previousPosition = waypoint.Position
    end
end

local function refreshPathVisualization(force: boolean)
    if not Config.PathVisualization.Enabled then
        return
    end

    local rootPosition = root.Position
    if not lastVisualizationRootPosition then
        force = true
    end

    if not force then
        if currentWaypointIndex ~= lastVisualizationWaypointIndex then
            force = true
        elseif (rootPosition - lastVisualizationRootPosition :: Vector3).Magnitude >= Config.PathVisualization.RefreshDistance then
            force = true
        end
    end

    if force then
        rebuildPathVisualization()
        lastVisualizationRootPosition = rootPosition
        lastVisualizationWaypointIndex = currentWaypointIndex
    end
end

local function ensureAnimator(): Animator?
    if animator then
        return animator
    end

    if humanoid then
        animator = humanoid:FindFirstChildOfClass("Animator")
        if not animator then
            local created = Instance.new("Animator")
            created.Name = "EnemyAnimator"
            created.Parent = humanoid
            animator = created
        end
    else
        local controller = npc:FindFirstChildOfClass("AnimationController")
        if not controller then
            controller = Instance.new("AnimationController")
            controller.Name = "EnemyAnimationController"
            controller.Parent = npc
        end

        animator = controller:FindFirstChildOfClass("Animator")
        if not animator then
            local created = Instance.new("Animator")
            created.Name = "EnemyAnimator"
            created.Parent = controller
            animator = created
        end
    end

    return animator
end

local function setupAnimations()
    if not Config.AnimationConfig.Enabled then
        return
    end

    local anim = ensureAnimator()
    if not anim then
        return
    end

    for state, animationId in pairs(Config.AnimationConfig.AnimationIds) do
        if animationId then
            local animation = Instance.new("Animation")
            animation.AnimationId = animationId
            animation.Name = string.format("Enemy_%sAnimation", state)

            local track = anim:LoadAnimation(animation)
            track.Looped = true
            track.Priority = Enum.AnimationPriority.Movement
            animationTracks[state] = track
        end
    end
end

local function playAnimationFor(activity: string)
    if not Config.AnimationConfig.Enabled then
        return
    end

    local desiredTrack = animationTracks[activity] or animationTracks.Idle
    if not desiredTrack then
        return
    end

    if currentAnimationTrack and currentAnimationTrack ~= desiredTrack then
        if currentAnimationTrack.IsPlaying then
            currentAnimationTrack:Stop()
        end
    end

    currentAnimationTrack = desiredTrack
    if not desiredTrack.IsPlaying then
        desiredTrack:Play()
    end
end

local function setActivity(activity: string)
    if currentActivity == activity then
        if currentAnimationTrack and Config.AnimationConfig.Enabled and not currentAnimationTrack.IsPlaying then
            currentAnimationTrack:Play()
        end
        return
    end

    currentActivity = activity
    playAnimationFor(activity)
end

setupAnimations()
setActivity("Idle")

local function clearMovement()
    if humanoid then
        humanoid:Move(Vector3.zero)
        if root then
            humanoid:MoveTo(root.Position)
        end
    end
end

local function setMovementPaused(paused: boolean, pauseActivity: string?)
    if paused then
        if isPaused and lastPauseActivity == pauseActivity then
            return
        end

        isPaused = true
        lastPauseActivity = pauseActivity
        waypoints = {}
        currentWaypointIndex = 0
        currentTargetPosition = nil
        clearMovement()
        setActivity(pauseActivity or "Idle")
        clearPathVisualization()
    else
        if not isPaused then
            return
        end

        isPaused = false
        lastPauseActivity = nil
    end
end

local function getClosestPlayer(): Player?
    local closestPlayer: Player? = nil
    local closestDistance = math.huge

    for _, player in Players:GetPlayers() do
        local character = player.Character
        if not character then
            continue
        end

        local targetHumanoid = character:FindFirstChildOfClass("Humanoid")
        if targetHumanoid and targetHumanoid.Health <= 0 then
            continue
        end

        local hrp = character:FindFirstChild("HumanoidRootPart")
        local primary = character.PrimaryPart
        local fallback = character:FindFirstChildWhichIsA("BasePart")
        local targetPart = hrp or primary or fallback
        if not targetPart then
            continue
        end

        local distance = (targetPart.Position - root.Position).Magnitude
        if distance < closestDistance then
            closestDistance = distance
            closestPlayer = player
        end
    end

    return closestPlayer
end

local function isPlayerLookingAtNPC(player: Player): boolean
    local character = player.Character
    if not character then
        return false
    end

    local hrp = character:FindFirstChild("HumanoidRootPart")
    local head = character:FindFirstChild("Head")
    if not hrp or not head then
        return false
    end

    local offset = root.Position - head.Position
    if offset.Magnitude < 0.001 then
        return true
    end

    local directionToNPC = offset.Unit
    local lookVector = head.CFrame.LookVector.Unit

    local dot = lookVector:Dot(directionToNPC)
    local angle = math.acos(math.clamp(dot, -1, 1))

    return angle < LOOK_THRESHOLD
end

local function computePath(targetPosition: Vector3)
    currentTargetPosition = targetPosition

    local success, errorMessage = pcall(function()
        path:ComputeAsync(root.Position, targetPosition)
    end)

    if not success or path.Status ~= Enum.PathStatus.Success then
        warn("Failed to compute path:", errorMessage)
        waypoints = {}
        currentWaypointIndex = 0
        currentTargetPosition = nil
        clearPathVisualization()
        if not isPaused then
            setActivity("Idle")
        end
        return
    end

    local rawWaypoints = path:GetWaypoints()
    waypoints = table.create(#rawWaypoints)
    for index, point in ipairs(rawWaypoints) do
        waypoints[index] = {
            Position = point.Position,
            Action = point.Action,
        }
    end

    if #waypoints == 0 then
        table.insert(waypoints, {
            Position = targetPosition,
            Action = Enum.PathWaypointAction.Walk,
        })
    end

    if #waypoints > 0 and (waypoints[1].Position - root.Position).Magnitude < 0.5 then
        table.remove(waypoints, 1)
    end

    if #waypoints == 0 then
        table.insert(waypoints, {
            Position = targetPosition,
            Action = Enum.PathWaypointAction.Walk,
        })
    end

    currentWaypointIndex = 1
    refreshPathVisualization(true)
end

local function followPathWithHumanoid()
    if currentWaypointIndex == 0 or currentWaypointIndex > #waypoints then
        return
    end

    local waypoint = waypoints[currentWaypointIndex]
    if waypoint.Action == Enum.PathWaypointAction.Jump then
        humanoid.Jump = true
    end

    humanoid:MoveTo(waypoint.Position)
end

local function followPathWithoutHumanoid(stepDistance: number)
    local remaining = stepDistance

    while remaining > 0 and currentWaypointIndex ~= 0 and currentWaypointIndex <= #waypoints do
        local waypoint = waypoints[currentWaypointIndex]
        local offset = waypoint.Position - root.Position
        local horizontal = Vector3.new(offset.X, 0, offset.Z)
        local distance = horizontal.Magnitude

        if distance <= Config.WaypointReachThreshold then
            currentWaypointIndex += 1
            refreshPathVisualization(true)
            if currentWaypointIndex > #waypoints then
                currentWaypointIndex = 0
                currentTargetPosition = nil
                setActivity("Idle")
                clearPathVisualization()
                return
            end
            continue
        end

        local step = math.min(distance, remaining)
        local direction = horizontal.Unit
        local verticalStep = math.clamp(offset.Y, -step, step)

        local newPosition = root.Position + direction * step + Vector3.new(0, verticalStep, 0)
        local lookAtTarget = newPosition + direction
        npc:PivotTo(CFrame.lookAt(newPosition, lookAtTarget))

        remaining -= step
    end

end

local function updateWaypointProgressForHumanoid()
    if currentWaypointIndex == 0 or currentWaypointIndex > #waypoints then
        return
    end

    local waypoint = waypoints[currentWaypointIndex]
    if (root.Position - waypoint.Position).Magnitude <= Config.WaypointReachThreshold then
        currentWaypointIndex += 1
        refreshPathVisualization(true)
        if currentWaypointIndex > #waypoints then
            currentWaypointIndex = 0
            currentTargetPosition = nil
            setActivity("Idle")
            clearPathVisualization()
        end
    end
end

local function moveTowardsPlayer(player: Player, dt: number)
    local character = player.Character
    if not character then
        return
    end

    local hrp = character:FindFirstChild("HumanoidRootPart")
    local primary = character.PrimaryPart
    local fallback = character:FindFirstChildWhichIsA("BasePart")
    local targetPart = hrp or primary or fallback
    if not targetPart then
        return
    end

    setActivity("Moving")

    if currentWaypointIndex == 0
        or not currentTargetPosition
        or (currentTargetPosition - targetPart.Position).Magnitude >= 2
        or (targetPart.Position - root.Position).Magnitude >= Config.PathRecalculateDistance
    then
        computePath(targetPart.Position)
    end

    if currentWaypointIndex == 0 then
        return
    end

    if humanoid then
        followPathWithHumanoid()
    else
        local stepDistance = Config.MovementSpeed * dt
        followPathWithoutHumanoid(stepDistance)
    end

    refreshPathVisualization(false)
end

path.Blocked:Connect(function(blockedWaypointIndex)
    if isPaused then
        return
    end

    if currentTargetPosition and blockedWaypointIndex >= currentWaypointIndex then
        task.defer(function()
            if currentTargetPosition then
                computePath(currentTargetPosition :: Vector3)
            end
        end)
    end
end)

if humanoid then
    humanoid.MoveToFinished:Connect(function(_reached)
        updateWaypointProgressForHumanoid()
    end)
end

RunService.Heartbeat:Connect(function(dt)
    local player = getClosestPlayer()
    if not player then
        setMovementPaused(true, "Idle")
        return
    end

    if isPlayerLookingAtNPC(player) then
        setMovementPaused(true, "Watched")
        return
    end

    if isPaused then
        setMovementPaused(false)
    end

    moveTowardsPlayer(player, dt)

    if humanoid then
        updateWaypointProgressForHumanoid()
    end
end)

