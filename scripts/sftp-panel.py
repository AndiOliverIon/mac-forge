#!/usr/bin/env python3
"""Dual-pane SSH/SFTP browser: left = remote (SFTP), right = local filesystem.

Launched by sshc.sh after a station is picked. The remote side uses paramiko
over SSH, resolving the host through ~/.ssh/config exactly like the ssh client
(falling back to sensible defaults for hosts without a config block).

Navigation is fzf-style: just start typing to filter the active panel and the
selection jumps to the first fuzzy match. Letters are reserved for filtering,
so transfer actions use function keys.

Keys:
  <type>         filter active panel (fuzzy, fzf-style)
  Esc            clear filter (or quit when the filter is empty)
  Tab            switch active panel
  Up/Down        move selection among matches
  PgUp/PgDn      page selection
  Home/End       jump to first/last match
  Enter / Right  enter directory (clears filter)
  Left           parent directory
  Backspace      delete a filter char, or go to parent when filter is empty
  F6             upload selected local file to remote current dir
  F5             download selected remote file to local current dir
  Ctrl-R         refresh both panels
  F10 / Ctrl-Q   quit
"""

import curses
import getpass
import os
import shutil
import stat
import sys
import termios
import time

import paramiko

# Color pair ids, populated by setup_colors().
CP = {
    "normal": 0,
    "dir": 0,
    "sel_active": 0,
    "sel_inactive": 0,
    "header_active": 0,
    "header_inactive": 0,
    "dim": 0,
    "status": 0,
    "warn": 0,
}


def disable_flow_control():
    """Stop the tty from eating Ctrl-Q / Ctrl-S (XON/XOFF) so we can bind them."""
    try:
        fd = sys.stdin.fileno()
        attrs = termios.tcgetattr(fd)
        attrs[0] &= ~(termios.IXON | termios.IXOFF | termios.IXANY)
        termios.tcsetattr(fd, termios.TCSANOW, attrs)
    except Exception:
        pass


def setup_colors():
    """Dark theme: black background with a few accent colors."""
    if not curses.has_colors():
        return False
    curses.start_color()
    try:
        curses.use_default_colors()
        bg = -1  # terminal's native background (true black in a dark theme)
    except curses.error:
        bg = curses.COLOR_BLACK
    curses.init_pair(1, curses.COLOR_WHITE, bg)     # normal
    curses.init_pair(2, curses.COLOR_CYAN, bg)      # directory
    curses.init_pair(3, curses.COLOR_BLACK, curses.COLOR_CYAN)   # active selection bar
    curses.init_pair(4, curses.COLOR_WHITE, bg)     # inactive selection (underline)
    curses.init_pair(5, curses.COLOR_BLACK, curses.COLOR_WHITE)  # active header
    curses.init_pair(6, curses.COLOR_WHITE, bg)     # inactive header
    curses.init_pair(7, curses.COLOR_WHITE, bg)     # dim/help
    curses.init_pair(8, curses.COLOR_GREEN, bg)     # status
    curses.init_pair(9, curses.COLOR_RED, bg)       # warning / danger
    CP["normal"] = curses.color_pair(1)
    CP["dir"] = curses.color_pair(2) | curses.A_BOLD
    CP["sel_active"] = curses.color_pair(3) | curses.A_BOLD
    CP["sel_inactive"] = curses.color_pair(4) | curses.A_UNDERLINE
    CP["header_active"] = curses.color_pair(5) | curses.A_BOLD
    CP["header_inactive"] = curses.color_pair(6)
    CP["dim"] = curses.color_pair(7) | curses.A_DIM
    CP["status"] = curses.color_pair(8) | curses.A_BOLD
    CP["warn"] = curses.color_pair(9) | curses.A_BOLD
    return True


