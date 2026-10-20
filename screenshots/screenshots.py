#!/usr/bin/env python3
"""Render deterministic screenshots of yagent inside yazi.

Drives a real yazi session in tmux (100x14) against a generated demo repo
with fake agent state, captures the pane text with SGR escapes, and renders
each capture to a terminal-window PNG through an SVG. Requires rsvg-convert
or ImageMagick's `magick`; without either it still writes the SVGs.

    python3 screenshots/screenshots.py [--only NAME] [--svg-dir DIR]
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unicodedata
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DEMO = Path(__file__).resolve().parent / "demo-repo"
IMAGES = Path(__file__).resolve().parent / "images"

COLUMNS = 100
ROWS = 14
FONT = "JetBrainsMono Nerd Font Mono, JetBrainsMono Nerd Font, JetBrains Mono, Menlo, monospace"
FONT_SIZE = 14
LINE_HEIGHT = 20
CHAR_WIDTH = 8.43
PAD = 16
TITLE_HEIGHT = 36
BG = "#1b1b1f"
FG = "#d6d6d6"
DIM = "#8b8b8b"
BORDER = "#333"

PALETTE16 = [
    "#1b1b1f", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd",
    "#56b6c2", "#d6d6d6", "#6b6b73", "#ef7a85", "#a5d48a", "#ecd08a",
    "#74baf5", "#d28ae6", "#6cc5cf", "#ffffff",
]
CUBE_LEVELS = (0, 95, 135, 175, 215, 255)

SGR_RE = re.compile(r"\x1b\[([0-9;]*)m")

# name -> (state, action, title, live tmux session?)
AGENTS = {
    "api": ("working", "thinking", "add rate limiting middleware", True),
    "auth": ("needs-you", "awaiting input", "refactor auth to async/await", True),
    "db": ("done", "", "migrate users table", False),
}

SHOT_TITLES = {
    "browse": "yagent",
    "new-agent": "yagent · N  new agent",
    "overview": "yagent · g a  agents overview",
}


def color_256(index):
    if index < 16:
        return PALETTE16[index]
    if index < 232:
        index -= 16
        red = CUBE_LEVELS[index // 36]
        green = CUBE_LEVELS[(index % 36) // 6]
        blue = CUBE_LEVELS[index % 6]
        return "#%02x%02x%02x" % (red, green, blue)
    level = 8 + 10 * (index - 232)
    return "#%02x%02x%02x" % (level, level, level)


def parse_line(line):
    """Split a line into (text, style) runs.

    Style keys: bold, dim, inverse, fg, bg. fg/bg are None when default.
    """
    style = {"bold": False, "dim": False, "inverse": False, "fg": None, "bg": None}
    runs = []
    cursor = 0
    for match in SGR_RE.finditer(line):
        if match.start() > cursor:
            runs.append((line[cursor:match.start()], dict(style)))
        codes = [int(code) for code in match.group(1).split(";") if code] or [0]
        index = 0
        while index < len(codes):
            code = codes[index]
            if code == 0:
                style = {"bold": False, "dim": False, "inverse": False,
                         "fg": None, "bg": None}
            elif code == 1:
                style["bold"] = True
            elif code == 2:
                style["dim"] = True
            elif code == 7:
                style["inverse"] = True
            elif code == 22:
                style["bold"] = style["dim"] = False
            elif code == 27:
                style["inverse"] = False
            elif 30 <= code <= 37:
                style["fg"] = PALETTE16[code - 30]
            elif 90 <= code <= 97:
                style["fg"] = PALETTE16[code - 90 + 8]
            elif 40 <= code <= 47:
                style["bg"] = PALETTE16[code - 40]
            elif 100 <= code <= 107:
                style["bg"] = PALETTE16[code - 100 + 8]
            elif code == 39:
                style["fg"] = None
            elif code == 49:
                style["bg"] = None
            elif code in (38, 48) and index + 2 < len(codes) and codes[index + 1] == 5:
                key = "fg" if code == 38 else "bg"
                style[key] = color_256(codes[index + 2])
                index += 2
            elif code in (38, 48) and index + 4 < len(codes) and codes[index + 1] == 2:
                key = "fg" if code == 38 else "bg"
                style[key] = "#%02x%02x%02x" % tuple(codes[index + 2:index + 5])
                index += 4
            index += 1
        cursor = match.end()
    if cursor < len(line):
        runs.append((line[cursor:], dict(style)))
    return runs


def cell_width(ch):
    return 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1


def line_cells(runs):
    """Flatten runs into [(char, style, width)] cells."""
    return [
        (ch, style, cell_width(ch))
        for segment, style in runs
        for ch in segment
    ]


def effective(style):
    """Resolve a cell style to (fg, bg, bold) paint colours.

    bg is None when the terminal background shows through.
    """
    fg = style["fg"] or FG
    bg = style["bg"]
    if style["inverse"]:
        fg, bg = (bg or BG), fg
    elif style["dim"]:
        fg = DIM
    return fg, bg, style["bold"]


def escape(text):
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
    )


def render_svg(text, title):
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    rows = len(lines)
    width = int(PAD + COLUMNS * CHAR_WIDTH + PAD)
    height = TITLE_HEIGHT + PAD + rows * LINE_HEIGHT + PAD
    parts = [
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'width="%d" height="%d" viewBox="0 0 %d %d">' % (width, height, width, height),
        '<rect x="0.5" y="0.5" width="%d" height="%d" rx="10" fill="%s" stroke="%s"/>'
        % (width - 1, height - 1, BG, BORDER),
        '<path d="M0.5 10.5 a10 10 0 0 1 10 -10 h%d a10 10 0 0 1 10 10 v25.5 h-%d z" '
        'fill="#2a2a2e"/>' % (width - 21, width - 1),
        '<circle cx="20" cy="18.5" r="6" fill="#ff5f57"/>',
        '<circle cx="40" cy="18.5" r="6" fill="#febc2e"/>',
        '<circle cx="60" cy="18.5" r="6" fill="#28c840"/>',
        '<text x="%d" y="23" fill="%s" font-family="%s" font-size="13" '
        'text-anchor="middle">%s</text>'
        % (width // 2, DIM, FONT, escape(title)),
        '<g font-family="%s" font-size="%d" xml:space="preserve">'
        % (FONT, FONT_SIZE),
    ]
    top = TITLE_HEIGHT + PAD
    for row, line in enumerate(lines):
        cells = line_cells(parse_line(line))
        column = 0
        run_text = []
        run_style = None
        run_col = 0
        run_width = 0

        def flush():
            nonlocal run_text, run_style, run_col, run_width
            if not run_text:
                return
            fg, bg, bold = run_style
            x = PAD + run_col * CHAR_WIDTH
            y = top + row * LINE_HEIGHT + 14
            if bg is not None:
                parts.append(
                    '<rect x="%.2f" y="%d" width="%.2f" height="18" fill="%s"/>'
                    % (x, top + row * LINE_HEIGHT + 1, run_width * CHAR_WIDTH, bg)
                )
            weight = ' font-weight="700"' if bold else ""
            parts.append(
                '<text x="%.2f" y="%d" fill="%s"%s>%s</text>'
                % (x, y, fg, weight, escape("".join(run_text)))
            )
            run_text = []
            run_style = None
            run_width = 0

        for ch, style, w in cells:
            paint = effective(style)
            # Non-ASCII glyphs get their own centred <text> so a font
            # fallback can't shift the columns around them.
            if not ch.isascii() and ch != " ":
                flush()
                fg, bg, bold = paint
                x = PAD + (column + w / 2) * CHAR_WIDTH
                y = top + row * LINE_HEIGHT + 14
                if bg is not None:
                    parts.append(
                        '<rect x="%.2f" y="%d" width="%.2f" height="18" fill="%s"/>'
                        % (PAD + column * CHAR_WIDTH,
                           top + row * LINE_HEIGHT + 1, w * CHAR_WIDTH, bg)
                    )
                weight = ' font-weight="700"' if bold else ""
                parts.append(
                    '<text x="%.2f" y="%d" fill="%s"%s text-anchor="middle">%s</text>'
                    % (x, y, fg, weight, escape(ch))
                )
            else:
                if run_style is None:
                    run_col = column
                if run_style is not None and paint != run_style:
                    flush()
                    run_col = column
                if run_style is None:
                    run_col = column
                run_style = paint
                run_text.append(ch)
                run_width += w
            column += w
        flush()
    parts.append("</g>")
    parts.append("</svg>")
    return "\n".join(parts) + "\n"


# ── demo environment ────────────────────────────────────────────────────────

def slug_for(directory):
    return "yagent-" + hashlib.sha256(directory.encode()).hexdigest()[:12]


def build_demo(state_root):
    """Create the demo tree, agent locks/state files, and dummy tmux sessions.

    Returns (src_dir, [dummy tmux session names]).
    """
    for rel in ("docs", "test", "src/api", "src/auth", "src/db", "src/web"):
        (DEMO / rel).mkdir(parents=True, exist_ok=True)
    dummies = []
    for name, (state, action, title, live) in AGENTS.items():
        directory = os.path.realpath(DEMO / "src" / name)
        lock = Path(directory) / ".yagent"
        lock.mkdir(exist_ok=True)
        (lock / "owner.json").write_text(json.dumps({
            "id": "demo-%s" % name,
            "title": title,
            "tmux_session": slug_for(directory),
            "created_at": 1,
        }))
        key = hashlib.sha256(directory.encode()).hexdigest()
        (Path(state_root) / ("%s.json" % key)).write_text(json.dumps({
            "workdir": directory,
            "state": state,
            "action": action,
            "title": title,
        }))
        if live:
            slug = slug_for(directory)
            subprocess.run(
                ["tmux", "new-session", "-d", "-s", slug, "sleep 900"],
                check=True,
            )
            dummies.append(slug)
    return os.path.realpath(DEMO / "src"), dummies


# ── tmux driving ────────────────────────────────────────────────────────────

def tmux(*args):
    subprocess.run(["tmux"] + list(args), check=True)


def send(session, *keys):
    tmux("send-keys", "-t", session, *keys)


def send_literal(session, text):
    tmux("send-keys", "-l", "-t", session, text)


def capture(session):
    out = subprocess.run(
        ["tmux", "capture-pane", "-p", "-e", "-N", "-t", session],
        check=True, capture_output=True, text=True,
    ).stdout
    return out.rstrip("\n")


def wait_for(session, needle, timeout=10.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if needle in capture(session):
            return True
        time.sleep(0.25)
    return False


def take_shots():
    """Run one yazi session in tmux; return {shot_name: captured_text}."""
    state_root = tempfile.mkdtemp(prefix="yagent-state-")
    session = "yagent-shot-%d" % os.getpid()
    src, dummies = build_demo(state_root)
    shots = {}
    try:
        env = (
            "env PATH=%s:%s YAGENT_STATE_ROOT=%s YAGENT_YAZI_ID=%d yagent ."
            % (REPO / "bin", os.environ["PATH"], state_root, int(time.time()))
        )
        tmux("new-session", "-d", "-s", session, "-x", str(COLUMNS),
             "-y", str(ROWS), "-c", src, env)
        if not wait_for(session, "needs you"):
            raise RuntimeError("yazi never showed the 'needs you' chip")

        send(session, "j")          # hover auth
        time.sleep(0.8)
        shots["browse"] = capture(session)

        send(session, "G")          # hover web (no agent)
        time.sleep(0.8)
        send(session, "N")
        time.sleep(0.8)
        send_literal(session, "add a dark mode toggle to settings")
        time.sleep(0.8)
        shots["new-agent"] = capture(session)
        send(session, "Escape")
        time.sleep(0.4)
        send(session, "Escape")
        time.sleep(0.4)

        send(session, "g", "g")     # back to top
        time.sleep(0.8)
        send(session, "j")          # hover auth so its panel is visible
        time.sleep(0.8)
        send(session, "g")
        time.sleep(0.3)
        send(session, "a")
        time.sleep(1.5)
        shots["overview"] = capture(session)
        send(session, "Escape")
        time.sleep(0.4)
    finally:
        subprocess.run(["tmux", "kill-session", "-t", session],
                       capture_output=True)
        for slug in dummies:
            subprocess.run(["tmux", "kill-session", "-t", slug],
                           capture_output=True)
        shutil.rmtree(state_root, ignore_errors=True)
        for name in AGENTS:
            shutil.rmtree(DEMO / "src" / name / ".yagent", ignore_errors=True)
    return shots


# ── output ──────────────────────────────────────────────────────────────────

def convert(svg_path, png_path):
    rsvg = shutil.which("rsvg-convert")
    if rsvg:
        subprocess.run(
            [rsvg, "-z", "2", str(svg_path), "-o", str(png_path)],
            check=True,
        )
        if png_path.stat().st_size > 400 * 1024:
            subprocess.run(
                [rsvg, "-z", "1.5", str(svg_path), "-o", str(png_path)],
                check=True,
            )
        return True
    magick = shutil.which("magick")
    if magick:
        subprocess.run(
            [magick, "-density", "192", str(svg_path), str(png_path)],
            check=True,
        )
        return True
    return False


def main():
    parser = argparse.ArgumentParser(prog="screenshots")
    parser.add_argument("--only", choices=sorted(SHOT_TITLES))
    parser.add_argument("--svg-dir", help="keep the intermediate SVGs here")
    args = parser.parse_args()

    IMAGES.mkdir(exist_ok=True)
    svg_dir = Path(args.svg_dir) if args.svg_dir else Path(
        tempfile.mkdtemp(prefix="yagent-shots-svg-")
    )
    svg_dir.mkdir(parents=True, exist_ok=True)

    shots = take_shots()
    names = [args.only] if args.only else list(SHOT_TITLES)
    wrote_png = False
    for name in names:
        if name not in shots:
            print("shot %r was not captured" % name, file=sys.stderr)
            continue
        svg_path = svg_dir / ("%s.svg" % name)
        svg_path.write_text(render_svg(shots[name], SHOT_TITLES[name]),
                            encoding="utf-8")
        png_path = IMAGES / ("%s.png" % name)
        if convert(svg_path, png_path):
            wrote_png = True
            print(png_path)
        else:
            print("no rsvg-convert/magick found; wrote SVG only: %s" % svg_path)
    if args.svg_dir:
        print("SVGs kept in %s" % svg_dir)
    return 0 if wrote_png or args.svg_dir else 1


if __name__ == "__main__":
    sys.exit(main())
