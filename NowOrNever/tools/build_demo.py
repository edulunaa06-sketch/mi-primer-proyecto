#!/usr/bin/env python3
"""Genera demo/NowOrNever-demo.html inyectando el catálogo real (SeedCatalog.json) en la plantilla."""
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent
catalog = json.loads((root / "NowOrNever/Resources/SeedCatalog.json").read_text(encoding="utf-8"))
template = (root / "demo/demo.template.html").read_text(encoding="utf-8")
marker = "/*@@CATALOG@@*/null"
assert template.count(marker) == 1, "falta el marcador del catálogo"
out = template.replace(marker, json.dumps(catalog, ensure_ascii=False, separators=(",", ":")))
# Las mismas frases motivadoras que la app (Models/Motivation.swift).
swift = (root / "NowOrNever/Models/Motivation.swift").read_text(encoding="utf-8")
quotes = [{"text": t, "author": None if a == "nil" else a.strip('"')}
          for t, a in re.findall(r'Quote\(text: "([^"]+)", author: (nil|"[^"]+")\)', swift)]
assert len(quotes) >= 30, "no se encontraron las frases"
out = out.replace("/*@@QUOTES@@*/[]", json.dumps(quotes, ensure_ascii=False))
(root / "demo/NowOrNever-demo.html").write_text(out, encoding="utf-8")
print(f"demo/NowOrNever-demo.html · {len(out) // 1024} KB · {len(catalog['foods'])} alimentos, "
      f"{len(catalog['menus'])} menús, {len(catalog.get('ideas', []))} ideas")