def fuzzy_match(query, text):
    """fzf-like subsequence match; case-insensitive. Empty query matches all."""
    if not query:
        return True
    q = query.lower()
    t = text.lower()
    pos = 0
    for ch in q:
        pos = t.find(ch, pos)
        if pos < 0:
            return False
        pos += 1
    return True


def human_size(n):
    if n is None:
        return "?"
    units = ["B", "K", "M", "G", "T", "P"]
    f = float(n)
    i = 0
    while f >= 1024 and i < len(units) - 1:
        f /= 1024
        i += 1
    if i == 0:
        return "{}B".format(int(n))
    return "{:.1f}{}".format(f, units[i])


def local_size(path, is_dir):
    try:
        if not is_dir:
            return os.path.getsize(path)
        total = 0
        for root, _dirs, files in os.walk(path):
            for name in files:
                try:
                    total += os.path.getsize(os.path.join(root, name))
                except OSError:
                    pass
        return total
    except OSError:
        return None


class Progress:
    """Throttled transfer progress drawn on the bottom status line.

    Redraws at most ~10x/sec so rendering never throttles the transfer.
    """

    def __init__(self, stdscr, label, total, interval=0.1):
        self.stdscr = stdscr
        self.label = label
        self.total = total
        self.interval = interval
        self.done = 0
        self.start = time.time()
        self.last = 0.0
        self._draw(force=True)

    def advance(self, n):
        self.done += n
        now = time.time()
        if now - self.last >= self.interval:
            self.last = now
            self._draw()

    def _draw(self, force=False):
        try:
            h, w = self.stdscr.getmaxyx()
        except curses.error:
            return
        elapsed = max(1e-6, time.time() - self.start)
        rate = self.done / elapsed
        if self.total:
            pct = min(100, int(self.done * 100 / self.total))
            bar_w = max(10, min(30, w - 50))
            filled = int(bar_w * pct / 100)
            bar = "#" * filled + "-" * (bar_w - filled)
            text = "{}  [{}] {:3d}%  {}/{}  {}/s".format(
                self.label, bar, pct,
                human_size(self.done), human_size(self.total), human_size(int(rate)))
        else:
            text = "{}  {}  {}/s".format(
                self.label, human_size(self.done), human_size(int(rate)))
        try:
            self.stdscr.move(h - 2, 0)
            self.stdscr.clrtoeol()
            self.stdscr.addstr(h - 2, 0, ("> " + text)[: w - 1], CP["status"])
            self.stdscr.refresh()
        except curses.error:
            pass


def ensure_sizes(panel, remote):
    """Compute sizes once per directory listing; cached via panel.sized_path."""
    if panel.sized_path == panel.path:
        return
    for e in panel.all_entries:
        if e["name"] == "..":
            e["size"] = None
            continue
        if panel.kind == "remote":
            if e["is_dir"]:
                e["size"] = remote.size(e["name"], True)
            elif e.get("size") is not None:
                pass  # size already known from the MLSD listing
            else:
                e["size"] = remote.size(e["name"], False)
        else:
            e["size"] = local_size(os.path.join(panel.path, e["name"]), e["is_dir"])
    panel.sized_path = panel.path


class Panel:
    def __init__(self, kind):
        self.kind = kind  # "remote" or "local"
        self.path = ""
        self.all_entries = []  # full listing: {name, is_dir}
        self.entries = []      # filtered view
        self.query = ""
        self.idx = 0
        self.top = 0
        self.sized_path = None  # path for which sizes were last computed

    def set_entries(self, entries, keep_query=False):
        self.all_entries = entries
        self.sized_path = None
        if not keep_query:
            self.query = ""
        self.apply_filter()

    def apply_filter(self):
        if self.query:
            self.entries = [e for e in self.all_entries if fuzzy_match(self.query, e["name"])]
        else:
            self.entries = list(self.all_entries)
        self.idx = 0
        self.top = 0

    @property
    def selected(self):
        if 0 <= self.idx < len(self.entries):
            return self.entries[self.idx]
        return None


