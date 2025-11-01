# Horror Survival Enemy AI

This repository provides a Roblox enemy AI Script (`EnemyAI.lua`) that makes an NPC pursue the nearest player while avoiding eye contact. The NPC advances toward players using pathfinding, but pauses whenever the player looks directly at it. The script now works with or without a `Humanoid`, and you can optionally hook up your own animations for idle/movement/watched states.

## Adding the Script to Your NPC
1. In Roblox Studio, insert or open the NPC model you want to control.
2. Add a **Script** as a direct child of the NPC model and rename it to something like `EnemyAI`.
3. Copy the contents of `EnemyAI.lua` from this repository and paste them into the script.
4. Configure the NPC:
   - **With a Humanoid**: leave the standard Roblox rig in place. The script will use the `HumanoidRootPart` and humanoid movement.
   - **Without a Humanoid**: make sure the model has a `PrimaryPart` (or at least one BasePart). The script will automatically move the model by pivoting it, so keep the parts unanchored. If you want animations, add an `AnimationController` with an `Animator`.
5. Press **Play**. The NPC will chase the closest alive player and freeze whenever that player is looking toward the enemy.

## Customization Tips
- Open the `Config` table near the top of `EnemyAI.lua` to tweak behaviour:
  - `MovementSpeed`, `WaypointReachThreshold`, `PathTargetDriftThreshold`, and `MinPathRecomputeInterval` help the NPC keep chasing smoothly while continuously refreshing its path.
  - `PathRecalculateDistance` and `PathAgentParameters` (radius, height, can jump) should match the size of your enemy for best pathfinding results.
  - `PathVisualization` draws the current path using neon segments and waypoint orbs so you can see where the AI plans to move. Adjust colours, thickness, waypoint size, or set `Enabled = false` if you want to hide it. You can also assign a specific parent (e.g. a dedicated folder in `Workspace`).
  - `LookThresholdDegrees` adjusts how wide the vision cone is for freezing behaviour.
- `RequireLineOfSightToPause` controls whether the NPC only freezes when the player has a clear raycast to the enemy. Leave it enabled to prevent the NPC from stopping through walls.
- To use your own animations, set `AnimationConfig.Enabled = true` and fill in the `AnimationIds` table with your animation asset IDs. The script accepts either numeric IDs (e.g. `123456789`) or full strings (e.g. `rbxassetid://123456789`). Provide IDs for `Idle`, `Moving`, and optionally `Watched` (played when the player is looking at the enemy). You can further customise priorities through `AnimationConfig.Priorities` if you need different layering. The script automatically loads the animations on a `Humanoid` or, if your rig is humanoid-free, an `AnimationController`.
