import socket, threading

LISTEN_PORTS = [80, 143, 442, 8080]
DROPBEAR_HOST = '127.0.0.1'
DROPBEAR_PORT = 109
BUFFER_SIZE = 8192

RESPONSE_101 = b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"

def forward_stream(source, destination):
    try:
        while True:
            data = source.recv(BUFFER_SIZE)
            if not data:
                break
            destination.sendall(data)
    except Exception:
        pass
    finally:
        try: source.close()
        except: pass
        try: destination.close()
        except: pass

def handle_client(client_socket):
    target_socket = None
    try:
        client_socket.settimeout(10.0)
        initial_data = client_socket.recv(BUFFER_SIZE)
        if not initial_data:
            client_socket.close()
            return

        target_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        target_socket.connect((DROPBEAR_HOST, DROPBEAR_PORT))

        http_methods = (b'GET', b'POST', b'HEAD', b'PUT', b'DELETE', b'CONNECT', b'OPTIONS', b'TRACE', b'PATCH')
        is_http_payload = any(initial_data.startswith(m) for m in http_methods) or b'HTTP/' in initial_data

        if is_http_payload:
            client_socket.sendall(RESPONSE_101)
        else:
            target_socket.sendall(initial_data)

        client_socket.settimeout(None)
        target_socket.settimeout(None)

        t1 = threading.Thread(target=forward_stream, args=(client_socket, target_socket), daemon=True)
        t2 = threading.Thread(target=forward_stream, args=(target_socket, client_socket), daemon=True)
        t1.start()
        t2.start()
        t1.join()
        t2.join()

    except Exception:
        pass
    finally:
        try: client_socket.close()
        except: pass
        if target_socket:
            try: target_socket.close()
            except: pass

def start_listener(port):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('0.0.0.0', port))
    server.listen(500)
    while True:
        try:
            client, _ = server.accept()
            threading.Thread(target=handle_client, args=(client,), daemon=True).start()
        except Exception:
            pass

def main():
    threads = []
    for port in LISTEN_PORTS:
        t = threading.Thread(target=start_listener, args=(port,), daemon=True)
        t.start()
        threads.append(t)
    for t in threads:
        t.join()

if __name__ == '__main__':
    main()
