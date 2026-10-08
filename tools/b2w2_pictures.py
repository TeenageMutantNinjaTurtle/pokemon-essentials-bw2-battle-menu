#!/usr/bin/env python3
"""Write the pictures, the font and the target tables the B2W2 Battle Screen plugin reads, from a Pokémon White
Version 2 (USA, Europe) ROM, at twice the DS size (Essentials draws at 512x384). Nothing this writes may be passed
on: it is the game's own art. Needs Python 3.9 or later and Pillow.

Usage: b2w2_pictures.py <rom.nds> <game folder>

The files go to <game folder>/Graphics/Pictures/B2W2/Battle and .../BattleBag."""
from __future__ import annotations

import argparse
import mmap
import pathlib
import struct
import sys
from enum import IntEnum
from typing import NamedTuple

from PIL import Image

GAME_CODE = b"IRDO"
SCREEN_WIDTH, SCREEN_HEIGHT = 256, 192


class Archive(IntEnum):
    """The archives read, by the game's number for them: a/0/1/1 is 11."""
    BATTLE = 11
    FONTS = 23
    SHARED = 82
    BATTLE_BAG = 98


class Battle(IntEnum):
    """Members of the battle archive."""
    TILES = 358
    PALETTE = 359
    BUTTONS = 361
    BUTTONS_WITH_BACK = 364
    FIELD = 372
    FIELD_DOUBLE = 373
    FIELD_TRIPLE = 374
    FIELD_CLOSING = 378
    FIELD_MOVES = 379
    BALL_TILES = 381
    BALL_MAP = 382
    FIRST_OUTLINES = 384
    LAST_OUTLINES = 419
    OBJ_TILES = 420
    OBJ_PALETTE = 421
    OBJ_CELLS = 422
    CURSOR_TILES = 424
    CURSOR_CELLS = 425
    FOE_PANEL_PALETTE = 481
    OWN_PANEL_PALETTE = 482


class Shared(IntEnum):
    """Members of the archive of pictures several programs share."""
    TYPE_ICON_PALETTE = 33
    FIRST_TYPE_ICON = 34


class Bag(IntEnum):
    """Members of the battle bag's archive."""
    TILES = 0
    PALETTE = 1
    BACKGROUND = 3
    PANELS = 4
    FIRST_BUTTON = 5
    LAST_BUTTON = 13


class Fonts(IntEnum):
    """Members of the font archive."""
    FONT_0 = 0
    TEXT_PALETTE = 5


class GlyphPixel(IntEnum):
    """What a pixel of a glyph is."""
    EMPTY = 0
    LETTER = 1
    SHADOW = 2


class Colour(NamedTuple):
    r: int
    g: int
    b: int


RGBA = tuple[int, int, int, int]
CLEAR: RGBA = (0, 0, 0, 0)


class Section(NamedTuple):
    """The body of one section of a Nitro file."""
    offset: int
    size: int


class Tiles(NamedTuple):
    """An NCGR: 8x8 tiles, each 64 palette indices."""
    bpp: int
    pixels: list[bytes]


class MapEntry(NamedTuple):
    tile: int
    hflip: bool
    vflip: bool
    row: int


class TileMap(NamedTuple):
    """An NSCR: its size in pixels and its entries row by row."""
    width: int
    height: int
    entries: list[MapEntry]


class Oam(NamedTuple):
    """One OBJ of a cell, placed relative to the cell's position."""
    x: int
    y: int
    width: int
    height: int
    tile: int
    row: int
    hflip: bool
    vflip: bool


class CellBank(NamedTuple):
    """An NCER: its cells, and how far an OBJ's tile number is shifted."""
    shift: int
    cells: list[list[Oam]]


class Glyph(NamedTuple):
    code: int
    left: int
    width: int
    advance: int


class Font(NamedTuple):
    """An NFTR as a sheet of 32 glyphs per row; pixels holds the sheet row by row as GlyphPixel values."""
    cell_width: int
    cell_height: int
    glyphs: list[Glyph]
    sheet_width: int
    sheet_height: int
    pixels: list[int]


