#!/usr/bin/env python3
"""One panel per BRAND provider — colour review grid.

    .venv/bin/python scripts/show_panels.py              # paginate, keypress
    .venv/bin/python scripts/show_panels.py --page 1     # one page, exit
    .venv/bin/python scripts/show_panels.py --provider xai
    .venv/bin/python scripts/show_panels.py --check      # square grid assert

Panel chrome matches scripts/demo_swarm.py (red border, brand fill, logo
badge, model name, task id, action lines). Every key in stormcode.app.BRAND
gets a panel — no subset.

CRITICAL (measured, do not re-derive):
- Terminal font must be Menlo-RegularStormCodeColor or logos are tofu.
- Content taller than the window scrolls the top away. Every finished frame
  is measured against shutil.get_terminal_size().lines and trimmed before
  print (same discipline as demo_swarm.render).
"""
from __future__ import annotations

import argparse
import re
import shutil
import sys
import termios
import tty
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from stormcode import icons  # noqa: E402
from stormcode.app import BRAND, brand_display, use_icon_font  # noqa: E402
from stormcode import providers as P  # noqa: E402

R = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"
CLEAR = "\033[2J\033[H"
HIDE, SHOW = "\033[?25l", "\033[?25h"

FRAME = "#ff003c"
GHOST = "#8a8a8a"
FLASH = "#ffffff"
VOID = "#000000"

_ANSI = re.compile(r"\033\[[0-9;?]*[a-zA-Z]")

GUTTER = 1
MIN_PANEL = 34
ACTION_LINES = 2
# border, title, task id, actions…, border — same as demo_swarm
PANEL_ROWS = 2 + ACTION_LINES + 2
# page title + rule + footer rule + footer + bottom border, + print() NL reserve
PAGE_CHROME = 6

# Use the same explicit preference as the app. An installed font file alone
# does not prove the active Terminal profile is the colour font.
USE_FONT = use_icon_font()
CELLS = 3

def vlen(s: str) -> int:
    return len(_ANSI.sub("", s))


def fit(s: str, w: int) -> str:
    n = vlen(s)
    if n == w:
        return s
    if n < w:
        return s + " " * (w - n)
    out, count = [], 0
    i = 0
    while i < len(s):
        m = _ANSI.match(s, i)
        if m:
            out.append(m.group())
            i = m.end()
            continue
        if count + 1 > w:
            break
        out.append(s[i])
        count += 1
        i += 1
    if count < w:
        out.append(" " * (w - count))
    return "".join(out)


def fg(h: str) -> str:
    h = h.lstrip("#")
    return f"\033[38;2;{int(h[0:2],16)};{int(h[2:4],16)};{int(h[4:6],16)}m"


def bg(h: str) -> str:
    h = h.lstrip("#")
    return f"\033[48;2;{int(h[0:2],16)};{int(h[2:4],16)};{int(h[4:6],16)}m"


def logo(pid: str) -> str:
    """3-cell colour badge + trailing spaces the cursor did not advance over."""
    if not USE_FONT:
        return icons.mark(pid) + "  "
    g = icons.GLYPH.get(pid)
    if not g:
        return icons.mark(pid) + "  "
    cp = ord(g) if CELLS == 1 else ord(g) + CELLS * 0x100
    return chr(cp) + " " * (CELLS - 1)


def all_provider_ids() -> list[str]:
    """Every BRAND key, stable order: known PROVIDERS first, then the rest."""
    primary = [pid for pid in P.PROVIDERS if pid in BRAND]
    rest = sorted(pid for pid in BRAND if pid not in primary)
    # de-dupe while preserving order (BRAND may redefine a key)
    seen: set[str] = set()
    out: list[str] = []
    for pid in primary + rest:
        if pid not in seen:
            seen.add(pid)
            out.append(pid)
    return out


def top(inner: int) -> str:
    return f"{bg(VOID)}{fg(FRAME)}┌{'─' * inner}┐{R}"


def mid(inner: int) -> str:
    return f"{bg(VOID)}{fg(FRAME)}├{'─' * inner}┤{R}"


def bot(inner: int) -> str:
    return f"{bg(VOID)}{fg(FRAME)}└{'─' * inner}┘{R}"


def row(body: str, inner: int) -> str:
    return (f"{bg(VOID)}{fg(FRAME)}│{R}{bg(VOID)}{fit(body, inner)}"
            f"{bg(VOID)}{fg(FRAME)}│{R}")


