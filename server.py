"""NANDAL local preview server. Auth and data live in Supabase."""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
import os

ROOT = Path(__file__).parent

if __name__ == "__main__":
    os.chdir(ROOT)
    print("NANDAL preview is live at http://localhost:8000")
    ThreadingHTTPServer(("", 8000), SimpleHTTPRequestHandler).serve_forever()
