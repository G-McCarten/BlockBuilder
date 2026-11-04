# Frostward

You are a hearthkeeper raising warm halls across a frozen valley before the long night falls.

Frostward is built with the formula in [`BUILDER_GAME_FORMULA_PROMPT.md`](BUILDER_GAME_FORMULA_PROMPT.md): Unharvester's meta and run shape, a new verb (click a ghost block to place it, in an order a fixed blueprint decides), and a new skin.

## Status

This repo holds Phase 1 of the formula, the new verb's core, written from the spec **before** the fork. Phase 0, forking Unharvester's code and place, hasn't happened yet: it needs Unharvester's source and Studio, which the session that started this repo couldn't reach. Run Phase 0 on the PC, then bring this work into the fork.

| Piece | Where | State |
|---|---|---|
| Blueprint: slots, default supports, packing | `src/shared/Blueprint.luau` | done, tested |
| Validator: range, overlaps, floating, cycles, cap, reach | `src/shared/BlueprintValidator.luau` | done, tested |
| BuildSite: slot states and rules (4.2) | `src/shared/BuildSite.luau` | done, tested |
| SiteCodec: snapshot and delta messages | `src/shared/SiteCodec.luau` | done, tested |
| Theme: player-facing words | `src/shared/Theme.luau` | slot pick A |
| Stamp tool, script-generated sources | `tools/stamp_blueprint.luau` | done |
| Stamp tool, Studio Model input | | not started |
| Test blueprint | `tools/blueprints/TestHut.luau`, stamped to `src/shared/Blueprints/TestHut.luau` | done |

### Reconcile at the fork

- **`BuildSite` and `CropField`.** Field names follow section 4.2. The behaviour of `shield` (`NONE`, `HAND_ONLY`, `BLOCKED`) is inferred from the boss table in 5.3. `bound` is only stored, not enforced. Check both against `CropField`.
- **`SiteCodec` and `FieldCodec`.** This is a new wire format, not `FieldCodec`'s. A delta entry is 8 bytes (u16 slot, u16 progress, f32 rate). A snapshot is a placed bitset plus an entry for each active slot.
- **Base grasp.** The validator and stamp tool assume 5 cells (15 studs at 3 studs a block) and 2 cells of headroom. Replace these with `UpgradeConfig`'s base grasp.
- **Layout.** Code lives under `src/shared`; move it to match the fork's folders.
- **Requires.** The shared modules don't require each other, so they load the same way under Lune and in Roblox. Tests and tools use Lune string requires.
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

```bash
lune run tools/stamp_blueprint TestHut
```

```bash
lune run tools/stamp_blueprint TestHut --check
```

```bash
stylua src tools tests
```
