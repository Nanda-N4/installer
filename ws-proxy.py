import socket, threading

LISTEN_IP = '0.0.0.0'
LISTEN_PORT = 80
FORWARD_IP = '127.0.0.1'
FORWARD_PORT = 143
BUFFER = 8192

RESPONSE_101 = b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"

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

def handle(client):
    try:
        req = client.recv(BUFFER)
        if not req:
            client.close()
            return
        client.sendall(RESPONSE_101)
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.connect((FORWARD_IP, FORWARD_PORT))
        t1 = threading.Thread(target=pipe, args=(client, server), daemon=True)
        t2 = threading.Thread(target=pipe, args=(server, client), daemon=True)
        t1.start(); t2.start()
        t1.join(); t2.join()
    except:
        try: client.close()
        except: pass

def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((LISTEN_IP, LISTEN_PORT))
    s.listen(200)
    while True:
        c, _ = s.accept()
        threading.Thread(target=handle, args=(c,), daemon=True).start()

if __name__ == '__main__':
    main()
