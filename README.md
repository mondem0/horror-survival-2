# Simple Enemy AI

This repository contains a plug-and-play Roblox Studio script called `EnemyAI.lua`. Drop it inside an NPC model and the character will continuously chase the nearest player while drawing the path it intends to take.

## Setup

1. Insert an NPC model into the Workspace and make sure it has a **Humanoid** plus a **HumanoidRootPart** (or a set `PrimaryPart`).
2. Add a **Script** under the NPC and paste the contents of `EnemyAI.lua` into it.
3. Playtest the experience. The NPC should pathfind toward the closest alive player and display neon waypoints along its route.

## Configuration

Open the `CONFIG` table near the top of the script to tweak behaviour:

- `RepathInterval`: How often (in seconds) the enemy recomputes a fresh path.
- `AllowJump`: Set `true` if the NPC should obey jump waypoints produced by the pathfinder.
- `PathAgent`: Adjust the agent height/radius if your character model is taller or wider.
- `Visualization.Enabled`: Toggle the neon line and waypoint spheres.
- `Visualization` colours and sizes: Change the look of the rendered path.
- `Animations.Idle` / `Animations.Move`: Optional animation IDs (number, string, or table with `{ Id = 123 }`) that play while standing still or moving. Adjust `TransitionTime` to control the fade between clips.

That’s it—keep the script inside the NPC and it will automatically chase players whenever they spawn.
