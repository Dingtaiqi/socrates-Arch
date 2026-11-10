"""Route only GitHub HTTPS through the runner over the existing SSH session."""
import select
import socket
import threading


class SourceCloudProxy:
    def __init__(self, transport):
        self.transport = transport
        self.port = transport.request_port_forward('127.0.0.1', 0, self.accept)

    def accept(self, channel, origin, server):
        threading.Thread(target=self.forward, args=(channel,), daemon=True).start()

    @staticmethod
    def forward(channel):
        upstream = None
        try:
            header = bytearray()
            while b'\r\n\r\n' not in header:
                block = channel.recv(4096)
                if not block:
                    return
                header.extend(block)
                if len(header) > 4096:
                    raise ValueError('Oversized proxy header')
            first = bytes(header).split(b'\r\n', 1)[0].decode('ascii').split()
            if len(first) != 3 or first[0] != 'CONNECT' or first[1] not in (
                    'api.github.com:443', 'uploads.github.com:443'):
                raise ValueError('Unsupported proxy destination')
            upstream = socket.create_connection((first[1].split(':')[0], 443), timeout=30)
            channel.sendall(b'HTTP/1.0 200 Connection established\r\n\r\n')
            while True:
                ready, _, _ = select.select([channel, upstream], [], [], 60)
                for source in ready:
                    block = source.recv(128 * 1024)
                    if not block:
                        return
                    (upstream if source is channel else channel).sendall(block)
        except (OSError, ValueError, EOFError) as error:
            print('SOURCE_CLOUD_PROXY_CONNECTION_CLOSED', type(error).__name__, flush=True)
        finally:
            channel.close()
            if upstream:
                upstream.close()

    def close(self):
        self.transport.cancel_port_forward('127.0.0.1', self.port)
