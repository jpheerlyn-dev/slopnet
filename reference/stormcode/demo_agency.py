#!/usr/bin/env python3
"""TexFaber Agency — the session as boxed panels, straight from StormCode.md.

    .venv/bin/python scripts/demo_agency.py            # whole conversation
    .venv/bin/python scripts/demo_agency.py --plain    # no font, Unicode marks
    .venv/bin/python scripts/demo_agency.py --lanes    # just the parallel block

COLOUR SCHEMA — this is the spec, not a suggestion:

    field        jet black  #000000, painted explicitly on every cell
    borders      red        #FF003C, on every panel
    default text red        #FF003C — the app's own voice (user, chrome)
    panel fill   THE BRAND OF THE MODEL THAT OWNS THE PANEL, from BRAND[pid],
                 with that brand's own fg for the text inside it

Every entry in the source sketch is a box. It is a box here. An earlier pass
stripped the boxes as "wasteful" and flattened the panels to a plain feed —
that was a redesign nobody asked for, and it threw away the one thing that
makes a vendor's territory legible on screen.

ANSI rule that keeps the fill clean: a line sets its background at the start of
each run and emits exactly ONE reset, at the very end. A bare \\033[0m mid-line
hands the background back to the user's Terminal profile, which is what put
grey boxes behind the text in an earlier attempt. Never reset mid-line.
"""
from __future__ import annotations

import argparse
import re
import shutil
import sys
import textwrap
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from stormcode import action_frames as AF  # noqa: E402
from stormcode import icons  # noqa: E402
from stormcode.app import BRAND  # noqa: E402
# Imported but unused on purpose: FACED below is empty, and keeping the import
# is what makes re-enabling the striped face a genuine one-liner.
from stormcode.ibm_stripes import striped  # noqa: E402,F401

RESET = "\033[0m"
BOLD, DIM = "\033[1m", "\033[2m"

VOID = "#000000"      # jet black field
RED = "#ff003c"       # borders, and the app's default text colour
USER_FG = "#ff003c"

# Terminal advances ONE cell per Private Use Area character whatever the font
# declares, so an N-cell bitmap paints N columns while the cursor moves one.
# Each mark carries N-1 trailing spaces to reserve the columns it drew into.
BRAND_CELLS = 3

_ANSI = re.compile(r"\033\[[0-9;]*m")


def vlen(s: str) -> int:
    return len(_ANSI.sub("", s))


def _rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def fg(h: str) -> str:
    r, g, b = _rgb(h)
    return f"\033[38;2;{r};{g};{b}m"


def bg(h: str) -> str:
    r, g, b = _rgb(h)
    return f"\033[48;2;{r};{g};{b}m"


def skin(pid: str | None) -> tuple[str, str]:
    """(background, foreground) for a panel. None == the app's own voice."""
    if pid is None or pid not in BRAND:
        return VOID, USER_FG
    b = BRAND[pid]
    return b.get("bg", VOID), b.get("fg", "#ffffff")


def mark(pid: str | None, use_font: bool) -> str:
    """Exactly BRAND_CELLS cells in every mode, so nothing shifts."""
    pad = " " * (BRAND_CELLS - 1)
    if pid is None:
        return "▶" + pad
    if use_font and pid in icons.GLYPH:
        cp = ord(icons.GLYPH[pid])
        return chr(cp + BRAND_CELLS * 0x100) + pad
    return icons.MARK.get(pid, "◆") + pad


def label_of(pid: str | None) -> str:
    if pid is None:
        return "You"
    return BRAND.get(pid, {}).get("display", pid)


# Vendors with their own display face — DELIBERATELY EMPTY.
#
# The IBM 8-bar face is a DISPLAY face and cannot work at body-text size. At the
# 20 ppem strike a cell is 10x20px, so the cap height is ~14px; eight bars and
# seven gaps inside that means each bar is 1.2px and each gap 0.6px. Sub-pixel:
# they blur to grey haze rather than reading as stripes. IBM only ever set the
# mark at logo scale, for exactly this reason.
#
# It was also slow. Every character became its own sbix PNG — 1,762 bitmaps per
# screen against 25 for the logos — each decoded and alpha-composited on every
# scroll repaint.
#
# The 3-cell logo glyph ALREADY carries the striped wordmark at a size where it
# reads, so nothing is lost. scripts/build_ibm_bars.py and the U+E800+ glyphs
# stay built: put "ibm": striped back here if a large header ever wants them.
FACED: dict[str, object] = {}


