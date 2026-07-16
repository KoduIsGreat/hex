Project Wayfinder – Game Design Document (Revised)

1. Concept overview

Working title: Project Wayfinder  
Genre: Automation Roguelike / Cartographic Exploration Strategy  
Core fantasy: You are the Chief Cartographer and Quartermaster of a prestigious Exploration Society. You don’t control the explorer directly—you design their doctrine, configure their instincts, and then launch them into a fog‑shrouded world, trying to understand and influence a semi‑autonomous “expedition AI” that always remains partly a black box.

The player’s power is in planning, inference, and analysis, not in moment‑to‑moment movement. Runs are fast—seconds long—but dense with information, logs, and emergent behavior.

---

2. Core loop

Each run follows a tight, four‑phase loop:

1. Map Room (Review & Study)
   - Review the persistent global hex map.
   - Study revealed terrain, events, and prior expedition logs.
   - Observe belief overlays to understand what the expedition AI “thinks” the world looks like.

2. Prep Phase (Expedition Programming)
   - Configure expedition doctrine:
     - Route intent (primary goal).
     - Terrain behavior profile (proximity matrix).
     - Risk protocols and dynamic behavior triggers.
     - Thresholds for key behaviors.
   - Choose party composition (professions).
   - Select gear loadout.
   - Allocate funding (rations, gear, radio signals).

3. Simulation (Automated Run)
   - Launch the expedition.
   - The explorer follows manual waypoints through known tiles, then switches to autonomous behavior.
   - Pathfinding uses both the revealed map and the belief map to make decisions.
   - Events trigger, resources are consumed, and dynamic behaviors (impasse handling, ration emergencies, reveal mode) fire automatically.

4. Investor Pitch & Analysis
   - Convert artifacts and intel into funding and permanent upgrades.
   - Review the expedition log in detail:
     - Scrub day‑by‑day.
     - See what the explorer saw and believed.
     - Understand why decisions were made.
   - Use insights to refine templates and doctrine for future runs.

> “All map data cleared during a run remains permanently cleared on the world globe across subsequent expeditions.”   

---

3. World & terrain

3.1 Global hex globe

The world is a procedurally generated global hex grid, rendered as a rotatable globe with smooth zoom from tactical tile view to planetary scale. Macro‑biomes resemble a Civilization V‑style world: grasslands, forests, deserts, swamps, hills, mountains, coasts, and oceans.

3.2 Baseline terrain cost matrix

Each tile has a base day cost (movement cost) and a vision radius. Standing on a tile consumes rations equal to its day cost to exit.

> “Every tile on the hex grid possesses a fundamental movement cost represented as Days. If an explorer stands on a tile, they consume an equivalent number of rations to exit it.”   

| Terrain Type          | Base Day Cost | Vision Radius | Special Traits                                                |
|-----------------------|---------------|---------------|----------------------------------------------------------------|
| Grassland / Plains    | 1 Day         | 1 Hex         | Baseline pathing.                                             |
| Forest / Jungle       | 2 Days        | 1 Hex         | Dense cover; hides blueprints/relics.                         |
| Swamp / Marsh         | 3 Days        | 1 Hex         | Heavy navigation penalty.                                     |
| Hill                  | 2 Days        | 2 Hexes       | Elevated; minor radar visibility.                            |
| Mountain              | Impassable*   | 3 Hexes       | Requires climbing gear; massive fog clearing.                |
| Coastal / Shore       | 1 Day         | 1 Hex         | Land–water boundary.                                         |
| Ocean / Deep Sea      | Impassable*   | 1 Hex         | Requires naval tech to cross.                                |

\*Impassable unless specific gear/tech is equipped.

Terrain types also influence event distribution (tribes near forests, portals near mountains, ruins in deserts, etc.), feeding into the belief system.

---

4. The belief map system

This is the heart of Project Wayfinder.

4.1 Purpose

The belief map is the expedition AI’s probabilistic understanding of fogged tiles. It does not generate terrain; the full world is generated at game start. Instead, the belief map estimates, for each fogged tile:

- The probability of each terrain type.
- The confidence level of that estimate.
- The inferred shape of larger structures (desert basins, mountain ranges, forest blobs, etc.).

Pathfinding uses expected costs derived from these probabilities, allowing the explorer to act intelligently in unknown territory.

4.2 Dual maps: revealed vs belief

The game maintains two parallel representations:

- Revealed Map
  - Tiles the player and explorer have actually seen.
  - Exact terrain, events, and costs.
  - Persistent across runs.

