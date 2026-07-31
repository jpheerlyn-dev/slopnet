"""Terminal glyph art for provider logos — GENERATED, do not edit.

Regenerate with:  .venv/bin/python scripts/build_icons.py
Source of truth:  font-icons/*.svg

MARK  — one character from standard Unicode. Works in ANY terminal,
        no install; an approximation of the brand, not the logo.
GLYPH — the REAL logo at text size, from StormCodeIcons.ttf. Requires
        the user to have installed and selected that font.
"""
from __future__ import annotations


MARK: dict[str, str] = {
    'aihorde': '⚔',
    'alibaba': '◈',
    'anthropic': '✳',
    'cerebras': '⬣',
    'cognition': '⬡',
    'cohere': '◐',
    'deepseek': '▲',
    'google': '✦',
    'huggingface': '☻',
    'ibm': '☰',
    'inclusionai': '◉',
    'internlm': '◧',
    'jina': '⊙',
    'meta': '∞',
    'microsoft': '⊞',
    'minimax': '⬢',
    'mistral': '▤',
    'moonshot': '☾',
    'nous': '✧',
    'nova': '✶',
    'nvidia': '◤',
    'ollama': '◍',
    'openai': '❋',
    'openrouter': '⋈',
    'perplexity': '⌕',
    'poolside': '≋',
    'rivescript': '❖',
    'scale': '▰',
    'searxng': '⊚',
    'stepfun': '▦',
    'stormcode': '🌀',
    'tencent': '◑',
    'together': '⧉',
    'venice': '⚿',
    'xai': '⦸',
    'xiaomi': '▣',
    'zai': '⧫',
}


# One cell per badge. The colour font's bitmaps are cut to the
# cell's own aspect ratio, so a glyph never overflows it.
GLYPH: dict[str, str] = {
    'aihorde': '\ue009',   # U+E009
    'alibaba': '\ue008',   # U+E008
    'anthropic': '\ue000',   # U+E000
    'cerebras': '\ue00a',   # U+E00A
    'cognition': '\ue01c',   # U+E01C
    'cohere': '\ue00b',   # U+E00B
    'deepseek': '\ue00c',   # U+E00C
    'google': '\ue001',   # U+E001
    'huggingface': '\ue00e',   # U+E00E
    'ibm': '\ue00f',   # U+E00F
    'inclusionai': '\ue01f',   # U+E01F
    'internlm': '\ue010',   # U+E010
    'jina': '\ue024',   # U+E024
    'meta': '\ue011',   # U+E011
    'microsoft': '\ue012',   # U+E012
    'minimax': '\ue006',   # U+E006
    'mistral': '\ue007',   # U+E007
    'moonshot': '\ue004',   # U+E004
    'nous': '\ue013',   # U+E013
    'nova': '\ue020',   # U+E020
    'nvidia': '\ue014',   # U+E014
    'ollama': '\ue015',   # U+E015
    'openai': '\ue002',   # U+E002
    'openrouter': '\ue016',   # U+E016
    'perplexity': '\ue017',   # U+E017
    'poolside': '\ue021',   # U+E021
    'rivescript': '\ue025',   # U+E025
    'scale': '\ue022',   # U+E022
    'searxng': '\ue026',   # U+E026
    'stepfun': '\ue023',   # U+E023
    'stormcode': '\ue01b',   # U+E01B
    'tencent': '\ue018',   # U+E018
    'together': '\ue019',   # U+E019
    'venice': '\ue01a',   # U+E01A
    'xai': '\ue003',   # U+E003
    'xiaomi': '\ue01e',   # U+E01E
    'zai': '\ue005',   # U+E005
}


def mark(provider_id: str, use_font: bool = False) -> str:
    """One-character inline mark for a provider.

    use_font=True returns the real logo glyph from StormCodeIcons.ttf —
    only correct when the terminal is actually using that font, so the
    caller decides. Otherwise a portable Unicode approximation.
    """
    if use_font and provider_id in GLYPH:
        return GLYPH[provider_id]
    return MARK.get(provider_id, "•")