def faced(pid: str | None, text: str, use_font: bool) -> str:
    """Draw a name in its vendor's own lettering where we have one."""
    fn = FACED.get(pid or "")
    return fn(text) if (fn and use_font) else text


# The label shown in a panel maps to a drawn icon. Anything unmapped simply
# gets blank cells of the same width, so the columns never shift.
ACT_CELLS = 2
ACTION_MAP = {
    "Search": "search", "Rerank": "rerank", "Reading": "read", "Read": "read",
    "Writing": "write", "Think": "think", "Message": "message",
    "Button Press": "user-press", "Deep Research Template": "template",
    "Prompt Guard 86M": "instruction",
}


def act_icon(action: str, tick: int, pid: str | None = None) -> str:
    """The action's icon for this tick — always exactly ACT_CELLS columns.

    Animation is nothing more than picking a different codepoint each tick and
    redrawing the cell; the font has no timeline of its own.
    """
    concept = ACTION_MAP.get(action)
    if pid is None and concept == "message":
        concept = "user-message"
    if not concept or concept not in AF.FRAMES:
        return " " * ACT_CELLS
    return AF.frame(concept, tick, ACT_CELLS)


# ── the session, exactly as StormCode.md lays it out ─────────────────────────
# (pid, action, title-override, body)   pid None == the user
S: list[tuple] = [
    (None, "Button Press", None, "I have an idea for a story I'd like you to write for me?"),
    ("rivescript", "Message", None,
     "Great! Tell me about the idea and then I'll ask questions to make sure that "
     "I understand everything."),
    (None, "Message", None,
     "It's a Harry Potter fan fiction story where Harry is sent back in time when "
     "he is hit by the killing curse in the Forbidden Forest during book seven — "
     "instead of the canon ending he wakes up as a baby in Godric's Hollow the "
     "night his parents were killed."),
    ("meta", "Prompt Guard 86M", "Llama Prompt Guard", "Benign"),
    ("rivescript", "Message", None,
     "Awesome, any other details you want to add? Perhaps if you told me everything "
     "you can think of about the idea and I'll put these ideas to the writing team?"),
    (None, "Message", None,
     "It's a time travel fix-it type story with a dark Harry who tries to stop "
     "Voldemort by doing highly drastic things which are borderline dark wizard "
     "in nature."),
    ("meta", "Prompt Guard 86M", "Llama Prompt Guard", "Benign"),
    ("rivescript", "Message", None,
     "Great! If you want to add more details now, it would really help us narrow "
     "things down during the writing process. Do you want to add more details "
     "before we begin working?"),
    (None, "Button Press", None, "Yes, I'd like to add some Characters"),
    ("rivescript", "Message", None, "__FORM__"),
    (None, "Message", None, "__SHEET__"),
    ("meta", "Prompt Guard 86M", "Llama Prompt Guard", "Benign"),
    ("rivescript", "Message", None,
     "Nice! Do you want to add some more, or shall we get going with our work?"),
    (None, "Button Press", None, "Launch Agency"),
    ("ibm", "Think", "Granite 4.1 8B",
     "\"Harry Potter\" and \"Book 7\" must mean Harry Potter and the Deathly "
     "Hallows by J.K. Rowling. I will search and find the event the user mentioned."),
    ("ibm", "Deep Research Template", "Granite 4.1 8B", "__TEMPLATE__"),
    ("__LANES__", "", None, ""),
    ("ibm", "Read", "Granite 4.1 8B", "deep-research-report.md"),
    ("ibm", "Think", "Granite 4.1 8B",
     "The report shows that the idea is a highly popular premise in the fan "
     "fiction community with potential for a wide audience.\n"
     "→ Highlight to the user that their story is already likely to be popular "
     "based on the \"Epilogue, what epilogue?\" or \"EWE\" trend among die hard fans.\n\n"
     "Plot: The user has proposed a story which would require quite a long running "
     "writing commitment; writing the plot from the beginning all over again won't "
     "be trivial.\n"
     "→ Highlight that the task ahead is difficult due to the plot holes which "
     "could occur if they ignore the original canon timeline.\n\n"
     "Characters:\n"
     "→ Highlight the importance of keeping the main characters as authentic as "
     "possible in order to avoid alienating the \"EWE\" type demographic readers."),
    ("ibm", "Message", "Granite 4.1 8B",
     "What a great idea! Before we go any further there are a few things I'd like "
     "to mention. The idea touches on what a lot of fans call \"EWE\" which refers "
     "to a common gripe among fans about the way the series ended. Older fans "
     "specifically are drawn to this type of fan fiction.\n\n"
     "Another point to note is that the task ahead for you will be difficult due to "
     "the plot holes which could occur in the story if you don't properly consider "
     "the original canon timeline. There is a high complexity and demanding nature "
     "to writing this type of story for readers who will expect regular updates and "
     "to see the story reach its ending.\n\n"
     "The importance of keeping the characters authentic can also not be "
     "understated. Deal with characters carefully to ensure that you don't alienate "
     "your audience. I can go forward with the story but I need final approval to "
     "create a Story Treatment."),
    (None, "Button Press", None,
     "Yes, I grant final approval to proceed with Pre-Production"),
]

