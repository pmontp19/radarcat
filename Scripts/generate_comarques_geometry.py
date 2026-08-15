#!/usr/bin/env python3
"""Decode the official comarques TopoJSON into `Sources/RadarCat/Resources/comarques.json`.

One-time (well, occasional) dev-time step, not part of the app's runtime: RadarCat vendors
pre-decoded geometry instead of shipping a TopoJSON decoder in Swift or fetching it on every
launch. Run this again only if Meteocat changes the comarques' administrative boundaries
(rare - see the note in CLAUDE.md).

Source: https://static-m.meteo.cat/assets-w3/json/topojson/comarquesAmbMar.json - the same
public TopoJSON `ha-avisoscat` downloads at config-flow time
(`custom_components/avisoscat/comarques.py`). That file carries the 43 land comarques
(idComarca 1-43) plus 12 maritime zones (88-99); only the land ones are written out here -
RadarCat always runs on land, so the maritime zones would just be dead weight.

Usage:
    python3 Scripts/generate_comarques_geometry.py <path-to-comarquesAmbMar.json>

The arc-delta decoding and the ring stitching below are a direct port of
`ha-avisoscat/custom_components/avisoscat/comarques.py` (`_decode_arcs`, `_stitch`,
`_iter_polygons`, `_decode_polygon`, `decode_topology`) - kept in lockstep with that module on
purpose, since both projects read the same file. Only the packaging of the result differs:
RadarCat wants a flat `[{"idComarca", "nom", "rings"}]` list of closed `[lat, lon]` rings
(polygon/hole grouping is not preserved - a comarca's rings are combined under one flattened
even-odd point-in-polygon test in `ComarcaResolver`, which gives the same answer as testing
each polygon separately as long as the ring set does not overlap, true for real comarca
shapes), not `ha-avisoscat`'s `dict[id, list[Polygon]]` used for its own point-in-polygon test.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

TOPOJSON_OBJECT = "comarquesAmbMarCorrectes84"
TOPOJSON_ID_PROPERTY = "IDComarca"
FIRST_MARITIME_ID = 88

# Generated from docs/captures/comarques-idcomarca-2026-08-05.json in ha-avisoscat; Catalan
# spelling is data and is reproduced exactly, accents included.
COMARCA_NAMES: dict[int, str] = {
    1: "Alt Camp",
    2: "Alt Empordà",
    3: "Alt Penedès",
    4: "Alt Urgell",
    5: "Alta Ribagorça",
    6: "Anoia",
    7: "Bages",
    8: "Baix Camp",
    9: "Baix Ebre",
    10: "Baix Empordà",
    11: "Baix Llobregat",
    12: "Baix Penedès",
    13: "Barcelonès",
    14: "Berguedà",
    15: "Cerdanya",
    16: "Conca de Barberà",
    17: "Garraf",
    18: "Garrigues",
    19: "Garrotxa",
    20: "Gironès",
    21: "Maresme",
    22: "Montsià",
    23: "Noguera",
    24: "Osona",
    25: "Pallars Jussà",
    26: "Pallars Sobirà",
    27: "Pla d'Urgell",
    28: "Pla de l'Estany",
    29: "Priorat",
    30: "Ribera d'Ebre",
    31: "Ripollès",
    32: "Segarra",
    33: "Segrià",
    34: "Selva",
    35: "Solsonès",
    36: "Tarragonès",
    37: "Terra Alta",
    38: "Urgell",
    39: "Val d'Aran",
    40: "Vallès Occidental",
    41: "Vallès Oriental",
    42: "Moianès",
    43: "Lluçanès",
}

# Two known-good check points, latitude/longitude in degrees, verified against a real
# `ha-avisoscat` config-flow run: (lat, lon, expected idComarca).
CHECKPOINTS: tuple[tuple[float, float, int], ...] = (
    (41.3851, 2.1734, 13),  # Barcelona -> Barcelonès
    (41.9301, 2.2545, 24),  # Vic -> Osona
)

Ring = list[tuple[float, float]]  # (lon, lat)
Polygon = list[Ring]


def _decode_arcs(topology: dict[str, Any]) -> list[Ring]:
    transform = topology.get("transform") or {}
    scale_x, scale_y = transform.get("scale", (1.0, 1.0))
    translate_x, translate_y = transform.get("translate", (0.0, 0.0))

    decoded: list[Ring] = []
    for arc in topology.get("arcs", []):
        points: Ring = []
        x = y = 0
        for position in arc:
            x += position[0]
            y += position[1]
            points.append((x * scale_x + translate_x, y * scale_y + translate_y))
        decoded.append(points)
    return decoded


def _stitch(ring_arcs: list[int], arcs: list[Ring]) -> Ring:
    ring: Ring = []
    for index in ring_arcs:
        arc = arcs[~index][::-1] if index < 0 else arcs[index]
        ring.extend(arc[1:] if ring else arc)
    return ring


def _iter_polygons(geometry: dict[str, Any]):
    geometry_type = geometry.get("type")
    if geometry_type == "Polygon":
        yield geometry.get("arcs", [])
    elif geometry_type == "MultiPolygon":
        yield from geometry.get("arcs", [])


def _decode_polygon(polygon: list[list[int]], arcs: list[Ring]) -> Polygon:
    return [ring for ring in (_stitch(ring_arcs, arcs) for ring_arcs in polygon) if ring]


def decode_topology(payload: dict[str, Any]) -> dict[int, list[Polygon]]:
    arcs = _decode_arcs(payload)
    collection = (payload.get("objects") or {}).get(TOPOJSON_OBJECT) or {}

    geometries: dict[int, list[Polygon]] = {}
    for geometry in collection.get("geometries", []):
        properties = geometry.get("properties") or {}
        raw_id = properties.get(TOPOJSON_ID_PROPERTY)
        if not isinstance(raw_id, int):
            continue
        polygons = [
            rings
            for rings in (_decode_polygon(polygon, arcs) for polygon in _iter_polygons(geometry))
            if rings
        ]
        if polygons:
            geometries.setdefault(raw_id, []).extend(polygons)
    return geometries


def _close_ring(ring: Ring) -> Ring:
    """Repeat the first point at the end if the ring is not already closed."""
    if not ring:
        return ring
    if ring[0] != ring[-1]:
        return ring + [ring[0]]
    return ring


def _point_in_rings(lat: float, lon: float, rings: list[list[tuple[float, float]]]) -> bool:
    """Even-odd ray casting across every ring at once - same test `ComarcaResolver` runs in
    Swift, kept here only to self-verify the checkpoints below before writing the output."""
    inside = False
    for ring in rings:
        for index in range(len(ring)):
            lat1, lon1 = ring[index - 1]
            lat2, lon2 = ring[index]
            if (lat1 > lat) == (lat2 > lat):
                continue
            crossing_lon = lon1 + (lat - lat1) * (lon2 - lon1) / (lat2 - lat1)
            if lon < crossing_lon:
                inside = not inside
    return inside


def main() -> None:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <path-to-comarquesAmbMar.json>", file=sys.stderr)
        raise SystemExit(2)

    source_path = Path(sys.argv[1])
    with source_path.open(encoding="utf-8") as f:
        payload = json.load(f)

    geometries = decode_topology(payload)

    output: list[dict[str, Any]] = []
    # `rings` per comarca: every ring of every polygon, converted to (lat, lon) and closed -
    # see the module docstring for why flattening polygon grouping is safe here.
    rings_by_id: dict[int, list[list[tuple[float, float]]]] = {}
    for id_comarca, polygons in sorted(geometries.items()):
        if id_comarca >= FIRST_MARITIME_ID:
            continue
        rings = [
            _close_ring([(lat, lon) for lon, lat in ring]) for polygon in polygons for ring in polygon
        ]
        if not rings:
            continue
        rings_by_id[id_comarca] = rings
        nom = COMARCA_NAMES.get(id_comarca)
        if nom is None:
            print(f"warning: no name for idComarca {id_comarca}, skipping it", file=sys.stderr)
            continue
        output.append({"idComarca": id_comarca, "nom": nom, "rings": rings})

    if len(output) != len(COMARCA_NAMES):
        print(
            f"warning: decoded {len(output)} land comarques, expected {len(COMARCA_NAMES)}",
            file=sys.stderr,
        )

    for lat, lon, expected_id in CHECKPOINTS:
        resolved = next(
            (cid for cid, rings in rings_by_id.items() if _point_in_rings(lat, lon, rings)),
            None,
        )
        if resolved != expected_id:
            print(
                f"error: checkpoint ({lat}, {lon}) resolved to {resolved!r}, expected {expected_id}",
                file=sys.stderr,
            )
            raise SystemExit(1)

    output_path = (
        Path(__file__).resolve().parent.parent / "Sources" / "RadarCat" / "Resources" / "comarques.json"
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")

    print(f"Wrote {len(output)} comarques to {output_path}")
    print(f"Verified {len(CHECKPOINTS)} checkpoints OK")


if __name__ == "__main__":
    main()
