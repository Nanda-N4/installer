#!/usr/bin/env python3
from __future__ import annotations
import asyncio, logging, resource, signal
from pathlib import Path
CONF=Path('/etc/n4vpn/n4.conf'); LOG='/var/log/n4vpn/ws-proxy.log'
def cfg():
    d={}
    if CONF.exists():
        for x in CONF.read_text(errors='ignore').splitlines():
            x=x.strip()
            if x and not x.startswith('#') and '=' in x:
                k,v=x.split('=',1); d[k.strip()]=v.strip().strip('"').strip("'")
    return d
def ports(s, default):
    out=[]
    for x in s.split(','):
        try:p=int(x.strip())
        except:continue
        if 1<=p<=65535 and p not in out: out.append(p)
    return out or default
C=cfg(); LISTEN=ports(C.get('WS_PORTS','80,143,442,8080'),[80,143,442,8080]); BACKEND=int(C.get('VPN_SSH_PORT','109')); MAX=max(64,int(C.get('WS_MAX_CLIENTS','2048'))); IDLE=max(30,int(C.get('WS_IDLE_TIMEOUT','180')))
Path(LOG).parent.mkdir(parents=True,exist_ok=True); logging.basicConfig(level=logging.INFO,format='%(asctime)s %(levelname)s %(message)s',handlers=[logging.FileHandler(LOG),logging.StreamHandler()]); log=logging.getLogger('n4ws'); sem=asyncio.Semaphore(MAX); active=0
async def close(w):
    if not w:return
    try:w.close(); await w.wait_closed()
    except:pass
async def pump(r,w):
    while True:
        b=await asyncio.wait_for(r.read(65536),timeout=IDLE)
        if not b:return
        w.write(b); await w.drain()
async def client(r,w):
    global active
    try: await asyncio.wait_for(sem.acquire(),timeout=.05)
    except asyncio.TimeoutError: await close(w); return
    active+=1; uw=None
    try:
        first=await asyncio.wait_for(r.read(65536),timeout=10)
        if not first:return
        ur,uw=await asyncio.wait_for(asyncio.open_connection('127.0.0.1',BACKEND),timeout=8)
        if b'HTTP/' in first or b'Host:' in first or b'host:' in first:
            w.write(b'HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\r\n'); await w.drain()
        else: uw.write(first); await uw.drain()
        tasks={asyncio.create_task(pump(r,uw)),asyncio.create_task(pump(ur,w))}; done,pending=await asyncio.wait(tasks,return_when=asyncio.FIRST_COMPLETED)
        for t in pending:t.cancel()
        await asyncio.gather(*pending,return_exceptions=True)
        for t in done:
            try:t.result()
            except:pass
    except (asyncio.TimeoutError,ConnectionError,OSError):pass
    except Exception:log.exception('proxy error')
    finally: active-=1; sem.release(); await close(uw); await close(w)
async def stats():
    while True: await asyncio.sleep(60); log.info('active=%d/%d backend=127.0.0.1:%d',active,MAX,BACKEND)
async def main():
    try:
        s,h=resource.getrlimit(resource.RLIMIT_NOFILE); resource.setrlimit(resource.RLIMIT_NOFILE,(min(max(s,262144),h),h))
    except:pass
    servers=[]
    for p in LISTEN:
        servers.append(await asyncio.start_server(client,'0.0.0.0',p,backlog=4096,reuse_address=True)); log.info('listen :%d -> :%d',p,BACKEND)
    stop=asyncio.Event(); loop=asyncio.get_running_loop()
    for sig in (signal.SIGTERM,signal.SIGINT):
        try:loop.add_signal_handler(sig,stop.set)
        except:pass
    st=asyncio.create_task(stats()); await stop.wait(); st.cancel(); await asyncio.gather(st,return_exceptions=True)
    for s in servers:s.close()
    await asyncio.gather(*(s.wait_closed() for s in servers))
if __name__=='__main__':
    try:asyncio.run(main())
    except KeyboardInterrupt:pass
