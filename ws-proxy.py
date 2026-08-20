import socket, threading

LISTEN_PORTS = [80, 143, 442, 8080]
DROPBEAR_HOST = '127.0.0.1'
DROPBEAR_PORT = 109
BUFFER = 8192

HTTP_METHODS = [b'GET', b'POST', b'HEAD', b'PUT', b'DELETE', b'CONNECT', b'OPTIONS', b'TRACE', b'PATCH']
HTTP_101 = b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"

def pipe(src, dst):
    try:
        while True:
            data = src.recv(BUFFER)
            if not data: break
            dst.sendall(data)
    except: pass
    finally:
        try: src.close()
        except: pass
        try: dst.close()
        except: pass

def handle_client(client):
    try:
        initial_data = client.recv(BUFFER)
        if not initial_data:
            client.close()
            return
        
        target = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        target.connect((DROPBEAR_HOST, DROPBEAR_PORT))
        
        is_http = any(initial_data.startswith(m) for m in HTTP_METHODS)
        if is_http:
            client.sendall(HTTP_101)
        else:
            target.sendall(initial_data)
            
        t1 = threading.Thread(target=pipe, args=(client, target), daemon=True)
        t2 = threading.Thread(target=pipe, args=(target, client), daemon=True)
        t1.start(); t2.start()
        t1.join(); t2.join()
    except:
        try: client.close()
        except: pass

def start_server(port):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('0.0.0.0', port))
    s.listen(200)
    while True:
        c, _ = s.accept()
        threading.Thread(target=handle_client, args=(c,), daemon=True).start()

def main():
    threads = []
    for p in LISTEN_PORTS:
        t = threading.Thread(target=start_server, args=(p,), daemon=True)
        t.start()
        threads.append(t)
    for t in threads:
        t.join()

if __name__ == '__main__':
    main()
