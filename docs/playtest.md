# Playtest checklist

What to check in Studio, on the PC and on a phone, before the Phase 2 gate. The formula's gate asks two things: that you play the prototype and judge the click, and that you report the stress-test ceiling on Low graphics at phone size.

Everything here was built and tested in Lune with a Roblox stand-in, but never run in Studio. The tests show that the scripts run without errors and that the state is right. They can't show how anything looks, feels or performs. This list collects every point that only Studio can settle.

## Before you start

1. Run `aftman install`, then `lune run tools/check`. It should end with "all checks passed".
2. Build the place, open `Frostward.rbxl` in Studio, and press Play:

   ```bash
   rojo build default.project.json -o Frostward.rbxl
   ```

3. Watch the Output window for errors from the first second. Any error is worth a note.

## 1. It runs at all

- [ ] **The scripts load.** The shared modules require each other by string (`require("./BuildSite")`). Lune and the tests accept that; Studio may not. If you see "require" errors, switch the seven files the README lists to `require(script.Parent.X)`.
- [ ] **The site and HUD appear.** The silhouette of the Woodcutter's Lodge stands on the snow, the HUD reads "Woodcutter's Lodge: laid 0%", and a hint at the bottom says how to lay.
- [ ] **You spawn facing the site,** with the site sign in front of you.

## 2. The click (the gate)

Play the lodge solo for 10 minutes or more, with `Difficulty` set to `None`, then `Normal`.

- [ ] **A click feels immediate.** The block shows at once (prediction) and drops in with a small squash, a puff of dust and a tick.
- [ ] **Holding lays steadily.** The cooldown ring fills between blocks, and a fast chain makes the tick climb in pitch.
- [ ] **Aiming is clear.** The outlined slot is the one you get, and the ghost you'd lay shows brighter than the rest.
- [ ] **Growth feels earned.** Buy skills with the number keys or the shop, and the run should get quicker.
- [ ] **Reaching the work is easy.** Step on a blue hoist pad to ride up as the build rises. Every step is a full block, so stairs take a jump: say if that's a chore.
- [ ] **Being walled in never traps you.** If a block lands where you stand, you're moved onto it. If you're ever stuck, you should be moved clear within 2 seconds.

## 3. On a phone

Use Studio's Device emulator at a phone size held sideways, then a real phone if you can (Team Test or a private server).

- [ ] **Buttons are thumb-sized** (44 px or more). The Sled Train and Forge Hammer buttons sit beside the jump button.
- [ ] **The shop starts folded.** Tap Shop at the top left to open it.
- [ ] **A tap on a button never lays a block.** The prototype assumes an `Active` frame marks a tap as processed, as Roblox documents.
- [ ] **The thumbstick and a lay don't interfere.** One thumb moves while the other holds to lay.
- [ ] **Hints name touch controls** ("Tap a glowing ghost…").
- [ ] **Open question:** dragging a finger to turn the camera also lays blocks along the way. Is that right, or should a drag only turn the camera?

## 4. The boss

Set `Difficulty` to `Hard`, then `Nightmare`. `TestSpeed` up to 5 reaches the boss sooner.

- [ ] **The Rime rises at 20% built.** Its name shows above it, and a faint ring on the surface under it marks the shoo radius. The prototype turns that ring a quarter turn, assuming a cylinder adornment's axis runs along Z. Check that it lies flat.
- [ ] **Shooing works:** walking into the ring makes the boss leave.
- [ ] **Markers can be broken:** walk to a frost mark before it bursts.
- [ ] **On Hard,** an ice chain at each of three far corners holds the site at 80% until you break it. A peace circle, where nothing can be laid, comes at most once a minute.
- [ ] **Difficulty adds errands, not tougher blocks.** That rule isn't negotiable, so note anything that breaks it.
- [ ] **Finishing ends the boss.** On Nightmare the boss makes a final stand at 95%, but when the last block lands it leaves, and nothing more is undone during the timelapse.

## 5. Bots and co-op (the Phase 3 and 4 proofs)

- [ ] **A bot run lands near the sim's time.** Set `BotPlayers` to 1, `Difficulty` to `None` and `TestSpeed` to 5. Stand aside and time the lodge from the first block to the timelapse. At ×5, about 6 minutes of real time is 30 minutes of play. The sim says 29.4 minutes for a bot buying the cheapest skill first, with 32 blocks a click from minute 25. Phase 3 asks for the two to agree within 10%.
- [ ] **×5 can be trusted.** The formula asks you to compare one ×5 run against real time before trusting ×5. Play one site at `TestSpeed` 1 with a bot and check the times agree.
- [ ] **Two real clients agree.** Start a Local Server with 2 players (Test, then Clients and Servers). Lay blocks in both windows, sometimes the same cell, against a `Hard` boss. Both windows should show the same build, and a block one player lays should land for the other within a moment.

## 6. Looks

- [ ] **Each block kind is easy to tell apart:** stone, timber, thatch, ice, rope, lantern, slate and glass.
- [ ] **The sites read well.** Set `Site` to `IceBridge`, `Watchtower` or `GreatHall`. The sites agent judged them from its own renders only.
- [ ] **The world changes as the build rises.** The blizzard thins and night falls.
- [ ] **The ending plays.** It's a ten-second timelapse, then each player's payout, then the next site 30 seconds later.
- [ ] **The dust looks right.** It uses the emitter's default texture, since no asset ids were added. The emitter is moved one frame and burst the next, which assumes the burst comes from the new spot.

## 7. The stress test (the gate's number)

The README's "Stress test" section has the details. In short:

1. **Set graphics to Low.** Press Play, press Esc, open Settings, set Graphics Mode to Manual and drag Graphics Quality to its lowest bar, then press Stop.
2. **Emulate a phone.** Turn on the Device emulator (the Device button on the Test tab) and pick a phone held sideways, such as an iPhone 14 at 844 by 390.
3. **Start the ladder.** Select Workspace, add a string attribute `StressTest` with the value `Ladder`, press Play, and leave the mouse and keyboard alone for about 3 minutes. The site steps through 5,000 to 65,535 blocks. At each step the camera spends half the time near the site's edge and half in an overview, and a readout at the right shows the frame rate. F3 hides or shows it.
4. **Read the table.** It prints to the Output window and shows on screen. Its first line names the viewport and quality: check that it says `QualityLevel1`.
5. **Find the ceiling.** It's the last step where both rows, near and overview, hold a mean of 55 FPS or more and a 5% FPS of 30 or more. To narrow it down, set `StressTest` to a list such as `40000, 42500, 45000` and play again.

A PC is faster than a phone even at Low and phone size, so treat the result as an upper bound until a real phone confirms it.

- [ ] The ladder runs to its end and the camera comes back to you.
- [ ] The readout fits a phone screen.
- [ ] Building the biggest site causes no long hitch, or note how long it is.

## What to send back

- Anything from the Output window.
- Your verdict on the click, and what would make it better.
- The stress-test table and the device you ran it on.
- Every box you couldn't tick, with a line on what you saw.
