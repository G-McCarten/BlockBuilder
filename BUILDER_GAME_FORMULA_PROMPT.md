# Builder game formula prompt

**How to use this**

1. Fill in the `Yours` column in section 1. Blank slots are fine: the agent proposes options and waits for your picks.
2. Open a new session in `C:\Users\jerry\Desktop\Unharvester`, then paste everything below the line.
3. The agent stops at four gates for your verdict, marked **GATE**.

To make another game later, change the slots and run the formula on the finished builder game instead of on Unharvester. Rule 4 in section 2 is there to make that cheap.

---

# Fork Unharvester into {{GAME_NAME}}

You are turning my Roblox game Unharvester into a new game, {{GAME_NAME}}. The formula:

> **New game = Unharvester's meta + Unharvester's run shape + a new verb + a new skin**

- **Meta, keep it working:** hub, parties, reserved servers, pets, eggs, fusion, mutations, mounts, shop, premium currency, daily reward, tasks, achievements, leaderboards, statistics, news, community, codes, settings, admin panel, telemetry.
- **Run shape, keep it:** a run is one site from scratch, with a bare skill tree and an empty purse. Every click earns run currency, skills stack until one click does the work of dozens, a boss pushes back, and finishing pays the currency players keep and unlocks the next site. Nothing of a run is saved.
- **New verb:** players no longer click a plant to wither it. They click a ghost block to place it. A fixed blueprint decides every block's position, type and order. Players choose where to work, never what goes where.
- **New skin:** the slots below replace every word, model, icon, sound and colour of the old theme.

Unharvester's source is at `C:\Users\jerry\Desktop\Unharvester\unharvester`. Its module header comments explain its design, so read them first: `server/CropField`, `server/FieldService`, `server/GameRun`, `shared/UpgradeConfig`, `shared/PetConfig`, `shared/DifficultyConfig`, `shared/TenderConfig`, `shared/PartyPressure`, `client/WitherController`, `client/FieldRenderer`. Then read `C:\Users\jerry\Desktop\Unharvester\LAUNCH_CHECKLIST.md`.

## 1. Slots

If any slot is blank, propose three options for it in one table and wait for my picks. Do this before anything else.

| Slot | In Unharvester | Yours |
|---|---|---|
| `GAME_NAME` | Unharvester | |
| `PREMISE`, one sentence | You are the blight, withering a valley's fields | |
| `TONE_AND_PALETTE` | Bleak and rural, old straw and ash | |
| `WORLD_ARC`, what the world does as the build grows | Sky greys, sound dies, an eclipse closes over the sun | |
| `BLOCK` | plant | |
| `PLACE_VERB` | wither | |
| `SITE` | field | |
| `RUN_CURRENCY`, spent on the skill tree, lost after the run | Blight | |
| `META_CURRENCY`, kept, paid for a finished site | Tithes | |
| `PREMIUM_CURRENCY` | Moontears | |
| `PET` and `PET_ROLL_PLACE` | familiar, Blight Shrine | |
| `MOUNT` and `MOUNT_SHOP` | mount, Stable | |
| `START_PAD` | Sowing Stone | |
| `BOSS` | the Tender, who brings dead plants back | |
| `SERVER_EVENT` | Blood Moon | |
| `DAILY_REWARD` | The Long Watch | |
| `ABILITY`, sweeps a line across the site | Locust Swarm | |
| `POWER_TOOL`, the game pass | Void Scythe | |
| `SITES`, in order: what each builds, its block types | Long Field, Shuttered Village, Ashen Village, Spared Vineyard | |
| `BLOCK_STUDS` | not applicable | default 3 |
| `FIRST_SITE_BLOCKS` | 51,984 plants | default 6,000 |
| `FIRST_RUN_MINUTES`, solo | about 30 | default 30 |
| `ACCESS`, how players reach high blocks | flat ground | default in 4.4 |

