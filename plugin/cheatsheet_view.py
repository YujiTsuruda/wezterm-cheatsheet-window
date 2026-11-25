#!/usr/bin/env python3
"""Show the cheatsheet. q / Esc closes; j / k scrolls when it does not fit.

Usage: cheatsheet_view.py TEXT FOOTER TITLE
"""

import os
import re
import select
import shutil
import signal
import sys
import termios
import tty

SGR = re.compile(r"(\x1b\[[0-9;]*m)")


def read_key(fd):
    # Arrow keys are multi-byte sequences starting with Esc; read them whole
    data = os.read(fd, 1)
    while select.select([fd], [], [], 0.02)[0]:
        data += os.read(fd, 32)
    return data


def draw(lines, top, body, footer):
    out = ["\x1b[H\x1b[2J"]
    for row, line in enumerate(lines[top : top + body]):
        out.append(f"\x1b[{row + 1};2H{line}\x1b[0m")
    out.append(f"\x1b[{body + 2};2H\x1b[2m{footer}\x1b[0m")
    sys.stdout.write("".join(out))
    sys.stdout.flush()


def main():
    text, footer, title = sys.argv[1:4]
    lines = text.split("\n")
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    # Redraw when the window is resized
    wake_read, wake_write = os.pipe()
    os.set_blocking(wake_write, False)
    signal.set_wakeup_fd(wake_write)
    signal.signal(signal.SIGWINCH, lambda *_: None)
    top = 0
    try:
        tty.setcbreak(fd)
        # Alternate screen, no cursor, no line wrapping
        sys.stdout.write(f"\x1b]0;{title}\x07\x1b[?1049h\x1b[?25l\x1b[?7l")
        while True:
            body = max(shutil.get_terminal_size().lines - 2, 1)
            last_top = max(len(lines) - body, 0)
            top = min(max(top, 0), last_top)
            draw(lines, top, body, footer)
            ready = select.select([fd, wake_read], [], [])[0]
            if wake_read in ready:
                os.read(wake_read, 1024)
                continue
            key = read_key(fd)
            if key in (b"q", b"\x1b", b"\x03", b""):
                break
            if key in (b"j", b"\x1b[B"):
                top += 1
            elif key in (b"k", b"\x1b[A"):
                top -= 1
            elif key in (b" ", b"\x1b[6~"):
                top += body
            elif key == b"\x1b[5~":
                top -= body
    finally:
        sys.stdout.write("\x1b[?7h\x1b[?25h\x1b[?1049l")
        sys.stdout.flush()
        termios.tcsetattr(fd, termios.TCSADRAIN, old)


if __name__ == "__main__":
    main()
