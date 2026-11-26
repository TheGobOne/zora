"""Show Item Pickups (the ZORA flag show_item_pickups): the ROM side of asm/flags2/item-line.

The patch writes "GOT <item>" in the status bar's blank top row when Link takes an item. Its table (asm/rom_space.toml
site "item-line-names", bank 6 $B220-$B3FF, inside the owner's reservation $B150-$B3FF) holds, for each item code
TakeItem can get (0 to ITEM_CODES - 1), the low and then the high byte of its text's address, a high byte of 0 for
no line; then the texts, each its length and its font tiles (asm/flags2/item-line/bank_06.s reads it).
"""
from __future__ import annotations

from ..model.enums import Item
from ..model.item_names import item_names
from .text_encoding import CHAR_TO_BYTE

ITEM_LINE_FLAG = "show_item_pickups"
PEGASUS_BOOTS_FLAG = "pegasus_boots"

TABLE = 0x1B230                         # bank 6 $B220
TABLE_CPU = 0xB220
TABLE_END = 0x1B410                     # bank 6 $B400, the end of the owner's reservation
ITEM_CODES = 0x24                       # TakeItem's codes: bombs $00 to the fairy $23
ROW_TILES = 28
PREFIX = "GOT "

# Taken often, or shown by the HUD's own counts: no line.
QUIET = frozenset({Item.BOMBS, Item.FIVE_RUPEES, Item.ITEM_0x18, Item.KEY, Item.SINGLE_HEART, Item.FAIRY,
                   Item.ITEM_0x21})


def item_texts(pegasus_boots: bool = False) -> dict[int, str]:
    """Each item code's line, by code: "GOT " and its name, upper case."""
    names = item_names(pegasus_boots)
    return {int(item): f"{PREFIX}{names[item].upper()}" for item in names
            if int(item) < ITEM_CODES and item not in QUIET}


def encode(text: str) -> bytes:
    """`text` as font tiles; every character must be one the font has."""
    if not 0 < len(text) <= ROW_TILES:
        raise ValueError(f"an item line must be 1-{ROW_TILES} characters: {text!r}")
    return bytes(CHAR_TO_BYTE[c] for c in text)


def item_line_table(pegasus_boots: bool = False) -> bytes:
    """The table the patch reads at TABLE."""
    texts = item_texts(pegasus_boots)
    low, high = bytearray(ITEM_CODES), bytearray(ITEM_CODES)
    body = bytearray()
    for code in range(ITEM_CODES):
        if code not in texts:
            continue
        address = TABLE_CPU + 2 * ITEM_CODES + len(body)
        low[code], high[code] = address & 0xFF, address >> 8
        tiles = encode(texts[code])
        body += bytes([len(tiles)]) + tiles
    table = bytes(low + high + body)
    if len(table) > TABLE_END - TABLE:
        raise ValueError(f"the item line table is {len(table)} bytes, over its {TABLE_END - TABLE}")
    return table


def item_line_writes(pegasus_boots: bool = False) -> list[tuple[int, bytes]]:
    """The table's write, as (file offset, bytes)."""
    return [(TABLE, item_line_table(pegasus_boots))]
