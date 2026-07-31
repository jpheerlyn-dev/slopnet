"""Render ASCII in the striped IBM-style face.

The font (built by scripts/build_ibm_stripes.py, injected by patch_font.py)
holds the classic 8-bar striped IBM wordmark — derived from OFL IBM Plex Mono —
for A-Z, a-z, 0-9 at U+E800+. ``striped()`` remaps an ASCII string onto that
PUA range so a title like "IBM" draws in the striped face while every other
character (spaces, punctuation) passes through unchanged.

One glyph == one terminal cell, and every striped glyph carries the base
monospace advance, so mapping text this way never breaks the grid.
"""
from __future__ import annotations

BASE_CP = 0xE800
# Must stay byte-for-byte identical to scripts/build_ibm_stripes.py CHARSET,
# or the codepoints and glyphs drift apart.
CHARSET = ("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
           # Punctuation appended, never inserted — inserting would shift
           # every existing codepoint and silently rewrite the alphabet.
           ".,:;!?'\"()[]{}<>-+=/\\|@#$%&*_~^`"
           "\u2013\u2014\u2192\u201c\u201d\u2018\u2019\u00b7\u2026")

_LOOKUP = {ch: chr(BASE_CP + i) for i, ch in enumerate(CHARSET)}


def striped(text: str) -> str:
    """Remap ASCII letters/digits in ``text`` to the striped PUA glyphs.

    Characters outside A-Z/a-z/0-9 (spaces, punctuation, non-ASCII) are left
    untouched, so ``striped("IBM Granite")`` keeps its space and lowercase.
    """
    return "".join(_LOOKUP.get(ch, ch) for ch in text)


def pua_codepoint(ch: str) -> int | None:
    """The U+E800+ codepoint a character maps to, or None if it has none."""
    i = CHARSET.find(ch)
    return BASE_CP + i if i >= 0 else None
