#!/usr/bin/env python3
"""Maintain bounded, experimental, non-gating resQ self-coverage trends."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


SUMMARY_KEYS = {
    "functionsMeasured", "functionsHit", "logicalLinesMeasured",
    "logicalLinesHit", "blocksMeasured", "blocksHit",
}


def validate_summary(summary: Any) -> dict[str, int]:
    if not isinstance(summary, dict) or set(summary) != SUMMARY_KEYS:
        raise RuntimeError("self-coverage trend summary contract drifted")
    for basis in ("functions", "logicalLines", "blocks"):
        measured = summary[f"{basis}Measured"]
        hit = summary[f"{basis}Hit"]
        if (
            isinstance(measured, bool) or not isinstance(measured, int) or measured < 0
            or isinstance(hit, bool) or not isinstance(hit, int) or not 0 <= hit <= measured
        ):
            raise RuntimeError(f"invalid self-coverage {basis} counts")
    return summary


def validate_trend(document: Any) -> dict[str, Any]:
    if not isinstance(document, dict):
        raise RuntimeError("self-coverage trend must be an object")
    if (
        document.get("schemaVersion") != 1
        or document.get("kind") != "resq-self-coverage-trend"
        or document.get("experimental") is not True
        or document.get("gatingSupported") is not False
    ):
        raise RuntimeError("unexpected self-coverage trend contract")
    points = document.get("points")
    if not isinstance(points, list):
        raise RuntimeError("self-coverage trend points must be an array")
    timestamps: list[str] = []
    for point in points:
        if not isinstance(point, dict):
            raise RuntimeError("self-coverage trend point must be an object")
        for name in ("generatedAt", "frameworkVersion", "qVersion"):
            if not isinstance(point.get(name), str) or not point[name]:
                raise RuntimeError(f"self-coverage trend point lacks {name}")
        validate_summary(point.get("summary"))
        timestamps.append(point["generatedAt"])
    if timestamps != sorted(timestamps) or len(timestamps) != len(set(timestamps)):
        raise RuntimeError("self-coverage trend timestamps must be unique and sorted")
    return document


def append_point(
    artifact: dict[str, Any], existing: dict[str, Any] | None = None, limit: int = 100
) -> dict[str, Any]:
    if isinstance(limit, bool) or not isinstance(limit, int) or limit < 1 or limit > 1000:
        raise RuntimeError("self-coverage trend limit must be from 1 through 1000")
    measurement = artifact.get("measurement", {})
    if measurement.get("complete") is not False or measurement.get("gatingSupported") is not False:
        raise RuntimeError("self-coverage source must be partial and non-gating")
    point = {
        "generatedAt": artifact.get("generatedAt"),
        "frameworkVersion": artifact.get("frameworkVersion"),
        "qVersion": artifact.get("qVersion"),
        "summary": validate_summary(artifact.get("summary")).copy(),
    }
    if not all(isinstance(point[name], str) and point[name] for name in ("generatedAt", "frameworkVersion", "qVersion")):
        raise RuntimeError("self-coverage source lacks trend identity")
    if existing is None:
        points: list[dict[str, Any]] = []
    else:
        previous = validate_trend(existing)
        points = list(previous["points"])
    points = [old for old in points if old["generatedAt"] != point["generatedAt"]]
    points.append(point)
    points.sort(key=lambda row: row["generatedAt"])
    return {
        "schemaVersion": 1,
        "kind": "resq-self-coverage-trend",
        "framework": "resQ",
        "experimental": True,
        "gatingSupported": False,
        "measurementBasis": measurement.get("basis", "provider-defined partial measurement"),
        "retentionLimit": limit,
        "points": points[-limit:],
    }


def update_file(path: Path, artifact: dict[str, Any], limit: int = 100) -> dict[str, Any]:
    existing = json.loads(path.read_text(encoding="utf-8")) if path.exists() else None
    result = append_point(artifact, existing, limit)
    validate_trend(result)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)
    return result
