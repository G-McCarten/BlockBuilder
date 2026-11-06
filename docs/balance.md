# Balance

What the run sim (`tools/sim`) measures about the economy and the boss, and the exact commands that reproduce each table. Every number comes from bots (`BotBrain`) playing whole runs through `SiteSession` at a 0.1 s step, solo unless a table says otherwise, over seeds 1 to 20. A run is deterministic for its seed, so the commands print these numbers exactly.

Bots buy the cheapest skill level they can afford unless a table says they buy by value (`--buy value`, below). Run every command from the repo root.

The sites were measured on their current blueprints: WoodcuttersLodge 5,928 blocks, IceBridge 7,459, Watchtower 9,617 and GreatHall 12,333. When a blueprint changes, its rows change too, so rerun them.

## Sites by difficulty

Minutes to finish, mean (fastest to slowest) over 20 runs each, and how much longer than with no boss. Every run finished.

| site | no boss | Normal | Hard | Nightmare |
|---|---|---|---|---|
| WoodcuttersLodge | 29.2 (28.8 to 30.1) | 32.7 (31.3 to 35.3), +12% | 35.2 (32.5 to 41.4), +21% | 38.8 (36.3 to 42.2), +33% |
| IceBridge | 32.2 (31.7 to 32.7) | 34.3 (33.1 to 36.6), +6% | 37.1 (35.2 to 42.7), +15% | 45.6 (40.7 to 51.6), +41% |
| Watchtower | 37.0 (35.4 to 38.6) | 40.1 (38.6 to 41.9), +8% | 45.4 (41.0 to 56.6), +23% | 51.5 (43.6 to 73.7), +39% |
| GreatHall | 41.2 (39.9 to 43.2) | 42.2 (40.6 to 43.4), +2% | 44.6 (40.6 to 47.3), +8% | 50.0 (45.6 to 57.3), +21% |

```bash
lune run tools/sim/run -- --site all --boss all --seeds 20
```

That runs 320 runs in one process, about five minutes. One site at a time, which you can run side by side:

```bash
lune run tools/sim/run -- --site WoodcuttersLodge --boss all --seeds 20
```

Before this tuning, the same 20 seeds gave Normal no longer than no boss on the Watchtower (37.4 both), Nightmare barely above Hard on the GreatHall (49.9 against 49.2 over 10 seeds), and Watchtower runs from 36 to 80 minutes on Hard and Nightmare. With a peace circle at every stop, the redesigned Ice Bridge took 53.6 minutes on Hard (+65%) and 68.2 on Nightmare (+110%), one run 117.6.

Normal costs the Great Hall almost nothing (+2%). Its blocks are spread over a big footprint, so the boss's mending lands where a click's batch soon lays the gaps again.

## Bots that buy by value

`--buy value` makes bots save for the skill level that adds the most pay a second for its price, by `BotBrain.earning`'s rough model of their play. Same seeds:

| site | no boss | Normal | Hard | Nightmare |
|---|---|---|---|---|
| WoodcuttersLodge | 19.5 (19.3 to 19.6) | 20.3 (19.2 to 21.3), +4% | 22.3 (20.0 to 29.6), +14% | 24.4 (22.9 to 31.3), +25% |
| IceBridge | 22.4 (22.3 to 22.8) | 24.2 (23.0 to 25.2), +8% | 26.0 (24.1 to 29.8), +16% | 31.6 (29.5 to 35.0), +41% |
| Watchtower | 26.7 (26.3 to 27.3) | 28.1 (26.9 to 30.3), +5% | 32.1 (27.5 to 39.5), +20% | 35.8 (30.4 to 48.0), +34% |
| GreatHall | 29.7 (28.7 to 30.6) | 31.1 (29.4 to 32.6), +4% | 33.2 (29.6 to 36.8), +12% | 37.1 (33.4 to 45.9), +25% |

```bash
lune run tools/sim/run -- --site all --boss all --seeds 20 --buy value
```

Buying by value finishes every site 28 to 33% sooner with no boss: the lodge in 19.5 minutes, not 29.2. The skill tree in `SkillTuning` is tuned so cheapest-first bots take about 30 minutes, and a player who buys sensibly beats that by a third. Cheapest first buys the setTime node first, which only hurries a chain's blocks, and the ability last. Retune the tree against value-buying bots, or against both, when it comes from the fork. The order of the difficulties holds either way.

## Co-op

The lodge on Normal, by party size, with what each player's share of the site's payout (`SiteList` payout, split by `SiteSession.shares`) pays per minute played:

| players | time | of the solo time | payout a minute, each (lowest to highest) | of the solo rate |
|---|---|---|---|---|
| 1 | 32.7 min | 1.00 | 3.06 | 1.00 |
| 2 | 16.4 min | 0.50 | 3.05 (2.83 to 3.30) | 1.00 |
| 3 | 11.1 min | 0.34 | 2.99 (2.74 to 3.23) | 0.98 |
| 4 | 8.5 min | 0.26 | 2.96 (2.63 to 3.58) | 0.97 |

Unharvester's targets are 0.51, 0.36 and 0.27 of the solo time, with each player earning about the solo rate. With no boss the ratios are 0.54, 0.38 and 0.28, and each player earns 0.93, 0.89 and 0.88 of the solo rate.

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
| 10 | 20 | 16% | 2.0 | 2.0 | 2.0 |
| 15 | 20 | 30% | 3.0 | 2.9 | 3.0 |
| 20 | 20 | 52% | 3.0 | 2.8 | 3.0 |
| 25 | 20 | 78% | 3.9 | 3.5 | 3.7 |
| 30 | 13 | 100% | 3.6 | 3.5 | 3.7 |

The median click tops out at 4.0 blocks, at minute 28. Bots buying by value reach 5.0 at minute 15, then fall back as their ability's band takes the easy work.

```bash
lune run tools/sim/run -- --seeds 20 --clicks
```

```bash
lune run tools/sim/run -- --seeds 20 --clicks --buy value
```

A click's batch takes the READY or SETTING slots nearest the aimed one, out to the player's grasp plus a cell for each block of the batch, wherever the player stands. Before, it only took slots within the player's own grasp of 5 cells, where there were seldom more than 3 or 4, so the batch rarely filled. With the wider reach, the same tree laid the lodge in 26.4 minutes, so every price was raised by a fifth to keep the run near 30.

The formula wants skills to stack "until one click does the work of dozens". This tree gets to 4. Dozens a click and a 30-minute run pull against each other on a site of about 6,000 blocks:

- Each block pays once, and a bot clicks about 70 times a minute, so a click of 20 blocks lays 1,400 blocks a minute. At that rate the lodge's 5,928 blocks last about 4 minutes. A 30-minute run averages about 3 blocks a click.
- A stacked tree was tried on top of the wider reach. Armful had one level, then a Many Hands node multiplied the batch by four a level: two levels, at 515 and 536, so the batch went 2, 8, 32. Cheapest-first bots then laid 1 block a click until minute 11, 2 until minute 26, and 23 at minute 28, in a 28.4-minute run. But bots buying by value took Many Hands first, laid 32 a click from minute 10, and finished in 11.2 minutes. It works only with Many Hands priced between 506 and 544, so it isn't the tuning here.
- Unharvester reaches dozens because its fields are big: the Long Field has 51,984 plants. So dozens a click needs sites several times the first site's 6,000 blocks, or it can only fill a run's last minutes. Decide once the stress test sets how many blocks a site can hold.

Chains still add little, 0.1 to 0.2 blocks a click. A chain only starts what the batch's own blocks just readied, which the next click takes anyway.

## When skills are bought

The mean minute each level was bought on the lodge with no boss. "Not bought" means no run got that far.

Cheapest first:

| skill | level 1 | level 2 | level 3 | level 4 | level 5 |
|---|---|---|---|---|---|
| batch | 6.9 | 13.4 | 20.4 | 28.9 | not bought |
| chain | 8.4 | 16.3 | 23.5 | not bought | not bought |
| setTime | 2.1 | 10.0 | 14.8 | 21.8 | |
| perfect | 4.5 | 11.7 | 18.9 | 25.3 | |
| crew | 17.8 | 26.9 | not bought | not bought | |

By value:

| skill | level 1 | level 2 | level 3 | level 4 | level 5 |
|---|---|---|---|---|---|
| batch | 2.6 | 4.6 | 8.0 | 12.5 | 18.6 |
| chain | not bought | not bought | not bought | not bought | not bought |
| setTime | not bought | not bought | not bought | not bought | |
| perfect | 8.4 | 13.2 | 16.0 | not bought | |
| crew | 6.5 | 10.5 | 15.3 | not bought | |

```bash
lune run tools/sim/run -- --seeds 20 --skills
```

```bash
lune run tools/sim/run -- --seeds 20 --skills --buy value
```

## Run currency

Held and earned in all by minute on the lodge with no boss, cheapest first. A bot spends nearly all it earns as it goes. A run earns about 6,800, and the whole tree costs about 13,600.

