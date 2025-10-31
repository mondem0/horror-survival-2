--!strict
--[[
Simple enemy AI script for Roblox Studio.
Place this Script inside the enemy NPC model.
Make sure the model has a Humanoid and HumanoidRootPart.
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")

local npc = script.Parent
local humanoid: Humanoid = npc:WaitForChild("Humanoid")
local root: BasePart = npc:WaitForChild("HumanoidRootPart")

local PATH_RECALCULATE_DISTANCE = 10
local LOOK_THRESHOLD = math.rad(45)
local path: Path = PathfindingService:CreatePath({
AgentRadius = 3,
AgentHeight = 6,
AgentCanJump = true,
})

local currentWaypointIndex = 0
local waypoints: {PathWaypoint} = {}
local currentTargetPosition: Vector3? = nil
local isPaused = false

local function getClosestPlayer(): Player?
    local closestPlayer: Player? = nil
    local closestDistance = math.huge

    for _, player in Players:GetPlayers() do
        local character = player.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        local targetHumanoid = character and character:FindFirstChildOfClass("Humanoid")
        if hrp and targetHumanoid and targetHumanoid.Health > 0 then
            local distance = (hrp.Position - root.Position).Magnitude
            if distance < closestDistance then
                closestDistance = distance
                closestPlayer = player
            end
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

local function stopMovement()
    isPaused = true
    waypoints = {}
    currentWaypointIndex = 0
    currentTargetPosition = nil
    humanoid:Move(Vector3.zero)
    humanoid:MoveTo(root.Position)
end

local function startFollowingPath()
    if currentWaypointIndex == 0 or currentWaypointIndex > #waypoints then
        humanoid:Move(Vector3.zero)
        return
    end

    humanoid:MoveTo(waypoints[currentWaypointIndex].Position)
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
        return
    end

    waypoints = path:GetWaypoints()
    currentWaypointIndex = 1
    startFollowingPath()
end

local function moveTowardsPlayer(player: Player)
    local character = player.Character
    if not character then
        return
    end

    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return
    end

    isPaused = false

    if currentWaypointIndex == 0
        or not currentTargetPosition
        or (currentTargetPosition - hrp.Position).Magnitude >= 2
        or (hrp.Position - root.Position).Magnitude >= PATH_RECALCULATE_DISTANCE
    then
        computePath(hrp.Position)
    elseif currentWaypointIndex <= #waypoints then
        humanoid:MoveTo(waypoints[currentWaypointIndex].Position)
    end
end

RunService.Heartbeat:Connect(function()
    local player = getClosestPlayer()
    if not player then
        stopMovement()
        return
    end

    if isPlayerLookingAtNPC(player) then
        stopMovement()
    else
        moveTowardsPlayer(player)
    end
end)

humanoid.MoveToFinished:Connect(function(reached)
    if isPaused or currentWaypointIndex == 0 then
        return
    end

    if reached then
        currentWaypointIndex += 1
        if currentWaypointIndex <= #waypoints then
            humanoid:MoveTo(waypoints[currentWaypointIndex].Position)
        end
    elseif currentTargetPosition then
        task.defer(function()
            computePath(currentTargetPosition :: Vector3)
        end)
    end
end)

path.Blocked:Connect(function(blockedWaypointIndex)
    if isPaused then
        return
    end

    if currentTargetPosition and blockedWaypointIndex >= currentWaypointIndex then
        task.defer(function()
            computePath(currentTargetPosition :: Vector3)
        end)
    end
end)
