# Frostward

You are a hearthkeeper raising warm halls across a frozen valley before the long night falls.

Frostward is built with the formula in [`BUILDER_GAME_FORMULA_PROMPT.md`](BUILDER_GAME_FORMULA_PROMPT.md): Unharvester's meta and run shape, a new verb (click a ghost block to place it, in an order a fixed blueprint decides), and a new skin.

This repo was started **before** the Unharvester fork (the formula's Phase 0), in sessions that couldn't reach Unharvester's source or Studio. It holds the new verb's core as pure, tested logic, a run sim, and a graybox prototype you can play in Studio now. Run Phase 0 on the PC, then bring this work into the fork.

## Play the prototype

The prototype runs the first site, the Woodcutter's Lodge (5,928 blocks), in a plain place. It's there to judge the click (the Phase 2 gate) and the shape of a run.

1. Install the tools with `aftman install` (Rojo, Lune, StyLua, selene).
2. Build a place and open it in Studio, then press Play:

   ```bash
   rojo build default.project.json -o Frostward.rbxl
   ```

   Or open any Baseplate place, run `rojo serve`, and connect from the Rojo plugin.

Controls:

- Click or tap to lay a brick, and hold to keep laying. The outlined slot is the one you'd lay.
- Keys 1 to 5, or the shop on the left, buy skill levels with Embers.
- Q, or the button on the right, calls the Sled Train once its skill is bought.
- On a gamepad, R2 lays at the screen centre and X calls the crew.
- Step on a blue hoist pad to ride up to the working height.

What it does:

- **Blocks:** your clicks show at once and roll back if the server refuses them. Blocks near the camera drop in with a small squash, and a tick climbs in pitch during a fast chain.
- **Ghosts:** the finished build always shows as a faint silhouette. READY slots near you pulse as ghosts.
- **Collisions:** a block that lands where you stand moves you onto it, and a character stuck for 2 seconds is moved clear.
- **The boss:** the Rime rises at 15% built. Walk up to it to shoo it away, and break its frost marks (and, on Hard, its ice chains) for a bounty.
- **The world:** the blizzard thins and night falls as the hold rises. When it's finished, a ten-second timelapse raises the build again in the order it was placed, and a fresh site starts 30 seconds later.

Workspace attributes change it while it runs:

- `Difficulty`: `None`, `Normal`, `Hard` or `Nightmare`. It's read when a site starts.
- `Cooldown`, `Grasp`, `Batch`, `SetTime`, `ChainChance`, `ChainRadius`, `PerfectChance`, `CrewWidth`, `CrewCooldown`: each overrides that stat for everyone.

It's a sandbox, not the game. It has no meta, saves, pets, mounts, parties or menus. The cooldown shows as a bar rather than a ring, and its tick is a built-in Studio sound. At the fork, the Unharvester-based `BuildRenderer`, `PlaceController` and `SiteService` replace `src/client` and `src/server`, calling the same shared modules.

## What's built

| Piece | Where | State |
|---|---|---|
| Blueprint: slots, default supports, packing | `src/shared/Blueprint.luau` | tested |
| Validator: range, overlaps, floating, cycles, cap, reach per layer | `src/shared/BlueprintValidator.luau` | tested |
| BuildSite: slot states and rules (4.2), shields, binding cap | `src/shared/BuildSite.luau` | tested |
| SiteCodec: snapshot and delta messages | `src/shared/SiteCodec.luau` | tested |
| SiteConfig: cell size, chunk size, base grasp, headroom | `src/shared/SiteConfig.luau` | |
| SiteIndex: chunks, nearest and region queries (4.3, 5.2) | `src/shared/SiteIndex.luau` | tested |
| SiteRay: grid raycast for aiming (4.3) | `src/shared/SiteRay.luau` | tested |
| Prediction: clicks shown at once, rolled back if refused (4.3) | `src/shared/Prediction.luau` | tested over a laggy network |
| CollisionBoxes: greedy-merged boxes per chunk (4.5) | `src/shared/CollisionBoxes.luau` | tested |
| Access: stand cells, free surface, working layer (4.4) | `src/shared/Access.luau` | tested |
| SiteActions: click, batch, chain, ability sweep, power tool, pets (5.1, 5.2) | `src/shared/SiteActions.luau` | tested |
| BossEffects, BossBrain, BossConfig: the boss at three difficulties (5.3) | `src/shared/Boss*.luau` | tested, tuning provisional |
| SiteSession: one site's run on the server | `src/shared/SiteSession.luau` | tested |
| SkillTuning: placeholder skill tree and base stats | `src/shared/SkillTuning.luau` | tuned by the sim |
| WorldArc, WorldArcConfig: the look by share built | `src/shared/WorldArc*.luau` | tested |
| Timelapse: the ending's order and pacing (4.7) | `src/shared/Timelapse.luau` | tested |
| Theme: player-facing words | `src/shared/Theme.luau` | slot pick A |
| Prototype server and client | `src/server`, `src/client` | run under a Roblox stand-in in tests |
| Run sim with bots | `tools/sim/` | tested |
| Stamp tool, from a script or a Studio model | `tools/stamp_blueprint.luau`, `tools/lib/ModelSource.luau` | tested |
| Blueprints: TestHut (508), WoodcuttersLodge (5,928) | `tools/blueprints/` | validated |

### How the prototype is tested

The prototype's scripts aren't run in Studio here; `tests/Prototype.spec.luau` runs them under Lune instead. `tests/lib/PlaceBuilder` builds the place from `default.project.json` the way `rojo build` does. `tests/lib/FakeRoblox` runs the server Script and client LocalScript with real Lune instances, whose properties Lune checks against Roblox's API database. Stand-ins replace the players, the run loop, input, tweens, sounds, remotes, the camera and the clock.

The tests boot the place, lay blocks by holding the mouse, buy a skill, let a Hard boss bind the site, ride a hoist pad, and play a site to the end through its timelapse and reset, all with no script errors. What they can't show is how it looks, feels or performs, or anything about physics, which only Studio shows.

### What the sim measures

`lune run tools/sim/run` plays whole runs with bots through `SiteSession`. Bots buy the cheapest skill they can afford, use the ability when it's ready, break markers and bindings, and shoo the boss; otherwise they work the nearest slot. The economy in `src/shared/SkillTuning.luau` is a placeholder, tuned so a solo first run of the lodge takes about 30 minutes. Measured on the WoodcuttersLodge:

| Run | Result |
|---|---|
| Solo, no boss, 10 seeds | 29.8 min (28.8 to 30.4) |
| Solo, Normal, 20 seeds | 31.2 min (27.9 to 32.9), all finished |
| Solo, Hard, 20 seeds | 37.0 min (32.7 to 47.4), all finished |
| Solo, Nightmare, 20 seeds | 39.9 min (36.0 to 45.4), all finished |
| 2, 3, 4 players, Normal | 0.54, 0.36, 0.29 of the solo time (Unharvester: 0.51, 0.36, 0.27) |

Co-op reaches those ratios through `partyShare`: every teammate also earns the base pay of each first placement, so a party climbs the tree as fast per share built as a solo player. Without it, 4 players took 0.51 of the solo time, because each player's tree only grew from their own blocks. PartyPressure isn't modelled.

### Reconcile at the fork

- **`BuildSite` and `CropField`.** Field names follow section 4.2. `shield` holds flags, `HAND_ONLY` and `BLOCKED`, inferred from the boss table in 5.3; they combine, so the peace circle can lift without clearing a stubborn band. `bound` caps how many blocks can stand until the boss's bindings break. Check both against `CropField`.
- **Strike paths.** `SiteActions` reads the stat table in 5.1 one way, to be checked against `FieldService`:
  - Batch takes the READY or SETTING slots nearest the aimed one, among those within the player's grasp. It counts as `BATCH`, not `HAND`, so it skips stubborn slots.
  - A chain starts READY slots within `chainRadius` of each block placed.
  - The power tool and pets place what is workable when they act, never what their own placing readies.
  - A band places `bandRate` (6) blocks a second per cell of its width, so it is as strong at any tick rate.
- **Run economy.** `SkillTuning` stands in for `UpgradeConfig`. Port the real tree's nodes and prices into its shape and rerun the sim.
- **Party share.** `SiteSession` pays every teammate the base pay of each first placement (`partyShare` 1). Check it against how Unharvester's purses work in a party.
- **Premium drops.** One roll per player per step with a first placement, not only on perfect steps, as the formula's bug note asks.
- **Collapse.** When a section collapses, only its lowest blocks animate. The ones above drop to LOCKED at once, because BuildSite resets anything resting on a block that stops counting as placed.
- **`SiteCodec` and `FieldCodec`.** This is a new wire format, not `FieldCodec`'s. A delta entry is 8 bytes (u16 slot, u16 progress, f32 rate). A snapshot is a placed bitset plus an entry for each active slot. Each tick's answers to clicks must go out after that tick's delta, which `Prediction` relies on.
- **Base grasp.** `SiteConfig` assumes a base grasp of 5 cells (15 studs at 3 studs a block) and 2 cells of headroom. Replace the grasp with `UpgradeConfig`'s, then restamp and revalidate every blueprint.
- **Reach model.** The validator checks reach layer by layer: while a layer is worked, the layers below are built and the ones above aren't. So it lets a player stand on the layer being built, but never in the cell being placed. It doesn't check that a player can walk to the spot where they'd stand; hoist pads cover that.
- **Layout.** Shared code lives under `src/shared`; move it to match the fork's folders.
- **Requires.** `SiteActions`, `BossEffects`, `BossBrain`, `SiteSession` and `Prediction` require their neighbours by string (`require("./BuildSite")`). Lune accepts that, and so does the test harness, which resolves it the way Roblox's require-by-string does. It hasn't been tried in real Studio. If the place refuses it, switch those five files to `require(script.Parent.BuildSite)`.
- **Type checking.** Nothing has been run through `luau-lsp`; selene lints it with a small Roblox standard (`roblox_lite.yml`). Record it all in the fork's baseline.

## Slots

| Slot | Frostward |
|---|---|
| `GAME_NAME` | Frostward |
| `PREMISE` | You are a hearthkeeper raising warm halls across a frozen valley before the long night falls |
| `TONE_AND_PALETTE` | Cozy and wintry: snow white, pine green, lantern amber |
| `WORLD_ARC` | Blizzard thins, stars come out, an aurora opens over the finished hall |
| `BLOCK` | brick |
| `PLACE_VERB` | lay |
| `SITE` | hold |
| `RUN_CURRENCY` | Embers |
| `META_CURRENCY` | Hearthstones |
| `PREMIUM_CURRENCY` | Starglass |
| `PET`, `PET_ROLL_PLACE` | hearthling, Kindling Hearth |
| `MOUNT`, `MOUNT_SHOP` | sled beast, Sledyard |
| `START_PAD` | First Stone |
| `BOSS` | the Rime, a frost wraith that cracks exposed bricks loose |
| `SERVER_EVENT` | Aurora Night |
| `DAILY_REWARD` | The Warm Welcome |
| `ABILITY` | Sled Train |
| `POWER_TOOL` | Forge Hammer |
| `SITES` | Woodcutter's Lodge (timber, stone, thatch), Ice Bridge (ice, rope rail), Watchtower (stone, timber, lantern), Great Hall (stone, timber, slate, glass) |
| `BLOCK_STUDS` | 3 |
| `FIRST_SITE_BLOCKS` | 6,000 |
| `FIRST_RUN_MINUTES` | 30 |
| `ACCESS` | default in 4.4 |

## Commands

Run from the repo root. `aftman install` fetches the tools.

Everything the repo can check on its own (format, lint, tests, stamped blueprints), with a real exit status:

```bash
lune run tools/check
```

Just the tests:

```bash
lune run tests/run
```

The sim, solo or against a boss, and co-op ratios:

```bash
lune run tools/sim/run
```

```bash
lune run tools/sim/run -- --boss Hard --seeds 20
```

```bash
lune run tools/sim/run -- --coop
```

Stamp a blueprint after changing its source, or check the stamped file is current. The source is a script, `tools/blueprints/<Name>.luau`, or a Studio model exported as `tools/blueprints/<Name>.rbxm` or `.rbxmx`. In a model, every part is one block: a 3-stud cube snapped to the 3-stud grid, upright, turned only in quarter turns, with its kind in a `Kind` attribute or its name.

```bash
lune run tools/stamp_blueprint WoodcuttersLodge
```

```bash
lune run tools/stamp_blueprint WoodcuttersLodge --check
```

Format the code:

```bash
stylua src tools tests
```