- Belief Map
  - For each fogged tile:
    - \( P(\text{Grassland}), P(\text{Forest}), P(\text{Swamp}), \dots \)
    - Confidence score (0–100%).
  - Updated whenever new tiles are revealed.
  - Informed by:
    - Local neighbors.
    - Regional patterns.
    - Shape continuity.
    - Directional trends.
    - Profession bonuses.

4.3 Local neighborhood inference

At the simplest level, fogged tiles infer terrain from adjacent revealed tiles:

- Adjacent to mountains → higher \( P(\text{Mountain}) \).
- Adjacent to forests → higher \( P(\text{Forest}) \).
- Adjacent to plains → higher \( P(\text{Plains}) \).

This is the local component:

\[
P_{\text{local}}(t) = f(\text{adjacent revealed tiles})
\]

4.4 Regional influence

Beyond immediate neighbors, the belief map considers all revealed tiles within a radius \( R \):

- Each revealed tile contributes to the probability of matching terrain types.
- Contributions are weighted by distance (e.g., inverse square or exponential decay).

\[
P{\text{regional}}(t) = \sum{i \in \text{revealed within } R} w(di) \cdot \mathbf{1}(\text{terrain}i = t)
\]

Where:

- \( d_i \) = distance from fogged tile to revealed tile \( i \).
- \( w(d) \) = distance weight (e.g., \( 1/d^2 \)).
- \( \mathbf{1} \) = indicator function.

This captures regional density: deserts cluster, forests patch, mountains band.

4.5 Shape continuity (blobs, bands, basins)

Terrain types have characteristic shapes:

- Deserts → amorphous blobs / basins.
- Forests → clustered patches.
- Mountains → ridges, arcs, bands.
- Swamps → lowland basins.
- Hills → scattered but often adjacent to mountains.

The belief system detects these shapes by clustering revealed tiles:

1. Connected components / flood‑fill
   - Group contiguous tiles of the same terrain.
2. Bounding shapes
   - Compute convex hulls, bounding boxes, or approximate “blobs.”
3. Continuation zones
   - Infer where the shape likely extends beyond revealed edges.

Fogged tiles inside these inferred zones get boosted probabilities:

\[
P_{\text{shape}}(t) = g(\text{cluster membership, terrain type})
\]

Example:

- Two revealed desert patches trending NE–SW.
- Fogged tiles between them along that vector get significantly higher \( P(\text{Desert}) \).

4.6 Directional alignment

The system also tracks directional trends:

- Mountain ranges running north–south.
- Desert belts running east–west.
- Forest bands following river valleys.

When multiple clusters share a direction vector, the belief map infers continuity:

- Fogged tiles along that vector between clusters get boosted \( P(\text{matching terrain}) \).
- This is especially important for mountain ranges:
  - If two revealed mountain lines are parallel and separated, tiles between them along the same axis are likely part of the same range.

4.7 Profession modifiers

Professions directly enhance belief accuracy:

- Navigator
  - Improves coast/ocean predictions.
  - Extends inference radius for shoreline continuity.
- Geologist
  - Improves mountain/hill band detection.
  - Increases confidence in ridge‑line continuity.
- Ecologist
  - Enhances forest/swamp blob detection.
  - Better prediction of dense vegetation zones.
- Anthropologist
  - Improves tribal region inference.
  - Predicts likely village locations and hostility.
- Surveyor
  - Increases fog‑clearing efficiency.
  - Slightly boosts belief confidence globally.
- Linguist
  - Improves event interpretation, not terrain—but affects how belief interacts with narrative nodes.

Professions modify weights:

- Increase \( R \) (regional radius).
- Adjust \( w(d) \) (distance decay).
- Boost \( P_{\text{shape}} \) for specific terrain types.
- Raise confidence thresholds.

4.8 Combined belief model

For each fogged tile and terrain type \( t \):

\[
P(t) = \alpha P{\text{local}}(t) + \beta P{\text{regional}}(t) + \gamma P{\text{shape}}(t) + \delta P{\text{direction}}(t)
\]

Where:

- \(\alpha, \beta, \gamma, \delta\) are weights influenced by:
  - Route intent.
  - Terrain behavior profile.
  - Professions.
  - Upgrades.

Probabilities are normalized to sum to 1 across all terrain types.

4.9 Expected cost for pathfinding

Pathfinding uses expected movement cost for fogged tiles:

\[
\text{ExpectedCost} = \sum_{t} P(t) \cdot \text{BaseCost}(t)
\]