| minute | held | earned |
|---|---|---|
| 1 | 74 | 74 |
| 5 | 38 | 374 |
| 10 | 87 | 995 |
| 15 | 92 | 1,958 |
| 20 | 343 | 3,415 |
| 25 | 426 | 5,192 |
| 30 | 86 | 6,808 |

```bash
lune run tools/sim/run -- --seeds 20 --purse
```

## Boss undo rates

Placed blocks the boss and its works undid per run, and per minute over the minutes from its rise to its relenting. "Nearest" is the boss and its minions undoing the exposed blocks nearest them, "markers" the markers whose fuse ran out, and "collapses" the collapses.

| site | difficulty | undone per run | a minute while up | nearest | markers | collapses |
|---|---|---|---|---|---|---|
| WoodcuttersLodge | Normal | 1,039 | 52 | 1,002 | 36 | 0 |
| WoodcuttersLodge | Hard | 1,355 | 61 | 1,318 | 36 | 0 |
| WoodcuttersLodge | Nightmare | 2,455 | 93 | 2,250 | 39 | 167 |
| IceBridge | Normal | 564 | 29 | 389 | 175 | 0 |
| IceBridge | Hard | 815 | 37 | 645 | 170 | 0 |
| IceBridge | Nightmare | 2,762 | 89 | 2,398 | 234 | 130 |
| Watchtower | Normal | 1,519 | 68 | 1,409 | 109 | 0 |
| Watchtower | Hard | 2,028 | 77 | 1,883 | 145 | 0 |
| Watchtower | Nightmare | 3,361 | 104 | 3,036 | 172 | 153 |
| GreatHall | Normal | 547 | 25 | 379 | 168 | 0 |
| GreatHall | Hard | 879 | 37 | 697 | 183 | 0 |
| GreatHall | Nightmare | 2,109 | 74 | 1,718 | 213 | 178 |

By minute on the lodge, as blocks undone a minute:

| minute | Normal | Hard | Nightmare |
|---|---|---|---|
| 10 | 0 | 0 | 0 |
| 15 | 43 | 49 | 76 |
| 20 | 58 | 65 | 95 |
| 25 | 61 | 50 | 90 |
| 30 | 48 | 57 | 123 |
| 35 | 0 | 15 | 101 |
| 40 | | 0 | 37 |

```bash
lune run tools/sim/run -- --site all --boss all --seeds 20 --undo
```

## How the boss was balanced

The rule from the formula holds: difficulty gives players things to go and do, and never adds tougher blocks or longer waits. The sim showed why the old tuning cost some sites nothing and others a great deal:

- **Undoing next to the work costs little.** A click's batch usually has room for a gap or two, so blocks the boss undoes beside a player are laid again almost free. On a compact site, the Watchtower above all, the boss only costs time once it undoes faster than that. So Normal mends 4 blocks at a time within 5 cells, and Hard 6.
- **Trips cost long sites and help compact ones.** On the IceBridge a bot clicks steadily, 73 to 75 times a minute, so every walk to a marker or to shoo the boss is time lost. On the Watchtower a greedy bot works less well with no boss, and the walks land it by fresh work: a boss that undid nothing at all made the Watchtower a minute faster. Markers now come every 90 seconds, not 45.
- **The stubborn band was a lottery.** It runs across the site at every height, so where it lay along a wall it took up to 18% of the Watchtower's slots, and everything resting on them waited for single clicks. That one feature was nearly all of Hard's cost and all of its spread. It now comes at 60% built and is 2 cells wide.
- **A peace circle comes at most once a minute.** The boss works the exposed spot farthest from the players, so on the long Ice Bridge a circle stood about 50 cells from the bot, against 20 on the lodge. With a circle at every stop, the bot spent a third of a Hard run walking to them: 122 circles in a 63-minute run, about 10 seconds each. On the lodge the same walks cross fresh work, so they cost almost nothing. With `peace.every` at 60 seconds, a stop sooner than that raises no circle. Hard then cost 8 to 17% on every site, and 8 to 23% with the wider batch. Keeping the boss's spots near the players instead didn't help: it came back sooner, and its circles fell on the players' own work. Neither did keeping Nightmare's minions near the boss.
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

- Nightmare costs the most on the Ice Bridge and the Watchtower, +41% and +39%, and one Watchtower run took 73.7 minutes. On the Ice Bridge its minions cost the most: before the wider batch, it took 40.2 minutes without them and 49.4 with them, over 10 seeds.
- It measures bots, not players. The bots aim perfectly, shoo the boss when it works within 20 cells, break every marker within 30 and never dodge a strike. Strikes cost them almost nothing.
- It plays one tick rate (0.1 s) and no latency.
- `PartyPressure` isn't modelled, so co-op has no extra pressure from the boss.
