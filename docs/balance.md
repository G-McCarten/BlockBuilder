# Balance

What the run sim (`tools/sim`) measures about the economy and the boss, and the exact commands that reproduce each table. Every number comes from bots (`BotBrain`) playing whole runs through `SiteSession` at a 0.1 s step, solo unless a table says otherwise, over seeds 1 to 20. A run is deterministic for its seed, so the commands print these numbers exactly.

Bots buy the cheapest skill level they can afford unless a table says they buy by value (`--buy value`, below). Run every command from the repo root.

The sites were measured on their current blueprints: WoodcuttersLodge 20,008 blocks, IceBridge 26,130, Watchtower 33,108 and GreatHall 41,750. Their sizes are provisional until the stress test, and when a blueprint changes its rows change too, so rerun them.

## Sites by difficulty

Minutes to finish, mean (fastest to slowest) over 20 runs each, and how much longer than with no boss. Every run finished.

| site | no boss | Normal | Hard | Nightmare |
|---|---|---|---|---|
| WoodcuttersLodge | 29.4 (29.3 to 29.4) | 29.7 (29.4 to 30.2), +1% | 33.0 (31.9 to 34.6), +12% | 36.0 (34.5 to 38.2), +23% |
| IceBridge | 32.4 (32.1 to 32.6) | 32.8 (32.3 to 33.2), +1% | 37.6 (34.4 to 40.0), +16% | 42.6 (39.1 to 46.5), +32% |
| Watchtower | 35.9 (35.8 to 36.3) | 36.3 (35.9 to 36.5), +1% | 41.4 (38.1 to 45.5), +15% | 48.1 (43.3 to 51.8), +34% |
| GreatHall | 40.4 (40.3 to 40.6) | 40.7 (40.5 to 41.2), +1% | 48.9 (44.4 to 53.0), +21% | 55.1 (51.3 to 61.4), +36% |

```bash
lune run tools/sim/run -- --site all --boss all --seeds 20
```

That's 320 runs in one process. One site at a time, which you can run side by side:

```bash
lune run tools/sim/run -- --site WoodcuttersLodge --boss all --seeds 20
```

Normal costs almost nothing. Late in a run a click lays 32 blocks, the nearest workable ones anywhere on the site, so whatever the boss undid is laid again with the fresh work. Hard and Nightmare cost through their stubborn band, whose slots each need a click of their own, and through errands. Bigger sites pay more at the same difficulty: see "How the boss was balanced".

## Bots that buy by value

`--buy value` makes bots save for the skill level that adds the most pay a second for its price, by `BotBrain.earning`'s rough model of their play. Same seeds:

| site | no boss | Normal | Hard | Nightmare |
|---|---|---|---|---|
| WoodcuttersLodge | 26.9 (26.9 to 26.9) | 27.2 (26.8 to 27.5), +1% | 30.6 (29.1 to 32.9), +14% | 33.0 (31.4 to 35.6), +23% |
| IceBridge | 29.9 (29.9 to 29.9) | 30.2 (29.9 to 30.6), +1% | 35.4 (32.3 to 38.3), +18% | 40.5 (37.2 to 43.9), +35% |
| Watchtower | 33.6 (33.6 to 33.6) | 33.7 (33.4 to 34.1), +0% | 38.5 (35.3 to 41.8), +15% | 46.6 (43.9 to 48.3), +39% |
| GreatHall | 37.7 (37.7 to 37.7) | 38.0 (37.6 to 38.5), +1% | 47.4 (42.4 to 51.0), +26% | 52.1 (47.0 to 58.9), +38% |

```bash
lune run tools/sim/run -- --site all --boss all --seeds 20 --buy value
```

Buying by value finishes every site 7 to 9% sooner with no boss: the lodge in 26.9 minutes, not 29.4. Before the tree was rebuilt, a sensible buyer beat cheapest first by a third. A first try at a stacked tree let one finish in 11.2 minutes (see "Blocks per click"). The order of the difficulties holds either way.

## Co-op

The lodge on Normal, by party size, with what each player's share of the site's payout (`SiteList` payout, split by `SiteSession.shares`) pays per minute played:

