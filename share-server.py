#!/usr/bin/env python3
import html, json, os, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse
BASE='/etc/n4vpn/shares'

def load_token(token):
    if not token or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-' for c in token): return None
    p=os.path.join(BASE, token+'.json')
    try:
        with open(p, encoding='utf-8') as f: d=json.load(f)
        if int(d.get('expires_epoch',0)) <= int(time.time()):
            try: os.unlink(p)
            except OSError: pass
            return None
        return d
    except (OSError,ValueError,TypeError): return None

def esc(v): return html.escape(str(v or ''))
class H(BaseHTTPRequestHandler):
    server_version='N4Share/1.0'
    def log_message(self, fmt, *args): return
    def sendb(self, code, body, ctype='text/html; charset=utf-8', extra=None):
        b=body.encode(); self.send_response(code); self.send_header('Content-Type',ctype); self.send_header('Content-Length',str(len(b))); self.send_header('Cache-Control','no-store, max-age=0'); self.send_header('X-Content-Type-Options','nosniff'); self.send_header('X-Frame-Options','DENY'); self.send_header('Referrer-Policy','no-referrer');
        if extra:
            for k,v in extra.items(): self.send_header(k,v)
        self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        parts=urlparse(self.path).path.strip('/').split('/')
        if len(parts)<2 or parts[0] != 's': return self.sendb(404,'Not found','text/plain')
        token=parts[1]; d=load_token(token)
        if not d: return self.sendb(410,'This share link is expired or revoked.','text/plain')
        if len(parts)==3 and parts[2]=='wireguard.conf':
            cfg=d.get('wireguard_config','')
            if not cfg: return self.sendb(404,'No WireGuard config','text/plain')
            return self.sendb(200,cfg,'text/plain; charset=utf-8',{'Content-Disposition':f'attachment; filename="{esc(d.get("username","n4"))}.conf"'})
        rows=[]
        for label,key in [('Host','host'),('Username','username'),('Password','password'),('VPN SSH','ssh_port'),('WebSocket','ws_ports'),('Dropbear','dropbear_ports'),('SlowDNS NS','slowdns_ns'),('WireGuard Endpoint','wg_endpoint')]:
            val=d.get(key)
            if val not in (None,'','disabled'):
                rows.append(f'<div class="row"><span>{esc(label)}</span><code id="{key}">{esc(val)}</code><button onclick="cp(\'{key}\')">Copy</button></div>')
        wg=''
        if d.get('wireguard_config'):
            wg=f'<h2>WireGuard</h2><textarea id="wg" readonly>{esc(d["wireguard_config"])}</textarea><div class="actions"><button onclick="cp(\'wg\')">Copy config</button><a class="btn" href="/s/{token}/wireguard.conf">Download .conf</a></div>'
        body=f'''<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>N4 VPN</title><style>body{{margin:0;background:#090c10;color:#e8eef5;font:15px system-ui;padding:22px}}main{{max-width:720px;margin:auto}}.card{{background:#111820;border:1px solid #263545;border-radius:18px;padding:20px}}h1{{margin:0 0 5px}}.muted{{color:#8fa0b3}}.row{{display:grid;grid-template-columns:150px 1fr auto;gap:10px;align-items:center;padding:12px 0;border-bottom:1px solid #202b36}}code,textarea{{background:#0a1016;color:#8ef0a8;border:1px solid #253341;border-radius:8px;padding:9px;overflow:auto}}button,.btn{{border:0;border-radius:9px;padding:9px 12px;background:#2a7fff;color:white;text-decoration:none;cursor:pointer}}textarea{{box-sizing:border-box;width:100%;height:280px;white-space:pre}}.actions{{display:flex;gap:10px;margin-top:10px}}@media(max-width:560px){{.row{{grid-template-columns:1fr auto}}.row span{{grid-column:1/-1}}}}</style></head><body><main><div class="card"><h1>N4 VPN</h1><p class="muted">Account details • expires {esc(d.get('expires_date',''))}</p>{''.join(rows)}{wg}<p class="muted">This private link automatically expires with the account.</p></div></main><script>function cp(id){{let e=document.getElementById(id);navigator.clipboard.writeText(e.value||e.textContent);}}</script></body></html>'''
        self.sendb(200,body)
if __name__=='__main__':
    os.makedirs(BASE,mode=0o700,exist_ok=True)
    ThreadingHTTPServer(('0.0.0.0',8880),H).serve_forever()