Proximity rules (Hug/Skirt/Avoid) apply to expected terrain, weighted by confidence:

- If \( P(\text{Mountain}) = 0.7 \), Mountain rules apply at 70% strength.
- If \( P(\text{Forest}) = 0.2 \), Forest rules apply at 20% strength.

This makes the explorer behave “intelligently uncertain.”

---

5. Expedition programming (pre‑run doctrine)

The pre‑run UI is where the player configures the expedition’s doctrine. It must be fast, concise, and expressive—no giant forms, no scripting.

5.1 Route intent (primary mission)

The player chooses one primary intent:

- Reach Objective
  - Minimize days and risk.
  - Prioritize direct paths.
- Survey Region
  - Maximize fog clearing.
  - Prioritize hills/mountains and high‑vision tiles.
- Artifact Hunt
  - Prioritize ruins, caves, relic nodes.
- Resource Forage
  - Prioritize forests and safe food sources.
- Scientific Study
  - Prioritize tribes, portals, research events.

Route intent heavily influences:

- Tile desirability.
- Event desirability.
- Risk tolerance.
- Belief weighting.
- Proximity rule strength.

5.2 Manual waypoints (known‑map routing)

Before autonomous behavior, the player can:

- Place sequential waypoints on revealed tiles.
- Remove or reorder them.

> “The absolute second the explorer reaches the final player-placed waypoint at the edge of the fog, manual control ends and the Proximity Matrix rules take over.”   

Waypoints define a deterministic spine through known territory; beyond that, the black box takes over.

5.3 Terrain behavior profile (proximity matrix)

The proximity matrix defines how the explorer “feels” about each terrain type:

- Hug – strongly prefers being on/inside that terrain.
- Skirt – prefers borders; traces edges.
- Avoid – repulsed; penalizes paths through it.
- Ignore – neutral; uses base costs only.

To keep the UI concise, players can choose from presets or define a custom profile.

Presets

- Cautious Pathing
  - Avoid mountains/swamps.
  - Skirt forests.
  - Hug plains/coasts.
- Aggressive Surveyor
  - Hug hills/mountains.
  - Skirt forests/swamps.
  - Ignore plains.
- Opportunistic Forager
  - Hug forests (food).
  - Avoid swamps.
  - Skirt mountains.

Custom profile

For each terrain type:

- Set Hug/Skirt/Avoid/Ignore.

Internally, this feeds into weight modifiers similar to:

> “If rule == .Avoid -> Weight  3.0 (Heavy Repulsion)… If rule == .Hug -> Weight  0.5 if on/inside terrain type (Deep dive).”   

5.4 Risk protocols

Risk protocols define how the explorer behaves under danger and opportunity.

Risk appetite

- Low Risk
  - Avoids uncertain tiles.
  - Prefers high‑confidence belief.
- Moderate Risk
  - Accepts some uncertainty.
- High Risk
  - Will traverse low‑confidence tiles for speed or reward.

Event priority

- Ignore Minor Events
  - Only major nodes (e.g., portals) considered.
- Investigate Selectively
  - Investigate events within detour thresholds.
- Investigate Everything
  - Aggressively pursue events.

Emergency protocol

> “Safe-Return Switch… Burn the Boats… Cut Losses & Retreat… Last Stand (Cartography Push)… Science Salvage.”   

The player chooses one:

- Safe Return
  - Automatically retreat when rations equal exact cost to return.
- Burn the Boats
  - Ignore safe return; push until success or failure.
- Cut Losses
  - Emergency evacuation; partial funding refund.
- Last Stand
  - Ignore objective; maximize fog clearing before death.
- Science Salvage
  - Halt movement; maximize research/intel before death.

5.5 Dynamic behavior triggers & thresholds

These are policies that authorize the explorer to make autonomous mid‑run decisions. Each has optional thresholds.

Impasse handling

- Strict Detour
  - Always go around obstacles.
- Smart Reveal
  - If detour cost > threshold (e.g., 8–20 days), climb one hill/mountain to reveal fog and find a better route.
- Aggressive Breakthrough
  - Immediately climb nearby high‑vision tiles when blocked.

Thresholds:

- Max detour days.
- Max number of reveal attempts.

Ration emergency

- Stay the Course
  - Ignore ration danger until near death.
- Forage Opportunistically
  - If rations < threshold (e.g., 4–10 days), prioritize nearby forests.
- Full Forage Mode
  - Aggressively divert into forests when rations low.

Thresholds:

- Ration danger level.
- Max detour distance for foraging.

Reveal mode

