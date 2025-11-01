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
PathAgent = {
AgentHeight = 6,
AgentRadius = 2,
AgentCanJump = true,
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

local function followPath(path: Path)
local waypoints = path:GetWaypoints()
renderPath(waypoints)

for _, waypoint in ipairs(waypoints) do
if waypoint.Action == Enum.PathWaypointAction.Jump then
humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
end

humanoid:MoveTo(waypoint.Position)
local reached = humanoid.MoveToFinished:Wait()
if not reached then
return false
end

if (root.Position - waypoint.Position).Magnitude > CONFIG.WaypointTolerance then
return false
end
end

return true
end

local lastTarget: Player? = nil
local nextRecompute = 0

RunService.Heartbeat:Connect(function()
if not root or not root.Parent then
return
end

local targetPlayer = getNearestPlayer()
if not targetPlayer then
clearVisualization()
lastTarget = nil
return
end

if targetPlayer ~= lastTarget then
nextRecompute = 0
lastTarget = targetPlayer
end

if time() < nextRecompute then
return
end
nextRecompute = time() + CONFIG.RecomputeDelay

local targetCharacter = targetPlayer.Character
local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
if not targetRoot then
return
end

local path = computePath(targetRoot.Position)
if path then
local finished = followPath(path)
if not finished then
-- Path failed mid-way; try again soon.
nextRecompute = time() + 0.25
end
end
end)
