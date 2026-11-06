# Building a site in Studio

A site's blueprint can come from a script (`tools/blueprints/<Name>.luau`) or from a model you build in Studio and export (`tools/blueprints/<Name>.rbxm` or `.rbxmx`). This page covers the model route: building it, exporting it, stamping it and checking it. `tools/lib/ModelSource.luau` reads the model and `tools/stamp_blueprint.luau` turns it into `src/shared/Blueprints/<Name>.luau`. [Resize a scripted site](#resize-a-scripted-site) covers the four sites' scripts.

## Resize a scripted site

The four sites are scripts, and each starts with its size in blocks:

```lua
-- The site's size in blocks.
local BLOCKS = 42000
```

To restamp a site at another size, such as the ceiling the stress test finds, change that number and stamp it again:

```bash
lune run tools/stamp_blueprint GreatHall
```

The script builds the site at a scale factor, and a bisection picks the factor whose count lands nearest `BLOCKS`, never over the 65,535 a site can hold. The stamp's line gives the count it reached, usually within 2% of `BLOCKS`. Each script's header says what scales:

| Site | Default | What scales | What stays | Range that fits the baseplate |
|---|---|---|---|---|
| WoodcuttersLodge | 20,000 | every length of the camp | storey heights, windows, doors | up to about 30,000 (102 cells wide) |
| IceBridge | 26,000 | the deck's height and width, the gates, the lantern arch | the spans, so it stays 99 cells long | about 12,700 to 65,535 |
| Watchtower | 33,000 | the tower's width and height, the yard | treads, doors, windows, houses, gatehouse | about 9,000 to 63,500 |
| GreatHall | 42,000 | every length and height, and the bays' count | the bays' width, windows, doors, porch, dormers | up to 65,535 (100 cells wide) |

`SiteServer` puts a site's corner cell at (24, 24) studs, so on the place's 512-stud baseplate a site fits while it is at most about 100 cells along x, which leaves room for the hoist pad past its far corner, and 99 along z. Below a range's lower end a site stops shrinking: the bridge needs its deck 16 layers up for its middle arch, and the tower keeps a least width and height.

After a resize:

- Keep the sites in order. The SiteList test wants each site bigger than the one before it.
- Run `lune run tools/check`: the stamp check fails until the stamped file matches the script.
- Rerun the sim's tables in [`balance.md`](balance.md), which were measured on the old sizes.

## Set up Studio

- In the Model tab, set Move snap to 3 studs and Rotate snap to 90°.
- Build on the world's 3-stud grid: every face of every part sits on a multiple of 3 studs. Put the first part on the grid by typing its Position (a 3-stud cube at `1.5, 1.5, 1.5`, a 6 x 3 x 9 part at `3, 1.5, 4.5`), then copy and move from there. Snapping keeps parts on the grid once they're on it.
- Where the build stands doesn't matter. The stamp shifts it so its lowest corner is cell (0, 0, 0), and its lowest layer becomes the ground.

## Parts

- Each part covers a box of cells, and every cell becomes one block. Its size must be a whole number of cells on each axis: 3, 6, 9... studs. A 30 x 12 x 3 wall is 10 x 4 x 1 cells, so 40 blocks.
- Wedges, mesh parts and unions count as their bounding box. Their shape and colour don't matter, because the game draws each block from its kind.
- Parts stand upright and turn only in quarter turns about y. Every cell of a part faces the way the part does: facing 0 is the part's front toward -z, 1 toward -x, 2 toward +z, 3 toward +x.
- No two parts may cover the same cell. Watch the corners where two walls meet.
- Everything you export becomes blocks, so leave the baseplate, spawn and any helpers out of the selection.

## Kinds

A block's kind is the part's `Kind` attribute (a string). If the part has none, it takes the `Kind` of the nearest Model or Folder around it that has one, and failing that the part's name. So you can set `Kind = "timber"` once on a Walls model and leave its parts alone.

Use kinds `src/shared/KindLooks.luau` knows, such as `stone`, `timber`, `thatch`, `slate` and `glass`. Others draw in plain grey, and the SiteList test refuses a listed site that uses them.

## Stages: walls before roof

A block always waits for what it rests on. To make one part of a build wait for another as well, such as the roof for the walls, use a `Stage` attribute (a number):