- Never Reveal
  - No intentional climbs for visibility.
- Reveal When Blocked
  - Only reveal when path is impassable.
- Reveal Regularly
  - Reveal at intervals or when uncertainty exceeds threshold.

Thresholds:

- Reveal interval (days).
- Uncertainty threshold (%).

Belief confidence

- High Confidence Only
  - Avoid tiles with low belief confidence.
- Moderate Confidence
  - Accept moderate uncertainty.
- Low Confidence Allowed
  - Will traverse highly uncertain tiles.

Thresholds:

- Minimum confidence.
- Max consecutive low‑confidence tiles.

5.6 Party composition (professions)

The player selects 2–3 professions:

- Navigator  
- Geologist  
- Ecologist  
- Anthropologist  
- Surveyor  
- Quartermaster  
- Linguist  

Each profession:

- Modifies belief map accuracy.
- Adjusts dynamic behavior thresholds.
- Influences event outcomes.
- Alters resource efficiency.

5.7 Gear loadout

Limited slots (e.g., 2–3):

- Climbing Rope – unlocks mountains.
- Survey Lens – boosts belief accuracy.
- Machete – reduces forest movement cost.
- Seismic Rod – improves mountain continuity detection.
- Food Cache – extra rations.
- Radio Beacon – extra mid‑run intervention.
- Portal Stabilizer – reduces portal research time.

Gear interacts with terrain, belief, and events.

5.8 Funding allocation

The player allocates expedition budget:

- Rations.
- Gear purchases.
- Radio signals.
- Profession hiring.

Investor upgrades can raise baseline minimum funding, preventing financial game‑over.

---

6. Run execution & events

6.1 Fast simulation

Runs should resolve in a few seconds:

- Internally, the game computes the full path and event sequence.
- Day‑by‑day logs are generated from this simulation.
- The player watches a quick playback or jumps straight to analysis.

6.2 Radio signals (mid‑run intervention)

> “At any moment, the player can press the Transmit button to pause the simulation… alter the manual waypoint path or swap proximity rules before resuming.”   

Radio signals allow limited mid‑run adjustments:

- Pause.
- Adjust waypoints.
- Swap terrain profile preset.
- Change risk appetite.

They do not allow direct tile‑by‑tile control.

6.3 Narrative encounter nodes

Events pause the simulation for decisions:

- Broken Radio Tower
  - Invest days to reveal a large region near the final objective.
- Ancient Portals
  - Spend days to teleport to a random coordinate—high risk, high reward.
- Tribal Encounters
  - Friendly: hidden trails, reduced movement costs.
  - Hostile: ambushes, traps, forced celebrations.
  - Linguistic skill reveals or obscures danger.

Belief and professions influence:

- Whether the explorer approaches or avoids events.
- How likely they are to detect danger (e.g., ominous totems, mistranslated phrases).

---

7. Expedition log & analysis

This is where the game’s depth really lands.

7.1 Purpose

The expedition log is a forensic replay of the run. It lets the player:

- Scrub through each day.
- See what the explorer saw.
- See what the explorer believed.
- Understand why decisions were made.
- Refine doctrine and templates based on evidence.

7.2 Log structure

The log viewer has three main panels:

Left: Timeline & summary

- Day timeline (Day 1 → Day N).
- Event markers (ruins, tribes, portals, impasses).
- Ration graph.
- Distance traveled.
- Outcome summary.

Center: Map view

For the selected day:

- Explorer position.
- Revealed tiles as of that day.
- Fog tiles.
- Belief overlay (optional toggle).
- Path taken so far.

Right: Thought process & breakdown

For the selected day and tile:

- Tile probability breakdown.
- Factors influencing belief.
- Dynamic behavior triggers fired.
- Proximity rules applied.
- Risk protocols active.
- Thresholds crossed.

7.3 Day selection

The player can:

- Click any day on the timeline.
- Jump to event days.
- Step forward/backward day‑by‑day.

For each day, the map and belief state reflect exactly what the explorer knew at that time.

7.4 Belief overlay

Fog tiles show:

- Top terrain probabilities (e.g., Desert 62%, Plains 20%, Hills 10%, Forest 8%).
- Confidence shading (color intensity or opacity).
- Optional filter to show only tiles above/below certain confidence.

7.5 Tile probability breakdown

Clicking a fog tile opens a detailed breakdown:

- Local factors
  - Adjacent revealed tiles.
  - Immediate neighborhood composition.
- Regional factors
  - Revealed tiles within radius \( R \).
  - Distance‑weighted contributions.
