#!/usr/bin/env python3
"""Open every spreadsheet in a folder with the real app; report crashes, hangs and read errors.
Usage: scripts/corpus_test.py <folder> [parallel=6]   (after scripts/build.sh --arm64-only)"""
import os, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "build/Foglio.app/Contents/MacOS/Foglio")
folder = sys.argv[1]
par = int(sys.argv[2]) if len(sys.argv) > 2 else 6
files = sorted(f for f in os.listdir(folder) if f.lower().endswith((".xlsx", ".xlsm", ".xls", ".xlsb", ".ods", ".csv")))
env = dict(os.environ, FOGLIO_PERF="1", FOGLIO_EXIT_AFTER_FIRST_FRAME="1")

def run(name):
    t = time.time()
    try:
        p = subprocess.run([APP, os.path.join(folder, name)], env=env, capture_output=True, text=True, timeout=25)
        rc, out = p.returncode, p.stdout + p.stderr
    except subprocess.TimeoutExpired:
        rc, out = 124, ""
    ms = (time.time() - t) * 1000
    status = {0: "OK", 3: "READ_ERROR", 124: "HANG"}.get(rc, f"CRASH({rc})")
    detail = next((l for l in out.splitlines() if l.startswith("OPEN_ERROR")), "")
    return status, ms, name, detail

with ThreadPoolExecutor(par) as ex:
    results = list(ex.map(run, files))
counts = {}
for s, *_ in results:
    k = s.split("(")[0]; counts[k] = counts.get(k, 0) + 1
print("== summary", counts, "of", len(results))
for s, ms, n, d in results:
    if s != "OK": print(f"{s}\t{ms:.0f}ms\t{n}\t{d[:140]}")
print("== slowest OK"); [print(f"{ms:.0f}ms\t{n}") for s, ms, n, d in sorted(results, key=lambda r: -r[1])[:5] if s == "OK"]