FORM_INTRO = "Perfect, lets lock them down, for each character give me:"
FORM_FIELDS = [
    "Character Name:", "Character Role:  (eg. Protagonist, Antagonist, etc)",
    "Character Outer Goal:", "Character Inner Goal:", "Character Fatal Flaw:",
    "Physical Description:", "Character Age:", "Character Alliances:",
    "Character Biography:", "Character Notes:",
]
FORM_OUTRO = ("If you fill in whatever you can, and leave the parts you don't want "
              "to fill in blank, that's completely fine. Fill in as much or as "
              "little as you like, for as many or as few characters as you like.")

SHEET = [
    ("Character Name:", "Harry Potter"),
    ("Character Role:", "Protagonist"),
    ("Character Outer Goal:", "Defeat Voldemort"),
    ("Character Inner Goal:", "Live in Peace"),
    ("Character Fatal Flaw:", "Forgiving"),
    ("Physical Description:", "Young, black hair, scar on forehead, wears glasses."),
    ("Character Age:", "15 Months"),
    ("Character Alliances:", "None"),
    ("Character Biography:", "Sent back in time to when he was a baby after being "
                             "hit by the killing curse during the Battle of "
                             "Hogwarts in the Deathly Hallows."),
]

LANES = [
    {"tag": "T1a", "name": "Database Research", "source": "RAG",
     "steps": [("ibm", "Granite 4.1 8B", "Search", ["\"Deathly Hallows,", "Forbidden Forest\""], 10),
               ("ibm", "Granite Rerank", "Rerank", ["85 db files"], 10),
               ("alibaba", "Qwen 3.6 14B", "Reading", ["10 database files"], 10),
               ("alibaba", "Qwen 3.6 14B", "Writing", ["db-search-terms.json", "shared-thoughts.md"], 10)]},
    {"tag": "T1b", "name": "Internet Research", "source": "SearXNG",
     "steps": [("ibm", "Granite 4.1 8B", "Search", ["db-search-terms.json"], 10),
               ("jina", "Jina Rerank", "Rerank", ["200 URLs"], 10),
               ("alibaba", "Qwen 3.6 35B", "Reading", ["10 URLs"], 10),
               ("alibaba", "Qwen 3.6 35B", "Writing", ["net-search-terms.json", "shared-thoughts.md"], 10)]},
    {"tag": "T1c", "name": "Deep Research", "source": "RAG + SearXNG",
     "steps": [("ibm", "Granite 4.1 8B", "Search", ["db-terms.json", "net-terms.json"], 10),
               ("alibaba", "Qwen3-VL Rerank", "Rerank", ["250 files · 350 URLs"], 10),
               ("deepseek", "DeepSeek V4 Flash", "Reading", ["10 db files · 10 URLs"], 10),
               ("deepseek", "DeepSeek V4 Flash", "Writing", ["deep-research-report.md"], 10)]},
]


# ── panel primitives ─────────────────────────────────────────────────────────
def rule(w: int, left: str, right: str) -> str:
    return bg(VOID) + fg(RED) + left + "─" * (w - 2) + right + RESET


def prow(w: int, pbg: str, pfg: str, body: str, body_cells: int | None = None) -> str:
    """One panel row: red border, brand fill, single reset at the very end."""
    inner = w - 2
    used = body_cells if body_cells is not None else vlen(body)
    return (bg(VOID) + fg(RED) + "│"
            + bg(pbg) + fg(pfg) + body + " " * max(0, inner - used)
            + bg(VOID) + fg(RED) + "│" + RESET)


