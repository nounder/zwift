"""Run the native test binary against an ephemeral loopback-only WebKit fixture."""
import http.server
import os
import subprocess
import sys
import threading


class Fixture(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        title = "Second" if self.path == "/second" else "First"
        body = f'<!doctype html><title>{title}</title><h1>{title}</h1><a href="/second">Next</a>'.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Fixture)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    env = dict(os.environ, ZWIFT_TEST_URL=f"http://127.0.0.1:{server.server_port}")
    result = subprocess.run(sys.argv[1:], env=env, timeout=90)
finally:
    server.shutdown()
    server.server_close()
    thread.join()
sys.exit(result.returncode)