class RemoteSSH:
    def __init__(self, host_alias, display):
        self.display = display
        cfg = paramiko.SSHConfig()
        cfg_path = os.path.expanduser("~/.ssh/config")
        if os.path.exists(cfg_path):
            with open(cfg_path) as f:
                cfg.parse(f)
        o = cfg.lookup(host_alias)
        hostname = o.get("hostname", host_alias)
        user = o.get("user") or getpass.getuser()
        port = int(o.get("port", 22))
        key_files = o.get("identityfile")

        client = paramiko.SSHClient()
        client.load_system_host_keys()
        known = os.path.expanduser("~/.ssh/known_hosts")
        if os.path.exists(known):
            try:
                client.load_host_keys(known)
            except Exception:
                pass
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

        kwargs = dict(
            hostname=hostname, port=port, username=user,
            timeout=30, allow_agent=True, look_for_keys=True,
        )
        if key_files:
            kwargs["key_filename"] = [os.path.expanduser(k) for k in key_files]
        client.connect(**kwargs)

        self.client = client
        self.sftp = client.open_sftp()
        self._cwd = self.sftp.normalize(".")

    def _resolve(self, path):
        import posixpath
        if path.startswith("/"):
            return posixpath.normpath(path)
        return posixpath.normpath(posixpath.join(self._cwd, path))

    def cwd(self):
        return self._cwd

    def chdir(self, path):
        target = self._resolve(path)
        self._cwd = self.sftp.normalize(target)

    def size(self, path, is_dir):
        """Size in bytes. Files via stat; directories summed recursively."""
        rp = self._resolve(path)
        if not is_dir:
            try:
                return self.sftp.stat(rp).st_size
            except Exception:
                return None
        total = 0
        try:
            for attr in self.sftp.listdir_attr(rp):
                child = rp.rstrip("/") + "/" + attr.filename
                if stat.S_ISDIR(attr.st_mode):
                    total += self.size(child, True) or 0
                else:
                    total += attr.st_size or 0
        except Exception:
            return None
        return total

    def list(self, path):
        rp = self._resolve(path)
        entries = []
        for attr in self.sftp.listdir_attr(rp):
            name = attr.filename
            if name in (".", ".."):
                continue
            is_dir = stat.S_ISDIR(attr.st_mode)
            entries.append({
                "name": name,
                "is_dir": is_dir,
                "size": None if is_dir else attr.st_size,
            })
        return entries

    def download(self, remote_name, local_path, callback=None):
        rp = self._resolve(remote_name)
        self.sftp.get(rp, local_path, callback=callback)

    def upload(self, local_path, remote_name, callback=None):
        rp = self._resolve(remote_name)
        self.sftp.put(local_path, rp, callback=callback)

    def delete(self, path, is_dir):
        """Delete a remote file, or a directory recursively."""
        rp = self._resolve(path)
        if not is_dir:
            self.sftp.remove(rp)
            return
        for attr in self.sftp.listdir_attr(rp):
            child = rp.rstrip("/") + "/" + attr.filename
            self.delete(child, stat.S_ISDIR(attr.st_mode))
        self.sftp.rmdir(rp)

    def close(self):
        try:
            self.sftp.close()
        except Exception:
            pass
        try:
            self.client.close()
        except Exception:
            pass


def load_remote(panel, remote, path=None, keep_query=False):
    if path is not None:
        remote.chdir(path)
    panel.path = remote.cwd()
    entries = remote.list(panel.path)
    entries.sort(key=lambda e: (not e["is_dir"], e["name"].lower()))
    if panel.path not in ("/", ""):
        entries.insert(0, {"name": "..", "is_dir": True})
    panel.set_entries(entries, keep_query=keep_query)