def panel(w: int, pid: str | None, action: str, title: str | None,
          body: str, use_font: bool, tick: int = 0) -> list[str]:
    pbg, pfg = skin(pid)
    inner = w - 2
    text_w = inner - 4
    L = [rule(w, "┌", "┐")]

    name = title or label_of(pid)
    head = (f" {mark(pid, use_font)} {BOLD}{faced(pid, name, use_font)}"
            f"{RESET}{bg(pbg)}{fg(pfg)}")
    if action:
        icon = act_icon(action, tick, pid) if use_font else " " * ACT_CELLS
        head += (f"  {icon} {DIM}{faced(pid, action, use_font)}"
                 f"{RESET}{bg(pbg)}{fg(pfg)}")
    L.append(prow(w, pbg, pfg, head))

    # EVERY character inside a branded panel is drawn in that vendor's face —
    # not just the title. faced() is applied to raw text only, never to an
    # already-styled string: an escape like \033[1m contains letters and digits
    # that would be remapped into striped glyphs and corrupt the sequence.
    def F(s: str) -> str:
        return faced(pid, s, use_font)

    def text(s: str, indent: int = 2) -> None:
        for para in s.split("\n\n"):
            for raw in para.split("\n"):
                for ln in textwrap.wrap(raw, text_w - indent + 2) or [""]:
                    L.append(prow(w, pbg, pfg, " " * indent + F(ln)))
            L.append(prow(w, pbg, pfg, ""))

    if body == "__FORM__":
        text(FORM_INTRO)
        for f in FORM_FIELDS:
            L.append(prow(w, pbg, pfg, "   " + F(f)))
        L.append(prow(w, pbg, pfg, ""))
        text(FORM_OUTRO)
    elif body == "__SHEET__":
        for k, v in SHEET:
            wrapped = textwrap.wrap(v, text_w - 26) or [""]
            for i, ln in enumerate(wrapped):
                L.append(prow(w, pbg, pfg,
                              "  " + F((k if i == 0 else "").ljust(24) + ln)))
    elif body == "__TEMPLATE__":
        L.append(prow(w, pbg, pfg, "  " + F("deep-research-template.md")))
    elif body:
        text(body)
    L.append(rule(w, "└", "┘"))
    return L


def lanes(w: int, use_font: bool, tick: int = 0) -> list[str]:
    """Three parallel lanes. Each panel is filled with ITS OWN model's brand."""
    L: list[str] = []
    gap = 1
    # Widths must sum to exactly w, so the remainder is shared out rather than
    # dropped — three equal lanes only fit when (w - gaps) divides by three.
    span = w - gap * 2
    base, rem = divmod(span, 3)
    LW = [base + (1 if i < rem else 0) for i in range(3)]

    def join(parts: list[str]) -> None:
        # The gap between lanes must be painted, not just spaced. Each part
        # ends with a reset, so a bare space here would render on the user's
        # Terminal background and draw a stripe down between the columns.
        L.append((bg(VOID) + " " * gap).join(parts))

    def seg(lw: int, pbg: str, pfg: str, body: str, cells: int | None = None) -> str:
        inner = lw - 2
        used = cells if cells is not None else vlen(body)
        return (bg(VOID) + fg(RED) + "│" + bg(pbg) + fg(pfg) + body
                + " " * max(0, inner - used) + bg(VOID) + fg(RED) + "│" + RESET)

    def hrule(lw: int, l: str, r: str) -> str:
        return bg(VOID) + fg(RED) + l + "─" * (lw - 2) + r + RESET

    join([hrule(lw, "┌", "┐") for lw in LW])
    join([seg(lw, VOID, RED,
              f" {BOLD}{l['tag']}{RESET}{bg(VOID)}{fg(RED)}  {l['name'][:lw - 8]}")
          for lw, l in zip(LW, LANES)])
    # The RESET must re-establish the field, or the padding seg() appends after
    # it renders on the user's own Terminal background — which is what put a
    # black rectangle after "Source: RAG" in every lane.
    join([seg(lw, VOID, RED,
              f" {DIM}Source: {l['source'][:lw - 12]}{RESET}{bg(VOID)}{fg(RED)}")
          for lw, l in zip(LW, LANES)])
    join([hrule(lw, "├", "┤") for lw in LW])

    for s in range(4):
        depth = max(len(l["steps"][s][3]) for l in LANES)
        rows: list[list[str]] = []
        for lw, l in zip(LW, LANES):
            inner, tw = lw - 2, lw - 4
            pid, name, action, details, done = l["steps"][s]
            pbg, pfg = skin(pid)
            nm = name[:tw - BRAND_CELLS - 1]
            col = [seg(lw, pbg, pfg,
                       f" {mark(pid, use_font)} {faced(pid, nm, use_font)}")]
            ic = act_icon(action, tick, pid) if use_font else " " * ACT_CELLS
            col.append(seg(lw, pbg, pfg,
                           f" {ic} {DIM}{faced(pid, action, use_font)}"
                           f"{RESET}{bg(pbg)}{fg(pfg)}"))
            for k in range(depth):
                d = details[k][:tw] if k < len(details) else ""
                col.append(seg(lw, pbg, pfg, "  " + faced(pid, d, use_font)))
            # Tag first, bar gets whatever is left — " 10/10 " is 7 cells, not 6,
            # and hard-coding that width is what pushed these rows over.
            tag = faced(pid, f" {done}/10 ", use_font)
            barw = max(0, inner - len(tag))
            fill = round(barw * done / 10)
            col.append(bg(VOID) + fg(RED) + "│" + bg(pbg)
                       + fg(RED) + "█" * fill + " " * (barw - fill)
                       + fg(pfg) + tag
                       + bg(VOID) + fg(RED) + "│" + RESET)
            rows.append(col)
        for i in range(len(rows[0])):
            join([r[i] for r in rows])
        join([hrule(lw, "├" if s < 3 else "└", "┤" if s < 3 else "┘")
              for lw in LW])
    return L


