#!/usr/bin/env python3
import argparse
import json
import os
import threading
import time
import webbrowser
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse, urlunsplit

from collector import collect

INDEX = Path(__file__).with_name("index.html")
HOST = "127.0.0.1"
_collect_lock = threading.Lock()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        url = urlparse(self.path)
        port = self.server.server_address[1]
        if self.headers.get("Host") not in {f"{HOST}:{port}", f"localhost:{port}"}:
            # Blocks DNS rebinding: another site's hostname resolving to 127.0.0.1 could otherwise read process data.
            self._send(HTTPStatus.MISDIRECTED_REQUEST, "text/plain", b"unexpected Host header")
        elif url.path == "/":
            self._send(HTTPStatus.OK, "text/html; charset=utf-8", INDEX.read_bytes())
        elif url.path == "/api/snapshot":
            split = parse_qs(url.query).get("split") == ["1"]
            started = time.monotonic()
            with _collect_lock:
                snapshot = collect(split).to_json()
            snapshot["collect_ms"] = round((time.monotonic() - started) * 1000)
            self._send(HTTPStatus.OK, "application/json", json.dumps(snapshot).encode())
        else:
            self._send(HTTPStatus.NOT_FOUND, "text/plain", b"not found")

    def _send(self, status: HTTPStatus, content_type: str, body: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        pass


def main() -> None:
    parser = argparse.ArgumentParser(description="Treemap of process memory use")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--no-open", action="store_true", help="don't open a browser tab")
    args = parser.parse_args()

    server = ThreadingHTTPServer((HOST, args.port), Handler)
    url = urlunsplit(("http", ":".join((HOST, str(args.port))), "/", "", ""))
    print("memmap serving", url, " (Ctrl-C to stop)")
    if not args.no_open and os.geteuid() != 0:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