Example fill, to show the shape. Replace it: *Tidewall. A drowned coast where lamplit masons raise sea walls and lighthouses before the tide takes them back. BLOCK stone, PLACE_VERB lay, SITE works, RUN_CURRENCY Mortar, META_CURRENCY Keystones, PREMIUM_CURRENCY Pearls, PET sprite, BOSS the Undertow (a swirl of water that drags exposed stones back into the sea), SERVER_EVENT Spring Tide, WORLD_ARC storm clearing to a calm sunset.*

All names, blueprints and art must be original. Don't copy another game, brand or franchise, including recognisable buildings from them.

## 2. Ground rules

1. **Unharvester is read-only.** Don't commit, merge, push, switch branches, Rojo-sync or publish in its repo, any of its worktrees or its Studio place.
2. **Check which Studio you're driving.** Before every Studio write, use `list_roblox_studios` and confirm the target is the fork's place. If it's Unharvester, stop.
3. **One source of truth from day one.** All scripts live in the new repo and reach Studio through Rojo, one way. Studio holds only models, terrain and animation. Unharvester broke this rule, and 108 of its 231 scripts ended up differing between Studio and git.
4. **Neutral code names.** Code says `Block`, `Site`, `Blueprint`, `RunCurrency`, `MetaCurrency`, `PremiumCurrency`, `Pet`, `Mount`, `Boss`, `ServerEvent`. Player-facing theme words come from one module, `shared/Theme.luau`, and from content configs. Comments describe mechanics in the same neutral words. Unharvester's theme words are in about 169 of its 232 modules. The next reskin of this game should touch only `Theme`, the content configs and art.
5. **Ask before anything outward or paid:** publishing, creating a universe or GitHub remote, uploading or granting assets, spending Meshy or other generation credits, creating products or passes.
6. **Keys stay out of git.** `meshyapikey.txt` and `unharvester_uploadkey.txt` are read by path, never copied, printed or committed.
7. **One feature branch per step, named for the feature.** Parallel sessions each get their own worktree.
8. **Report plainly at each gate:** what changed, tests run with their numbers, and what is still unverified.

## 3. Phase 0: fork

**3.1 Take inventory, read-only.** Run `git worktree list`, `git status` in each worktree and `git branch --no-merged main`, and compare against the place. Produce a table: feature, committed on main or not, where it lives, whether Studio has it. This was the state on 2026-11-04. Re-check it:

- `main` is `d99981c`, 53 commits ahead of `origin/main`.
- 17 worktrees hold uncommitted changes, including pet work I want to keep: `familiar-mutations`, `roll-a-familiar`, `familiar-roster-and-shop-wagon`, `secret-rarity`, `familiar-slot-prices`, `ten-new-familiars`. `RollWindow`, `RollScene`, `ShrineWake` and `ScreenClaim` exist only in worktrees.
- `field-delta-sections` and `inspect-players` are committed but not merged.
- Studio has scripts git lacks: `SmithyBuild`, `MillCladding`, `JournalArt`, `UiArt`, `HubPlan` scaling. They may belong to another developer.
- Models aren't in git at all. `PetModels`, `MountModels`, `EggModels`, `NpcModels`, `SceneryMeshes`, `FoliageMeshes` and `CutsceneModels` in ReplicatedStorage exist only in the place file.

**GATE: show me the table and your recommended base, then wait.** If work I want is uncommitted, tell me to merge it in Unharvester first. Don't do that from this session.

**3.2 New repo.** Create `C:\Users\jerry\Desktop\{{GAME_NAME}}`. Use `git archive <chosen commit>` to export the code, run `git init`, make one import commit, and add `ORIGIN.md` naming the source commit. Add no remote until I give you one, so nothing can be pushed into Unharvester's repo.

**3.3 New place.** Ask me to open a local copy of the place and save it as `{{GAME_NAME}}.rbxl` in the new folder. It must not be the Team Create place. `Backups\Unharvester7.rbxl` was the newest full copy on 2026-11-02, so check for a newer one. Then remove the scripts Rojo doesn't own and serve the repo into it.

**3.4 Cut the ties:**

