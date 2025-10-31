# Horror Survival Enemy AI

This repository provides a Roblox enemy AI Script (`EnemyAI.lua`) that makes an NPC pursue the nearest player while avoiding eye contact. The NPC advances toward players using pathfinding, but pauses whenever the player looks directly at it.

## Adding the Script to Your NPC
1. In Roblox Studio, insert or open the NPC model you want to control.
2. Ensure the model contains a **Humanoid** and a **HumanoidRootPart**.
3. Add a **Script** as a direct child of the NPC model and rename it to something like `EnemyAI`.
4. Copy the contents of `EnemyAI.lua` from this repository and paste them into the script.
5. Playtest the game. The NPC will patrol toward the closest alive player, halting whenever the player looks at it.

## Customization Tips
- Adjust `PATH_RECALCULATE_DISTANCE` to change how often the path is recomputed.
- Modify `LOOK_THRESHOLD` to tweak how sensitive the enemy is to players looking at it (the value is in radians).
- Update the `AgentRadius`, `AgentHeight`, and `AgentCanJump` properties in the path configuration to better match your NPC's size and capabilities.
