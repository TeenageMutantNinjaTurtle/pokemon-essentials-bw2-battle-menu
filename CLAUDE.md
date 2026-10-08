# Notes for agents

- This repository is public. Never add anything taken or made from a ROM: no pictures, fonts, tables or
  decompiled code. `tools/b2w2_pictures.py` makes those files on the user's machine; `.gitignore` keeps them out.
- No licence is granted and none may be added without the owner's say; see the README's last section.
- Commit as `TeenageMutantNinjaTurtle` with its no-reply address (set in this repo's git config).
- The plugin targets Essentials v19.1 with Elite Battle DX. All engine questions go through `DualScreen.mode`
  in `001_Core.rb`; with `:single` every override must pass on to the game's own method.
- The plugin has not been run as a packaged plugin yet. The same code runs as loose script files in one game.
- Checks: `ruby -c` on each script; `mypy --strict tools/b2w2_pictures.py`; the tool's output for a White 2
  (USA, Europe) ROM must stay identical file for file.
