#!/usr/bin/env python3
## dev_server.py — Server konten lokal untuk development/uji launcher.
## Mendukung HTTP Range (resume unduhan) — fitur ini wajib untuk uji resume.
##
## Pakai:  python3 tools/dev_server.py [PORT] [DIR]
##   default PORT=8787, DIR=<repo>/server
import http.server, os, sys, re

class Handler(http.server.SimpleHTTPRequestHandler):
    server_version = "PulauToonDev/1.0"

    def do_GET(self):
        rng = self.headers.get("Range")
        if rng:
            m = re.match(r"bytes=(\d+)-(\d*)", rng)
            if m:
                return self._range_get(m)
        return super().do_GET()

    def _range_get(self, m):
        path = self.translate_path(self.path)
        if not os.path.isfile(path):
            self.send_error(404)
            return
        start = int(m.group(1))
        size = os.path.getsize(path)
        end = int(m.group(2)) if m.group(2) else size - 1
        end = min(end, size - 1)
        if start >= size or start > end:
            self.send_error(416, "Requested Range Not Satisfiable")
            return
        length = end - start + 1
        self.send_response(206)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.send_header("Content-Length", str(length))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()
        with open(path, "rb") as f:
            f.seek(start)
            remaining = length
            while remaining > 0:
                chunk = f.read(min(64 * 1024, remaining))
                if not chunk:
                    break
                self.wfile.write(chunk)
                remaining -= len(chunk)

    def log_message(self, fmt, *args):
        sys.stdout.write("[dev_server] " + (fmt % args) + "\n")

def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8787
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    directory = sys.argv[2] if len(sys.argv) > 2 else os.path.join(root, "server")
    os.chdir(directory)
    addr = ("0.0.0.0", port)
    httpd = http.server.ThreadingHTTPServer(addr, Handler)
    print(f"[dev_server] http://0.0.0.0:{port}  melayani {directory}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass

if __name__ == "__main__":
    main()
