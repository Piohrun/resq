#!/usr/bin/env python3
"""Dependency-free projections for declared resQ report-v2 evidence profiles."""

from __future__ import annotations

import copy
from typing import Any


PROFILES = {"full", "results", "telemetry"}
OMITTED_SECTIONS = [
    "performance",
    "coverage",
    "flake",
    "snapshotInventory",
    "benchmarkAnalysis",
    "manifest",
    "events",
]
OMITTED_TEST_FIELDS = [
    "time",
    "failures",
    "namespace",
    "tags",
    "output",
    "parameters",
    "attemptHistory",
    "parameterCases",
    "property",
    "diagnostics",
    "snapshots",
    "benchmark",
    "quarantine",
]
TELEMETRY_TEST_FIELDS = [
    "suite",
    "description",
    "status",
    "message",
    "durationSeconds",
    "assertsRun",
    "file",
    "line",
    "testId",
    "caseId",
    "kind",
    "attempts",
    "retried",
    "flaky",
    "startedAt",
    "finishedAt",
]


def completeness(profile: str) -> dict[str, Any]:
    if profile not in PROFILES:
        raise ValueError(f"unsupported report profile: {profile}")
    return {
        "evidenceComplete": profile == "full",
        "omittedSections": [] if profile == "full" else list(OMITTED_SECTIONS),
        "omittedTestFields": list(OMITTED_TEST_FIELDS) if profile == "telemetry" else [],
        "boundedFields": ["tests.message", "diagnostics.message"]
        if profile == "telemetry"
        else [],
    }


def project(document: dict[str, Any], profile: str) -> dict[str, Any]:
    """Return a detached profile projection of a complete canonical report."""
    if profile not in PROFILES:
        raise ValueError(f"unsupported report profile: {profile}")
    out = copy.deepcopy(document)
    if profile != "full":
        for section in OMITTED_SECTIONS:
            out.pop(section, None)
    for row in out.get("tests", []):
        if not row.get("quarantine"):
            row.pop("quarantine", None)
    if profile == "telemetry":
        out["tests"] = [
            {name: row[name] for name in TELEMETRY_TEST_FIELDS if name in row}
            for row in out.get("tests", [])
        ]
    out["profile"] = profile
    out["completeness"] = completeness(profile)
    return out
