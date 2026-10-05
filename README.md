# Hull Down

WWII naval combat. A Squatch Squad Studios production. Godot 4.3+ (GDScript).

## Run
1. Install Godot 4.3 or newer (free, MIT licence): https://godotengine.org
2. Import this folder (open `project.godot`) and press F5.
3. The title cinematic plays (Space / click skips), then the surface testbed loads.
   Command line: `godot --path . -- savo_island` picks a battleground directly.

## Testbed controls
| Key | Action |
|---|---|
| W / S | throttle up / down |
| A / D | rudder |
| Right mouse + drag | orbit camera (wheel zooms) |
| Left mouse | fire main battery at the cursor |
| F1-F7 | switch battleground |
| [ / ] | cycle your ship |

## Layout
- `scripts/ship/` - `Compartment` (one damageable part), `ShipBuilder` (builds the internal layout from roster data), `Ship` (damage, flooding, fire, magazines, grounding, performance), `ShipVisual` (placeholder procedural model).
- `scripts/combat/` - `Shell` (ballistics, ship / terrain / water impact) and `Gunnery` (per-turret fire control).
- `scripts/ai/` - `CombatProfiles` (per-ship-type doctrine, pure data) and `AICaptain` (target scoring, stationing, attack runs, withdrawal, fire-safety, hazard and terrain avoidance).
- `scripts/world/terrain.gd` - deformable heightmap: land above sea level, seabed below, craters, landslides, gouged shoals, destructible fort hardpoints.
- `scripts/data/` - roster per nation, plus the seven battlegrounds (Surigao Strait, Ironbottom Sound, Rio de la Plata, Ofotfjord, Sunda Strait, Mers-el-Kebir, Omaha Beach).
- `scripts/game/` - the title cinematic and the testbed.

## Status / known gaps
- Submarines are in the roster (every nation) but disabled: `Roster.include_subs = false`. The subsurface layer (sonar, thermal layers, no visuals) is next.
- Ship art is procedural boxes keyed to compartments; replace per compartment id with real meshes.
- Damage numbers are first-pass and need tuning.
- Roster currently covers USA, UK, Japan, Germany, Italy, France, USSR. Smaller navies are queued.
- Verified with headless soak tests in Godot 4.7.2. Visuals (title cinematic, ship models) have not been seen on screen yet.
- Torpedoes and aircraft are not implemented, so destroyer/MTB attack runs are gun-based and carriers only evade.

## Test flags (headless)
`godot --headless --path . --fixed-fps 60 res://scenes/testbed.tscn --quit-after 5400 -- savo_island --report --auto`
- `--report` prints fleet / damage stats every 10 s
- `--auto` lets the AI drive the player ship (useful for soak tests)
Friendly fire is real. Shells hit whatever they hit.

## Combat profiles (per ship type)
Each roster `type` has a profile in `scripts/ai/combat_profiles.gd`: preferred range band, how much to circle vs close
(`exposure_deg`: 15 = nose-on, 90 = broadside), target priorities, who to stay near (cohesion/station), when to
withdraw (flooding / propulsion / main battery), and attack-run settings for destroyers and torpedo boats.
- battleship / battlecruiser: line of battle, long stand-off range, stay in company, high threshold to retreat
- heavy / light cruiser: support and flotilla roles, hunt destroyers and cruisers
- destroyer: screen the capital ships, then strike at high-value targets (run in, break away, cool down)
- escort: guard the carrier/capital ships, engage only close threats
- carrier: keep away from enemies (aircraft not implemented yet)
- motor torpedo boat: hit-and-run, nose-on at flank speed
Captain types (later) will scale these through `AICaptain.captain_mods`, e.g. `{"aggression": 1.3, "engage_cap_m": 1.1}`.

## Safety and chain reactions
- Captains check that a salvo will not cross a friendly ship (including point-blank), and hold fire if it would.
  Each captain has an error rate (1-5%) of botching a check and a position error (15-60 m) on where friends are.
- Ammunition spaces can cook off: burning ammo heats up (armour slows it), flooding puts fires out, and heavy hits or
  nearby blasts can trigger sympathetic detonations. Explosions damage other ships in range (blast radius ~25-60 m).
- Captains steer clear of ships that look ready to blow, with the same error rate.