| players | time | of the solo time | payout a minute, each (lowest to highest) | of the solo rate |
|---|---|---|---|---|
| 1 | 29.7 min | 1.00 | 3.36 | 1.00 |
| 2 | 15.0 min | 0.50 | 3.34 (3.24 to 3.45) | 0.99 |
| 3 | 10.0 min | 0.34 | 3.34 (2.93 to 3.54) | 0.99 |
| 4 | 7.6 min | 0.26 | 3.27 (3.02 to 3.55) | 0.97 |

Unharvester's targets are 0.51, 0.36 and 0.27 of the solo time, with each player earning about the solo rate. With no boss the ratios are 0.51, 0.34 and 0.26, and each player earns 0.98, 0.97 and 0.97 of the solo rate.

```bash
lune run tools/sim/run -- --coop --pay --boss Normal --seeds 20
```

```bash
lune run tools/sim/run -- --coop --pay --seeds 20
```

Bots in a party leave work a teammate could lay from where they stand to that teammate. With dozens a click, bots that all headed for the nearest slot ended up on one spot, and 4 players took 0.29 of the solo time with each paid 0.85 of the solo rate. Players can't stand in one another, so a party spreads out.

## Blocks per click

What a click placed itself (the aimed block and its batch), minute by minute on the lodge with no boss: the share built, the mean over runs of each minute's median, and the mean over every click. Chains add almost nothing.

| minute | cheapest first: built | median | mean | by value: built | median | mean |
|---|---|---|---|---|---|---|
| 1 | 0% | 1.0 | 1.0 | 0% | 1.0 | 1.0 |
| 5 | 2% | 2.0 | 1.9 | 2% | 2.0 | 1.9 |
| 9 | 6% | 3.0 | 3.0 | 6% | 3.0 | 3.0 |
| 13 | 10% | 4.0 | 4.0 | 10% | 3.0 | 3.4 |
| 14 | 12% | 4.0 | 4.0 | 12% | 6.0 | 6.0 |
| 18 | 18% | 4.0 | 4.0 | 23% | 12.0 | 12.0 |
| 20 | 24% | 8.0 | 8.0 | 30% | 12.0 | 12.0 |
| 21 | 26% | 8.0 | 8.0 | 36% | 24.0 | 19.9 |
| 22 | 31% | 8.0 | 10.8 | 48% | 32.0 | 32.0 |
| 23 | 37% | 16.0 | 16.0 | 59% | 32.0 | 32.0 |
| 24 | 42% | 16.0 | 17.2 | 70% | 32.0 | 32.0 |
| 25 | 53% | 32.0 | 32.0 | 82% | 32.0 | 32.0 |
| 26 | 65% | 32.0 | 32.0 | 93% | 32.0 | 32.0 |
| 27 | 75% | 32.0 | 32.0 | 100% | 32.0 | 26.3 |
| 28 | 87% | 32.0 | 32.0 | | | |
| 29 | 97% | 32.0 | 30.8 | | | |
| 30 | 100% | 26.2 | 22.9 | | | |

The commands print every minute; the table leaves out minutes where nothing changed. The median click lays 32 blocks from minute 25 to the finish for a bot buying the cheapest skill first, and from minute 22 for one buying by value.

```bash
lune run tools/sim/run -- --seeds 20 --clicks --every 1
```

```bash
lune run tools/sim/run -- --seeds 20 --clicks --every 1 --buy value
```

The formula wants skills to stack "until one click does the work of dozens". This is how the tree gets there:

- **Two nodes stack the batch.** Armful adds a block a click a level, up to 4. Many Hands then doubles the batch a level, to 8, 16 and 32. It doubles the batch while its price grows by half, so a level is worth most once the batch is already big. Its first level turns one block into two, which Armful does for a quarter of the price, so no buyer gains by jumping ahead.
- **A batch takes the workable slots nearest the aimed one, anywhere on the site.** That's section 5.1's "the one aimed at plus the nearest READY". Late in a big build the work comes in patches far apart, such as the tops of towers, and a reach around the aimed slot left a big batch short. Only the aimed slot is checked against grasp plus slack.
- **The other nodes cost more than Many Hands' last level,** so cheapest-first bots buy them only after reaching 32, and they never delay it.
- **Why the sites grew.** A run earns about an Ember a block, and at 32 a click a bot lays about 2,100 blocks a minute. So dozens a click for the last 5 minutes of a 30-minute run need about half the site still unbuilt when the batch reaches 32. On the old 5,928-block lodge, the median click topped out at 4. A stacked tree tried there, with Many Hands at ×4 a level, gave cheapest-first bots dozens for only the last 2 minutes. Value buyers took Many Hands first and finished in 11.2 minutes. At about 20,000 blocks, both buying styles get 5 to 6 minutes of dozens.
- **The early run is slow by design.** Armful's 1,812 Embers, earned at 1 to 4 blocks a click, set how long the run lasts. A cheaper first level made the whole run faster.

## When skills are bought

The mean minute each level was bought on the lodge with no boss. "Not bought" means no run got that far.

Cheapest first:

| skill | level 1 | level 2 | level 3 | level 4 |
|---|---|---|---|---|
| batch (Armful) | 4.1 | 7.7 | 12.0 | |
| hands (Many Hands) | 18.8 | 21.6 | 23.9 | |
| chain (Mortar Run) | 27.7 | not bought | not bought | |
| setTime (Quick Set) | 29.0 | not bought | not bought | |
| perfect (True Eye) | 26.3 | not bought | not bought | |
| crew (Sled Train) | 15.8 | 25.2 | not bought | not bought |

By value:

| skill | level 1 | level 2 | level 3 | level 4 |
|---|---|---|---|---|
| batch (Armful) | 4.1 | 7.7 | 21.0 | |
| hands (Many Hands) | 12.8 | 17.0 | 20.3 | |
| chain (Mortar Run) | not bought | not bought | not bought | |
| setTime (Quick Set) | not bought | not bought | not bought | |
| perfect (True Eye) | 22.6 | 24.3 | not bought | |
| crew (Sled Train) | 21.5 | not bought | not bought | not bought |

```bash
lune run tools/sim/run -- --seeds 20 --skills
```

```bash
lune run tools/sim/run -- --seeds 20 --skills --buy value
```

Purchases are sparse: about a dozen a run, three of them in the first 12 minutes. Mortar Run and Quick Set do little for bots, and value buyers never buy them.

## Run currency

Held and earned in all by minute on the lodge with no boss, cheapest first. A bot spends nearly all it earns as it goes. A run earns about 20,400, and the whole tree costs 72,832, so a first run buys about a third of it and the later, bigger sites buy more.

| minute | held | earned |
|---|---|---|
| 1 | 75 | 75 |
| 5 | 142 | 442 |
| 10 | 528 | 1,368 |
| 15 | 864 | 2,676 |
| 20 | 714 | 4,726 |
| 25 | 2,356 | 10,681 |
| 30 | 592 | 20,442 |

```bash
lune run tools/sim/run -- --seeds 20 --purse
```

## Boss undo rates

Placed blocks the boss and its works undid per run, and per minute from its rise to its relenting. "Nearest" is the boss and its minions undoing the exposed blocks nearest them, "markers" the markers whose fuse ran out, and "collapses" the collapses.

| site | difficulty | undone per run | a minute while up | nearest | markers | collapses |
|---|---|---|---|---|---|---|
| WoodcuttersLodge | Normal | 643 | 63 | 541 | 102 | 0 |
| WoodcuttersLodge | Hard | 879 | 79 | 759 | 119 | 0 |
| WoodcuttersLodge | Nightmare | 1,257 | 94 | 1,020 | 129 | 108 |
| IceBridge | Normal | 380 | 35 | 309 | 71 | 0 |
| IceBridge | Hard | 655 | 55 | 589 | 66 | 0 |
| IceBridge | Nightmare | 1,054 | 74 | 796 | 77 | 181 |
| Watchtower | Normal | 539 | 47 | 332 | 206 | 0 |
| Watchtower | Hard | 641 | 52 | 477 | 164 | 0 |
| Watchtower | Nightmare | 1,052 | 73 | 747 | 186 | 118 |
| GreatHall | Normal | 702 | 50 | 471 | 230 | 0 |
| GreatHall | Hard | 883 | 59 | 702 | 180 | 0 |
| GreatHall | Nightmare | 1,280 | 74 | 931 | 196 | 153 |