class FileSpan(NamedTuple):
    start: int
    end: int


class Rom(NamedTuple):
    data: mmap.mmap
    files: list[FileSpan]
    names: dict[str, int]


class Overlay(NamedTuple):
    """An overlay's code and data, and the address its first byte is loaded at."""
    data: bytes
    base: int


class TargetRule(NamedTuple):
    """Where a battle rule's target screen tables are: the cursor table pointers in overlay 169 (btlv_scd.c) and
    the layout members in overlay 168 (btlv_input.c)."""
    battlers_per_side: int
    cursors: int
    layouts: int


TARGET_RULES = (TargetRule(2, 0x0689e6e0, 0x021f3c58), TargetRule(3, 0x0689e884, 0x021f3d0c))
RANGES_PER_POSITION = 15
SCD_OVERLAY, INPUT_OVERLAY = 169, 168

# OBJ sizes in pixels by [shape][size]
OBJ_SIZES = (((8, 8), (16, 16), (32, 32), (64, 64)),
             ((16, 8), (32, 8), (32, 16), (64, 32)),
             ((8, 16), (8, 32), (16, 32), (32, 64)))


# ---------------------------------------------------------------------------------------------------------------
# The ROM: its files by path, and its overlays
# ---------------------------------------------------------------------------------------------------------------
def open_rom(path: pathlib.Path) -> Rom:
    """Map the ROM and read its file tables. Exits if it is not White 2 (USA, Europe)."""
    with open(path, "rb") as file:
        data = mmap.mmap(file.fileno(), 0, access=mmap.ACCESS_READ)
    code = bytes(data[12:16])
    if code != GAME_CODE:
        sys.exit(f"{path}: not a Pokémon White Version 2 (USA, Europe) ROM. Its game code is {code!r}; "
                 f"this tool reads {GAME_CODE!r} only, because the members and addresses it uses are that game's.")
    names_at, _, files_at, files_size = struct.unpack_from("<4I", data, 0x40)
    files = [FileSpan(*struct.unpack_from("<II", data, files_at + 8 * i)) for i in range(files_size // 8)]
    names: dict[str, int] = {}
    read_directory(data, names_at, 0, "", names)
    return Rom(data, files, names)


def read_directory(data: mmap.mmap, names_at: int, directory: int, prefix: str, names: dict[str, int]) -> None:
    """Add every file under a directory of the name table to names, as path -> file number."""
    at, file = struct.unpack_from("<IH", data, names_at + 8 * directory)
    at += names_at
    while data[at]:
        length = data[at] & 0x7F
        name = prefix + bytes(data[at + 1:at + 1 + length]).decode("ascii")
        if data[at] & 0x80:
            child = struct.unpack_from("<H", data, at + 1 + length)[0] & 0xFFF
            read_directory(data, names_at, child, name + "/", names)
            at += 2
        else:
            names[name] = file
            file += 1
        at += 1 + length


def rom_file(rom: Rom, number: int) -> bytes:
    span = rom.files[number]
    return bytes(rom.data[span.start:span.end])


def archive(rom: Rom, which: Archive) -> list[bytes]:
    """The members of one of the game's archives, which are files named by the digits of their number."""
    return narc_members(rom_file(rom, rom.names["a/" + "/".join(f"{which:03d}")]))


def overlay(rom: Rom, number: int) -> Overlay:
    """An overlay, decompressed."""
    table = struct.unpack_from("<I", rom.data, 0x50)[0]
    _, base, _, _, _, _, file, flags = struct.unpack_from("<8I", rom.data, table + 32 * number)
    data = rom_file(rom, file)
    if flags >> 24 & 1:
        data = blz_decompress(data[:flags & 0xFFFFFF])
    return Overlay(data, base)


def blz_decompress(data: bytes) -> bytes:
    """Undo the backwards LZ compression of the ROM's code."""
    grown = struct.unpack_from("<I", data, len(data) - 4)[0]
    if grown == 0:
        return data[:-4]
    header = data[len(data) - 5]
    packed = struct.unpack_from("<I", data, len(data) - 8)[0] & 0xFFFFFF
    plain = len(data) - packed   # the head, which is stored as it is
    out = bytearray(len(data) + grown)
    out[:plain] = data[:plain]
    src, dst = len(data) - header, len(out)
    mask = flags = 0
    while dst > plain:
        mask >>= 1
        if mask == 0:
            src -= 1
            flags = data[src]
            mask = 0x80
        if flags & mask:
            src -= 2
            info = data[src + 1] << 8 | data[src]
            for _ in range((info >> 12) + 3):
                dst -= 1
                out[dst] = out[dst + (info & 0xFFF) + 3]
        else:
            src -= 1
            dst -= 1
            out[dst] = data[src]
    return bytes(out)


# ---------------------------------------------------------------------------------------------------------------
# Nitro containers: NARC archives and LZ10/LZ11 compression
# ---------------------------------------------------------------------------------------------------------------
def unlz(data: bytes) -> bytes:
    """Return data decompressed if it starts with an LZ10 or LZ11 header, else unchanged."""
    if len(data) < 5 or data[0] not in (0x10, 0x11):
        return data
    size = int.from_bytes(data[1:4], "little")
    if size == 0 or size > 0x400000:
        return data
    kind, src, out = data[0], 4, bytearray()
    try:
        while len(out) < size:
            flags = data[src]
            src += 1
            for bit in range(8):
                if len(out) >= size:
                    break
                if not flags & (0x80 >> bit):
                    out.append(data[src])
                    src += 1
                    continue
                if kind == 0x10:
                    b = data[src] << 8 | data[src + 1]
                    src += 2
                    length, disp = (b >> 12) + 3, (b & 0xFFF) + 1
                else:
                    ind = data[src] >> 4
                    if ind == 0:
                        b = int.from_bytes(data[src:src + 3], "big")
                        src += 3
                        length, disp = ((b >> 12) & 0xFF) + 0x11, (b & 0xFFF) + 1
                    elif ind == 1:
                        b = int.from_bytes(data[src:src + 4], "big")
                        src += 4
                        length, disp = ((b >> 12) & 0xFFFF) + 0x111, (b & 0xFFF) + 1
                    else:
                        b = data[src] << 8 | data[src + 1]
                        src += 2
                        length, disp = (b >> 12) + 1, (b & 0xFFF) + 1
                for _ in range(length):
                    out.append(out[-disp])
    except IndexError:
        return data
    return bytes(out[:size])


def narc_members(data: bytes) -> list[bytes]:
    """The members of a NARC file, decompressed where they are LZ-compressed."""
    header = struct.unpack_from("<H", data, 12)[0]
    count = struct.unpack_from("<I", data, header + 8)[0]
    entries = [FileSpan(*struct.unpack_from("<II", data, header + 12 + 8 * i)) for i in range(count)]
    btnf = header + struct.unpack_from("<I", data, header + 4)[0]
    gmif = btnf + struct.unpack_from("<I", data, btnf + 4)[0] + 8
    return [unlz(data[gmif + entry.start:gmif + entry.end]) for entry in entries]


# ---------------------------------------------------------------------------------------------------------------
# Nitro 2D formats: NCLR palettes, NCGR tiles, NSCR tile maps, NCER cells, NFTR fonts. Colour 0 of a palette is
# transparent.
# ---------------------------------------------------------------------------------------------------------------
def sections(data: bytes) -> dict[bytes, Section]:
    """Each section of a Nitro file by its magic as stored, e.g. b'TTLP'."""
    found: dict[bytes, Section] = {}
    at = struct.unpack_from("<H", data, 12)[0]
    for _ in range(struct.unpack_from("<H", data, 14)[0]):
        size = struct.unpack_from("<I", data, at + 4)[0]
        found[bytes(data[at:at + 4])] = Section(at + 8, size - 8)
        at += size
    return found


def palette(data: bytes) -> list[Colour]:
    body = sections(data)[b"TTLP"]
    start = body.offset + struct.unpack_from("<I", data, body.offset + 12)[0]
    count = (body.offset + body.size - start) // 2
    return [Colour((value & 31) * 255 // 31, (value >> 5 & 31) * 255 // 31, (value >> 10 & 31) * 255 // 31)
            for value in struct.unpack_from(f"<{count}H", data, start)]


def tiles(data: bytes) -> Tiles:
    body = sections(data)[b"RAHC"]
    depth = struct.unpack_from("<I", data, body.offset + 4)[0]
    length, offset = struct.unpack_from("<II", data, body.offset + 16)
    raw = data[body.offset + offset:body.offset + offset + length]
    bpp = 8 if depth == 4 else 4
    if bpp == 4:
        flat = bytearray()
        for byte in raw:
            flat += bytes((byte & 15, byte >> 4))
    else:
        flat = bytearray(raw)
    return Tiles(bpp, [bytes(flat[i:i + 64]) for i in range(0, len(flat) - 63, 64)])


def tile_image(chars: Tiles, colours: list[Colour], tile: int, row: int = 0, hflip: bool = False,
               vflip: bool = False) -> Image.Image:
    """One 8x8 tile, using palette row `row` (4bpp) or the whole palette (8bpp)."""
    image = Image.new("RGBA", (8, 8))
    if tile >= len(chars.pixels):
        return image
    base = row * 16 if chars.bpp == 4 else 0
    out: list[RGBA] = []
    for index in chars.pixels[tile]:
        colour = colours[base + index] if base + index < len(colours) else Colour(255, 0, 255)
        out.append((*colour, 0 if index == 0 else 255))
    image.putdata(out)
    if hflip:
        image = image.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    if vflip:
        image = image.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    return image


def sheet(chars: Tiles, colours: list[Colour], row: int, across: int) -> Image.Image:
    """All tiles of an NCGR side by side, `across` tiles per line."""
    count = len(chars.pixels)
    image = Image.new("RGBA", (across * 8, max(1, -(-count // across)) * 8))
    for tile in range(count):
        image.paste(tile_image(chars, colours, tile, row), (tile % across * 8, tile // across * 8))
    return image


def tile_map(data: bytes) -> TileMap:
    """A text map larger than 256 pixels is stored as 256x256 blocks one after another, as in VRAM; affine and
    extended maps are stored row by row."""
    body = sections(data)[b"NRCS"]
    width, height, _, kind, length = struct.unpack_from("<HHHHI", data, body.offset)
    values = list(struct.unpack_from(f"<{length // 2}H", data, body.offset + 12))
    across, down = width // 8, height // 8
    if kind == 0 and (across > 32 or down > 32):
        rows = [[0] * across for _ in range(down)]
        for i, value in enumerate(values):
            block, cell = divmod(i, 1024)
            rows[block // (across // 32) * 32 + cell // 32][block % (across // 32) * 32 + cell % 32] = value
        values = [value for line in rows for value in line]
    return TileMap(width, height,
                   [MapEntry(value & 0x3FF, bool(value & 0x400), bool(value & 0x800), value >> 12) for value in values])


def map_image(layout: TileMap, chars: Tiles, colours: list[Colour]) -> Image.Image:
    image = Image.new("RGBA", (layout.width, layout.height))
    across = layout.width // 8
    for i, entry in enumerate(layout.entries):
        image.paste(tile_image(chars, colours, entry.tile, entry.row, entry.hflip, entry.vflip),
                    (i % across * 8, i // across * 8))
    return image


def cells(data: bytes) -> CellBank:
    body = sections(data)[b"KBEC"]
    count, kind, offset, mapping = struct.unpack_from("<HHII", data, body.offset)
    table = body.offset + offset
    entry = 16 if kind == 1 else 8
    oam_base = table + count * entry
    out: list[list[Oam]] = []
    for c in range(count):
        number, _, oam_offset = struct.unpack_from("<HHI", data, table + c * entry)
        oams: list[Oam] = []
        for o in range(number):
            attr0, attr1, attr2 = struct.unpack_from("<HHH", data, oam_base + oam_offset + o * 6)
            y = attr0 & 0xFF
            x = attr1 & 0x1FF
            width, height = OBJ_SIZES[attr0 >> 14][attr1 >> 14] if attr0 >> 14 < 3 else (8, 8)
            oams.append(Oam(x - 512 if x >= 256 else x, y - 256 if y >= 128 else y, width, height, attr2 & 0x3FF,
                            attr2 >> 12, bool(attr1 & 0x1000), bool(attr1 & 0x2000)))
        out.append(oams)
    return CellBank(mapping & 0xFF if mapping < 4 else 0, out)


def cell_image(oams: list[Oam], chars: Tiles, colours: list[Colour], shift: int) -> Image.Image:
    """One cell, cut to the rectangle its OBJs cover."""
    left, top = min(oam.x for oam in oams), min(oam.y for oam in oams)
    right, bottom = max(oam.x + oam.width for oam in oams), max(oam.y + oam.height for oam in oams)
    image = Image.new("RGBA", (right - left, bottom - top))
    step = 1 if chars.bpp == 4 else 2   # an 8bpp tile takes two 32-byte units
    for oam in reversed(oams):   # the first OBJ is drawn on top
        part = Image.new("RGBA", (oam.width, oam.height))
        first = (oam.tile << shift) // step
        across = oam.width // 8
        for t in range(across * (oam.height // 8)):
            part.paste(tile_image(chars, colours, first + t, oam.row), (t % across * 8, t // across * 8))
        if oam.hflip:
            part = part.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        if oam.vflip:
            part = part.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
        image.alpha_composite(part, (oam.x - left, oam.y - top))
    return image


def font(data: bytes) -> Font:
    """The game's fonts differ from standard NFTR in one way: each glyph's cell starts with its three width bytes,
    and the width section is not a table of them."""
    finf = data.index(b"FNIF") + 8
    cglp, _, cmap = struct.unpack_from("<3I", data, finf + 8)
    cell_width, cell_height, cell_size, _, _, bpp, _ = struct.unpack_from("<BBHBBBB", data, cglp)
    count = (struct.unpack_from("<I", data, cglp - 4)[0] - 16) // cell_size
    sheet_width, sheet_height = 32 * cell_width, -(-count // 32) * cell_height
    pixels = [int(GlyphPixel.EMPTY)] * (sheet_width * sheet_height)
    for glyph in range(count):
        base = (cglp + 8 + glyph * cell_size + 3) * 8
        for i in range(cell_width * cell_height):
            value = 0
            for bit in range(bpp):
                at = base + i * bpp + bit
                value = value << 1 | (data[at >> 3] >> (7 - (at & 7)) & 1)
            x, y = glyph % 32 * cell_width + i % cell_width, glyph // 32 * cell_height + i // cell_width
            pixels[y * sheet_width + x] = value
    codes: dict[int, int] = {}
    while 0 < cmap <= len(data) - 12:
        first, last, method, _, following = struct.unpack_from("<HHHHI", data, cmap)
        if method == 0:
            start = struct.unpack_from("<H", data, cmap + 12)[0]
            for code in range(first, last + 1):
                codes[start + code - first] = code
        elif method == 1:
            for code in range(first, last + 1):
                glyph = struct.unpack_from("<H", data, cmap + 12 + 2 * (code - first))[0]
                if glyph != 0xFFFF:
                    codes[glyph] = code
        else:
            for i in range(struct.unpack_from("<H", data, cmap + 12)[0]):
                code, glyph = struct.unpack_from("<HH", data, cmap + 14 + 4 * i)
                codes[glyph] = code
        cmap = following
    glyphs: list[Glyph] = []
    for glyph in range(count):
        left, width, advance = data[cglp + 8 + glyph * cell_size:cglp + 11 + glyph * cell_size]
        glyphs.append(Glyph(codes[glyph], left - 256 * (left > 127), width, advance))
    return Font(cell_width, cell_height, glyphs, sheet_width, sheet_height, pixels)


# ---------------------------------------------------------------------------------------------------------------
# What the plugin reads
# ---------------------------------------------------------------------------------------------------------------
def save(image: Image.Image, path: pathlib.Path) -> None:
    """At twice the size."""
    image.resize((image.width * 2, image.height * 2), Image.Resampling.NEAREST).save(path)


def silhouette(layout: TileMap, chars: Tiles, colours: list[Colour], rows: tuple[int, ...]) -> Image.Image:
    """White wherever a tile of one of the palette rows draws: laid over the map at n/16 opacity it is the press
    flash, a blend of those rows toward white."""
    across = layout.width // 8
    image = Image.new("RGBA", (layout.width, layout.height))
    for i, entry in enumerate(layout.entries):
        if entry.row in rows:
            alpha = tile_image(chars, colours, entry.tile, entry.row, entry.hflip, entry.vflip).getchannel("A")
            image.paste(Image.merge("RGBA", (alpha, alpha, alpha, alpha)), (i % across * 8, i // across * 8))
    return image


def font_image(glyphs: Font, letter: Colour, shadow: Colour) -> Image.Image:
    """The font's sheet in one pair of colours."""
    lookup: dict[int, RGBA] = {GlyphPixel.LETTER: (*letter, 255), GlyphPixel.SHADOW: (*shadow, 255)}
    image = Image.new("RGBA", (glyphs.sheet_width, glyphs.sheet_height))
    image.putdata([lookup.get(value, CLEAR) for value in glyphs.pixels])
    return image


def write_battle(rom: Rom, glyphs: Font, out: pathlib.Path) -> None:
    """The battle's lower screen: standby, command, move and target screens."""
    battle = archive(rom, Archive.BATTLE)
    chars, colours = tiles(battle[Battle.TILES]), palette(battle[Battle.PALETTE])

    # The Poké Ball of BG 7, scaled by the scene, so kept at its own size; and as it is in standby, with palette
    # rows 0 and 1 blended 12/16 toward the colour 0x0842. Cross-fading the two gives the steps in between.
    dim = Colour(16, 16, 16)
    dimmed = list(colours)
    dimmed[:32] = [Colour(*((c * 4 + d * 12) // 16 for c, d in zip(colour, dim))) for colour in colours[:32]]
    ball, ball_chars = tile_map(battle[Battle.BALL_MAP]), tiles(battle[Battle.BALL_TILES])
    map_image(ball, ball_chars, colours).save(out / "ball.png")
    map_image(ball, ball_chars, dimmed).save(out / "ball_dim.png")

    # Field and button maps, whole: the scene shows one 256x192 part at a time, as the game scrolls them
    for member in (Battle.FIELD, Battle.FIELD_CLOSING, Battle.FIELD_MOVES):
        layout = tile_map(battle[member])
        save(map_image(layout, chars, colours), out / f"field_{member}.png")
        save(silhouette(layout, chars, colours, (0, 1)), out / f"field_{member}_rows01.png")
    for member in (Battle.BUTTONS, Battle.BUTTONS_WITH_BACK):
        save(map_image(tile_map(battle[member]), chars, colours), out / f"buttons_{member}.png")

    # The four move tiles of the field map in each type's colours: palette rows 9-12 all take the type's sixteen
    # colours. The palettes are in the game's order of types; the last is the empty slot's.
    type_palettes = (464, 470, 473, 471, 472, 476, 475, 477, 479, 465, 466, 468, 467, 469, 478, 474, 480, 463)
    field = tile_map(battle[Battle.FIELD])
    frames = field._replace(entries=[e if 9 <= e.row <= 12 else MapEntry(0, False, False, 0) for e in field.entries])
    for number, type_palette in enumerate(type_palettes):
        tinted = list(colours)
        tinted[9 * 16:13 * 16] = palette(battle[type_palette])[:16] * 4
        save(map_image(frames, chars, tinted).crop((256, 224, 512, 320)), out / f"tiles_{number:02d}.png")

    # OBJ: the party balls by state, the player's large ones over the foe's small ones (cells 3, 0, 2, 1 and
    # 7, 4, 6, 5: none, fine, fainted, status problem); the growing tile; the cursor's four brackets
    bank, obj_colours = cells(battle[Battle.OBJ_CELLS]), palette(battle[Battle.OBJ_PALETTE])
    obj_chars = tiles(battle[Battle.OBJ_TILES])
    balls = Image.new("RGBA", (64, 24))
    for state, (large, small) in enumerate(((3, 7), (0, 4), (2, 6), (1, 5))):
        balls.paste(cell_image(bank.cells[large], obj_chars, obj_colours, bank.shift), (state * 16, 0))
        balls.paste(cell_image(bank.cells[small], obj_chars, obj_colours, bank.shift), (state * 16, 16))
    save(balls, out / "balls.png")
    save(cell_image(bank.cells[8], obj_chars, obj_colours, bank.shift), out / "tile_grow.png")
    cursor, cursor_chars = cells(battle[Battle.CURSOR_CELLS]), tiles(battle[Battle.CURSOR_TILES])
    for corner in range(4):
        save(cell_image(cursor.cells[corner], cursor_chars, obj_colours, cursor.shift), out / f"cursor_{corner}.png")

    # Type icons: one member per type, each in the palette row the game's table (arm9, 0x020920b8) gives it
    icon_rows = (0, 0, 1, 1, 0, 0, 2, 1, 0, 0, 1, 2, 0, 1, 1, 2, 0)
    shared = archive(rom, Archive.SHARED)
    icon_colours = palette(shared[Shared.TYPE_ICON_PALETTE])
    icons = Image.new("RGBA", (32, 16 * len(icon_rows)))
    for kind, row in enumerate(icon_rows):
        icons.paste(sheet(tiles(shared[Shared.FIRST_TYPE_ICON + kind]), icon_colours, row, 4), (0, kind * 16))
    save(icons, out / "types.png")

    # Font 0 in the four text colour pairs of palette row 13 (letter, shadow): 1/2 white, 3/4, 5/6, 7/8 for low PP
    for pair in range(4):
        letter, shadow = colours[13 * 16 + 1 + pair * 2], colours[13 * 16 + 2 + pair * 2]
        save(font_image(glyphs, letter, shadow), out / f"font_{pair}.png")
    lines = [f"{glyphs.cell_width} {glyphs.cell_height}"]
    lines += [f"{glyph.code} {glyph.left} {glyph.width} {glyph.advance}" for glyph in glyphs.glyphs]
    (out / "font.txt").write_text("\n".join(lines) + "\n")

    # Target screen. The double and triple fields, the part at (256, 192), with the foes' panel rows in their
    # palette and the player's in theirs; one silhouette per panel row for its flash; the 36 outline layouts,
    # which the game copies into the button map 16 pixels down.
    foe, own = palette(battle[Battle.FOE_PANEL_PALETTE])[:16], palette(battle[Battle.OWN_PANEL_PALETTE])[:16]
    part = (SCREEN_WIDTH, SCREEN_HEIGHT, 2 * SCREEN_WIDTH, 2 * SCREEN_HEIGHT)
    for member, rows in ((Battle.FIELD_DOUBLE, (7, 8, 9, 10)), (Battle.FIELD_TRIPLE, (7, 8, 9, 10, 11, 12))):
        panels = list(colours)
        for i, row in enumerate(rows):
            panels[row * 16:row * 16 + 16] = foe if i < len(rows) // 2 else own
        layout = tile_map(battle[member])
        save(map_image(layout, chars, panels).crop(part), out / f"field_{member}.png")
        for row in rows:
            save(silhouette(layout, chars, colours, (row,)).crop(part), out / f"field_{member}_row{row}.png")
    for layout_member in range(Battle.FIRST_OUTLINES, Battle.LAST_OUTLINES + 1):
        outline = Image.new("RGBA", (SCREEN_WIDTH, SCREEN_HEIGHT))
        outline.paste(map_image(tile_map(battle[layout_member]), chars, colours), (0, 16))
        save(outline, out / f"target_{layout_member}.png")


def write_targets(rom: Rom, out: pathlib.Path) -> None:
    """The target screen's tables, one line per rule (2 double, 3 triple), attacker and move range: the layout
    member, then every cursor stop including cancel as twelve numbers: the rectangles its six corner brackets
    sit on, where Up, Down, Left and Right lead, and what Use and Back answer."""
    scd, layouts = overlay(rom, SCD_OVERLAY), overlay(rom, INPUT_OVERLAY)
    lines: list[str] = []
    for rule in TARGET_RULES:
        cancel = 2 * rule.battlers_per_side   # the stop after the last battler's
        for case in range(rule.battlers_per_side * RANGES_PER_POSITION):
            at = struct.unpack_from("<I", scd.data, rule.cursors + 4 * case - scd.base)[0]
            stops: list[str] = []
            while True:
                stop = struct.unpack_from("12b", scd.data, at - scd.base)
                stops.append(",".join(map(str, stop)))
                if stop[0] == cancel:
                    break
                at += 12
            member = struct.unpack_from("<i", layouts.data, rule.layouts + 4 * case - layouts.base)[0]
            position, move_range = divmod(case, RANGES_PER_POSITION)
            lines.append(f"{rule.battlers_per_side} {position} {move_range} {member} {' '.join(stops)}")
    (out / "targets.txt").write_text("\n".join(lines) + "\n")


def write_bag(rom: Rom, glyphs: Font, out: pathlib.Path) -> None:
    """The battle bag: the background, the fixed panels of each page (page 0 at (0, 0) of their map, page 1 at
    (256, 0), page 2 at (0, 256)), and each button map in its palette rows: as stored, then the next row
    (pressed) and the one after (disabled or empty)."""
    bag = archive(rom, Archive.BATTLE_BAG)
    chars, colours = tiles(bag[Bag.TILES]), palette(bag[Bag.PALETTE])
    screen = (0, 0, SCREEN_WIDTH, SCREEN_HEIGHT)
    save(map_image(tile_map(bag[Bag.BACKGROUND]), chars, colours).crop(screen), out / "background.png")
    panels = map_image(tile_map(bag[Bag.PANELS]), chars, colours)
    for page, (x, y) in enumerate(((0, 0), (256, 0), (0, 256))):
        save(panels.crop((x, y, x + SCREEN_WIDTH, y + SCREEN_HEIGHT)), out / f"panels_{page}.png")
    for member in range(Bag.FIRST_BUTTON, Bag.LAST_BUTTON + 1):
        layout = tile_map(bag[member])
        for state in range(3):
            shifted = layout._replace(entries=[entry._replace(row=entry.row + state) for entry in layout.entries])
            save(map_image(shifted, chars, colours), out / f"button_{member}_{state}.png")
    # Font 0 in the bag's text colours: letter 15, shadow 2 of the font palette
    text = palette(archive(rom, Archive.FONTS)[Fonts.TEXT_PALETTE])
    save(font_image(glyphs, text[15], text[2]), out / "font.png")


def main() -> None:
    parser = argparse.ArgumentParser(description="Write the pictures the B2W2 Battle Screen plugin reads, from "
                                                 "a Pokémon White Version 2 (USA, Europe) ROM.")
    parser.add_argument("rom", type=pathlib.Path, help="the ROM file (.nds)")
    parser.add_argument("game", type=pathlib.Path, help="the game's folder, the one that holds Graphics")
    arguments = parser.parse_args()
    rom = open_rom(arguments.rom)
    pictures: pathlib.Path = arguments.game / "Graphics" / "Pictures" / "B2W2"
    (pictures / "Battle").mkdir(parents=True, exist_ok=True)
    (pictures / "BattleBag").mkdir(exist_ok=True)
    glyphs = font(archive(rom, Archive.FONTS)[Fonts.FONT_0])
    write_battle(rom, glyphs, pictures / "Battle")
    write_targets(rom, pictures / "Battle")
    write_bag(rom, glyphs, pictures / "BattleBag")
    print(pictures)


if __name__ == "__main__":
    main()
