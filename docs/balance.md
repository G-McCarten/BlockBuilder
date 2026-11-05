# Balance

What the run sim (`tools/sim`) measures about the economy and the boss, and the exact commands that reproduce each table. Every number comes from bots (`BotBrain`) playing whole runs through `SiteSession` at a 0.1 s step, solo unless a table says otherwise, over seeds 1 to 20. A run is deterministic for its seed, so the commands print these numbers exactly.

Bots buy the cheapest skill level they can afford unless a table says they buy by value (`--buy value`, below). Run every command from the repo root.

The sites were measured on their current blueprints: WoodcuttersLodge 5,928 blocks, IceBridge 7,459, Watchtower 9,617 and GreatHall 12,333. When a blueprint changes, its rows change too, so rerun them.

## Sites by difficulty

Minutes to finish, mean (fastest to slowest) over 20 runs each, and how much longer than with no boss. Every run finished.

| site | no boss | Normal | Hard | Nightmare |
|---|---|---|---|---|
| WoodcuttersLodge | 29.6 (28.4 to 30.4) | 32.1 (29.6 to 34.4), +9% | 34.6 (31.7 to 38.6), +17% | 38.8 (34.3 to 43.9), +31% |
| IceBridge | 32.5 (31.6 to 33.1) | 34.8 (33.3 to 35.9), +7% | 37.4 (34.8 to 41.1), +15% | 50.0 (45.2 to 66.1), +54% |
| Watchtower | 37.6 (35.9 to 39.7) | 40.2 (37.5 to 42.7), +7% | 44.1 (39.3 to 59.6), +17% | 48.4 (44.1 to 55.4), +29% |
| GreatHall | 43.2 (39.7 to 45.0) | 43.5 (39.2 to 45.8), +1% | 46.6 (42.4 to 55.3), +8% | 52.8 (46.5 to 62.1), +22% |

```bash
lune run tools/sim/run -- --site all --boss all --seeds 20
```

That runs 320 runs in one process, about five minutes. One site at a time, which you can run side by side:

```bash
lune run tools/sim/run -- --site WoodcuttersLodge --boss all --seeds 20
```

Before this tuning, the same 20 seeds gave Normal no longer than no boss on the Watchtower (37.4 both), Nightmare barely above Hard on the GreatHall (49.9 against 49.2 over 10 seeds), and Watchtower runs from 36 to 80 minutes on Hard and Nightmare. With a peace circle at every stop, the redesigned Ice Bridge took 53.6 minutes on Hard (+65%) and 68.2 on Nightmare (+110%), one run 117.6.

Normal costs the Great Hall almost nothing (+1%). Its blocks are spread over a big footprint, so the boss's mending lands where a click's batch soon lays the gaps again.

## Bots that buy by value

`--buy value` makes bots save for the skill level that adds the most pay a second for its price, by `BotBrain.earning`'s rough model of their play. Same seeds:

| site | no boss | Normal | Hard | Nightmare |
|---|---|---|---|---|
| WoodcuttersLodge | 20.4 (20.2 to 20.6) | 21.2 (20.2 to 22.8), +4% | 23.4 (21.9 to 25.4), +14% | 26.7 (23.5 to 32.8), +31% |
| IceBridge | 24.3 (23.7 to 24.9) | 26.3 (25.3 to 28.3), +9% | 28.7 (26.2 to 34.9), +18% | 35.4 (31.9 to 43.9), +46% |
| Watchtower | 27.7 (26.4 to 28.5) | 29.7 (28.0 to 32.8), +7% | 34.0 (31.0 to 43.0), +23% | 38.7 (32.5 to 47.4), +40% |
| GreatHall | 32.5 (31.5 to 33.3) | 33.3 (30.5 to 35.8), +3% | 36.7 (32.8 to 40.2), +13% | 41.1 (36.2 to 58.0), +26% |

```bash
lune run tools/sim/run -- --site all --boss all --seeds 20 --buy value
```

Buying by value finishes every site 25 to 31% sooner with no boss: the lodge in 20.4 minutes, not 29.6. The skill tree in `SkillTuning` is tuned so cheapest-first bots take about 30 minutes, and a player who buys sensibly beats that by a third. Cheapest first buys the setTime node first, which only hurries a chain's blocks, and the ability last. Retune the tree against value-buying bots, or against both, when it comes from the fork. The order of the difficulties holds either way.

## Co-op

The lodge on Normal, by party size, with what each player's share of the site's payout (`SiteList` payout, split by `SiteSession.shares`) pays per minute played:

| players | time | of the solo time | payout a minute, each (lowest to highest) | of the solo rate |
|---|---|---|---|---|
| 1 | 32.1 min | 1.00 | 3.11 | 1.00 |
| 2 | 16.3 min | 0.51 | 3.07 (2.74 to 3.32) | 0.99 |
| 3 | 11.1 min | 0.34 | 3.02 (2.50 to 3.46) | 0.97 |
| 4 | 8.5 min | 0.26 | 2.96 (2.58 to 3.70) | 0.95 |

