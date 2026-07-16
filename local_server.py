#!/usr/bin/env python3
"""
Minimal local dev server — lets you test the slideshow against a local
folder of images instead of your Spaces bucket, without uploading
anything. Use this alongside index.html's ?source=local parameter.

Usage:
    python3 local_server.py --folder /path/to/photos --port 8000

Then open:
    http://localhost:8000/?source=local

Standard library only — no pip installs required.
"""
import argparse
import json
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".gif", ".webp"}

PHOTO_DIR: Path = None  # type: ignore
PORT = 8000


def list_images():
    files = []
    for entry in PHOTO_DIR.iterdir():
        if entry.is_file() and entry.suffix.lower() in IMAGE_EXTS and "_thumbnail" not in entry.stem.lower():
            files.append((entry.name, entry.stat().st_mtime))
    files.sort(key=lambda x: x[1])
    return [f"http://localhost:{PORT}/images/{name}" for name, _ in files]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # quiet logs

    def do_GET(self):
        path = urlparse(self.path).path
        if path in ("/", "/index.html"):
            self._serve_file(Path(__file__).parent / "index.html", "text/html")
        elif path == "/api/images":
            body = json.dumps(list_images()).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif path.startswith("/images/"):
            filename = path[len("/images/"):]
            filepath = (PHOTO_DIR / filename).resolve()
            if PHOTO_DIR.resolve() not in filepath.parents or not filepath.is_file():
                self.send_response(404)
                self.end_headers()
                return
            self._serve_file(filepath, "image/jpeg")
        else:
            self.send_response(404)
            self.end_headers()

    def _serve_file(self, path: Path, content_type: str):
        data = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def main():
    global PHOTO_DIR, PORT
    parser = argparse.ArgumentParser()
    parser.add_argument("--folder", required=True, help="Local folder of images to serve")
    parser.add_argument("--port", type=int, default=8000)
    args = parser.parse_args()

    PHOTO_DIR = Path(args.folder).resolve()
    PORT = args.port
    if not PHOTO_DIR.is_dir():
        raise SystemExit(f"Not a directory: {PHOTO_DIR}")

    print(f"Serving {PHOTO_DIR}")
    print(f"Open http://localhost:{PORT}/?source=local")
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
