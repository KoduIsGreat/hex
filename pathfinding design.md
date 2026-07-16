# Pathfinding Design

The player’s power comes from:

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

# **2. Core Loop**

### **Phase 1 — Map Room (Study & Analysis)**  
The player reviews:

- the persistent global hex map  
- revealed terrain  
- belief overlays  
- expedition logs from previous runs  
- patterns in terrain, events, and dangers  

This is where the player forms hypotheses about the world.

### **Phase 2 — Expedition Programming (Doctrine Setup)**  
The player configures:

- route intent  
- terrain behavior profile  
- risk protocols  
- dynamic behavior triggers  
- thresholds  
- party composition  
- gear loadout  
- funding allocation  
- **belief‑map tuning (priors, biases, pattern rules)**  
- **map‑based preferences/depreferences**  
- **guidance lines + branching fallback routes**  

This is the “programming” phase.

### **Phase 3 — Simulation (Automated Run)**  
The explorer:

- follows waypoints  
- then switches to autonomous mode  
- uses the belief map + doctrine to choose paths  
- triggers dynamic behaviors  
- encounters events  
- consumes rations  
- reveals tiles  
- logs decisions  

Runs resolve in seconds.

### **Phase 4 — Expedition Log (Forensic Replay)**  
The player:

- scrubs day‑by‑day  
- sees revealed map at each day  
- sees belief map at each day  
- sees tile probability breakdowns  
- sees dynamic triggers firing  
- sees why decisions were made  
- refines templates and priors  

This is the “learning” phase.

---

# **3. World & Terrain**

The world is a procedurally generated hex globe with:

- plains  
- forests  
- swamps  
- deserts  
- hills  
- mountains  
- coasts  
- oceans  

Each tile has:

- **movement cost (days)**  
- **vision radius**  
- **event likelihood**  
- **terrain type**  

Movement cost consumes rations.

---

# **4. The Belief Map System (Core Pillar)**

The belief map is the expedition AI’s **probabilistic model** of fogged tiles. It is the most important system in the game.

It determines:

- expected terrain  
- expected movement cost  
- expected danger  
- expected event likelihood  
- pathfinding decisions  
- dynamic behavior triggers  

The belief map is influenced by:

- system inference  
- player intuition  
- priors  
- pattern rules  
- regional biases  
- preferences/depreferences  
- guidance lines  
- professions  
- gear  
- thresholds  

---

## **4.1 System Inference (Base Model)**

The base belief model uses:

### **Local Neighborhood Influence**
Adjacent revealed tiles influence fogged tiles.

### **Regional Influence**
All revealed tiles within radius \(R\) contribute, weighted by distance.

### **Shape Continuity**
Terrain clusters (desert blobs, forest patches, mountain bands) are detected and extended.

### **Directional Trends**
Terrain often continues along axes (mountain ridges, desert belts).

### **Profession Modifiers**
Navigator, Geologist, Ecologist, etc. improve inference accuracy.

### **Expected Cost**
Pathfinding uses:

\[
\text{ExpectedCost} = \sum_{t} P(t) \cdot \text{BaseCost}(t)
\]

---

# **4.2 Player‑Driven Belief Map Tuning (Advanced Mode)**

This is the new, powerful system that lets players bake their intuition into the belief map.

Players can modify the belief map **before a run**, based on what they’ve learned from previous expeditions.

---

## **4.2.1 Global Priors (World-Level Intuition)**

Players can adjust global terrain likelihoods:

- “This world seems desert‑heavy.”  
- “Forests seem rare.”  
- “Swamps seem more common.”  

UI: sliders or percentage nudges.

\[
P'(t) = \text{Normalize}(P(t) \cdot (1 + \text{GlobalBias}_t))
\]

---

## **4.2.2 Regional Priors (Area-Level Intuition)**

Players can paint regions with biases:

- “This area feels swampy.”  
- “This coastline probably has villages.”  
- “This valley looks fertile.”  

UI: brush tool.

\[
P'(t) = \text{Normalize}(P(t) \cdot (1 + \text{RegionalBias}_t))
\]

---

