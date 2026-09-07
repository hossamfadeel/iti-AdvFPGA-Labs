#!/usr/bin/env python3
"""Lab02: extract the Part-5 DSE table from the four csynth reports."""
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROWS = []
for v in ("v0", "v1", "v2", "v3"):
    r = HERE / f"fir_proj_{v}" / v / "syn" / "report" / "fir_top_csynth.rpt"
    if not r.exists():
        continue
    t = r.read_text(encoding="utf-8", errors="ignore")
    # top-level latency/interval line: | min | max | ... | Interval min | max | type
    m = re.search(r"\|\s+(\d+)\|\s+(\d+)\|[\s\S]*?\|\s+(\d+)\|\s+(\d+)\|\s*(\w+)", t)
    lat = m.group(2) if m else "?"
    ivl = m.group(4) if m else "?"
    # utilization summary: Name BRAM_18K DSP FF LUT URAM -> Total row
    u = re.search(r"\|\s*Total\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|", t)
    dsp = u.group(2) if u else "?"
    lut = u.group(4) if u else "?"
    bram = u.group(1) if u else "?"
    pct = f"{100*int(dsp)/2520:.1f}" if dsp != "?" else "?"
    ROWS.append((v, ivl, lat, dsp, lut, bram, pct))

print(f"{'Var':<4}{'II(max)':<10}{'Latency':<10}{'DSP48E2':<9}{'LUT':<9}{'BRAM18':<8}{'%DSP':<6}")
for row in ROWS:
    print(f"{row[0]:<4}{row[1]:<10}{row[2]:<10}{row[3]:<9}{row[4]:<9}{row[5]:<8}{row[6]:<6}")
