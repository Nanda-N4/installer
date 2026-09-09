import socket, select, threading

LISTEN_PORTS = [80, 143, 442, 8080]
SSH_HOST = '127.0.0.1'
SSH_PORT = 109
BUFFER_SIZE = 8192

# Clean Standard Handshake (Auto-Replace 101/200 OK Friendly)
RESP_101 = b"HTTP/1.1 101 Switching Protocols\r\n\r\n"

def handle_connection(client_sock, client_addr):
    target_sock = None
    try:
        client_sock.settimeout(10.0)
        initial = client_sock.recv(BUFFER_SIZE)
        if not initial:
            client_sock.close()
            return

        target_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        target_sock.connect((SSH_HOST, SSH_PORT))

        # Check if HTTP Request / Custom Payload
        if b'HTTP/' in initial or b'Host:' in initial:
            client_sock.sendall(RESP_101)
        else:
            target_sock.sendall(initial)

        client_sock.settimeout(None)
        target_sock.settimeout(None)

        # Ultra-stable I/O multiplexer
        sockets = [client_sock, target_sock]
        while True:
            r, _, x = select.select(sockets, [], sockets, 120)
            if x or not r:
                break
            for s in r:
                data = s.recv(BUFFER_SIZE)
                if not data:
                    return
                other = target_sock if s is client_sock else client_sock
                other.sendall(data)

    except Exception:
        pass
    finally:
        try: client_sock.close()
        except: pass
        if target_sock:
            try: target_sock.close()
            except: pass

def start_server(port):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('0.0.0.0', port))
    server.listen(200)
    while True:
        try:
            client, addr = server.accept()
            threading.Thread(target=handle_connection, args=(client, addr), daemon=True).start()
        except Exception:
            pass

def main():
    threads = []
    for port in LISTEN_PORTS:
        t = threading.Thread(target=start_server, args=(port,), daemon=True)
        t.start()
        threads.append(t)
    for t in threads:
        t.join()

if __name__ == '__main__':
    main()
