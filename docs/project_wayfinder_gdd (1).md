# Project Wayfinder — Game Design Document

## 1. Concept Overview

**Working title:** Project Wayfinder
**Genre:** Automation Roguelike / Cartographic Exploration Strategy
**Core fantasy:** You are the Chief Cartographer and Quartermaster of a prestigious Exploration Society. You don't control the explorer directly — you design their doctrine, configure their instincts, and then launch them into a fog-shrouded world, trying to understand and influence a semi-autonomous "expedition AI" that always remains partly a black box.

The player's power is in planning, inference, and analysis, not in moment-to-moment movement. Runs are fast — seconds long — but dense with information, logs, and emergent behavior.

The player's power comes from:
- interpreting the revealed map
- tuning the belief map
- baking intuition into inference rules
- marking preferences and depreferences
- drawing guidance lines and fallback routes
- configuring dynamic behavior triggers
- analyzing expedition logs
- refining templates

The explorer is a black box. The player is trying to penetrate it.

---

## 2. Core Loop

Each run follows a tight, four-phase loop.

### Phase 1 — Map Room (Review & Study)
The player reviews:
- the persistent global hex map
- revealed terrain, events, and prior expedition logs
- belief overlays — what the expedition AI "thinks" the world looks like
- patterns in terrain, events, and dangers

This is where the player forms hypotheses about the world.

### Phase 2 — Prep Phase (Expedition Programming / Doctrine Setup)
The player configures:
- route intent (primary goal)
- terrain behavior profile (proximity matrix)
- risk protocols and dynamic behavior triggers
- thresholds for key behaviors
- party composition (professions)
- gear loadout
- funding allocation (rations, gear, radio signals)
- belief-map tuning (priors, biases, pattern rules)
- map-based preferences/depreferences
- guidance lines + branching fallback routes

This is the "programming" phase.

### Phase 3 — Simulation (Automated Run)
The explorer:
- follows manual waypoints through known tiles, then switches to autonomous mode
- uses the belief map + doctrine to choose paths
- triggers dynamic behaviors
- encounters events, consumes rations, reveals tiles
- logs decisions

Runs resolve in seconds. Internally the game computes the full path and event sequence; the player watches a quick playback or jumps straight to analysis.

### Phase 4 — Investor Pitch & Analysis (Expedition Log / Forensic Replay)
The player:
- converts artifacts and intel into funding and permanent upgrades
- scrubs day-by-day through the expedition log
- sees what the explorer saw and believed at each day
- sees tile probability breakdowns and why decisions were made
- refines templates and doctrine for future runs

> "All map data cleared during a run remains permanently cleared on the world globe across subsequent expeditions."

---

## 3. World & Terrain

### 3.1 Global Hex Globe
The world is a procedurally generated global hex grid, rendered as a rotatable globe with smooth zoom from tactical tile view to planetary scale. Macro-biomes resemble a Civilization V–style world: grasslands, forests, deserts, swamps, hills, mountains, coasts, and oceans.

### 3.2 Baseline Terrain Cost Matrix
Each tile has a base day cost (movement cost) and a vision radius. Standing on a tile consumes rations equal to its day cost to exit.

> "Every tile on the hex grid possesses a fundamental movement cost represented as Days. If an explorer stands on a tile, they consume an equivalent number of rations to exit it."

| Terrain Type | Base Day Cost | Vision Radius | Special Traits |
|---|---|---|---|
| Grassland / Plains | 1 Day | 1 Hex | Baseline pathing. |
| Forest / Jungle | 2 Days | 1 Hex | Dense cover; hides blueprints/relics. |
| Swamp / Marsh | 3 Days | 1 Hex | Heavy navigation penalty. |
| Hill | 2 Days | 2 Hexes | Elevated; minor radar visibility. |
| Mountain | Impassable* | 3 Hexes | Requires climbing gear; massive fog clearing. |
| Coastal / Shore | 1 Day | 1 Hex | Land–water boundary. |
| Ocean / Deep Sea | Impassable* | 1 Hex | Requires naval tech to cross. |

\*Impassable unless specific gear/tech is equipped.

Terrain types also influence event distribution (tribes near forests, portals near mountains, ruins in deserts, etc.), feeding into the belief system.

---

## 4. The Belief Map System (Core Pillar)