- Put `Stage` on a part, Model or Folder. Parts take the nearest one, as they do `Kind`.
- A stage orders the things side by side in one group: the Model or Folder holding what the attribute is on, or the top level of the export.
- Within a group, every block of a stage waits for the top corners of the stage before it. Those are the blocks on that stage's highest layer with the least and greatest x + z and x - z, so at most four.
- Only the order of the numbers counts, so `1.5` fits between `1` and `2`. Things without a `Stage` aren't ordered by it.
- Groups nest. A stage inside a group orders things within that group only.

For example:

```
Lodge           Model    Kind "stone"
  Plinth        Folder                         no Stage: only its supports order it
  Walls         Model    Kind "timber", Stage 1
  Roof          Model    Kind "thatch", Stage 2   waits for the walls' four top corners
  Porch         Model
    Posts       Folder   Kind "timber", Stage 1
    PorchRoof   Folder   Kind "thatch", Stage 2   waits for the posts' tops
```

The porch and the walls aren't ordered against each other, because they're in different groups.

Things to know:

- The top corners stand in for the whole stage. The roof can start once the walls' corners are topped out, even if the middle of a wall isn't. If something must be finished first, give it its own stage.
- If a stage's highest layer isn't where it finishes, the next stage waits for the wrong blocks. For example, a chimney rising above the walls in the walls' stage makes the roof wait for the chimney top. Give the chimney its own group or a later stage.
- Never mark something as later than a thing it holds up. Walls at Stage 2 under a roof at Stage 1 make a cycle, and the stamp reports it with the parts involved.
- Stages are cheap. Only a stage's lowest blocks and overhangs carry the extra supports; the blocks above them wait through what they rest on.

## Export

Select the top Model in the Explorer, right-click it, choose Save to File, and save it as `tools/blueprints/<Name>.rbxm` (binary) or `.rbxmx` (XML). The name may use letters, digits and underscores, like `MillHouse`. Keep one source per name: `MillHouse.luau`, `MillHouse.rbxm` and `MillHouse.rbxmx` can't sit side by side.

## Stamp and check

Run these from the repo root. Stamp the model after every export:

```bash
lune run tools/stamp_blueprint MillHouse
```

It prints the counts and the stages it read in each group, then writes `src/shared/Blueprints/MillHouse.luau`. For a small house model named House, with walls at Stage 1 and a roof at Stage 2:

```
MillHouse: 236 slots, 9 x 7 x 9 cells, 58 overhangs, 320 extra supports, depth 11
  stages in House: 1 (70 blocks), 2 (117 blocks)
wrote src/shared/Blueprints/MillHouse.luau (2544 characters of data)
```

Check that the stamped file matches its source, or run every check the repo has, including every blueprint's stamp check:

```bash
lune run tools/stamp_blueprint MillHouse --check
```

```bash
lune run tools/check
```

Commit the model and the stamped file together.

## What the stamp refuses

Reading the model stops at the first part it can't use, with a message that names the part and where it is:

- its size isn't a whole number of 3-stud cells on every axis
- it isn't upright, or it's turned some number of degrees that isn't a whole quarter turn
- it's off the 3-stud grid along an axis, by some number of studs
- two parts both cover the same cell
- a `Kind` attribute isn't a string, or a `Stage` isn't a finite number
- the model spans more than 256 cells along an axis, or covers more than 65,535 cells

Then `src/shared/BlueprintValidator.luau` checks the built blueprint. Its messages give a slot and its cell, counted from the model's lowest corner, and the stamp adds the part each slot came from on the line below. It checks:

- **The block cap.** A site has 1 to 65,535 blocks, the most a 16-bit slot index can name.
- **Cells.** Every block sits in cells 0 to 255, no two share a cell, and every kind and facing is valid.
- **No floating.** Every block above the ground rests on the block beneath it, or overhangs from a neighbour on its own layer that is itself connected to the ground. A part hanging in the air is refused.
- **No cycles.** Some order places every block, so a site can always be finished.
- **Reach per layer.** Every block must be within the base grasp of 5 cells of a cell a player could stand in while its layer is worked: the layers below are built, the ones above aren't, and the layer itself is part built. The standing cell needs 2 cells of headroom and can't be the block itself. The check doesn't prove a player can walk there, because hoist pads lift players to the working height. A wall can be worked from its own layer below, but a lone one-cell pillar or spire more than 6 cells tall fails, so give it a ledge, steps or a floor beside it.

## Play it

To play the site in the prototype, add it to `src/shared/SiteList.luau` with its blueprint name as the id. The SiteList test wants each site bigger than the one before it, and every kind in `KindLooks`. Then set the Workspace attribute `Site` to that id before pressing Play.