def load_local(panel, path=None, keep_query=False):
    if path is not None:
        panel.path = os.path.abspath(path)
    if not panel.path:
        panel.path = os.getcwd()
    entries = []
    try:
        with os.scandir(panel.path) as it:
            for e in it:
                try:
                    is_dir = e.is_dir(follow_symlinks=True)
                except OSError:
                    is_dir = False
                entries.append({"name": e.name, "is_dir": is_dir})
    except OSError:
        entries = []
    entries.sort(key=lambda e: (not e["is_dir"], e["name"].lower()))
    if os.path.dirname(panel.path) != panel.path:
        entries.insert(0, {"name": "..", "is_dir": True})
    panel.set_entries(entries, keep_query=keep_query)


def draw_panel(win, panel, active, height, width, show_sizes=False):
    win.bkgd(" ", CP["normal"])
    win.erase()
    border = CP["header_active"] if active else CP["dim"]
    win.attron(border)
    win.box()
    win.attroff(border)

    title = " {} : {} ".format(panel.kind.upper(), panel.path)
    title = title[: width - 2]
    hattr = CP["header_active"] if active else CP["header_inactive"]
    win.addstr(0, 1, title, hattr)

    # Filter query shown on the bottom border of the active panel.
    if active and panel.query:
        q = " /{} ({}) ".format(panel.query, len(panel.entries))
        q = q[: width - 2]
        win.addstr(height - 1, 1, q, CP["sel_active"])

    view_h = height - 2
    if panel.idx < panel.top:
        panel.top = panel.idx
    elif panel.idx >= panel.top + view_h:
        panel.top = panel.idx - view_h + 1

    if not panel.entries:
        msg = "(no matches)" if panel.query else "(empty)"
        win.addstr(1, 1, msg[: width - 3], CP["dim"])

    avail = width - 3
    for row in range(view_h):
        i = panel.top + row
        if i >= len(panel.entries):
            break
        e = panel.entries[i]
        size_str = ""
        if show_sizes and e["name"] != "..":
            size_str = human_size(e.get("size"))
        name = e["name"] + ("/" if e["is_dir"] else "")
        namew = avail - (len(size_str) + 1) if size_str else avail
        namew = max(1, namew)
        label = name[:namew].ljust(namew)
        content = label + ((" " + size_str) if size_str else "")
        line = (" " + content)[: avail + 1]
        if i == panel.idx and active:
            attr = CP["sel_active"]
        elif i == panel.idx:
            attr = CP["sel_inactive"]
        elif e["is_dir"]:
            attr = CP["dir"]
        else:
            attr = CP["normal"]
        win.addstr(row + 1, 1, line, attr)
    win.noutrefresh()


