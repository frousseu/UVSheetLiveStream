#!/usr/bin/env python3
"""
Minimal local proxy + static server for the slideshow.

Fetches your FTP-over-HTTP directory listing server-side (where CORS
doesn't apply) and serves it back to the browser as plain JSON.
Also serves index.html itself so you can open one localhost URL.

Usage:
    python3 proxy.py --listing-url "https://YOUR-SITE/path/to/photos/" --port 8000

Then open http://localhost:8000 in your browser.
Standard library only — no pip installs required.
"""
import argparse
import json
import re
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urljoin, urlparse
from urllib.request import Request, urlopen
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

IMAGE_EXT_RE = re.compile(r"\.(jpe?g|png|gif|webp)$", re.IGNORECASE)
THUMBNAIL_RE = re.compile(r"_thumbnail\.(jpe?g|png|gif|webp)$", re.IGNORECASE)

LISTING_URL = None  # set from CLI arg in main()


class LinkExtractor(HTMLParser):
    def __init__(self):
        super().__init__()
        self.hrefs = []

    def handle_starttag(self, tag, attrs):
        if tag.lower() == "a":
            for name, value in attrs:
                if name.lower() == "href" and value:
                    self.hrefs.append(value)


def fetch_image_list():
    req = Request(LISTING_URL, headers={"User-Agent": "slideshow-proxy/1.0"})
    with urlopen(req, timeout=15) as resp:
        html = resp.read().decode("utf-8", errors="replace")

    parser = LinkExtractor()
    parser.feed(html)

    urls = []
    for href in parser.hrefs:
        if href in ("../", "/", "./"):
            continue
        if href.lower().startswith("?"):
            continue
        if href.endswith("/"):
            continue  # skip subfolders, top-level only
        if not IMAGE_EXT_RE.search(href):
            continue
        if THUMBNAIL_RE.search(href):
            continue  # _thumbnail files are derived per-image on the frontend, never listed on their own
        urls.append(urljoin(LISTING_URL, href))
    return urls


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # quiet logs

    def do_GET(self):
        path = urlparse(self.path).path  # ignore query string (?view=..., ?duration=...) for routing
        if path in ("/", "/index.html"):
            self._serve_file(Path(__file__).parent / "index.html", "text/html")
        elif path == "/api/images":
            try:
                urls = fetch_image_list()
                body = json.dumps(urls).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            except Exception as e:
                body = json.dumps({"error": str(e)}).encode("utf-8")
                self.send_response(502)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def _serve_file(self, path: Path, content_type: str):
        if not path.is_file():
            self.send_response(404)
            self.end_headers()
            return
        body = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    global LISTING_URL
    parser = argparse.ArgumentParser()
    parser.add_argument("--listing-url", required=True, help="FTP-over-HTTP directory listing URL, e.g. https://site/photos/")
    parser.add_argument("--port", type=int, default=8000)
    args = parser.parse_args()

    LISTING_URL = args.listing_url
    if not LISTING_URL.endswith("/"):
        LISTING_URL += "/"

    server = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    print(f"Proxying {LISTING_URL}")
    print(f"Open http://localhost:{args.port} in your browser")
    server.serve_forever()


if __name__ == "__main__":
    main()