# Frostward

You are a hearthkeeper raising warm halls across a frozen valley before the long night falls.

Frostward is built with the formula in [`BUILDER_GAME_FORMULA_PROMPT.md`](BUILDER_GAME_FORMULA_PROMPT.md): Unharvester's meta and run shape, a new verb (click a ghost block to place it, in an order a fixed blueprint decides), and a new skin.

This repo was started **before** the Unharvester fork (the formula's Phase 0), in sessions that couldn't reach Unharvester's source or Studio. It holds the new verb's core as pure, tested logic, a run sim, and a graybox prototype you can play in Studio now. Run Phase 0 on the PC, then bring this work into the fork.

## Play the prototype

The prototype runs the four sites in a plain place, starting with the Woodcutter's Lodge (5,928 blocks), and moves to the next when one is finished. It's there to judge the click (the Phase 2 gate) and the shape of a run.

1. Install the tools with `aftman install` (Rojo, Lune, StyLua, selene).
2. Build a place and open it in Studio, then press Play:

   ```bash
   rojo build default.project.json -o Frostward.rbxl
   ```

   Or open any Baseplate place, run `rojo serve`, and connect from the Rojo plugin.

Controls:

- Click or tap to lay a brick, and hold to keep laying. The outlined slot is the one you'd lay.
- The number keys, or the shop on the left, buy skill levels with Embers. Sure Hand is auto-aim: a click with nothing under the cursor lays the nearest brick in reach.
- Q, or the button on the right, calls the Sled Train once its skill is bought.
- On a gamepad, R2 lays at the screen centre and X calls the crew.
- Step on a blue hoist pad to ride up to the working height.

What it does:

- **Hints:** a tip at the bottom of the screen when its moment comes: how to lay, when you can afford a skill, the boss and its works, the crew, and the hoist pads.
- **Blocks:** your clicks show at once and roll back if the server refuses them. Blocks near the camera drop in with a small squash, and a tick climbs in pitch during a fast chain.
- **Ghosts:** the finished build always shows as a faint silhouette. READY slots near you pulse as ghosts.
- **Collisions:** a block that lands where you stand moves you onto it, and a character stuck for 2 seconds is moved clear.
- **The boss:** the Rime rises at 15% built. Walk up to it to shoo it away, and break its frost marks (and, on Hard, its ice chains) for a bounty.
- **The world:** the blizzard thins and night falls as the hold rises. When it's finished, a ten-second timelapse raises the build again in the order it was placed. Each player is told their share of the site's Hearthstones, split by blocks placed, and what they did. 30 seconds later the next site starts, with a bare tree and an empty purse.

Workspace attributes change it while it runs:

- `Difficulty`: `None`, `Normal`, `Hard` or `Nightmare`. It's read when a site starts.
- `Site`: a site's id from `SiteList` (`WoodcuttersLodge`, `IceBridge`, `Watchtower`, `GreatHall`) to start there.
- `BotPlayers`: how many bots (the sim's `BotBrain`) work the site with you, drawn as orange stand-ins.
- `TestSpeed`: 1 to 5, how many times faster than real time the site runs.
- `PowerTool`: true gives everyone the Forge Hammer, as its game pass will. Swing it with F.
- `Pets`: how many hearthlings each player brings (0 to 4), read when they join. They fly to the nearest work near their owner, lay it, and rest.
- `SitePlaced` is set by the server each tick: how many blocks stand, for debugging.
- `AbilityPets`: how many rarer hearthlings each player brings. Every 20 seconds, one lays everything workable around its owner, as Unharvester's Cinderfall pets do.
- `Cooldown`, `Grasp`, `Batch`, `SetTime`, `ChainChance`, `ChainRadius`, `PerfectChance`, `CrewWidth`, `CrewCooldown`: each overrides that stat for everyone.

It's a sandbox, not the game. It has no meta, saves, eggs, mounts, parties or menus, and its pets are stand-ins. Its tick is a built-in Studio sound. At the fork, the Unharvester-based `BuildRenderer`, `PlaceController` and `SiteService` replace `src/client` and `src/server`, calling the same shared modules.

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
| SiteSession: one site's run on the server, with each player's counts for tasks and achievements | `src/shared/SiteSession.luau` | tested |
| SkillTuning: placeholder skill tree and base stats | `src/shared/SkillTuning.luau` | tuned by the sim |
| WorldArc, WorldArcConfig: the look by share built | `src/shared/WorldArc*.luau` | tested |
| Timelapse: the ending's order and pacing (4.7) | `src/shared/Timelapse.luau` | tested |
| Hints and HintConfig: first-time tips, one at a time | `src/shared/Hint*.luau` | tested |
| Theme: player-facing words | `src/shared/Theme.luau` | slot pick A |
| Prototype server and client | `src/server`, `src/client` | run under a Roblox stand-in in tests |
| BotBrain: a bot that plays a site, for the sim and for testing alone in Studio | `src/shared/BotBrain.luau` | tested |
| Run sim | `tools/sim/` | tested |
| Stamp tool, from a script or a Studio model: multi-cell parts, inherited kinds, stages | `tools/stamp_blueprint.luau`, `tools/lib/ModelSource.luau`, `docs/authoring.md` | tested; not yet tried on a real Studio export |
| Content drafts: hearthlings and eggs, sled beasts, achievements, tasks, lore, news, The Warm Welcome | `src/shared/content/` | structure tested, numbers placeholders |
| SiteList and KindLooks: the sites in order with their payouts, and each block kind's look | `src/shared/SiteList.luau`, `src/shared/KindLooks.luau` | tested, payouts provisional |
| Blueprints: TestHut (508), WoodcuttersLodge (5,928), IceBridge (7,320), Watchtower (8,754), GreatHall (10,746) | `tools/blueprints/` | validated, sizes provisional |

### How the prototype is tested

The prototype's scripts aren't run in Studio here; `tests/Prototype.spec.luau` runs them under Lune instead. `tests/lib/PlaceBuilder` builds the place from `default.project.json` the way `rojo build` does. `tests/lib/FakeRoblox` runs the server Script and client LocalScript with real Lune instances, whose properties Lune checks against Roblox's API database. Stand-ins replace the players, the run loop, input, tweens, sounds, remotes, the camera and the clock.

The tests boot the place, lay blocks by holding the mouse, buy a skill, let a Hard boss bind the site, ride a hoist pad, and play a site to the end through its timelapse and reset, all with no script errors. `tests/lib/FakeGroup` runs a server and two clients the way Studio's Local Server does, each with its own view, input and module cache. In `tests/Clients.spec.luau`, two players lay blocks against a Hard boss, sometimes racing for the same cells, and both clients end showing exactly what the server holds. What the tests can't show is how it looks, feels or performs, or anything about physics, which only Studio shows.

### What the sim measures

`lune run tools/sim/run` plays whole runs with bots through `SiteSession`. Bots buy the cheapest skill they can afford, use the ability when it's ready, break markers and bindings, and shoo the boss; otherwise they work the nearest slot. The economy in `src/shared/SkillTuning.luau` is a placeholder, tuned so a solo first run of the lodge takes about 30 minutes. Measured on the WoodcuttersLodge:

| Run | Result |
|---|---|
| Solo, no boss, 10 seeds | 29.8 min (28.8 to 30.4) |
| Solo, Normal, 20 seeds | 31.2 min (27.9 to 32.9), all finished |
| Solo, Hard, 20 seeds | 37.0 min (32.7 to 47.4), all finished |
| Solo, Nightmare, 20 seeds | 39.9 min (36.0 to 45.4), all finished |
| 2, 3, 4 players, Normal | 0.54, 0.36, 0.29 of the solo time (Unharvester: 0.51, 0.36, 0.27) |

The later sites, solo against Normal over 3 seeds: IceBridge 32.2, Watchtower 36.7 and GreatHall 39.5 minutes, all finished. Their sizes are placeholders until the renderer's stress test sets each site's ceiling.

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
- **Requires.** `SiteActions`, `BossEffects`, `BossBrain`, `SiteSession`, `Prediction`, `BotBrain` and `HintConfig` require their neighbours by string (`require("./BuildSite")`). Lune accepts that, and so does the test harness, which resolves it the way Roblox's require-by-string does. It hasn't been tried in real Studio. If the place refuses it, switch those seven files to `require(script.Parent.BuildSite)`.
- **Bots.** `BotBrain` plays the sim and the prototype's `BotPlayers`. Unharvester's `Bots` do the same job in its Studio tests; keep whichever fits the fork, and point the other at it.
- **Payouts and counts.** `SiteList`'s payouts stand in for `TitheConfig`. `SiteSession.counts` is what `TaskService` and `AchievementService` would read.
- **Hints.** `Hints` and `HintConfig` stand in for `FieldTutorial`.
- **Studio models.** `ModelSource` has only read models that Lune built and serialized. Export one from Studio and stamp it before building a site that way.
- **Content.** `src/shared/content/` drafts Phase 6's words as frozen data: `PetRoster` (PetConfig, EggConfig), `Mounts` (MountConfig), `Achievements` (AchievementConfig), `Tasks` (TaskConfig), `Lore` (LoreConfig), `News` (NewsConfig) and `DailyReward` (WatchConfig). Every number is a placeholder: port Unharvester's into these fields and resize the roster to its count per rarity. Goals count `SiteSession.counts` keys, plus `finished`, which the services must count per player when a site is finished.
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

Stamp a blueprint after changing its source, or check the stamped file is current. The source is a script, `tools/blueprints/<Name>.luau`, or a Studio model exported as `tools/blueprints/<Name>.rbxm` or `.rbxmx`. In a model, a part becomes one block for each 3-stud cell it covers: its size a whole number of cells, its faces on the 3-stud grid, upright and turned only in quarter turns. Its kind is its `Kind` attribute, else the nearest Model's or Folder's, else its name. A `Stage` number attribute orders the things in one group, such as a roof after its walls. [`docs/authoring.md`](docs/authoring.md) walks through building, exporting and checking a site in Studio.

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