- Rename both values of `STORE_NAME` in `SaveStore` to `{{GAME_NAME}}Players_v1`, keeping the `_Studio` suffix on the Studio one. Restart the save schema at version 1.
- Delete migration paths: `TitheConfig.OldCallCost`, `TitheConfig.fromBlight`, `legacyUpgrades`, and the notes about retired environment ids.
- Set every id in `MonetizationConfig` to 0 and confirm 0 means "not on sale yet" everywhere. Keep `KindredConfig.GroupId` at 0. Empty `PromoCodes` and `NewsConfig`.
- Every upload must set `ROBLOX_GRANT_UNIVERSE` to the new universe. `CharacterKit/roblox_upload.py` defaults to Unharvester's universe, so forgetting it grants new art to the wrong game.
- Telemetry's alerts read the experience secret `alert_webhook`, which belongs to one universe. Alerts stay off until I add it to the new one.

**3.5 Proof.** The fork boots in Studio and goes hub, party, site, back to hub with no new errors. It still looks like Unharvester at this point. Record the `luau-lsp` error baseline.

## 4. The new verb

### 4.1 Blueprint (replaces `FieldGrid` and `HandSown`)

A blueprint is a fixed list of slots held in flat arrays indexed by slot, as `CropField` does for plants. Each slot has a cell (integer x, y, z), a `kind` from the site's block palette, a `facing` from 0 to 3, and its `supports`: the slots that must be placed first. Store supports and their reverse, `dependents`, as flat offset-and-list arrays.

Supports default to the cell beneath, or a connected neighbour for an overhang. Authors can add extra ordering, such as walls before roof.

### 4.2 Slot states (`CropField` becomes `BuildSite`)

Keep `CropField`'s structure: `progress`, `rate`, `active`, `dirty`, `sentRate`, `spent`, `cause`, `causer`, `shield`, `bound`. Add `unmet[slot]`, the count of supports not yet placed, so nothing scans the whole site. Progress 1 now means placed.

| State | Meaning | Was |
|---|---|---|
| LOCKED | `unmet > 0`, can't be aimed at | no equivalent |
| READY | `unmet == 0`, progress 0, ghost shown | living plant |
| SETTING | progress rising by itself | infected plant |
| PLACED | progress 1, reduces `unmet` on its dependents | withered plant |
| UNDOING | negative rate, no longer counts as placed | growing back (`CropField.regrow`) |

These rules are invariants. Each one gets a test:

1. **Only READY or SETTING slots take a placement.** The server checks it the way `FieldService.wither` does: valid slot, within grasp plus slack in 3D, rate limit, recovered from cooldown.
2. **Nothing floats.** A block can be undone only if no placed block rests on it. A SETTING block whose support is undone drops back to LOCKED.
3. **A site can always be finished.** The authoring validator proves the blueprint has no cycles and connects to the ground. At runtime the boss stops before 100%, as the Tender's `relent` does.
4. **A block pays once** (`spent`), so undone blocks can't be farmed.
5. **No player gets trapped** (see 4.4).
6. **The server creates no Instance per block.** `FieldCodec` keeps its wire format as `SiteCodec`. Its u16 index caps a site at 65,535 blocks (`MAX_PLANTS`).

### 4.3 Input (`WitherController` becomes `PlaceController`)

Replace the aiming with a grid raycast from the camera through the blueprint. It takes the first READY slot within grasp, PLACED blocks stop the ray, and LOCKED slots are skipped. Keep everything else: the cooldown ring, the queued click, hold to place, auto-aim, touch tap, gamepad, and client prediction that rolls back if the server refuses.

### 4.4 Access

Default for `ACCESS`:

- Placed blocks are solid and walkable, and blueprints include steps where they need them.
- Each site has hoist pads that lift a player to the current working height. Falling costs nothing.
- The validator checks that every layer can be reached within base grasp from a surface a player can stand on.
- If a block lands in a character's cell, it still places and the client moves the character to the nearest free surface. A character stuck for 2 seconds is moved automatically.
- Mounts use the same collision. Pets ignore block collision and hop or fly to their targets.

