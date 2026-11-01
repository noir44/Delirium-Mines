# Delirium Mines

Build 42 mod for the Delirium server. No dependencies.

Limestone is rare in the world and its boulders do not come back; this mod gives the server lasting sources of stone and ore.

- An **admin** puts down a mine from the context menu (**Mines (admin)**): a 3x3 rock centred on the clicked tile, one of two kinds and two facings:
  - **Limestone quarry**: limestone, stone, clay, large stone;
  - **Ore mine**: iron ore, copper ore, stone.
  The work face looks south or east. The rock cannot be picked up or broken with a sledgehammer; the admin removes it or refills its stock from the same menu.
- **Anyone** right-clicks the rock: **Work the face** (or x10). The character walks to the face, takes a pickaxe (or a sledgehammer, club hammer, stone maul or hammer, as for vanilla ore boulders) and hits: every hit gives one item rolled from the kind's table, Masonry XP and wear on the tool.
- Each mine holds a **stock** of hits (200) that refills by 5 every game hour. The tooltip shows the stock and the chances.

## Sandbox options (page DelMines)

| Option | Default | Meaning |
|---|---|---|
| `Capacity` | 200 | hits in a full mine |
| `RegenPerHour` | 5 | hits added back each game hour (0: only the admin refills) |
| `HitTimePercent` | 100 | hit time, percent of vanilla's boulder (300 ticks less 10 per Strength) |
| `XpPerHit` | 5 | Masonry XP per hit |
| `QuarryTable` | `Base.Limestone:40; Base.Stone2:30; Base.Clay:20; Base.LargeStone:10` | item:weight pairs |
| `MineTable` | `Base.IronOre:30; Base.CopperOre:10; Base.Stone2:60` | item:weight pairs |

Tiles: pack `delmines`, `tiledef=delmines 1717`. The rock art is a placeholder for now (`art/make_placeholder.py`).