def main(stdscr, host_alias, display):
    curses.curs_set(0)
    stdscr.keypad(True)
    disable_flow_control()
    setup_colors()
    stdscr.bkgd(" ", CP["normal"])

    stdscr.addstr(0, 0, "Connecting to {} ...".format(display))
    stdscr.refresh()

    try:
        remote = RemoteSSH(host_alias, display)
    except Exception as exc:  # noqa: BLE001
        stdscr.addstr(2, 0, "Connection failed: {}".format(exc))
        stdscr.addstr(4, 0, "Press any key to exit.")
        stdscr.getch()
        return

    left = Panel("remote")
    right = Panel("local")
    load_remote(left, remote)
    load_local(right, os.getcwd())

    active = left
    status = "Connected: {}".format(display)
    show_sizes = False

    while True:
        h, w = stdscr.getmaxyx()
        panel_h = h - 2
        panel_w = w // 2

        if show_sizes:
            if left.sized_path != left.path or right.sized_path != right.path:
                stdscr.addstr(h - 2, 0, ("> Calculating sizes...")[: w - 1], CP["status"])
                stdscr.refresh()
            ensure_sizes(left, remote)
            ensure_sizes(right, remote)

        stdscr.erase()
        help_line = "type filter  Tab switch  Enter open  F5 dl  F6 up  Del rm  ^S sizes  ^H help  ^Q quit"
        stdscr.addstr(h - 1, 0, help_line[: w - 1], CP["dim"])
        stdscr.addstr(h - 2, 0, ("> " + status)[: w - 1], CP["status"])
        stdscr.noutrefresh()

        lwin = stdscr.derwin(panel_h, panel_w, 0, 0)
        rwin = stdscr.derwin(panel_h, w - panel_w, 0, panel_w)
        draw_panel(lwin, left, active is left, panel_h, panel_w, show_sizes)
        draw_panel(rwin, right, active is right, panel_h, w - panel_w, show_sizes)
        curses.doupdate()

        key = stdscr.getch()

        if key in (curses.KEY_F10, 17):  # F10 or Ctrl-Q
            break
        elif key == 19:  # Ctrl-S: toggle size display
            show_sizes = not show_sizes
            status = "Sizes shown (folders summed)." if show_sizes else "Sizes hidden."
        elif key == 27:  # Esc: clear filter, else quit
            if active.query:
                active.query = ""
                active.apply_filter()
            else:
                break
        elif key == ord("\t"):
            active = right if active is left else left
        elif key == curses.KEY_UP:
            active.idx = max(0, active.idx - 1)
        elif key == curses.KEY_DOWN:
            active.idx = min(len(active.entries) - 1, active.idx + 1)
        elif key == curses.KEY_NPAGE:
            active.idx = min(len(active.entries) - 1, active.idx + (panel_h - 2))
        elif key == curses.KEY_PPAGE:
            active.idx = max(0, active.idx - (panel_h - 2))
        elif key == curses.KEY_HOME:
            active.idx = 0
        elif key == curses.KEY_END:
            active.idx = max(0, len(active.entries) - 1)
        elif key in (curses.KEY_RIGHT, curses.KEY_ENTER, ord("\n"), ord("\r")):
            sel = active.selected
            if sel and sel["is_dir"]:
                try:
                    if active.kind == "remote":
                        load_remote(active, remote, sel["name"])
                    else:
                        newp = os.path.abspath(os.path.join(active.path, sel["name"]))
                        load_local(active, newp)
                except Exception as exc:  # noqa: BLE001
                    status = "Error: {}".format(exc)
        elif key == curses.KEY_LEFT:
            status = go_parent(active, remote) or status
        elif key in (curses.KEY_BACKSPACE, 127):
            if active.query:
                active.query = active.query[:-1]
                active.apply_filter()
            else:
                status = go_parent(active, remote) or status
        elif key == curses.KEY_F5:
            status = do_download(stdscr, left, right, remote)
        elif key == curses.KEY_F6:
            status = do_upload(stdscr, left, right, remote)
        elif key in (curses.KEY_DC, 330):  # Del -> delete with confirmation
            status = do_delete(stdscr, active, remote)
        elif key == 18:  # Ctrl-R
            try:
                load_remote(left, remote, left.path, keep_query=True)
                load_local(right, right.path, keep_query=True)
                status = "Refreshed."
            except Exception as exc:  # noqa: BLE001
                status = "Error: {}".format(exc)
        elif key == 8:  # Ctrl-H -> help overlay
            show_help(stdscr)
        elif 32 <= key <= 126:  # printable -> extend filter
            active.query += chr(key)
            active.apply_filter()

    remote.close()


