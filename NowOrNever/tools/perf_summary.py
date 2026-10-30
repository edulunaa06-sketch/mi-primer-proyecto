#!/usr/bin/env python3
"""Resume un perfil de Instruments (Time Profiler) exportado con
`xctrace export --xpath '//table[@schema="time-profile"]'`: qué funciones ocupan el hilo principal.

Uso: python3 tools/perf_summary.py time-profile.xml > perf-summary.txt
"""
import sys
import xml.etree.ElementTree as ET
from collections import Counter

root = ET.parse(sys.argv[1]).getroot()
by_id = {}
for el in root.iter():
    if "id" in el.attrib:
        by_id[el.attrib["id"]] = el


def resolve(el):
    while el is not None and "ref" in el.attrib:
        el = by_id.get(el.attrib["ref"])
    return el


inclusive = Counter()
self_time = Counter()
total = 0
main_total = 0
for row in root.iter("row"):
    thread = resolve(row.find("thread"))
    thread_name = ""
    if thread is not None:
        thread_name = thread.attrib.get("fmt", "")
    weight_el = resolve(row.find("weight"))
    weight = int(weight_el.text) if weight_el is not None and weight_el.text and weight_el.text.isdigit() else 1_000_000
    total += weight
    if "Main Thread" not in thread_name and "main" not in thread_name.lower():
        continue
    main_total += weight
    bt = resolve(row.find("backtrace"))
    if bt is None:
        continue
    names = []
    for fr in bt.findall("frame"):
        fr = resolve(fr)
        if fr is None:
            continue
        names.append(fr.attrib.get("name", "?"))
    if not names:
        continue
    self_time[names[0]] += weight
    for n in set(names):
        inclusive[n] += weight

ms = lambda w: w / 1_000_000
print(f"Muestras totales: {ms(total):.0f} ms · hilo principal: {ms(main_total):.0f} ms\n")
print("== Tiempo INCLUSIVO en el hilo principal (funciones de la app primero) ==")
app_like = [(n, w) for n, w in inclusive.most_common() if "NowOrNever" in n or "$s10NowOrNever" in n
            or any(k in n for k in ("View", "Store", "Snapshot", "Weight", "Nutrition", "Medal", "Tracking", "Chart"))]
for n, w in app_like[:80]:
    print(f"{ms(w):9.0f} ms  {n[:220]}")
print("\n== Top 60 inclusivo (todo) ==")
for n, w in inclusive.most_common(60):
    print(f"{ms(w):9.0f} ms  {n[:220]}")
print("\n== Top 40 tiempo PROPIO ==")
for n, w in self_time.most_common(40):
    print(f"{ms(w):9.0f} ms  {n[:220]}")
