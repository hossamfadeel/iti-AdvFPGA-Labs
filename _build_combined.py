import pathlib

base = pathlib.Path(__file__).parent
files = sorted(base.glob("Lab[0-9][0-9]_*.md"))
assert len(files) == 8, f"Expected 8 lab files, found {len(files)}"

yaml = r"""---
title: "Advanced Zynq MPSoC Curriculum"
subtitle: "Advanced FPGA Presentation --- Combined Lab Handbook --- Labs 01 to 08"
date: "August 2026"
geometry: margin=0.9in
fontsize: 10pt
colorlinks: true
linkcolor: blue
urlcolor: blue
toccolor: black
mainfont: "Calibri"
sansfont: "Calibri"
monofont: "Consolas"
monofontoptions:
- Scale=0.85
header-includes: |
  \usepackage{fvextra}
  \DefineVerbatimEnvironment{Highlighting}{Verbatim}{breaklines,breakanywhere,commandchars=\\\{\}}
  \usepackage{amssymb}
  \usepackage{newunicodechar}
  \newunicodechar{✓}{\ensuremath{\checkmark}}
---

"""

newpage = "\n\n```{=latex}\n\\newpage\n```\n\n"

parts = [yaml]
for i, f in enumerate(files):
    content = f.read_text(encoding="utf-8").strip()
    parts.append(content)
    if i < len(files) - 1:
        parts.append(newpage.strip())

out = base / "_combined_labs.md"
out.write_text("\n\n".join(parts) + "\n", encoding="utf-8")
print(f"Wrote {out} ({len(files)} labs)")
for f in files:
    print(" -", f.name)