This is the heart of Project Wayfinder.

### 4.1 Purpose
The belief map is the expedition AI's probabilistic understanding of fogged tiles. It does **not** generate terrain — the full world is generated at game start. Instead, the belief map estimates, for each fogged tile:
- the probability of each terrain type
- the confidence level of that estimate
- the inferred shape of larger structures (desert basins, mountain ranges, forest blobs, etc.)

Pathfinding uses expected costs derived from these probabilities, allowing the explorer to act intelligently in unknown territory.

### 4.2 Dual Maps: Revealed vs. Belief
The game maintains two parallel representations:

- **Revealed Map** — tiles the player and explorer have actually seen; exact terrain, events, and costs; persistent across runs.
- **Belief Map** — for each fogged tile: P(Grassland), P(Forest), P(Swamp), … plus a confidence score (0–100%). Updated whenever new tiles are revealed. Informed by local neighbors, regional patterns, shape continuity, directional trends, and profession bonuses.

### 4.3 Local Neighborhood Inference
Fogged tiles infer terrain from adjacent revealed tiles — adjacent to mountains raises P(Mountain), adjacent to forests raises P(Forest), and so on.

\[
P_{\text{local}}(t) = f(\text{adjacent revealed tiles})
\]

### 4.4 Regional Influence
Beyond immediate neighbors, the belief map considers all revealed tiles within a radius R, weighted by distance (e.g., inverse square or exponential decay):

\[
P_{\text{regional}}(t) = \sum_{i \in \text{revealed within } R} w(d_i) \cdot \mathbf{1}(\text{terrain}_i = t)
\]

This captures regional density: deserts cluster, forests patch, mountains band.

### 4.5 Shape Continuity (Blobs, Bands, Basins)
Terrain types have characteristic shapes — deserts as amorphous blobs, forests as clustered patches, mountains as ridges/arcs, swamps as lowland basins, hills scattered near mountains. The system detects these via:

1. **Connected components / flood-fill** — group contiguous tiles of the same terrain.
2. **Bounding shapes** — compute convex hulls, bounding boxes, or approximate "blobs."
3. **Continuation zones** — infer where the shape likely extends beyond revealed edges.

Fogged tiles inside inferred zones get boosted probabilities:

\[
P_{\text{shape}}(t) = g(\text{cluster membership, terrain type})
\]

### 4.6 Directional Alignment
The system tracks directional trends — mountain ranges running north–south, desert belts running east–west, forest bands following river valleys. When multiple clusters share a direction vector, fogged tiles along that vector between them get boosted matching probability. This matters most for mountain ranges: two parallel, separated revealed mountain lines suggest the tiles between them share the range.

### 4.7 Profession Modifiers
Professions directly enhance belief accuracy:

- **Navigator** — improves coast/ocean predictions; extends inference radius for shoreline continuity.
- **Geologist** — improves mountain/hill band detection; increases confidence in ridge-line continuity.
- **Ecologist** — enhances forest/swamp blob detection; better prediction of dense vegetation zones.
- **Anthropologist** — improves tribal region inference; predicts likely village locations and hostility.
- **Surveyor** — increases fog-clearing efficiency; slightly boosts belief confidence globally.
- **Linguist** — improves event interpretation, not terrain — affects how belief interacts with narrative nodes.

Professions modify weights by increasing R, adjusting w(d), boosting P(shape) for specific terrain types, or raising confidence thresholds.

### 4.8 Combined Belief Model
For each fogged tile and terrain type t:

\[
P(t) = \alpha P_{\text{local}}(t) + \beta P_{\text{regional}}(t) + \gamma P_{\text{shape}}(t) + \delta P_{\text{direction}}(t)
\]

Where α, β, γ, δ are weights influenced by route intent, terrain behavior profile, professions, and upgrades. Probabilities are normalized to sum to 1 across all terrain types.

### 4.9 Expected Cost for Pathfinding
\[
\text{ExpectedCost} = \sum_{t} P(t) \cdot \text{BaseCost}(t)
\]

Proximity rules (Hug/Skirt/Avoid) apply to expected terrain, weighted by confidence — e.g. if P(Mountain) = 0.7, Mountain rules apply at 70% strength. This makes the explorer behave "intelligently uncertain."

