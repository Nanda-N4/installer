#!/usr/bin/env python3
N4_VERSION = "2026.09.24-r10"

import html
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

BASE = Path("/etc/n4vpn/shares")
CONF = Path("/etc/n4vpn/n4.conf")


def read_conf():
    out = {}
    try:
        for line in CONF.read_text(encoding="utf-8", errors="ignore").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip().strip('"').strip("'")
    except OSError:
        pass
    return out


def load_token(token):
    if not token or any(
        c not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
        for c in token
    ):
        return None, "invalid"

    path = BASE / f"{token}.json"

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None, "missing"
    except Exception:
        return None, "unreadable"

    try:
        exp = int(data.get("expires_epoch", 0))
    except Exception:
        exp = 0

    if exp <= int(time.time()):
        try:
            path.unlink()
        except OSError:
            pass
        return None, "expired"

    return data, "ok"


def esc(value):
    return html.escape(str(value or ""))


class Handler(BaseHTTPRequestHandler):
    server_version = "N4Share/2.0"

    def log_message(self, fmt, *args):
        return

    def send_bytes(self, code, body, ctype="text/html; charset=utf-8"):
        if isinstance(body, str):
            body = body.encode()

        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "no-referrer")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parts = urlparse(self.path).path.strip("/").split("/")

        if len(parts) != 2 or parts[0] != "s":
            return self.send_bytes(
                404,
                "Not found",
                "text/plain; charset=utf-8",
            )

        data, state = load_token(parts[1])

        if not data:
            msg = (
                "This share link has expired."
                if state == "expired"
                else "This share link is invalid or revoked."
            )
            return self.send_bytes(
                410,
                msg,
                "text/plain; charset=utf-8",
            )

        rows = []

        fields = [
            ("Host", "host"),
            ("Username", "username"),
            ("Password", "password"),
            ("VPN SSH", "ssh_port"),
            ("WebSocket", "ws_ports"),
            ("Hybrid / Dropbear", "hybrid_port"),
            ("Dropbear Ports", "dropbear_ports"),
            ("SlowDNS NS", "slowdns_ns"),
        ]

        for label, key in fields:
            val = data.get(key)
            if val not in (None, "", "disabled"):
                rows.append(
                    f"""
                    <div class="item">
                        <div class="item-top">
                            <span class="label">{esc(label)}</span>
                            <button class="copy" onclick="cp('{key}', this)">
                                Copy
                            </button>
                        </div>
                        <code id="{key}">{esc(val)}</code>
                    </div>
                    """
                )

        body = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="robots" content="noindex,nofollow,noarchive">
<meta name="theme-color" content="#07090d">
<title>N4 VPN</title>

<style>
:root {{
    color-scheme: dark;
    --bg: #06080c;
    --panel: #0d1117;
    --panel-2: #0a0e13;
    --line: #1b2430;
    --text: #f5f7fa;
    --muted: #8894a3;
    --accent: #ff334f;
    --accent-soft: rgba(255, 51, 79, .10);
    --green: #7ee6a2;
}}

* {{
    box-sizing: border-box;
    -webkit-tap-highlight-color: transparent;
}}

html, body {{
    margin: 0;
    min-height: 100%;
    background:
        radial-gradient(circle at top, rgba(255, 51, 79, .08), transparent 32%),
        var(--bg);
    color: var(--text);
    font-family:
        Inter,
        ui-sans-serif,
        system-ui,
        -apple-system,
        BlinkMacSystemFont,
        "Segoe UI",
        Roboto,
        Arial,
        sans-serif;
}}

body {{
    padding:
        max(16px, env(safe-area-inset-top))
        14px
        max(20px, env(safe-area-inset-bottom));
}}

.wrap {{
    width: 100%;
    max-width: 520px;
    margin: 0 auto;
}}

.card {{
    overflow: hidden;
    border: 1px solid var(--line);
    border-radius: 22px;
    background: rgba(13, 17, 23, .96);
    box-shadow:
        0 24px 60px rgba(0, 0, 0, .35),
        inset 0 1px 0 rgba(255,255,255,.025);
}}

.head {{
    padding: 20px 18px 16px;
    border-bottom: 1px solid var(--line);
}}

.brand {{
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
}}

.logo {{
    display: flex;
    align-items: center;
    gap: 11px;
    min-width: 0;
}}

