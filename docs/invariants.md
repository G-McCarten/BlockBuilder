# The slot-state invariants and their tests

Section 4.2 of the formula lists six rules for `BuildSite` that every build must keep, and asks for a test for each one. This page lists the tests that cover each rule. Run them all with `lune run tests/run`.

Each test is named the way the runner prints it: the group, then the case.

## 1. Only READY or SETTING slots take a placement

The server checks the slot is valid, within grasp plus slack in 3D, under the rate limit, and that the player's cooldown has passed.

- BuildSite: "place takes READY slots and opens their dependents"
- BuildSite: "a hand placement finishes a SETTING block at once"
- BuildSite: "UNDOING slots take no placement and turn READY at progress 0"
- BuildSite: "shields: HAND_ONLY takes only a hand, BLOCKED takes nothing"
- BuildSite: "slots that don't exist are refused"
- SiteSession: "a click in reach places and pays; out of reach it's refused"
- SiteSession: "cooldown, its grace, and the rate limit"
- SiteSession: "refusals: not working, no such slot, smothered"

## 2. Nothing floats

A block can be undone only if no placed block rests on it. A SETTING block whose support is undone drops back to LOCKED.

- BuildSite: "nothing floats: undo waits until no placed block rests on it"
- BuildSite: "undo drops a SETTING dependent back to LOCKED and clears its progress"
- BuildSite: "random play on the TestHut keeps every rule, checking every slot after every op"
- BuildSite: "random play on 6,000-slot terrain keeps every rule"

The two random-play tests are Phase 1's proof: more than 10,000 random placements and undos, with every slot checked against a plain model of the rules.

## 3. A site can always be finished

The validator proves a blueprint has no cycles and rests on the ground. At runtime, the boss stops before 100%.

- BlueprintValidator: "rejects a cycle made by extra ordering"
- BlueprintValidator: "rejects a block that floats"
- BlueprintValidator: "rejects a block that supports itself"
- BossEffects: "the boss relents once enough is built"
- BossBrain: "it relents at relentAt and stops"
- BossBrain: "relenting lifts every hold, so the site can be finished"
- Sim: "bots finish the TestHut solo, in co-op, and against every boss"
- `lune run tools/check` stamps and validates every blueprint in `tools/blueprints/`.

On Nightmare the boss makes a final stand instead of relenting. BossBrain tests that the stand ends after its shoos.

## 4. A block pays once

Each slot has a `spent` flag, so an undone block can't be farmed by laying it again.

- BuildSite: "a SETTING block places itself and pays its causer once"
- BuildSite: "an undone block placed again doesn't pay again"
- SiteSession: "perfects pay their reward, and a block placed again pays nothing"

## 5. No player gets trapped

See section 4.4 of the formula.

- BlueprintValidator: "reach is per layer: a thick floor's lower layer is laid from on top of it"
- BlueprintValidator: "nobody stands in the cell they are placing"
- BlueprintValidator: "finds the top of a bare tower out of reach, and steps fix it"
- Access: "a character a block lands on steps up onto it"
- Access: "freeSurface finds the nearest stand cell, as a scan does"
- Invariants: "5: a block laid where a character stands moves them clear"
- Invariants: "5: a character wedged where it can't stand is moved after 2 seconds"
- Prototype: "a hoist pad lifts the player to the working height"

The two Invariants tests run the prototype client under the Roblox stand-in. Physics only exists in Studio, so they can't show that a real character walks away.

## 6. The server makes no Instance per block

`SiteCodec`'s u16 slot index caps a site at 65,535 blocks.

- SiteCodec: "the shared site modules create no Instance per block"
- Invariants: "6: the server makes no Instance per block". The prototype server runs while a client lays over 300 blocks, and the server must make no new Instance.
- Blueprint: "encode refuses more than 65,535 slots"
- BlueprintValidator: "caps a site at 65,535 slots"
- SiteCodec: "a full 65,535-slot site fits"