### 4.10 Player-Driven Belief Tuning (Advanced Mode)
Players can modify the belief map **before a run**, based on what they've learned from previous expeditions.

**Global Priors (world-level intuition)** — e.g. "this world seems desert-heavy," adjusted via sliders or percentage nudges:

\[
P'(t) = \text{Normalize}(P(t) \cdot (1 + \text{GlobalBias}_t))
\]

**Regional Priors (area-level intuition)** — painted with a brush tool, e.g. "this area feels swampy":

\[
P'(t) = \text{Normalize}(P(t) \cdot (1 + \text{RegionalBias}_t))
\]

**Pattern Rules (learned relationships)** — simple toggleable rules with a strength slider, e.g. "Valleys → Swamps," "Coasts → Villages," "River edges → Forests," "Mountain foothills → Tribes," "Desert edges → Ruins":

\[
P'(t) = \text{Normalize}(P(t) \cdot (1 + \text{PatternRuleStrength}))
\]

**Confidence Thresholds** — players set minimum confidence for system inference, maximum uncertainty allowed, and when player priors override system inference (e.g. "apply my priors only when confidence < 60%").

**System vs. Player Weighting** — players set System Weight (α) and Player Weight (β):

\[
P_{\text{final}}(t) = \text{Normalize}(\alpha P_{\text{system}}(t) + \beta P_{\text{player}}(t))
\]

This is the heart of advanced belief tuning.

### 4.11 Map-Based Player Controls
Three map tools the player can use before a run:

**Tile Preferences (soft attraction zones)** — mark tiles/regions as preferred (e.g. "this valley looks promising"):
\[
\text{TileWeight} \times= (1 - \text{PreferenceStrength})
\]

**Tile Depreferences (soft repulsion zones)** — mark tiles/regions to avoid (e.g. "last run encountered danger here"):
\[
\text{TileWeight} \times= (1 + \text{DepreferenceStrength})
\]

**Guidance Lines (soft path suggestions)** — draw lines the explorer tries to follow if doctrine allows:
\[
\text{TileWeight} \times= (1 - \text{LineAffinity})
\]

**Branching Fallback Routes** — draw a primary, secondary, and tertiary line. The explorer switches lines when detour, danger, or confidence thresholds are crossed, or impassable terrain is encountered. This creates a decision graph drawn directly on the map.

---

## 5. Expedition Programming (Pre-Run Doctrine)

The pre-run UI is where the player configures the expedition's doctrine. It must be fast, concise, and expressive — no giant forms, no scripting.

### 5.1 Route Intent (Primary Mission)
One primary intent, heavily influencing tile/event desirability, risk tolerance, belief weighting, and proximity rule strength:

- **Reach Objective** — minimize days and risk; prioritize direct paths.
- **Survey Region** — maximize fog clearing; prioritize hills/mountains and high-vision tiles.
- **Artifact Hunt** — prioritize ruins, caves, relic nodes.
- **Resource Forage** — prioritize forests and safe food sources.
- **Scientific Study** — prioritize tribes, portals, research events.
- **Survey Site** *(new — see §8)* — prioritize discovering and marking outpost-viable locations.

### 5.2 Manual Waypoints (Known-Map Routing)
Before autonomous behavior, the player places sequential waypoints on revealed tiles.

> "The absolute second the explorer reaches the final player-placed waypoint at the edge of the fog, manual control ends and the Proximity Matrix rules take over."

Waypoints define a deterministic spine through known territory; beyond that, the black box takes over.

### 5.3 Terrain Behavior Profile (Proximity Matrix)
Defines how the explorer "feels" about each terrain type:

- **Hug** — strongly prefers being on/inside that terrain.
- **Skirt** — prefers borders; traces edges.
- **Avoid** — repulsed; penalizes paths through it.
- **Ignore** — neutral; uses base costs only.

**Presets:**
- *Cautious Pathing* — avoid mountains/swamps, skirt forests, hug plains/coasts.
- *Aggressive Surveyor* — hug hills/mountains, skirt forests/swamps, ignore plains.
- *Opportunistic Forager* — hug forests (food), avoid swamps, skirt mountains.

**Custom profile:** set Hug/Skirt/Avoid/Ignore per terrain type. Internally this feeds weight modifiers similar to:

> "If rule == .Avoid → Weight × 3.0 (Heavy Repulsion)… If rule == .Hug → Weight × 0.5 if on/inside terrain type (Deep dive)."

### 5.4 Risk Protocols

**Risk appetite:** Low Risk (avoids uncertain tiles, prefers high-confidence belief) / Moderate Risk (accepts some uncertainty) / High Risk (traverses low-confidence tiles for speed or reward).

**Event priority:** Ignore Minor Events / Investigate Selectively (within detour thresholds) / Investigate Everything.

**Emergency protocol** — one of:
> "Safe-Return Switch… Burn the Boats… Cut Losses & Retreat… Last Stand (Cartography Push)… Science Salvage."

- *Safe Return* — automatically retreat when rations equal exact cost to return.
- *Burn the Boats* — ignore safe return; push until success or failure.
- *Cut Losses* — emergency evacuation; partial funding refund.
- *Last Stand* — ignore objective; maximize fog clearing before death.
- *Science Salvage* — halt movement; maximize research/intel before death.

### 5.5 Dynamic Behavior Triggers & Thresholds
Policies authorizing the explorer to make autonomous mid-run decisions.

**Impasse handling:** Strict Detour / Smart Reveal (climb one hill/mountain if detour cost exceeds threshold) / Aggressive Breakthrough (immediately climb nearby high-vision tiles when blocked). Thresholds: max detour days, max reveal attempts.

**Ration emergency:** Stay the Course / Forage Opportunistically (if rations below threshold) / Full Forage Mode. Thresholds: ration danger level, max detour distance for foraging.

**Reveal mode:** Never Reveal / Reveal When Blocked / Reveal Regularly (at intervals or when uncertainty exceeds threshold). Thresholds: reveal interval, uncertainty threshold.

**Belief confidence:** High Confidence Only / Moderate Confidence / Low Confidence Allowed. Thresholds: minimum confidence, max consecutive low-confidence tiles.

### 5.6 Party Composition (Professions)
Player selects 2–3: Navigator, Geologist, Ecologist, Anthropologist, Surveyor, Quartermaster, Linguist. Each modifies belief map accuracy, adjusts dynamic behavior thresholds, influences event outcomes, and alters resource efficiency.

### 5.7 Gear Loadout
Limited slots (2–3): Climbing Rope (unlocks mountains), Survey Lens (boosts belief accuracy), Machete (reduces forest movement cost), Seismic Rod (improves mountain continuity detection), Food Cache (extra rations), Radio Beacon (extra mid-run intervention), Portal Stabilizer (reduces portal research time).

### 5.8 Funding Allocation
Player allocates budget across rations, gear purchases, radio signals, and profession hiring. Investor upgrades can raise baseline minimum funding, preventing financial game-over.

---

## 6. Run Execution & Events

### 6.1 Fast Simulation
Runs resolve in a few seconds. Internally the game computes the full path and event sequence; day-by-day logs are generated from this simulation; the player watches a quick playback or jumps straight to analysis.

### 6.2 Radio Signals (Mid-Run Intervention)
> "At any moment, the player can press the Transmit button to pause the simulation… alter the manual waypoint path or swap proximity rules before resuming."

Radio signals allow pausing, adjusting waypoints, swapping terrain profile preset, and changing risk appetite — but not direct tile-by-tile control.

### 6.3 Narrative Encounter Nodes
Events pause the simulation for decisions:
- **Broken Radio Tower** — invest days to reveal a large region near the final objective.
- **Ancient Portals** — spend days to teleport to a random coordinate; high risk, high reward.
- **Tribal Encounters** — friendly (hidden trails, reduced movement costs) or hostile (ambushes, traps, forced celebrations); linguistic skill reveals or obscures danger.

Belief and professions influence whether the explorer approaches or avoids events, and how likely they are to detect danger.

---

## 7. Expedition Log & Analysis

This is where the game's depth really lands — a forensic replay of the run.

### 7.1 Log Structure — Three Panels

**Left: Timeline & summary** — day timeline (Day 1 → N), event markers (ruins, tribes, portals, impasses), ration graph, distance traveled, outcome summary.

**Center: Map view** — for the selected day: explorer position, revealed tiles as of that day, fog tiles, belief overlay (toggleable), path taken so far.