Unharvester's targets are 0.51, 0.36 and 0.27 of the solo time, with each player earning about the solo rate. With no boss the ratios are 0.54, 0.37 and 0.28, and each player earns 0.93, 0.89 and 0.89 of the solo rate.

```bash
lune run tools/sim/run -- --coop --pay --boss Normal --seeds 20
```

```bash
lune run tools/sim/run -- --coop --pay --seeds 20
```

## Blocks per click

What a click placed itself (the aimed block and its batch) by minute on the lodge with no boss: the mean over runs of each minute's median, the mean over every click, and the mean counting the blocks its chains set going.

| minute | runs | built | median | mean | with its chains |
|---|---|---|---|---|---|
| 1 | 20 | 1% | 1.0 | 1.0 | 1.0 |
| 5 | 20 | 6% | 1.0 | 1.0 | 1.0 |
| 10 | 20 | 18% | 2.0 | 2.0 | 2.0 |
| 15 | 20 | 34% | 3.0 | 2.7 | 2.9 |
| 20 | 20 | 57% | 2.6 | 2.7 | 2.7 |
| 25 | 20 | 79% | 2.9 | 2.8 | 2.9 |
| 30 | 16 | 100% | 2.6 | 2.8 | 2.9 |

The median click tops out at 3.2 blocks, at minute 27. Bots buying by value reach 4.0 at minute 8, then fall back to 2 to 3 as their ability's band takes the easy work.

```bash
lune run tools/sim/run -- --seeds 20 --clicks
```

```bash
lune run tools/sim/run -- --seeds 20 --clicks --buy value
```

The formula wants skills to stack "until one click does the work of dozens". This tree gets nowhere near that:

- The batch rarely fills. At batch level 4 a click may place 5 blocks, but within a grasp of 5 cells there are seldom 4 more READY slots.
- Chains add almost nothing, 0.1 to 0.2 blocks a click. When one starts, only 1% to 3% of the cells in its radius are READY, because the click's batch has just taken the nearest.

Reaching dozens needs reach to grow with the tree (grasp is base-only today), or chains that pick up SETTING and LOCKED neighbours. That's a change to `SkillTuning` and `SiteActions`.

## When skills are bought

The mean minute each level was bought on the lodge with no boss. "Not bought" means no run got that far.

Cheapest first:

| skill | level 1 | level 2 | level 3 | level 4 | level 5 |
|---|---|---|---|---|---|
| batch | 5.7 | 11.1 | 17.3 | 25.9 | not bought |
| chain | 6.9 | 13.7 | 20.3 | 28.0 | not bought |
| setTime | 1.8 | 8.2 | 12.4 | 18.7 | |
| perfect | 3.8 | 9.6 | 16.0 | 22.1 | |
| crew | 15.1 | 24.0 | not bought | not bought | |

By value:

| skill | level 1 | level 2 | level 3 | level 4 | level 5 |
|---|---|---|---|---|---|
| batch | 2.2 | 3.9 | 6.8 | 10.3 | 16.8 |
| chain | not bought | not bought | not bought | not bought | not bought |
| setTime | not bought | not bought | not bought | not bought | |
| perfect | 7.2 | 10.9 | 14.6 | not bought | |
| crew | 5.5 | 8.9 | 13.5 | not bought | |

```bash
lune run tools/sim/run -- --seeds 20 --skills
```

```bash
lune run tools/sim/run -- --seeds 20 --skills --buy value
```

## Run currency

Held and earned in all by minute on the lodge with no boss, cheapest first. A bot spends nearly all it earns as it goes. A run earns about 6,800, and the whole tree costs about 11,200.

| minute | held | earned |
|---|---|---|
| 1 | 74 | 74 |
| 5 | 99 | 379 |
| 10 | 66 | 1,116 |
| 15 | 170 | 2,233 |
| 20 | 342 | 3,800 |
| 25 | 374 | 5,293 |
| 30 | 444 | 6,823 |

```bash
lune run tools/sim/run -- --seeds 20 --purse
```

## Boss undo rates

Placed blocks the boss and its works undid per run, and per minute over the minutes from its rise to its relenting. "Nearest" is the boss and its minions undoing the exposed blocks nearest them, "markers" the markers whose fuse ran out, and "collapses" the collapses.