def confirm_overlay(stdscr, title, lines, danger_line=None):
    """Centered yes/no overlay. Returns True on confirm, False on cancel."""
    footer = "Enter / y = confirm     Esc / n = cancel"
    content = list(lines) + ["", footer]
    while True:
        h, w = stdscr.getmaxyx()
        box_w = min(max([len(s) for s in content] + [len(title) + 4]) + 4, w - 2)
        box_h = min(len(content) + 2, h - 2)
        y0 = (h - box_h) // 2
        x0 = (w - box_w) // 2

        win = curses.newwin(box_h, box_w, y0, x0)
        win.bkgd(" ", CP["normal"])
        win.erase()
        win.attron(CP["warn"])
        win.box()
        win.attroff(CP["warn"])
        win.addstr(0, 2, " {} ".format(title), CP["warn"])

        for row, text in enumerate(content):
            if row + 1 >= box_h - 1:
                break
            if text == footer:
                attr = CP["dim"]
            elif danger_line is not None and text == danger_line:
                attr = CP["warn"]
            else:
                attr = CP["normal"]
            win.addstr(row + 1, 2, text[: box_w - 4], attr)
        win.noutrefresh()
        curses.doupdate()

        key = stdscr.getch()
        if key in (ord("y"), ord("Y"), ord("\n"), ord("\r"), curses.KEY_ENTER):
            return True
        if key in (27, ord("n"), ord("N"), ord("q")):
            return False


def do_delete(stdscr, panel, remote):
    sel = panel.selected
    if not sel or sel["name"] == "..":
        return "Select an item to delete."
    kind = "folder" if sel["is_dir"] else "file"
    where = "remote" if panel.kind == "remote" else "local"
    target = os.path.join(panel.path, sel["name"]) if panel.kind == "local" else \
        panel.path.rstrip("/") + "/" + sel["name"]
    lines = [
        "Delete this {} {}?".format(where, kind),
        "",
        "  " + target,
    ]
    if sel["is_dir"]:
        lines.append("")
        lines.append("This removes the folder and ALL its contents.")
    if not confirm_overlay(stdscr, "Confirm delete", lines, danger_line="  " + target):
        return "Delete cancelled."
    try:
        if panel.kind == "remote":
            remote.delete(sel["name"], sel["is_dir"])
            load_remote(panel, remote, panel.path, keep_query=True)
        else:
            if sel["is_dir"]:
                shutil.rmtree(target)
            else:
                os.remove(target)
            load_local(panel, panel.path, keep_query=True)
    except Exception as exc:  # noqa: BLE001
        return "Delete failed: {}".format(exc)
    return "Deleted: {}".format(sel["name"])


HELP_LINES = [
    "mac-forge SSH/SFTP browser - key bindings",
    "",
    "Navigation",
    "  type text        filter active panel (fzf-style fuzzy match)",
    "  Backspace        delete a filter char, or go to parent if empty",
    "  Esc              clear filter, or quit when the filter is empty",
    "  Up / Down        move selection among matches",
    "  PgUp / PgDn      page selection",
    "  Home / End       jump to first / last match",
    "  Enter / Right    enter selected directory (clears filter)",
    "  Left             go to parent directory",
    "  Tab              switch active panel (remote <-> local)",
    "",
    "Transfers",
    "  F5               download selected remote file -> local dir",
    "  F6               upload selected local file -> remote dir",
    "  Del              delete selected file/folder (asks to confirm)",
    "",
    "Session",
    "  Ctrl-R           refresh both panels",
    "  Ctrl-S           show / hide sizes (folders summed recursively)",
    "  Ctrl-H           show / hide this help",
    "  Ctrl-Q / F10     quit",
    "",
    "Panels: left = remote (SFTP), right = local filesystem.",
    "Directories are shown in cyan and sorted before files.",
    "",
    "Scroll: Up/Down or PgUp/PgDn.  Close: Esc, q, Enter or Ctrl-H.",
]


