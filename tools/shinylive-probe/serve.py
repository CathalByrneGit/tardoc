import http.server, socketserver, functools
class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        # shinylive/webR wants cross-origin isolation for SharedArrayBuffer
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "cross-origin")
        super().end_headers()
    def log_message(self, *a): pass
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("127.0.0.1", 8811),
        functools.partial(H, directory="sl/site-db")) as s:
    s.serve_forever()
