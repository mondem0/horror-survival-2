# Simple Enemy AI

This repository contains a plug-and-play Roblox Studio Script called `EnemyAI.lua`. Drop it inside the model that represents your enemy NPC and the NPC will continuously chase the nearest player while rendering the path it plans to take.

## Setup Instructions

1. Insert an NPC model into the Workspace and ensure it has a **Humanoid** and a **HumanoidRootPart** (or set the model's `PrimaryPart`).
2. Add a **Script** under the NPC and paste the contents of `EnemyAI.lua` into it (or insert the file directly via the Asset Manager).
3. Playtest the experience. The NPC should:
   - Find the closest alive player.
   - Compute and follow a smooth path using Roblox Pathfinding.
   - Display neon segments and waypoint orbs so you can see the route it plans to follow.

### Tuning Options

Open the `CONFIG` table near the top of the script to customize behaviour:

- `RecomputeDelay`: How often (in seconds) the enemy refreshes its path to the target.
- `WaypointTolerance`: How close the NPC must get to a waypoint before advancing.
- `TargetDriftRepathDistance`: Horizontal distance (in studs) the player must move before the NPC instantly recomputes its path instead of waiting for the next refresh window.
- `TargetDriftRepathHeight`: Vertical change that also triggers an immediate path recompute—handy when players jump onto platforms.
- `StuckTime`: How long (in seconds) the NPC will try to reach the same waypoint before abandoning the route and requesting a new one.
- `StuckDistance`: Extra distance (in studs) the NPC expects to close within the `StuckTime` window. Increase this slightly if the character moves slowly.
- `Visualization.Enabled`: Turn the neon path rendering on or off.
- `Visualization.SegmentThickness` and `Visualization.WaypointSize`: Adjust the look of the visual path.
- `Visualization.Color`: Change the path colour.
- `AllowJump`: Let the NPC obey pathfinding jump commands when true; disabled by default to keep enemies grounded.
- `JumpToleranceMultiplier`: Extra distance the NPC will accept when it finishes a jump waypoint so minor ledge misalignments don't cause it to stall. Increase this slightly if your enemy still hesitates on small platforms.
- `Animations`: Provide optional idle/move animation IDs. Supply `CONFIG.Animations.Idle` and/or `CONFIG.Animations.Move` with an asset id (number/string) or a table such as `{ Id = 1234567890, Looped = true, Priority = Enum.AnimationPriority.Movement }` to have the script automatically play those tracks. Adjust `TransitionTime` to control the blend between clips.

If the NPC gets stuck, try increasing the path agent radius/height values or giving the enemy more room to move.

## Notes

- The path visualization folder (`EnemyPathVisualization`) is recreated on each update. Feel free to re-style the parts or swap them for your own assets if you prefer a different look.
- The script uses Roblox's default pathfinding settings; for more advanced behaviours consider tuning agent parameters or adding obstacle avoidance logic.