def geometry(force_cols: int | None = None) -> tuple[int, int, int]:
    term = shutil.get_terminal_size((100, 40)).columns
    avail = max(MIN_PANEL, min(term - 2, 150))
    if force_cols is not None:
        cols = max(1, force_cols)
    else:
        cols = max(1, min(3, (avail + GUTTER) // (MIN_PANEL + GUTTER)))
    pw = (avail - GUTTER * (cols - 1)) // cols
    inner = pw * cols + GUTTER * (cols - 1)
    return inner, pw, cols


def panel(pid: str, pw: int, *, large: bool = False,
          state: str = "DONE") -> list[str]:
    """Same boxed panel as demo_swarm.panel — brand fill, red edge, logo."""
    b = BRAND[pid]
    model = brand_display(pid)
    if pid == "ibm" and use_icon_font():
        # The three-cell bitmap is already the complete IBM wordmark.
        model = ""
    tid = f"T-{pid}-review"
    actions = ["Scanning brand/", "Painting panel", "colour check"]
    paint = bg(b["bg"]) + fg(b["fg"])
    edge = bg(VOID) + fg(FRAME)
    iw = pw - 2
    mark = {"DONE": "DONE", "RUNNING": "RUN ", "WAITING": "WAIT"}[state]
    action_n = max(ACTION_LINES, 4 if large else ACTION_LINES)

    def boxed(body: str) -> str:
        return f"{edge}│{R}{fit(body, iw)}{R}{edge}│{R}"

    lines = [f"{edge}┌{'─' * iw}┐{R}"]
    logo_paint = fg(b.get("mark", b["fg"]))
    head = fit(
        f"{paint}{BOLD} {logo_paint}{logo(pid)}{fg(b['fg'])}  {model}",
        iw - len(mark) - 1,
    )
    lines.append(boxed(f"{head}{paint}{DIM}{mark} "))
    lines.append(boxed(f"{paint}{DIM}  {tid}"))
    if large:
        lines.append(boxed(
            f"{paint}{DIM}  id={pid}  company={b['company']}  "
            f"display={b['display']}"))
        lines.append(boxed(f"{paint}{DIM}  bg={b['bg']}  fg={b['fg']}  "
                           f"tint={b['tint']}"))
    for i, a in enumerate(actions[:action_n]):
        shown = f"  > {a}" if i < len(actions) else "  "
        lines.append(boxed(f"{paint}{DIM}{shown}"))
    lines.append(f"{edge}└{'─' * iw}┘{R}")
    return lines


def panels_per_page(cols: int) -> int:
    """How many panels fit in one page without overflowing the window."""
    lines = shutil.get_terminal_size((100, 40)).lines
    # reserve PAGE_CHROME + 2 (print newline + prompt breathing room)
    room = max(PANEL_ROWS, lines - PAGE_CHROME - 2)
    rows_of_panels = max(1, room // (PANEL_ROWS + 1))  # +1 mid rule per row
    return rows_of_panels * cols


def trim_to_fit(L: list[str]) -> list[str]:
    """Guarantee the finished frame fits. Copied discipline from demo_swarm.

    One row reserved for the newline print() appends, one for the shell
    prompt / keypress line afterwards.
    """
    lines_avail = shutil.get_terminal_size((100, 40)).lines - 2
    while len(L) > lines_avail and len(L) > 4:
        # Drop content just above the bottom border (footer text first, then
        # panel mid-rules / rows). Never drop the closing border itself.
        if len(L) >= 2 and L[-1].startswith(f"{bg(VOID)}{fg(FRAME)}└"):
            del L[-2]
        else:
            del L[-1]
    return L


def render_page(ids: list[str], page: int, total_pages: int,
                page_ids: list[str]) -> str:
    inner, pw, cols = geometry()
    title = (f"Panel review  {len(ids)} providers  "
             f"page {page}/{total_pages}")
    L = [top(inner), row(f" {BOLD}{fg(FLASH)}{title}{R}", inner), mid(inner)]

    for r in range(0, len(page_ids), cols):
        group = [panel(page_ids[r + c], pw)
                 for c in range(cols) if r + c < len(page_ids)]
        if not group:
            break
        for i in range(len(group[0])):
            L.append(row(fit((" " * GUTTER).join(g[i] for g in group), inner),
                         inner))
        L.append(mid(inner))

    # providers not yet shown after this page
    remaining = max(0, len(ids) - ((page - 1) * panels_per_page(cols)
                                   + len(page_ids)))
    # drop trailing mid before footer chrome
    if L and L[-1].startswith(f"{bg(VOID)}{fg(FRAME)}├"):
        L.pop()
    if page < total_pages:
        foot = (f" {DIM}{fg(GHOST)}{remaining} more · "
                f"press any key for next · q to quit{R}")
    else:
        foot = f" {DIM}{fg(GHOST)}end · press any key to exit{R}"
    L.append(mid(inner))
    L.append(row(foot, inner))
    L.append(bot(inner))

    L = trim_to_fit(L)
    return "\n".join(L)


def render_one(pid: str) -> str:
    """Single provider, large panel."""
    if pid not in BRAND:
        known = ", ".join(all_provider_ids())
        raise SystemExit(f"unknown provider {pid!r}. BRAND keys: {known}")
    term = shutil.get_terminal_size((100, 40)).columns
    # wide single panel, still inside a red frame
    inner = max(MIN_PANEL, min(term - 2, 100))
    pw = inner
    L = [
        top(inner),
        row(f" {BOLD}{fg(FLASH)}Provider  {pid}{R}", inner),
        mid(inner),
    ]
    for line in panel(pid, pw, large=True, state="RUNNING"):
        L.append(row(fit(line, inner), inner))
    L.append(bot(inner))
    L = trim_to_fit(L)
    return "\n".join(L)


def pages_of(ids: list[str]) -> list[list[str]]:
    _, _, cols = geometry()
    n = panels_per_page(cols)
    return [ids[i:i + n] for i in range(0, len(ids), n)] or [[]]


def wait_key() -> str:
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        ch = sys.stdin.read(1)
        # swallow CSI sequences (arrow keys)
        if ch == "\033":
            rest = ""
            try:
                rest = sys.stdin.read(2)
            except Exception:
                pass
            ch = ch + rest
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
    return ch


def check() -> int:
    """Every nonempty row on every page must share one visible width."""
    ids = all_provider_ids()
    bad = 0
    for page_ids in pages_of(ids):
        # re-render via the same path as interactive (page numbers ignored for width)
        frame = render_page(ids, 1, 1, page_ids)
        widths: dict[int, list[int]] = {}
        for i, line in enumerate(frame.splitlines()):
            if not line:
                continue
            widths.setdefault(vlen(line), []).append(i)
        if len(widths) > 1:
            bad += 1
            print("ragged -> "
                  + ", ".join(f"{w} cells x{len(v)}"
                              for w, v in sorted(widths.items())))
    # also every single-provider view
    for pid in ids:
        frame = render_one(pid)
        widths = {}
        for i, line in enumerate(frame.splitlines()):
            if not line:
                continue
            widths.setdefault(vlen(line), []).append(i)
        if len(widths) > 1:
            bad += 1
            print(f"{pid}: ragged")
    print("GRID OK — every row is square" if not bad else f"{bad} ragged frames")
    return 1 if bad else 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--page", type=int, default=None,
                    help="show only this 1-based page and exit")
    ap.add_argument("--provider", type=str, default=None,
                    help="show one provider panel large")
    ap.add_argument("--check", action="store_true",
                    help="assert every row is the same visible width")
    ap.add_argument("--list", action="store_true",
                    help="print provider ids and exit")
    args = ap.parse_args(argv)

    if args.check:
        return check()

    ids = all_provider_ids()
    if args.list:
        for pid in ids:
            b = BRAND[pid]
            print(f"{pid:16}  company={b['company']:<16}  display={b['display']}")
        print(f"# {len(ids)} providers in BRAND", file=sys.stderr)
        return 0

    def emit(frame: str) -> None:
        # Only clear when painting to a real terminal — pipes/diagnose want
        # the raw rows, not a leading CSI clear.
        prefix = CLEAR if sys.stdout.isatty() else ""
        sys.stdout.write(prefix + frame + "\n")
        sys.stdout.flush()

    if args.provider:
        emit(render_one(args.provider))
        return 0

    chunks = pages_of(ids)
    total = len(chunks)

    if args.page is not None:
        if args.page < 1 or args.page > total:
            raise SystemExit(f"--page must be 1..{total} ({len(ids)} providers)")
        page_ids = chunks[args.page - 1]
        emit(render_page(ids, args.page, total, page_ids))
        return 0

    # interactive pagination
    if not sys.stdin.isatty():
        # non-TTY: dump page 1 only (diagnose / pipes)
        emit(render_page(ids, 1, total, chunks[0]))
        return 0

    try:
        sys.stdout.write(HIDE)
        for i, page_ids in enumerate(chunks, 1):
            sys.stdout.write(CLEAR + render_page(ids, i, total, page_ids) + "\n")
            sys.stdout.flush()
            if i >= total:
                break
            ch = wait_key()
            if ch.lower() in ("q", "\x03"):  # q or Ctrl-C
                break
    except KeyboardInterrupt:
        pass
    finally:
        sys.stdout.write(SHOW)
        sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