### 4.5 Drawing (`FieldRenderer` becomes `BuildRenderer`)

- **Same pattern:** client-only and pooled. A far chunk is one merged object, near chunks are individual pooled blocks, and the swap doesn't pop.
- **Prove the block count.** The Long Field's 51,984 plants work because they're baked patches without collision. Solid blocks are a different problem, so don't assume the same number holds. Stress test in Phase 2 on Low at a phone viewport, and set each site's ceiling from what you measure.
- **Collision:** client-only invisible boxes, greedy-merged per near chunk and rebuilt on a budget. Each character is moved by its own client, so this is enough for walking.
- **Ghosts:** the finished build always shows as one faint silhouette, so players can see what they're making. READY slots near the player pulse.
- **Placement feel:** the block drops in over about 0.15 s with a small squash, dust, and a tick whose pitch climbs during a fast chain. This plays near the camera only. Far blocks just appear, and mass placements are budgeted per frame.

### 4.6 Authoring

Build `tools/stamp_blueprint.luau`. It reads a Studio Model of grid-aligned parts, or a script-generated list, and writes `shared/Blueprints/<Site>.luau` as a compact string. The same tool validates: no cycles, connected to the ground, no overlaps, reachable, at most 65,535 blocks.

In this version every block fills one cell. It can look like a wedge or stair, but multi-cell pieces come later.

### 4.7 End of a run