By minute on the lodge, as blocks undone a minute:

| minute | Normal | Hard | Nightmare |
|---|---|---|---|
| 15 | 0 | 0 | 0 |
| 20 | 77 | 97 | 97 |
| 25 | 50 | 72 | 110 |
| 30 | | 76 | 113 |
| 35 | | | 17 |

```bash
lune run tools/sim/run -- --site all --boss all --seeds 20 --undo
```

The boss undoes 1 to 6% of a site's blocks per run. With a 32-block batch that costs little, as the first section explains.

## How the boss was balanced

The formula's rule holds: difficulty gives players things to go and do, and never adds tougher blocks or longer waits. What the sim showed:

- **Undoing costs little once batches are big.** A click's batch takes the nearest workable slots anywhere on the site, so it lays whatever the boss undid along with fresh work. Normal's mending adds about 1% to a run, however early the boss rises. On the lodge, rising at 10% or 6% built instead of 20% changed Normal by 0.1 to 0.4 minutes.
- **Stubborn slots cost the most.** Each one needs a player's own click, so a batch can't lay them. The band runs through every height, and where it fell at random, a tall wall or tower in its slab could hold thousands of slots. On the Great Hall, Hard took 42 to 59 minutes by seed, against 42 every time without the band.
  - Now the band's `share` picks a slab holding about that share of the site unbuilt, so it costs the same on every seed: 2% of the site on Hard, 3% on Nightmare.
  - A bigger site has more slots to a share, and a run that doesn't grow as fast. So the band costs a bigger site more: Hard is +12% on the lodge and +21% on the Great Hall.
- **Bots break every binding once the site is held.** Bindings hold the site at 80% until all three are broken.
  - Bots went for them only within 5 blocks of the cap. A big batch lays the boss's undoing again at once, so the count hovered just under the cap, and a bot kept turning back to lay. One lodge run sat at 80% for 15 minutes.
  - Now a bot held near the cap sets out and breaks every binding, as a player told the site is held would.
- **A peace circle comes at most once a minute.** The boss works the exposed spot farthest from the players, so on a long site a circle stood far from the bot. With a circle at every stop, the old Ice Bridge took 65% longer on Hard than with no boss.
  - With `peace.every` at 60 seconds, a stop sooner than that raises no circle.
  - Keeping the boss's spots near the players instead didn't help. The boss came back sooner, and its circles fell on the players' own work.
- **Minions keep a reach of 3.** At 4, on the 508-block TestHut, the boss and its minions undid about as fast as a fresh player lays, and a solo Nightmare run stalled for over an hour.
- **A finished site is finished.** Once the last block lands, bands and pets stop and the boss relents, even from Nightmare's final stand.

The tuning in `src/shared/BossConfig.luau`:

| | Normal | Hard | Nightmare |
|---|---|---|---|
| rises at, relents at | 20%, 95% | same | same |
| mends | 4 blocks within 5 cells every 2.5 s | 6 blocks | 6 blocks |
| markers | every 90 s, fuse 20 s, radius 4 | same | same |
| stubborn band | | at 60%, 2 cells wide, 2% of the site | 3% of the site |
| peace circle | | radius 5, at most once a minute | same |
| bindings | | at 55%, cap 80% | same |
| minions | | | 4, every 4 s, reach 3 |
| collapses | | | at 40% and 70%, 8 cells, 120 blocks |
| strikes | | | every 12 s, radius 4, 3 s |
| final stand | | | 6 shoos |

## What the sim can't say

- It measures bots, not players. The bots aim perfectly, shoo the boss when it works within 20 cells, break every marker within 30 and never dodge a strike. Strikes cost them almost nothing.
- Normal costs about 1% on every site. If playtests find it too gentle, its levers are the errands, markers and shooing, not the undoing.
- It plays one tick rate (0.1 s) and no latency.
- `PartyPressure` isn't modelled, so co-op has no extra pressure from the boss.
- Nobody has seen in Studio a click that lays its batch anywhere on the site. Late in a run, blocks will land far from the player as well as near them.
