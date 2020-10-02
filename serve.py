#!/usr/bin/python3

import http.server, os, re, signal, http.server, socket, sys, tarfile, tempfile, threading, time, zipfile

signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(0))

# Launch multiple listeners as threads
class Thread(threading.Thread):
    def __init__(self, i, socket):
        threading.Thread.__init__(self)
        self.i = i
        self.socket = socket
        self.daemon = True
        self.start()

    def run(self):
        httpd = http.server.HTTPServer(addr, http.server.SimpleHTTPRequestHandler, False)

        # Prevent the HTTP server from re-binding every handler.
        # https://stackoverflow.com/questions/46210672/
        httpd.socket = self.socket
        httpd.server_bind = self.server_close = lambda self: None

        httpd.serve_forever()

temp_dir = tempfile.mkdtemp()
print(('serving from {}'.format(temp_dir)))
os.chdir(temp_dir)
for arch in ['amd64']:
    os.mkdir(arch)
    for operating_system in ['linux', 'macos', 'windows']:
        os.mkdir(os.path.join(arch, operating_system))

for arch, operating_system, path in [
        ('amd64', 'linux', '/usr/share/kn/linux_amd64/kn-linux-amd64.tar.gz'),
        ('amd64', 'macos', '/usr/share/kn/macos/kn-macos-amd64.tar.gz'),
        ('amd64', 'windows', '/usr/share/kn/windows/kn-windows-amd64.zip'),
        ]:
    basename = os.path.basename(path)
    target_path = os.path.join(arch, operating_system, basename)
    os.symlink(path, target_path)

# Create socket
# IPv6 should handle IPv4 passively so long as it is not bound to a
# specific address or set to IPv6_ONLY
# https://stackoverflow.com/questions/25817848/python-3-does-http-server-support-ipv6
addr = ('::', 8080)
sock = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(addr)
sock.listen(5)

[Thread(i, socket=sock) for i in range(100)]
time.sleep(9e9)