**Right: Thought process & breakdown** — for the selected day/tile: tile probability breakdown, factors influencing belief, dynamic triggers fired, proximity rules applied, risk protocols active, thresholds crossed.

### 7.2 Day Selection
Click any day on the timeline, jump to event days, or step forward/backward day-by-day. For each day, the map and belief state reflect exactly what the explorer knew at that time.

### 7.3 Belief Overlay
Fog tiles show top terrain probabilities (e.g., Desert 62%, Plains 20%, Hills 10%, Forest 8%), confidence shading, and an optional filter for above/below-threshold tiles.

### 7.4 Tile Probability Breakdown
Clicking a fog tile opens a detailed breakdown across local factors, regional factors, shape factors, directional factors, and profession modifiers, ending in a final probability table:

| Terrain | Contribution Source | Weight | Final % |
|---|---|---|---|
| Desert | Local + Regional + Shape + Direction | 0.52 | 62% |
| Plains | Local only | 0.17 | 20% |
| Hills | Directional | 0.08 | 10% |
| Forest | Weak regional | 0.06 | 8% |

This makes the expedition AI's "thinking" legible without exposing raw math.

### 7.5 Decision Trace
For each day, the log highlights path choice (why tile A over tile B, expected cost comparison, belief confidence differences), trigger activations (impasse handling, ration emergency, reveal mode), and event decisions (why a ruin/portal/tribe was engaged or skipped). Failures become learning opportunities: the player can see whether the explorer took a calculated risk, misjudged a belief, or followed doctrine that now seems too conservative or too aggressive.

### 7.6 Template Refinement
From the log screen, the player can clone the current expedition's configuration into a new template, adjust thresholds and profiles based on observed behavior, and save the refined doctrine. This closes the loop:

> Plan → Launch → Observe → Understand → Refine → Relaunch

---

## 8. Outposts & Base Expansion *(new)*

After an expedition finishes, while reviewing the map, the player can select a revealed site and invest significant resources to request an outpost be built there.

### 8.1 Site Viability
A site's fitness is a function of nearby tile composition within some radius — for example:
- hills/mountains nearby (defense)
- open plains nearby (visibility against threats)
- a water source within radius (sustainability)

This reuses the same weighted regional-influence machinery already built for belief inference (§4.4/4.9) — site fitness is a scoring function over the same "nearby tiles within radius R" data rather than a new system. Additional factors (proximity to resources, distance from hostile territory, distance from other outposts) can be added to the same weighted-sum formula without new infrastructure.

### 8.2 "Survey Site" Route Intent
A new route intent (§5.1) that biases the explorer toward covering ground broadly and evaluating candidate sites rather than rushing a single objective — the explorer marks tiles/regions on the map that meet outpost viability thresholds for the player to review afterward, similar in spirit to how belief overlays are presented.

### 8.3 Outpost Function
Once built, an outpost becomes an alternate launch point and return point:
- future expeditions can start from an outpost instead of the default home base
- expeditions can end/return at an outpost instead of the home base

This directly rewards good surveying: a well-placed outpost shrinks the effective travel time to the frontier, meaning less of every subsequent expedition's ration budget is spent re-crossing already-known territory. Outposts become a second axis of meta-progression alongside the headquarters departments (§10) — more a strategic-geography choice than a stat upgrade.

*Open design questions to resolve later: can outposts be lost/destroyed (raising the stakes of site selection), do they need upkeep/funding to remain staffed, and do they extend the persistent revealed-map radius passively over time?*

---

## 9. Night Transmission & Lost Party Recovery *(new)*

Every night, at the end of the day, the expedition transmits its logs back to headquarters — by pigeon, radio, or similar in-fiction method. Critically, this only happens once per day, at night.

### 9.1 Consequence of Nightly-Only Transmission
If an expedition perishes during a day before that night's transmission, that final day's log is never received — the player loses visibility into exactly how and why the expedition died. This creates a genuine, earned mystery rather than a generic game-over: the log is complete right up until the point where the black box's opacity actually matters most.

### 9.2 Recovering a Lost Party
A subsequent expedition can be directed to search for a lost party's remains, recovering:
- the missing final log entry (or entries)
- any artifacts or intel the lost party was carrying