Keep `claimTithe`, `TitheConfig.split` (each player's share follows the blocks they placed), the next-site and difficulty unlocks, and `MoveOn`. `Ending` becomes a ten-second timelapse of the build rising in the order it was placed, using `placedAt` (was `diedAt`). `WorldDecay` is driven by percent built and moves from a `start` look to a `finished` look, following `WORLD_ARC`.

## 5. What each old system becomes

### 5.1 Skills

Keep `GameRun`, `UpgradeService`, the `UpgradeTree` window, each player's own tree and purse, join-in-progress at the average purse, and the shape of the price curve. Rename the nodes and map their effects:

| Unharvester stat | New stat | Meaning |
|---|---|---|
| `rotTime`, `cooldown` | `setTime`, `cooldown` | wait between placements, pace of passive setting |
| `stalks` | `batch` | blocks per click: the one aimed at plus the nearest READY |
| `grasp` | `grasp` | reach from the player, measured in 3D |
| `autoAim`, `holdWither` | `autoAim`, `holdPlace` | same |
| `critChance`, `critReward` | `perfectChance`, `perfectReward` | a perfect placement pays extra |
| `spreadChance`, `spreadRadius` | `chainChance`, `chainRadius` | a click may start nearby READY slots SETTING |
| `swarmWidth`, `swarmSpeed`, `swarmDuration`, `swarmCooldown` | `crewWidth`, `crewSpeed`, `crewDuration`, `crewCooldown` | `ABILITY` sweeps a band across the site at every height |
| `yield`, `yieldMult` | same | pay per block |
| `reach` | `petReach` | blocks around a pet's target that it also places |

Today's tree grants only these stats, apart from the base-only `cooldown`, `grasp`, `reach`, `yield` and `yieldMult`. Delete the dormant ones (`burst*`, `auraRadius`, `contagion`, `sporeCount`, `sickle*`, `hurl*`) along with their code paths.

`POWER_TOOL` keeps the Void Scythe's behaviour: a second hand on its own cooldown that places everything READY in an arc and starts a band past it SETTING.

### 5.2 Pets

The system stays whole. Only targets, words and models change.

- `bonus.blight`, `bonus.speed` and `bonus.burst` become `bonus.pay`, `bonus.speed` and `bonus.ability`.
- `forage`: the pet runs to the nearest READY slot within `leash`, places it and everything within reach, starts `rotRing` (now `setRing`) SETTING, then rests. Change the search in `ForageService` to 3D.
- Keep the Cinderfall pattern for pets with a timed `ability`.
- Keep rarities including egg-only Secret, odds shown before every roll, slots and their prices, fusion, `exclusive`, mutation skins, `Index`, `Fold`, the roll page and reveal, eggs, `PetShop`.
- New roster: same count per rarity and the same numbers as today, so the balance carries over and can be tuned afterwards. Use Unharvester's models as placeholders until Phase 5. Build new ones with the `CharacterKit` pipeline (`AssemblePet.luau`).

### 5.3 Boss (`Tender*` become `Boss*`)

My rule, and it isn't negotiable: **difficulty gives players things to go and do. It never adds tougher blocks or longer waits.** Don't use `rotTimeMult`-style multipliers for difficulty.

| Tender | Boss | Unlocks at |
|---|---|---|
| Rises at a percentage, mends plants, shooed when a hand comes near, gives up near the end | Rises at a percent built, undoes exposed blocks, same shooing and `relent` | Normal |
| Mother Sheaf: ripens on a fuse and revives a radius, a hand breaks it for a bounty | A marker that undoes a radius of exposed blocks when its fuse ends, broken for a bounty | Normal |
| Golden Wheat: only a hand's own touch takes it | A band of stubborn slots only a player's click can place | Hard |
| Peace: nothing withers inside a circle until he's shooed out | A circle where nothing can be placed until the boss is shooed out | Hard |
| Binding Roots: three far corners, the field is bound until all are broken | Same, the site is `bound` until all three are broken | Hard |
| Straw Helpers: minions that wander and mend | Minions that wander and undo exposed blocks | Nightmare |
| Great Mend and Last Harvest | A section collapse, and a final stand in place of relenting | Nightmare |
| Strike and Smother: a struck hand can't act for a while | Same, reskinned | Nightmare |

Hard must measurably differ from Normal. In Unharvester it doesn't (solo real-time runs of 37:51 against 37:24), so measure this rather than inheriting the tuning.

### 5.4 Co-op

Keep `PartyPressure` and its curves. Edge regrowth becomes exposed blocks being undone when several players work a site. Targets from Unharvester: 2, 3 and 4 players finish in about 0.51, 0.36 and 0.27 of the solo time and each earns about the solo rate per minute.

## 6. Fate of every module

**Keep, words and art only:**

- Foundation: `Main` (client and server, rewired as modules change), `Net`, `Format`, `Config`, `SaveStore`, `SaveService`, `PlayerDataService`, `Telemetry`, `TesterService`, `Admin`, `Flight`, `TestSpeed`, `Boot`, `Loading`, `LoadingScreen`, `Sfx`, `SfxSheet`, `SoundAssets`, `KeyframeClip`, `MeshLibrary`, `MeshAssets`, `Footsteps`
- Interface: `Ui`, `Hud`, `Device`, `Prompts`, `Overlay`, `Talk`, `UiMode`, `UiToggle`, `Settings`, `SettingsWindow`, `SettingsConfig`, `StartCard`, `Travel`, `MoveOn`, `Inspect`, `Almanac`, `ScreenClaim`
- Parties and runs: `PartyService`, `FieldServers`, `PlotService`, `PlotLayout`, `PlotTemplates`, `GameRun`, `UpgradeService`, `UpgradeTree`, `FieldTally`, `Stats`
- Pets: `PetService`, `PetsWindow`, `PetRenderer`, `PetModel`, `PetShop`, `PetShopWindow`, `EggService`, `Eggs`, `EggModel`, `EggChip`, `Fold`, `Index`, `RollWindow`, `RollReveal`, `RollScene`, `ShrineWake`, `ShrineCall`
- Mounts and outfits: `MountService`, `MountController`, `MountRenderer`, `MountModel`, `Stable`, `StableWindow`, `AshCall`, `WardrobeService`, `OutfitRenderer`
- Economy and retention: `MonetizationService`, `Shop`, `MoontearService`, `MoontearDrop`, `WatchService`, `Watch`, `TaskService`, `Tasks`, `AchievementService`, `Achievements`, `LeaderboardService`, `LeaderboardBoards`, `Leaderboards`, `News`, `NewsService`, `Kindred`, `KindredService`, `PromoService`, `PromoCodes`, `BloodMoonService`, `BloodMoon`, `FactionService`, `Faction`

**Reskin, new words, numbers and art:**

- Configs: `PetConfig`, `IndexConfig`, `MountConfig`, `EggConfig`, `OutfitConfig`, `TitheConfig`, `MoontearConfig`, `MonetizationConfig`, `TaskConfig`, `AchievementConfig`, `LeaderboardConfig`, `TallyConfig`, `BloodMoonConfig`, `CinderfallConfig`, `WatchConfig`, `FactionConfig`, `NewsConfig`, `LoreConfig`, `KindredConfig`, `EnvironmentConfig`, `WeatherConfig`, `DifficultyConfig`, `TenderConfig`, `UpgradeConfig`, `ScytheConfig`, `SwarmConfig`
- Behaviour with theme in it: `Hub`, `HubPlan`, `HubMountains`, `Landscape`, `SceneryRenderer`, `Standards`, `WorldDecay`, `Atmos`, `Soundscape`, `Ending`, `Journal`, `Notes`, `LoreService`, `FieldTutorial`, `BloodMoonCutscene`, `TenderCutscene`, `Scythe`, `ScytheModel`, `ScytheOffer`, `LocustSwarm`, `WitherVfx`, `Cinderfall`, `CinderfallService`, `Smother`

**Replace, new behaviour behind the same role:**

| Old | New | Notes |
|---|---|---|
| `CropField` | `BuildSite` | 4.2 |
| `FieldGrid`, `HandSown` | `Blueprint` | 4.1 |
| `FieldCodec` | `SiteCodec` | same wire format |
| `FieldService` | `SiteService` | tick, sessions, hands, pay and tally stay; strike paths change |
| `FieldRenderer`, `CropMeshes` | `BuildRenderer`, `BlockMeshes` | 4.5 |
| `WitherController` | `PlaceController` | 4.3 |
| `ForageService` | same name | 3D targets |
| `Tender`, `TenderBlessing`, `TenderHarvest`, `TenderHelpers`, `TenderSheaves` | `Boss*` | 5.3, on both server and client |
| `Bots`, `tools/sim` | same names | bots aim at READY slots, the sim models supports |

**Cut for version 1. They are tied to the old theme, and you can ask me about any of them later:**

- Crop and wind: `CropParting`, `Gusts`, `GustDebris`, `SceneryLean`, `SceneryWind`, `TreeSway`, `Windmill`, `Signpost`, `Ravens`, `RavenConfig`, `FieldStill`, `FieldOverHub`, `GreatScale`
- Old weapons and effects: `Sickle`, `SickleConfig`, `CorpseCandles`, `SmotherStraw`, `SporeBurst`
- Old cast: `War`, `WarDuel`, `WarConfig`, `Conquest`, `ConquestConfig`, `Death`, `DeathConfig`, `Horseman`, `HorsemanConfig`, `Horsemen`, `Witch`, `WitchConfig`, `Cauldron`, `CauldronFx`, `CauldronWindow`, `LobbyIntro`, `IntroCutscene`
- Old buildings: `Barn`, `AbbeyPlan`, `AbbeyKit`, `RuinKit`, `HouseKit`, `HouseMeshes`, `VillagePlan`, `HubHamlet`, `HubWoods`, `Eclipse`
- Baked mesh data: everything under `client/Meshes` (crop patches, crop layouts, village and scenery meshes), except `client/Meshes/Pets.luau` until the new roster replaces it

If a module isn't listed or a cut module turns out to be needed, say so at the next gate. Don't quietly keep or delete it.

**Don't inherit these bugs:**

- The premium-currency drop roll sits inside `if #shown > 0` in `FieldService`, around line 1193, so it only runs on critical steps. With base `critChance` 0, no drops happen. Run it once per step on first placements.
- Go through sections A and C of `LAUNCH_CHECKLIST.md` and fix whatever still applies.

**Renaming:** do it module by module with `luau-lsp` after each. Never use a blind global replace, because `plant`, `field` and `crop` appear inside unrelated names.

## 7. Phases

Build mechanics before art. Unharvester's art stays as a placeholder until Phase 5, in Studio only.

| Phase | Work | Proof |
|---|---|---|
| 0 | Fork (section 3) | **GATE** at 3.1, boot test at 3.5 |
| 1 | `Blueprint`, `BuildSite`, `SiteCodec`, validator, one test blueprint | Random-order test of 10,000+ placements and undos with no invariant broken; codec round trip |
| 2 | `BuildRenderer`, `PlaceController`, access, one graybox site of `FIRST_SITE_BLOCKS`, pay and finish | **GATE:** I play it and judge the click. Report the stress-test ceiling on Low at phone size |
| 3 | Skill tree, `ABILITY`, `POWER_TOOL`, pets, HUD, tally, counts for tasks and achievements, bots, sim | Sim and a real bot run land within 10% of `FIRST_RUN_MINUTES`, and every pet rarity works |
| 4 | Boss, difficulties, co-op | 20 seeded bot runs all finish, Hard differs from Normal, co-op ratios near 5.4, tested with two real clients in Local Server |
| 5 | Neutral names, `Theme`, and a look: one hub corner, one site, five icons, one pet | **GATE:** I approve the look before any batch generation or upload |
| 6 | All `SITES`, roster, mounts, hub, lore, tutorial, sounds, news. Remove the placeholders and cut modules | No old theme word in player-facing text, checked by a scan. No Unharvester asset id left unless I chose to keep it |
| 7 | Products, passes, group, secrets, asset grants, phone pass, launch checklist rewritten for this game | **GATE:** publishing is mine to do |

## 8. Lessons already paid for

- **Moderation:** Roblox warned the upload account for gore over a red-smeared icon. Look at every image before uploading: no red stains, drips, wounds or flesh. Upload one at a time, riskiest last, and recheck after a minute. If you see "User is moderated", stop and tell me. Don't try another account or route.
- **Grants:** assets must be granted to the new universe or live servers can refuse them, and Studio hides this because it's more lenient. Unharvester's standing permission covers its own universe only, so ask me first. Use `CharacterKit/asset_ids.luau` and `CharacterKit/grant_universe.py`.
- **Image ids:** an Open Cloud Decal upload returns a decal id that ImageLabels can't load. Get the image id with `game:GetObjects("rbxassetid://<decalId>")[1].Texture`, and grant both.
- **Preloading:** `PreloadAsync` skips SurfaceAppearance maps. Run `tools/stamp_maps.luau` after adding or retexturing models.
- **Published-only paths:** reserved-server teleports and MemoryStore tickets can only be proven in a published game. Team Test exercises the in-place plots instead. Studio simulates a field server with the `DebugFieldServer` workspace attribute.
- **Testing:** use workspace attributes `BotPlayers` and `TestSpeed` (max 5), and the debug hooks on the server's `Main`. Compare one ×5 run against real time before trusting ×5. The Studio MCP `screen_capture` can ignore the client camera in Play and blank viewports, so check on screen when it matters.
- **Rojo syncback:** children with duplicate names pack the parent into one `.rbxm`, and a module stored as a single file silently drops its children. Always dry-run. Since rule 3 makes Rojo one-way, you shouldn't need syncback at all.
- **Tooling:** this PC uses Aftman, not Rokit. Working trees are CRLF, so run StyLua with `--line-endings Windows`.

## 9. Done means

- A new player goes hub, party, site, finished build, back to hub, on PC and phone, with no reference to Unharvester anywhere they can see.
- Every system in section 6's Keep list works in Studio under the new theme.
- Every invariant in 4.2 has a passing test, and the numbers from 7 are in your final report.
- Everything that couldn't be tested outside a published game is listed for me, along with what I need to set up on Creator Hub.