| site | difficulty | undone per run | a minute while up | nearest | markers | collapses |
|---|---|---|---|---|---|---|
| WoodcuttersLodge | Normal | 1,022 | 51 | 996 | 26 | 0 |
| WoodcuttersLodge | Hard | 1,346 | 61 | 1,309 | 37 | 0 |
| WoodcuttersLodge | Nightmare | 2,584 | 97 | 2,394 | 34 | 156 |
| IceBridge | Normal | 607 | 29 | 432 | 175 | 0 |
| IceBridge | Hard | 911 | 39 | 714 | 196 | 0 |
| IceBridge | Nightmare | 3,044 | 85 | 2,623 | 273 | 148 |
| Watchtower | Normal | 1,671 | 71 | 1,547 | 124 | 0 |
| Watchtower | Hard | 2,158 | 81 | 1,978 | 180 | 0 |
| Watchtower | Nightmare | 3,387 | 107 | 2,976 | 228 | 182 |
| GreatHall | Normal | 793 | 33 | 602 | 191 | 0 |
| GreatHall | Hard | 1,011 | 38 | 823 | 189 | 0 |
| GreatHall | Nightmare | 2,461 | 73 | 2,034 | 261 | 166 |

By minute on the lodge, as blocks undone a minute:

| minute | Normal | Hard | Nightmare |
|---|---|---|---|
| 10 | 0 | 0 | 0 |
| 15 | 45 | 63 | 70 |
| 20 | 57 | 38 | 121 |
| 25 | 58 | 52 | 88 |
| 30 | 56 | 78 | 119 |
| 35 | | 20 | 108 |
| 40 | | | 46 |

```bash
lune run tools/sim/run -- --site all --boss all --seeds 20 --undo
```

## How the boss was balanced

The rule from the formula holds: difficulty gives players things to go and do, and never adds tougher blocks or longer waits. The sim showed why the old tuning cost some sites nothing and others a great deal:

- **Undoing next to the work costs little.** A click's batch usually has room for a gap or two, so blocks the boss undoes beside a player are laid again almost free. On a compact site, the Watchtower above all, the boss only costs time once it undoes faster than that. So Normal mends 4 blocks at a time within 5 cells, and Hard 6.
- **Trips cost long sites and help compact ones.** On the IceBridge a bot clicks steadily, 73 to 75 times a minute, so every walk to a marker or to shoo the boss is time lost. On the Watchtower a greedy bot works less well with no boss, and the walks land it by fresh work: a boss that undid nothing at all made the Watchtower a minute faster. Markers now come every 90 seconds, not 45.
- **The stubborn band was a lottery.** It runs across the site at every height, so where it lay along a wall it took up to 18% of the Watchtower's slots, and everything resting on them waited for single clicks. That one feature was nearly all of Hard's cost and all of its spread. It now comes at 60% built and is 2 cells wide.
- **A peace circle comes at most once a minute.** The boss works the exposed spot farthest from the players, so on the long Ice Bridge a circle stood about 50 cells from the bot, against 20 on the lodge. With a circle at every stop, the bot spent a third of a Hard run walking to them: 122 circles in a 63-minute run, about 10 seconds each. On the lodge the same walks cross fresh work, so they cost almost nothing. With `peace.every` at 60 seconds, a stop sooner than that raises no circle, and Hard costs 8 to 17% on every site. Keeping the boss's spots near the players instead didn't help: it came back sooner, and its circles fell on the players' own work. Neither did keeping Nightmare's minions near the boss.
- **Minions keep a reach of 3.** At 4, on the 508-block TestHut, the boss and its minions undid about as fast as a fresh player lays, and a solo Nightmare run stalled for over an hour. A block laid again pays nothing, so the player never earned the skills to get out. Nightmare's extra bite comes from a fourth minion and a final stand of 6 shoos instead.

The tuning in `src/shared/BossConfig.luau`:

| | Normal | Hard | Nightmare |
|---|---|---|---|
| rises at, relents at | 20%, 95% | same | same |
| mends | 4 blocks within 5 cells every 2.5 s | 6 blocks | 6 blocks |
| markers | every 90 s, fuse 20 s, radius 4 | same | same |
| stubborn band | | at 60%, 2 cells wide | same |
| peace circle | | radius 5, at most once a minute | same |
| bindings | | at 55%, cap 80% | same |
| minions | | | 4, every 4 s, reach 3 |
| collapses | | | at 40% and 70%, 8 cells, 120 blocks |
| strikes | | | every 12 s, radius 4, 3 s |
| final stand | | | 6 shoos |

## What the sim can't say

- The Ice Bridge on Nightmare is the costliest run, +54%. Its minions cost the most there: without them it takes 40.2 minutes, not 49.4, over 10 seeds.
- It measures bots, not players. The bots aim perfectly, shoo the boss when it works within 20 cells, break every marker within 30 and never dodge a strike. Strikes cost them almost nothing.
- It plays one tick rate (0.1 s) and no latency.
- `PartyPressure` isn't modelled, so co-op has no extra pressure from the boss.