- Shape factors
  - Cluster membership (desert blob, mountain band, forest patch).
  - Continuation zone inference.
- Directional factors
  - Alignment with known terrain trends.
- Profession modifiers
  - Navigator, Geologist, Ecologist, etc.
- Final probability
  - Table showing contributions and final percentages.

Example:

| Terrain | Contribution Source                    | Weight | Final % |
|--------|-----------------------------------------|--------|---------|
| Desert | Local + Regional + Shape + Direction    | 0.52   | 62%     |
| Plains | Local only                              | 0.17   | 20%     |
| Hills  | Directional                             | 0.08   | 10%     |
| Forest | Weak regional                           | 0.06   | 8%      |

This makes the expedition AI’s “thinking” legible without exposing raw math.

7.6 Decision trace

For each day, the log can highlight:

- Path choice
  - Why the explorer chose tile A over tile B.
  - Expected cost comparison.
  - Belief confidence differences.
- Trigger activations
  - Impasse handling fired.
  - Ration emergency triggered.
  - Reveal mode activated.
- Event decisions
  - Why a ruin was investigated or skipped.
  - Why a portal was used or ignored.
  - Why a tribe was approached or avoided.

This turns failures into learning opportunities: the player can see that the explorer took a calculated risk, misjudged a belief, or followed a doctrine that now seems too conservative or too aggressive.

7.7 Template refinement

From the log screen, the player can:

- Clone the current expedition’s configuration into a new template.
- Adjust thresholds and profiles based on observed behavior.
- Save the refined doctrine for future runs.

This closes the loop:

> Plan → Launch → Observe → Understand → Refine → Relaunch

---

8. Meta‑progression & headquarters

8.1 Departments

> “The Corporate Tycoons (Funding)… The Scholar’s Guild (Linguistics & Crafting)… The Cartography Board (Map Ledger).”   

1. Corporate Tycoons
   - Convert artifacts into cash.
   - Unlock higher baseline funding.
   - Offer investor goals (e.g., reveal X tiles, reach Y latitude).

2. Scholar’s Guild
   - Spend cultural intel to:
     - Improve language skills.
     - Unlock better gear blueprints.
     - Reduce portal research times.
     - Reveal double meanings in tribal dialogue.

3. Cartography Board
   - Maintains the persistent world ledger.
   - All cleared fog remains cleared across runs.
   - Provides tools to:
     - Draw waypoints on known terrain.
     - Visualize belief overlays.
     - Compare runs and logs.

8.2 Templates & doctrine library

Players can maintain a library of expedition templates:

- Recon templates.
- Objective‑rush templates.
- Artifact‑hunt templates.
- Forage‑heavy survival templates.
- Science‑focused templates.

Each template stores:

- Route intent.
- Terrain profile.
- Risk protocols.
- Dynamic triggers.
- Thresholds.
- Party composition.
- Gear.
- Funding allocation.
- Belief usage level.

Templates can be:

- Saved.
- Loaded.
- Cloned.
- Renamed.
- Deleted.

---

9. Implementation notes (high level)

9.1 Data structures

The Odin‑style structures from the prototype remain relevant:

> “TerrainType :: enum… ProximityRule :: enum… BehaviorProfile :: struct… Explorer :: struct…”   

Key additions:

- BeliefTile
  - Probabilities per terrain type.
  - Confidence score.
  - References to contributing clusters.

- Cluster
  - Terrain type.
  - Member tiles.
  - Direction vector.
  - Bounding shape.

- ExpeditionConfig
  - Route intent.
  - Terrain profile.
  - Risk protocols.
  - Dynamic triggers.
  - Thresholds.
  - Party & gear.
  - Funding.

- ExpeditionLogEntry
  - Day index.
  - Explorer position.
  - Revealed map snapshot.
  - Belief snapshot.
  - Decisions taken.
  - Triggers fired.

9.2 Performance

- Pre‑generate full world at game start.
- Maintain belief map incrementally.
- Precompute paths and logs per run.
- Use efficient neighbor and cluster queries.

---

10. Closing note

Project Wayfinder lives in the tension between control and opacity. The player is always trying to penetrate the black box of the expedition AI—nudging it with doctrine, thresholds, and templates—while accepting that they will never fully control it.

The belief map and expedition log are the two pillars that make this tension satisfying:

- The belief map shows what the explorer thinks the world is.
- The expedition log shows how those beliefs turned into actions.

Together, they make every run feel like a meaningful experiment in exploration, inference, and trust.