def header(w: int) -> list[str]:
    left = f" AGENCY  {BOLD}Harry Potter{RESET}{bg(VOID)}{fg(RED)} · EWE time-travel "
    right = " 04:17 · 128.4k tok · $0.27 "
    dash = w - vlen(left) - vlen(right)
    return [bg(VOID) + fg(RED) + left + "─" * max(0, dash) + right + RESET,
            bg(VOID) + " " * w + RESET]


def build(w: int, use_font: bool, tick: int = 0) -> list[str]:
    out = header(w)
    for pid, action, title, body in S:
        if pid == "__LANES__":
            out += lanes(w, use_font, tick)
        else:
            out += panel(w, pid, action, title, body, use_font, tick)
        out.append(bg(VOID) + " " * w + RESET)
    return out


def live(w: int, use_font: bool, fps: float) -> int:
    """Animate the lanes in place.

    Only the lanes animate, because only the lanes fit: the full transcript is
    ~200 rows and would scroll its own header off the top. Redrawing is a cursor
    jump plus a reprint — each frame is a different codepoint in the same cell,
    so the terminal repaints one glyph per icon and nothing reflows.
    """
    body = header(w) + lanes(w, use_font, 0)
    print("\033[?25l", end="")
    try:
        sys.stdout.write("\n" * len(body))
        tick = 0
        while True:
            rows = header(w) + lanes(w, use_font, tick)
            sys.stdout.write(f"\033[{len(rows)}A")
            sys.stdout.write("\n".join(r + "\033[K" for r in rows) + "\n")
            sys.stdout.flush()
            time.sleep(1.0 / fps)
            tick += 1
    except KeyboardInterrupt:
        pass
    finally:
        print("\033[?25h" + RESET, end="")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--plain", action="store_true")
    ap.add_argument("--lanes", action="store_true")
    ap.add_argument("--live", action="store_true",
                    help="animate the lanes in place; ctrl-c to stop")
    ap.add_argument("--fps", type=float, default=10.0)
    ap.add_argument("--tick", type=int, default=0,
                    help="which animation frame to draw in the static views")
    args = ap.parse_args()

    cols = shutil.get_terminal_size((100, 40)).columns
    w = max(76, min(cols - 1, 100))
    use_font = not args.plain

    if args.live:
        return live(w, use_font, max(1.0, args.fps))
    out = (header(w) + lanes(w, use_font, args.tick) if args.lanes
           else build(w, use_font, args.tick))
    sys.stdout.write("\n".join(out) + RESET + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
