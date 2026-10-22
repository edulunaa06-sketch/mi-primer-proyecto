#!/usr/bin/env python3
"""Genera demo/NowOrNever-demo.html inyectando el catálogo real (SeedCatalog.json) en la plantilla."""
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
catalog = json.loads((root / "NowOrNever/Resources/SeedCatalog.json").read_text(encoding="utf-8"))
template = (root / "demo/demo.template.html").read_text(encoding="utf-8")
marker = "/*@@CATALOG@@*/null"
assert template.count(marker) == 1, "falta el marcador del catálogo"
out = template.replace(marker, json.dumps(catalog, ensure_ascii=False, separators=(",", ":")))
(root / "demo/NowOrNever-demo.html").write_text(out, encoding="utf-8")
print(f"demo/NowOrNever-demo.html · {len(out) // 1024} KB · {len(catalog['foods'])} alimentos, "
      f"{len(catalog['menus'])} menús, {len(catalog.get('ideas', []))} ideas")
