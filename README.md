# Frostward

You are a hearthkeeper raising warm halls across a frozen valley before the long night falls.

Frostward is built with the formula in [`BUILDER_GAME_FORMULA_PROMPT.md`](BUILDER_GAME_FORMULA_PROMPT.md): Unharvester's meta and run shape, a new verb (click a ghost block to place it, in an order a fixed blueprint decides), and a new skin.

## Status

This repo holds the new verb's core, written from the spec **before** the fork: all of Phase 1, and the parts of Phases 2 to 4 that are pure logic. Phase 0, forking Unharvester's code and place, hasn't happened yet: it needs Unharvester's source and Studio, which the sessions that built this repo couldn't reach. Run Phase 0 on the PC, then bring this work into the fork.

Nothing here touches Roblox instances, so all of it runs and is tested under Lune. Still to do is the Roblox side: `BuildRenderer`, `PlaceController`, `SiteService`, hoist pads, the boss's movement and shooing, the skill tree's numbers, and the sim. It should be built on Unharvester's `FieldRenderer`, `WitherController`, `FieldService`, `Tender*`, `UpgradeConfig` and `tools/sim` once the fork exists, calling the modules below for everything that touches the site.

| Piece | Where | State |
|---|---|---|
| Blueprint: slots, default supports, packing | `src/shared/Blueprint.luau` | done, tested |
| Validator: range, overlaps, floating, cycles, cap, reach per layer | `src/shared/BlueprintValidator.luau` | done, tested |
| BuildSite: slot states and rules (4.2) | `src/shared/BuildSite.luau` | done, tested |
| SiteCodec: snapshot and delta messages | `src/shared/SiteCodec.luau` | done, tested |
| SiteConfig: cell size, chunk size, base grasp, headroom | `src/shared/SiteConfig.luau` | done |
| SiteIndex: chunks, nearest slots for auto-aim, batch and pets (4.3, 5.2) | `src/shared/SiteIndex.luau` | done, tested |
| SiteRay: grid raycast for aiming (4.3) | `src/shared/SiteRay.luau` | done, tested |
| CollisionBoxes: greedy-merged boxes per chunk (4.5) | `src/shared/CollisionBoxes.luau` | done, tested |
| Access: stand cells, free surface, working layer for hoists (4.4) | `src/shared/Access.luau` | done, tested |
| SiteActions: click with batch and chain, `ABILITY` sweep, `POWER_TOOL` arc, pet forage (5.1, 5.2) | `src/shared/SiteActions.luau` | done, tested |
| BossEffects: undo nearest, marker burst, collapse, peace and stubborn shields, relent (5.3) | `src/shared/BossEffects.luau` | done, tested |
| Theme: player-facing words | `src/shared/Theme.luau` | slot pick A |
| Stamp tool, from a script or a Studio model (`.rbxm`, `.rbxmx`) | `tools/stamp_blueprint.luau`, `tools/lib/ModelSource.luau` | done, tested |
| Test blueprint, 508 blocks | `tools/blueprints/TestHut.luau` | done |
| First site in graybox, 5,928 blocks | `tools/blueprints/WoodcuttersLodge.luau` | done, validated |

Stamped blueprints go to `src/shared/Blueprints/`. The finished lodge merges into 312 collision boxes over 96 chunks of 8 cells.

### Reconcile at the fork

- **`BuildSite` and `CropField`.** Field names follow section 4.2. `shield` holds flags, `HAND_ONLY` and `BLOCKED`, inferred from the boss table in 5.3; they combine, so the peace circle can lift without clearing a stubborn band. `bound` is only stored, not enforced. Check both against `CropField`.
- **Strike paths.** `SiteActions` reads the stat table in 5.1 one way, to be checked against `FieldService`:
  - Batch takes the READY or SETTING slots nearest the aimed one, among those within the player's grasp. It counts as `BATCH`, not `HAND`, so it skips stubborn slots.
  - A chain starts READY slots within `chainRadius` of each block placed.
  - The arc is a 3D radius narrowed to an angle seen from above.
  - A pet's leash, reach and ring are radii around its target.
- **Collapse.** When a section collapses, only its lowest blocks animate. The ones above drop to LOCKED at once, because BuildSite resets anything resting on a block that stops counting as placed.
- **`SiteCodec` and `FieldCodec`.** This is a new wire format, not `FieldCodec`'s. A delta entry is 8 bytes (u16 slot, u16 progress, f32 rate). A snapshot is a placed bitset plus an entry for each active slot.
- **Base grasp.** `SiteConfig` assumes a base grasp of 5 cells (15 studs at 3 studs a block) and 2 cells of headroom. Replace the grasp with `UpgradeConfig`'s, then restamp and revalidate every blueprint.
- **Reach model.** The validator checks reach layer by layer: while a layer is worked, the layers below are built and the ones above aren't. So it lets a player stand on the layer being built, but never in the cell being placed. It doesn't check that a player can walk to the spot where they'd stand; hoist pads cover that.
- **Block in a character's cell.** `Access.freeSurface` picks the nearest cell a character can stand in, preferring higher on ties, so a character a block lands on steps up onto it. The 2-second stuck timer belongs in the client controller.
- **Layout.** Code lives under `src/shared`; move it to match the fork's folders.
- **Requires.** `SiteActions` and `BossEffects` require their neighbours by string (`require("./BuildSite")`), which Lune and current Roblox Luau both accept. This hasn't been tried in Studio. If the place refuses it, switch those two to `require(script.Parent.BuildSite)`. The other shared modules require nothing.
- **Type checking.** These modules haven't been run through `luau-lsp`. Record them in the fork's baseline.

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

Run from the repo root. `aftman install` fetches Lune and StyLua.

```bash
lune run tests/run
```

Stamp a blueprint after changing its source, or check the stamped file is current. The source is a script, `tools/blueprints/<Name>.luau`, or a Studio model exported as `tools/blueprints/<Name>.rbxm` or `.rbxmx`. In a model, every part is one block: a 3-stud cube snapped to the 3-stud grid, upright, turned only in quarter turns, with its kind in a `Kind` attribute or its name.

```bash
lune run tools/stamp_blueprint WoodcuttersLodge
```

```bash
lune run tools/stamp_blueprint WoodcuttersLodge --check
```

```bash
stylua src tools tests
```