.logo-mark {{
    width: 42px;
    height: 42px;
    flex: 0 0 42px;
    display: grid;
    place-items: center;
    border-radius: 13px;
    background:
        linear-gradient(145deg, #ff3c58, #a6001d);
    box-shadow:
        0 8px 24px rgba(255, 51, 79, .22),
        inset 0 1px 0 rgba(255,255,255,.22);
    font-weight: 900;
    letter-spacing: -1.5px;
    font-size: 17px;
    color: white;
}}

.logo-text {{
    min-width: 0;
}}

.logo-text strong {{
    display: block;
    font-size: 18px;
    line-height: 1.1;
    letter-spacing: -.3px;
}}

.logo-text span {{
    display: block;
    margin-top: 3px;
    color: var(--muted);
    font-size: 12px;
}}

.badge {{
    flex: 0 0 auto;
    padding: 7px 10px;
    border: 1px solid rgba(255, 51, 79, .28);
    border-radius: 999px;
    background: var(--accent-soft);
    color: #ff8ea0;
    font-size: 10px;
    font-weight: 800;
    letter-spacing: .8px;
}}

.meta {{
    margin-top: 15px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    color: var(--muted);
    font-size: 12px;
}}

.status {{
    display: inline-flex;
    align-items: center;
    gap: 7px;
}}

.dot {{
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: var(--green);
    box-shadow: 0 0 0 4px rgba(126, 230, 162, .08);
}}

.content {{
    padding: 6px 18px 4px;
}}

.item {{
    padding: 14px 0;
    border-bottom: 1px solid var(--line);
}}

.item:last-child {{
    border-bottom: 0;
}}

.item-top {{
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    margin-bottom: 8px;
}}

.label {{
    color: #a8b2bf;
    font-size: 12px;
    font-weight: 700;
    letter-spacing: .2px;
}}

code {{
    display: block;
    width: 100%;
    overflow-x: auto;
    white-space: nowrap;
    padding: 11px 12px;
    border: 1px solid #202b37;
    border-radius: 12px;
    background: var(--panel-2);
    color: var(--green);
    font:
        13px/1.35
        ui-monospace,
        SFMono-Regular,
        Menlo,
        Monaco,
        Consolas,
        monospace;
    scrollbar-width: none;
}}

code::-webkit-scrollbar {{
    display: none;
}}

.copy {{
    border: 0;
    border-radius: 9px;
    padding: 7px 10px;
    background: #171d26;
    color: #dbe2ea;
    font-size: 11px;
    font-weight: 750;
    cursor: pointer;
    transition: .16s ease;
}}

.copy:active {{
    transform: scale(.96);
}}

.copy.ok {{
    background: rgba(126, 230, 162, .12);
    color: var(--green);
}}

.foot {{
    padding: 14px 18px 18px;
    border-top: 1px solid var(--line);
}}

.note {{
    display: flex;
    gap: 9px;
    align-items: flex-start;
    color: var(--muted);
    font-size: 11px;
    line-height: 1.5;
}}

.note-icon {{
    color: var(--accent);
    font-weight: 900;
}}

.n4 {{
    margin-top: 16px;
    text-align: center;
    color: #596675;
    font-size: 10px;
    letter-spacing: .7px;
}}

@media (max-width: 380px) {{
    body {{
        padding-left: 10px;
        padding-right: 10px;
    }}

    .head,
    .content,
    .foot {{
        padding-left: 14px;
        padding-right: 14px;
    }}

    .badge {{
        padding: 6px 8px;
        font-size: 9px;
    }}

    .logo-text strong {{
        font-size: 17px;
    }}
}}
</style>
</head>

<body>
<div class="wrap">
    <section class="card">

        <header class="head">
            <div class="brand">
                <div class="logo">
                    <div class="logo-mark">N4</div>
                    <div class="logo-text">
                        <strong>N4 VPN</strong>
                        <span>Secure Access Details</span>
                    </div>
                </div>

                <div class="badge">PRIVATE</div>
            </div>

            <div class="meta">
                <span class="status">
                    <span class="dot"></span>
                    Active Account
                </span>

                <span>Expires {esc(data.get("expires_date", ""))}</span>
            </div>
        </header>

        <main class="content">
            {"".join(rows)}
        </main>

        <footer class="foot">
            <div class="note">
                <span class="note-icon">●</span>
                <span>
                    This private share link automatically expires with your account.
                </span>
            </div>
        </footer>
    </section>

    <div class="n4">N4 NETWORK • {esc(N4_VERSION)}</div>
</div>

<script>
async function cp(id, btn) {{
    const el = document.getElementById(id);
    const text = el.textContent;

    try {{
        await navigator.clipboard.writeText(text);
    }} catch (_) {{
        const area = document.createElement("textarea");
        area.value = text;
        area.style.position = "fixed";
        area.style.opacity = "0";
        document.body.appendChild(area);
        area.focus();
        area.select();
        document.execCommand("copy");
        area.remove();
    }}

    const old = btn.textContent;
    btn.textContent = "Copied";
    btn.classList.add("ok");

    setTimeout(() => {{
        btn.textContent = old;
        btn.classList.remove("ok");
    }}, 1100);
}}
</script>

</body>
</html>
"""

        self.send_bytes(200, body)


def main():
    BASE.mkdir(parents=True, exist_ok=True)

    cfg = read_conf()

    try:
        port = int(cfg.get("SHARE_PORT", "8880"))
    except ValueError:
        port = 8880

    if not 1 <= port <= 65535:
        port = 8880

    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
