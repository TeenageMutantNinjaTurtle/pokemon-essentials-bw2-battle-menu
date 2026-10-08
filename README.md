# B2W2 Battle Screen

A plugin for Pokémon Essentials that puts the battle menus of Pokémon Black 2 and White 2 on a second screen
below the game: the battle plays on the upper screen as before, and the lower screen is the touch screen of the
DS games, with their layout, motion and timing.

Status: this code runs in one game (Essentials v19.1 with Elite Battle DX) as loose script files. Packaged as a
plugin, as it is here, it has not been run yet; expect to fix things on first use.

The repository holds two things:

- `Plugins/B2W2 Battle Screen/`: the plugin.
- `tools/b2w2_pictures.py`: a program that makes the plugin's pictures from your own copy of White 2.

## No pictures are included

The pictures, the font and the target tables the plugin reads are Nintendo's and Game Freak's. This repository
contains none of them, and nothing else taken from the ROM: no images, no font sheets, no tables, no decompiled
code, no ROM. Everyone who uses the plugin makes these files from their own copy of the game with the tool below.
Do not commit or pass on what the tool writes; `.gitignore` keeps it out of this repository.

Only the Ruby and Python here are ours to publish.

## Requirements

- Pokémon Essentials v19.1 with [Elite Battle DX](https://luka-sj.com/res/ebdx) (written against 1.2.6). Other
  versions of Essentials are not supported.
- An engine that reports the mouse (`Input.mouse_x`, `Input.mouse_y`, `Input::MOUSELEFT`), as mkxp-z does.
- For the pictures: a ROM of Pokémon White Version 2 (USA, Europe), game code `IRDO`, and Python 3.9 or later
  with [Pillow](https://python-pillow.org).

## Making the pictures

```
python3 tools/b2w2_pictures.py <White 2 ROM.nds> <game folder>
```

The game folder is the one that holds `Graphics`. The tool writes 89 files to
`Graphics/Pictures/B2W2/Battle` and 32 to `Graphics/Pictures/B2W2/BattleBag`, in about ten seconds. It checks the
ROM's game code and stops on any other game, Black 2 included, because the archive members and the addresses of
the target tables it reads are those of White 2 (USA, Europe).

## Installing

1. Copy the folder `Plugins/B2W2 Battle Screen` into the game's `Plugins` folder.
2. Make the pictures, as above.
3. Start the game once in debug mode, so that Essentials compiles the plugin.

## One screen or two

The plugin does nothing unless the game runs with a second screen, so one build of a game serves both kinds of
player. The decision is made in one place, `DualScreen.mode` in `001_Core.rb`, which answers `:single`,
`:stacked` or `:split`:

- If the engine has `Graphics.screen_mode`, the answer is the engine's. The plugin then expects the engine to
  show the lower screen as the area below `Graphics.height`, of the same size as the upper one, and to report
  the mouse there with `Input.mouse_y` from `Graphics.height` on.
- On any other engine the answer is `:stacked` when the environment variable `DUAL_SCREEN=stacked` is set, and
  the plugin itself makes the window twice as tall. Otherwise it is `:single`.

With `:single`, every method the plugin replaces passes straight on to the game's own. `:stacked` and `:split`
are the same to the plugin. A battle keeps the mode it started in.

## What is reproduced

From White 2, in single, double and triple battles:

- Standby (the dimmed Poké Ball), the command screen (FIGHT, BAG, POKéMON, RUN, or the back button for the
  second and third Pokémon), with the party balls of both sides and the icons of the player's Pokémon.
- The move screen: tiles in each type's colours, type icons, PP in the game's colours as it runs out.
- The target screen of double and triple battles: the panels, the outlines of what a move reaches, and the
  cursor's stops, from the game's own tables for every position and move range.
- The transitions between these screens and their frame counts, the press flash, the key cursor with its
  stepping brackets, the touch areas, and the cursor's memory.
- The bag in battle: the four pockets, the items of a pocket six to a page, the item page with its description
  and USE, and the last used item.
- The game's font.

## What is not

- The party list in battle is not White 2's yet. The game's own party screen opens on the lower screen instead,
  and answers to touch; the summary it leads to is left with the Back key.
- Sounds are the game's own, not White 2's.
- Safari battles, and other battles with commands of their own, keep the game's menu, shown on the lower screen.
- Outside battles the lower screen is empty. Moving the game's other menus there is not part of this plugin.
- Rotation battles, the SHIFT button of triple battles, the Wonder Launcher and the weather icons are absent.

## Credits

- [Pokémon Essentials](https://github.com/Maruno17/pokemon-essentials) by Maruno and its many contributors,
  based on work by Flameguru and Poccil.
- [Elite Battle DX](https://luka-sj.com/res/ebdx) by Luka S.J. and its contributors.
- The behaviour was worked out from the game with the help of
  [pokebw2](https://github.com/fuddlesworth/pokebw2), a decompilation of Black 2 and White 2. None of its code is
  in this repository.
- Pokémon Black 2 and White 2 are Nintendo's, Creatures' and Game Freak's. This project is not affiliated with
  them.

## Licence

No licence is granted for this code at present. It was written from the behaviour of Pokémon Black 2 and White 2,
worked out with the help of a decompilation, and parts of it follow Pokémon Essentials (CC BY-NC-SA 4.0) and Elite
Battle DX; under which terms it can be offered has not been settled. You may read it and use it with your own game
at your own judgement.
