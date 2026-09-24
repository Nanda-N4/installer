#!/usr/bin/env python3
import html
import json
import os
import subprocess
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

BASE = Path('/etc/n4vpn/shares')
CONF = Path('/etc/n4vpn/n4.conf')


def read_conf():
    out = {}
    try:
        for line in CONF.read_text(encoding='utf-8', errors='ignore').splitlines():
            line = line.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            k, v = line.split('=', 1)
            out[k.strip()] = v.strip().strip('"').strip("'")
    except OSError:
        pass
    return out


def load_token(token):
    if not token or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-' for c in token):
        return None, 'invalid'
    path = BASE / f'{token}.json'
    try:
        with path.open(encoding='utf-8') as f:
            data = json.load(f)
    except FileNotFoundError:
        return None, 'missing'
    except (OSError, ValueError, TypeError):
        return None, 'unreadable'

    try:
        expires = int(data.get('expires_epoch', 0))
    except (TypeError, ValueError):
        expires = 0
    if expires <= int(time.time()):
        try:
            path.unlink()
        except OSError:
            pass
        return None, 'expired'
    return data, 'ok'


def esc(value):
    return html.escape(str(value or ''))


class Handler(BaseHTTPRequestHandler):
    server_version = 'N4Share/1.1'

    def log_message(self, fmt, *args):
        return

    def send_bytes(self, code, body, ctype='text/html; charset=utf-8', extra=None):
        if isinstance(body, str):
            body = body.encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store, max-age=0')
        self.send_header('Pragma', 'no-cache')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('X-Frame-Options', 'DENY')
        self.send_header('Referrer-Policy', 'no-referrer')
        if extra:
            for k, v in extra.items():
                self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parts = urlparse(self.path).path.strip('/').split('/')
        if len(parts) < 2 or parts[0] != 's':
            return self.send_bytes(404, 'Not found', 'text/plain; charset=utf-8')

        token = parts[1]
        data, state = load_token(token)
        if not data:
            if state == 'expired':
                msg = 'This share link has expired.'
            else:
                msg = 'This share link is invalid or revoked.'
            return self.send_bytes(410, msg, 'text/plain; charset=utf-8')

        if len(parts) == 3 and parts[2] == 'wireguard.conf':
            cfg = data.get('wireguard_config', '')
            if not cfg:
                return self.send_bytes(404, 'No WireGuard config', 'text/plain; charset=utf-8')
            name = ''.join(c for c in str(data.get('username', 'n4')) if c.isalnum() or c in ('-', '_')) or 'n4'
            return self.send_bytes(
                200,
                cfg,
                'text/plain; charset=utf-8',
                {'Content-Disposition': f'attachment; filename="{name}.conf"'},
            )

        if len(parts) == 3 and parts[2] == 'wireguard.svg':
            cfg = data.get('wireguard_config', '')
            if not cfg:
                return self.send_bytes(404, 'No WireGuard config', 'text/plain; charset=utf-8')
            try:
                proc = subprocess.run(
                    ['qrencode', '-t', 'SVG', '-o', '-'],
                    input=cfg.encode('utf-8'),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                    timeout=4,
                    check=True,
                )
                return self.send_bytes(200, proc.stdout, 'image/svg+xml')
            except Exception:
                return self.send_bytes(503, 'QR unavailable', 'text/plain; charset=utf-8')

        rows = []
        for label, key in [
            ('Host', 'host'),
            ('Username', 'username'),
            ('Password', 'password'),
            ('VPN SSH', 'ssh_port'),
            ('WebSocket', 'ws_ports'),
            ('Dropbear', 'dropbear_ports'),
            ('SlowDNS NS', 'slowdns_ns'),
            ('WireGuard Endpoint', 'wg_endpoint'),
            ('WireGuard MTU', 'wg_mtu'),
        ]:
            value = data.get(key)
            if value not in (None, '', 'disabled'):
                rows.append(
                    f'<div class="row"><span>{esc(label)}</span>'
                    f'<code id="{key}">{esc(value)}</code>'
                    f'<button onclick="cp(\'{key}\')">Copy</button></div>'
                )

        wg = ''
        if data.get('wireguard_config'):
            wg = f'''
            <section class="wg">
              <h2>WireGuard</h2>
              <div class="qr"><img src="/s/{token}/wireguard.svg" alt="WireGuard QR"></div>
              <textarea id="wg" readonly>{esc(data['wireguard_config'])}</textarea>
              <div class="actions">
                <button onclick="cp('wg')">Copy Config</button>
                <a class="btn" href="/s/{token}/wireguard.conf">Download .conf</a>
              </div>
            </section>'''

        body = f'''<!doctype html>
<html>
<head>
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="robots" content="noindex,nofollow,noarchive">
<title>N4 VPN</title>
<style>
:root{{color-scheme:dark}}
*{{box-sizing:border-box}}
body{{margin:0;background:#070a0e;color:#edf4fb;font:15px system-ui,-apple-system,Segoe UI,Roboto,sans-serif;padding:20px}}
main{{max-width:760px;margin:auto}}
.card{{background:#0d141c;border:1px solid #263746;border-radius:20px;padding:20px;box-shadow:0 16px 40px #0008}}
.brand{{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:4px}}
h1{{font-size:24px;margin:0}}h2{{margin:24px 0 12px;font-size:18px}}
.pill{{font-size:12px;padding:6px 9px;border:1px solid #28445c;border-radius:999px;color:#8fd3ff}}
.muted{{color:#8394a6}}
.row{{display:grid;grid-template-columns:150px 1fr auto;gap:10px;align-items:center;padding:11px 0;border-bottom:1px solid #1b2732}}
code,textarea{{background:#071018;color:#9cf7b2;border:1px solid #213341;border-radius:10px;padding:10px;overflow:auto}}
button,.btn{{border:0;border-radius:10px;padding:10px 13px;background:#2484ff;color:white;text-decoration:none;cursor:pointer;font-weight:650}}
button:active,.btn:active{{transform:scale(.98)}}
textarea{{width:100%;height:280px;white-space:pre;resize:vertical}}
.actions{{display:flex;gap:10px;flex-wrap:wrap;margin-top:10px}}
.qr{{background:white;border-radius:16px;padding:14px;width:min(300px,100%);margin:0 auto 14px}}
.qr img{{display:block;width:100%;height:auto}}
.notice{{margin-top:18px;padding:12px;border-radius:12px;background:#0a1118;color:#94a5b5}}
@media(max-width:560px){{.row{{grid-template-columns:1fr auto}}.row span{{grid-column:1/-1}}.card{{padding:16px}}body{{padding:12px}}}}
</style>
</head>
<body>
<main><div class="card">
<div class="brand"><h1>N4 VPN</h1><span class="pill">PRIVATE SHARE</span></div>
<p class="muted">Account details • expires {esc(data.get('expires_date',''))}</p>
{''.join(rows)}
{wg}
<div class="notice">This link automatically expires with the account.</div>
</div></main>
<script>
async function cp(id){{
  const e=document.getElementById(id); const t=e.value||e.textContent;
  try{{await navigator.clipboard.writeText(t)}}catch(_){{e.select&&e.select();document.execCommand('copy')}}
}}
</script>
</body></html>'''
        self.send_bytes(200, body)


def main():
    BASE.mkdir(parents=True, exist_ok=True)
    cfg = read_conf()
    try:
        port = int(cfg.get('SHARE_PORT', '8880'))
    except ValueError:
        port = 8880
    if not 1 <= port <= 65535:
        port = 8880
    ThreadingHTTPServer(('0.0.0.0', port), Handler).serve_forever()


if __name__ == '__main__':
    main()
