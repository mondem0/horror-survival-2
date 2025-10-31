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
  - `MovementSpeed`, `WaypointReachThreshold`, and `PathRecalculateDistance` control chase movement.
  - `PathAgentParameters` (radius, height, can jump) should match the size of your enemy for best pathfinding results.
  - `LookThresholdDegrees` adjusts how wide the vision cone is for freezing behaviour.
- To use your own animations, set `AnimationConfig.Enabled = true` and fill in the `AnimationIds` table with your animation asset IDs (e.g. `rbxassetid://123456789`). Provide IDs for `Idle`, `Moving`, and optionally `Watched` (played when the player is looking at the enemy). The script will automatically create/load animations on a `Humanoid` or `AnimationController`.