## **4.2.3 Pattern Rules (Learned Relationships)**

Players can toggle simple pattern rules:

- “Valleys → Swamps”  
- “Coasts → Villages”  
- “River edges → Forests”  
- “Mountain foothills → Tribes”  
- “Desert edges → Ruins”  

Each rule has a strength slider.

\[
P'(t) = \text{Normalize}(P(t) \cdot (1 + \text{PatternRuleStrength}))
\]

---

## **4.2.4 Confidence Thresholds**

Players can set:

- minimum confidence for system inference  
- maximum uncertainty allowed  
- when player priors override system inference  

Example:

- “Apply my priors only when confidence < 60%.”

---

## **4.2.5 Weighting System (System vs Player)**

Players set:

- **System Weight (α)**  
- **Player Weight (β)**  

Final belief:

\[
P_{\text{final}}(t) = \text{Normalize}(\alpha P_{\text{system}}(t) + \beta P_{\text{player}}(t))
\]

This is the heart of advanced belief tuning.

---

# **4.3 Map-Based Player Controls**

These are the three new map tools the player can use before a run.

---

## **4.3.1 Tile Preferences (Soft Attraction Zones)**

Players can mark tiles or regions as “preferred.”

Examples:

- “This valley looks promising.”  
- “This forest cluster is safe for food.”  
- “This desert gap might be a shortcut.”  

Effect:

\[
\text{TileWeight} \times= (1 - \text{PreferenceStrength})
\]

---

## **4.3.2 Tile Depreferences (Soft Repulsion Zones)**

Players can mark tiles or regions as “avoid if possible.”

Examples:

- “Last run encountered danger here.”  
- “This swamp cluster is too costly.”  
- “This mountain band is risky.”  

Effect:

\[
\text{TileWeight} \times= (1 + \text{DepreferenceStrength})
\]

---

## **4.3.3 Guidance Lines (Soft Path Suggestions)**

Players can draw lines on the map.

The explorer tries to follow them **if doctrine allows**.

Effect:

\[
\text{TileWeight} \times= (1 - \text{LineAffinity})
\]

---

## **4.3.4 Branching Fallback Routes**

Players can draw:

- primary guidance line  
- secondary line  
- tertiary line  

Explorer switches lines when:

- detour > threshold  
- danger > threshold  
- confidence < threshold  
- impassable terrain encountered  

This creates a **decision graph** drawn directly on the map.

---

# **5. Expedition Programming (Doctrine)**

Players configure:

- route intent  
- terrain behavior profile  
- risk protocols  
- dynamic triggers  
- thresholds  
- party composition  
- gear  
- funding  
- belief tuning  
- map preferences  
- guidance lines  

Simple mode: presets  
Advanced mode: full control

---

# **6. Run Execution**

Runs resolve quickly.

Explorer:

- follows waypoints  
- switches to autonomous mode  
- uses belief map + doctrine  
- triggers dynamic behaviors  
- logs decisions  

---

# **7. Expedition Log (Forensic Replay)**

The log is a full replay of the explorer’s “thought process.”

Players can:

- scrub day‑by‑day  
- see revealed map  
- see belief map  
- see tile probability breakdowns  
- see dynamic triggers firing  
- see why decisions were made  
- see how priors influenced belief  
- see how preferences/depreferences affected path  
- see when guidance lines were followed or abandoned  

This is the main learning tool.

---

# **8. Templates & Meta-Progression**

Players can save:

- simple templates  
- advanced templates  
- belief tuning templates  
- map preference templates  
- guidance line templates  

Templates can be:

- saved  
- cloned  
- renamed  
- deleted  

This supports deep optimization.

---

# **9. Closing Note**

Project Wayfinder is a game about **inference**, **intuition**, and **trust**.  
The explorer is a black box.  
The belief map is the window into its mind.  
The expedition log is the record of its reasoning.  
The player’s job is to learn the world, tune the model, and refine doctrine.

The new belief‑tuning systems, map preferences, guidance lines, and fallback routes make the game deeper, more expressive, and more personal — letting players bake their own hypotheses into the expedition AI.