def show_help(stdscr):
    """Scrollable, centered help overlay."""
    top = 0
    while True:
        h, w = stdscr.getmaxyx()
        box_h = min(len(HELP_LINES) + 4, h - 2)
        box_w = min(max(len(s) for s in HELP_LINES) + 4, w - 2)
        y0 = (h - box_h) // 2
        x0 = (w - box_w) // 2
        inner_h = box_h - 4  # lines available for content
        max_top = max(0, len(HELP_LINES) - inner_h)
        top = max(0, min(top, max_top))

        win = curses.newwin(box_h, box_w, y0, x0)
        win.bkgd(" ", CP["normal"])
        win.erase()
        win.attron(CP["header_active"])
        win.box()
        win.attroff(CP["header_active"])
        win.addstr(0, 2, " Help ", CP["header_active"])

        for row in range(inner_h):
            i = top + row
            if i >= len(HELP_LINES):
                break
            line = HELP_LINES[i][: box_w - 4]
            attr = CP["dir"] if (line and not line.startswith(" ") and ":" not in line and i != 0) else CP["normal"]
            if i == 0:
                attr = CP["status"]
            win.addstr(row + 1, 2, line, attr)

        footer = "Up/Down PgUp/PgDn scroll   Esc/q/Enter/^H close"
        if max_top > 0:
            pct = int(top * 100 / max_top)
            footer = "{}   {}%".format(footer, pct)
        win.addstr(box_h - 2, 2, footer[: box_w - 4], CP["dim"])
        win.noutrefresh()
        curses.doupdate()

        key = stdscr.getch()
        if key in (27, ord("q"), ord("\n"), ord("\r"), curses.KEY_ENTER, 8):
            break
        elif key in (curses.KEY_DOWN, ord("j")):
            top += 1
        elif key in (curses.KEY_UP, ord("k")):
            top -= 1
        elif key == curses.KEY_NPAGE:
            top += inner_h
        elif key == curses.KEY_PPAGE:
            top -= inner_h
        elif key == curses.KEY_HOME:
            top = 0
        elif key == curses.KEY_END:
            top = max_top


def go_parent(panel, remote):
    try:
        if panel.kind == "remote":
            load_remote(panel, remote, "..")
        else:
            load_local(panel, os.path.dirname(panel.path))
        return None
    except Exception as exc:  # noqa: BLE001
        return "Error: {}".format(exc)


def _cumulative_cb(progress):
    """Adapt paramiko's (transferred, total) cumulative callback to Progress deltas."""
    state = {"last": 0}

    def cb(transferred, _total):
        progress.advance(transferred - state["last"])
        state["last"] = transferred

    return cb


def do_download(stdscr, left, right, remote):
    sel = left.selected
    if not sel or sel["name"] == "..":
        return "Select a remote file to download."
    if sel["is_dir"]:
        return "Directory download is not supported; pick a file."
    dest = os.path.join(right.path, sel["name"])
    total = sel.get("size")
    progress = Progress(stdscr, "Downloading " + sel["name"], total)
    try:
        remote.download(sel["name"], dest, callback=_cumulative_cb(progress))
    except Exception as exc:  # noqa: BLE001
        return "Download failed: {}".format(exc)
    load_local(right, right.path, keep_query=True)
    return "Downloaded: {} ({})".format(sel["name"], human_size(progress.done))


def do_upload(stdscr, left, right, remote):
    sel = right.selected
    if not sel or sel["name"] == "..":
        return "Select a local file to upload."
    src = os.path.join(right.path, sel["name"])
    if os.path.isdir(src):
        return "Directory upload is not supported; pick a file."
    try:
        total = os.path.getsize(src)
    except OSError:
        total = None
    progress = Progress(stdscr, "Uploading " + sel["name"], total)
    try:
        remote.upload(src, sel["name"], callback=_cumulative_cb(progress))
    except Exception as exc:  # noqa: BLE001
        return "Upload failed: {}".format(exc)
    load_remote(left, remote, left.path, keep_query=True)
    return "Uploaded: {} ({})".format(sel["name"], human_size(progress.done))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.stderr.write("usage: sftp-panel.py <ssh-host> [display]\n")
        sys.exit(2)
    host_ = sys.argv[1]
    display_ = sys.argv[2] if len(sys.argv) > 2 else host_
    try:
        curses.wrapper(main, host_, display_)
    except KeyboardInterrupt:
        pass