This gives the forensic-log pillar (§7) a second act: instead of just analyzing your *own* past decisions, you can be sent to reconstruct someone else's. It's also a natural reuse of the belief map's local-inference machinery — the lost party's last known position and heading become a strong local prior for where to search, so "find the lost party" is pathfinding-and-belief work the game already does, pointed at a different target.

### 9.3 Design Note: Time Pressure
Consider letting the recoverable log/artifacts degrade the longer a search is delayed — scavenging wildlife, weather, or hostile tribes could partially or fully destroy what's recoverable. This turns "go rescue the log now" vs. "finish my current expedition's objective first" into a real trade-off, rather than a recovery mission the player can indefinitely postpone with no cost.

---

## 10. Meta-Progression & Headquarters

### 10.1 Departments
> "The Corporate Tycoons (Funding)… The Scholar's Guild (Linguistics & Crafting)… The Cartography Board (Map Ledger)."

1. **Corporate Tycoons** — convert artifacts into cash; unlock higher baseline funding; offer investor goals (e.g., reveal X tiles, reach Y latitude).
2. **Scholar's Guild** — spend cultural intel to improve language skills, unlock better gear blueprints, reduce portal research times, reveal double meanings in tribal dialogue.
3. **Cartography Board** — maintains the persistent world ledger; all cleared fog remains cleared across runs; provides tools to draw waypoints on known terrain, visualize belief overlays, and compare runs and logs. *(Outposts, §8, are a natural extension of this department's scope.)*

### 10.2 Templates & Doctrine Library
Players maintain a library of expedition templates — Recon, Objective-Rush, Artifact-Hunt, Forage-Heavy Survival, Science-Focused, and (with §8) Site-Survey templates. Each stores route intent, terrain profile, risk protocols, dynamic triggers, thresholds, party composition, gear, funding allocation, and belief usage level. Templates can be saved, loaded, cloned, renamed, and deleted.

---

## 11. Implementation Notes (High Level)

### 11.1 Data Structures
The Odin-style structures from the prototype remain relevant:

> "TerrainType :: enum… ProximityRule :: enum… BehaviorProfile :: struct… Explorer :: struct…"

Key additions:

- **BeliefTile** — probabilities per terrain type, confidence score, references to contributing clusters.
- **Cluster** — terrain type, member tiles, direction vector, bounding shape.
- **ExpeditionConfig** — route intent, terrain profile, risk protocols, dynamic triggers, thresholds, party & gear, funding.
- **ExpeditionLogEntry** — day index, explorer position, revealed map snapshot, belief snapshot, decisions taken, triggers fired.
- **Outpost** *(new)* — location, site-fitness score, staffing/upkeep state, launch/return eligibility.
- **LostPartyRecord** *(new)* — last known position, last known heading, day of last transmission, recoverable artifact/log payload, decay state.

### 11.2 Performance
- Pre-generate the full world at game start.
- Maintain the belief map incrementally as tiles are revealed, rather than recomputing from scratch.
- Precompute paths and logs per run (the simulation is deterministic once doctrine + world are fixed).
- Use efficient neighbor and cluster queries — this is the part most worth profiling early, since shape-continuity clustering (§4.5) is the most expensive belief computation.

### 11.3 Suggested Build Order
Given the scope of this document, a recommended sequence for actually reaching a playable core loop:

1. Revealed map + local-neighbor belief only (§4.3), no shape/direction inference yet.
2. Proximity matrix presets (§5.3) driving expected-cost pathing.
3. Single route intent, single risk protocol, no professions/gear/funding.
4. A plain-text expedition log (a list of "Day N: chose tile X over Y because Z") before building the full three-panel scrubbing UI (§7.1).
5. Once the stripped-down loop is confirmed fun, layer in: regional priors, shape continuity, directional alignment, professions, gear, outposts, lost-party recovery, and the full doctrine/belief-tuning UI.

---

## 12. Rarity & Discovery Systems *(new)*

### 12.1 Design Intent
Project Wayfinder's core loop is analytical rather than combat-driven, so its "big win" dopamine has to come from *discovery*, not loot in the action-RPG sense. The goal is the same feeling — the small, unpredictable chance of something extraordinary — delivered through systems the game already has: artifacts, the belief map, and above all, the hex tile itself. Every rarity system below should be legible through UI the player already trusts (probability breakdowns, the expedition log, the regional belief brush) rather than requiring new interface.

### 12.2 Artifact & Gear Rarity Tiers
Artifacts recovered during a run (and the gear blueprints occasionally found alongside them) are assigned a rarity tier — Common / Uncommon / Rare / Legendary / Mythic. Tiers surface at the Investor Pitch phase (§7 wraps into the Phase 4 reveal): each artifact gets an individual reveal beat rather than being folded silently into a lump funding total, since the reveal moment is the reward as much as the artifact itself.

- **Common/Uncommon artifacts** — fund baseline funding and minor Scholar's Guild intel.
- **Rare artifacts** — meaningful funding spikes or a full gear blueprint (see below).
- **Legendary/Mythic gear blueprints** — not stat bumps, but doctrine-defining unlocks: e.g. a belief-tool upgrade that extends shape-continuity inference range, or a Radio Signal variant that grants an extra mid-run intervention. Rarity should track with *how much a find changes what future doctrine is possible*, not just its sale value — a purely cosmetic Mythic tier will not sustain the payoff feeling past the first few runs.
- The Expedition Log (§7.4) can retroactively surface how rare a given find was — e.g. "This tile had a 3% chance of yielding a Legendary relic," turning the forensic-replay pillar into an amplifier for discoveries the player already made.

### 12.3 Rare & Legendary Tiles — Natural Wonders
These are rare, but explainable within the world's internal logic — geography can plausibly still produce them, so they don't puncture the low-fantasy Victorian tone.

- **The Unmapped Basin** — a single tile of impossibly fertile land inside an otherwise hostile biome. Produces a small, ongoing ration/funding trickle on future expeditions that pass near it, or continuously once an outpost is built nearby — a payout that keeps giving rather than a one-time jackpot.
- **Fossil Bed / Bone Field** — a one-time, oversized Scholar's Guild intel dump. Thematically the world's memory, fitting the game's overall thesis of inferring the past to understand the present.
- **The Convergence Point** — a tile where multiple terrain-shape clusters (§4.5) mathematically "should" meet but don't. Standing on it grants a permanent, global belief-confidence boost for the remainder of the run (or into the next). A rare tile that reinforces the belief-map mechanic itself rather than acting as a simple treasure chest.

### 12.4 Rare & Legendary Tiles — True Anomalies
These break the belief model outright — the one thing the expedition AI's probabilistic machinery cannot see coming, which ties directly into the game's black-box theme. This category should carry the biggest "wow" moments, since it's expressed through the same belief-confidence numbers the player is staring at every run.

- **The Standing Silence** — a tile where belief-confidence for all neighboring fog tiles flatlines to zero the instant it's discovered; the tile detail panel shows blank fields where numbers normally populate. Reward candidates: a permanent new route intent, a new terrain-behavior preset, or an instant full-shape reveal of one biome.
- **The Fountain (working name)** — a supernatural hot spring/spa-style tile. Framed as: the day's log entry for that tile is contradictory or incomplete, and the effect discovered afterward doesn't fully add up on paper — e.g. a permanent day-cost reduction for a terrain type, ration decay removed for one profession, or a depleted gear item fully restored. The unexplained log entry preserves the grounded cartography aesthetic even though the effect itself is clearly impossible.
- **The Recursive Ruin** — investigating it spawns a second ruin event token elsewhere on the already-revealed map. A rare tile that generates a second rare event, at very low implementation cost since it reuses the existing ruin event type.
- **A Portal With Memory** — a rare Ancient Portal variant that teleports to a coordinate the belief map already had high confidence about but the explorer had never visited, instead of a fully random coordinate — either a strong confirmation of a standing prediction or a belief-shattering contradiction.
- **The Party's Echo** — an extremely rare tile containing remains/log fragments from an expedition the player never actually launched in this world-seed, implying an earlier, unrecorded Society presence. Reuses the existing `LostPartyRecord` structure (§11.1) with a seeded, non-player-run origin.

### 12.5 Seeding Guidance
To land the "stoked in your first few expeditions" feeling, at least one Natural Wonder and one True Anomaly tile should be curated to fall within realistic early-reveal radius on every world seed, rather than relying purely on long-tail random odds. Deeper, rarer variants of each category can still be governed by low-probability rolls for veteran players chasing the long tail.

---

## 13. Anomaly Zones (Stretch Goal) *(new)*

### 13.1 Concept
A later-development feature, inspired by *Outer Wilds*: rather than a single anomalous tile, a bounded *region* of the map behaves as though the normal rules of cartography, time, and record-keeping don't fully apply inside it. The player first notices this not through a warning or a monster, but by reviewing a completed expedition's log (§7) and finding entries that don't make sense — the same forensic-replay tool used every run, now used to detect something the tool itself wasn't designed to show.

### 13.2 Thematic Fit
The game's Victorian-era low-fantasy setting is built on an Enlightenment-era premise: the world is fully knowable given enough data, which is exactly what the belief map promises the player. An Anomaly Zone is the first crack in that premise — not "here be dragons," but a place where the Society's instruments, and the log format itself, stop being reliable. That reads as quiet unease rather than overt fantasy, keeping the tone intact even at its strangest.

### 13.3 Symptom Types
Each symptom is a controlled corruption of a log field the player already reads every run:

- **Glyph Days** — the plain-text decision trace (§7.5) renders in an invented glyph set for affected days instead of English. Frequency patterns across multiple expeditions allow attentive players to partially decode it over time.
- **Position Desync** — a day's logged position doesn't connect to the day before or after via any legal path, or two positions are logged for the same day.
- **The Long Day** — ration consumption for a single day is wildly disproportionate to distance traveled, with no trigger or protocol explaining why.
- **Doctrine Defiance** — the path chosen contradicts every active proximity rule and risk protocol, and the tile probability breakdown (§7.4) that normally always populates returns empty.
- **Retroactive Revision** — a tile already locked into the persistent world ledger (§2) reads as a different terrain type on a later expedition, violating the game's one stated absolute rule ("all cleared fog remains cleared").
- **Transmission Gaps** — the nightly log transmission (§9) is suppressed or scrambled mid-run even though the party survived, reusing the existing once-per-night mechanic for an eerier purpose than a party's death.

### 13.4 Boundary Mapping
Players triangulate a zone's extent across multiple expeditions approached from different headings and doctrines, using the *existing* regional belief-painting brush (§4.10/§4.11) repurposed to mark "anomalous" rather than "swampy." No new tool is required — only a new label for an existing one — and the activity is inherently a multi-run Plan → Launch → Observe → Refine loop, matching the game's stated closing thesis.

### 13.5 Suggested MVP Scope
Given this is a stretch goal, a minimal version needs very little new infrastructure:
1. Designate one region as an Anomaly Zone at world-gen, invisible until discovered.
2. Flag one or two log fields for corrupted rendering when the simulated path crosses it — Glyph Days and Doctrine Defiance are the cheapest starting points, since both are presentation-layer swaps on data the simulation already generates.
3. Let players mark suspected zone extent with the existing regional brush tool.
4. No mechanical payoff is required for an MVP — unexplained mystery, surfaced through a trusted tool suddenly behaving strangely, can carry engagement on its own before any reward is attached.

### 13.6 Long-Term Payoff Hook
Combined with the Party's Echo concept (§12.4), a fully decoded Anomaly Zone could eventually reveal that an earlier, pre-game Society expedition — one without access to the player's belief-map tooling — encountered something their era's science couldn't yet describe, and that expedition's bleed-through is what the player has been seeing. This keeps the payoff grounded in "science hasn't caught up yet" rather than overt magic, preserving the low-fantasy tone even at the feature's emotional climax.

---

## 14. Closing Note

Project Wayfinder lives in the tension between control and opacity. The player is always trying to penetrate the black box of the expedition AI — nudging it with doctrine, thresholds, and templates — while accepting that they will never fully control it.

The belief map and expedition log are the two pillars that make this tension satisfying:
- The belief map shows what the explorer thinks the world is.
- The expedition log shows how those beliefs turned into actions.

Outposts extend this into geography (where you choose to root yourself matters), and lost-party recovery extends it into stakes (what you fail to learn can still be recovered, at a cost). Rarity and discovery systems extend it into wonder (the map itself can still surprise you), and anomaly zones extend it into mystery (some things the Society's science cannot yet explain at all). Together, these systems make every run feel like a meaningful experiment in exploration, inference, and trust.
