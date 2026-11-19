#!/usr/bin/env python3
"""Validate YAML syntax and lint rule headers for the detection library.

Usage: python3 lint_rules.py <path-to-02-detection-engineering>

Checks
  1. Every .yml/.yaml parses (requires PyYAML; skipped with a warning if missing).
  2. Every .kql/.spl file has the required header keys, a valid MITRE technique,
     an allowed severity, and a unique id.
  3. Every rule under detection-as-code/rules has the required YAML keys.
  4. use-case-management/use-case-register.csv lists exactly the rule files that exist,
     and its path column points to the real file.
  5. query_file in rule YAML points to an existing query.
"""
import csv
import pathlib
import re
import sys

REQUIRED_HEADER = ["id", "name", "mitre_tactic", "mitre_technique", "severity",
                   "data_source", "false_positives", "status", "last_review"]
REQUIRED_YAML = ["id", "name", "objective", "mitre", "data_sources", "logic", "thresholds",
                 "severity", "false_positives", "tuning_guidance", "test_method", "owner", "status"]
SEVERITIES = {"Informational", "Low", "Medium", "High"}
STATUSES = {"Draft", "Testing", "Production", "Deprecated"}
TECH_RX = re.compile(r"^T\d{4}(\.\d{3})?$")
errors = []


def err(path, msg):
    errors.append("%s: %s" % (path, msg))


def header_value(text, key):
    m = re.search(r"(?m)^\s*(?://\s*)?%s:\s*(.+)$" % re.escape(key), text)
    return m.group(1).strip() if m else None


def main(root):
    root = pathlib.Path(root)
    try:
        import yaml
    except ImportError:
        yaml = None
        print("warning: PyYAML not installed, YAML syntax check skipped")

    if yaml:
        for f in sorted(list(root.rglob("*.yml")) + list(root.rglob("*.yaml"))):
            try:
                list(yaml.safe_load_all(f.read_text()))
            except Exception as exc:
                err(f.relative_to(root), "invalid YAML: %s" % str(exc).splitlines()[0])

    ids = {}
    tech = root / "use-cases-by-technology"
    paths = {}
    for f in sorted(list(tech.rglob("*.kql")) + list(tech.rglob("*.spl"))):
        text = f.read_text()
        rel = f.relative_to(root)
        for key in REQUIRED_HEADER:
            if header_value(text, key) in (None, ""):
                err(rel, "missing header key '%s'" % key)
        rid = header_value(text, "id")
        if rid:
            if rid in ids:
                err(rel, "duplicate id %s (also %s)" % (rid, ids[rid]))
            ids[rid] = rel
            paths[rid] = rel.as_posix()
        tech = (header_value(text, "mitre_technique") or "").split(" ")[0]
        if not TECH_RX.match(tech):
            err(rel, "mitre_technique '%s' is not a valid technique id" % tech)
        if header_value(text, "severity") not in SEVERITIES:
            err(rel, "severity must be one of %s" % sorted(SEVERITIES))
        if header_value(text, "status") not in STATUSES:
            err(rel, "status must be one of %s" % sorted(STATUSES))
        body = [l for l in text.splitlines() if l.strip() and not l.lstrip().startswith("//")]
        if f.suffix == ".kql" and len(body) < 3:
            err(rel, "query body is too short")

    if yaml:
        for f in sorted((root / "use-case-management" / "detection-as-code" / "rules").glob("*.y*ml")):
            data = yaml.safe_load(f.read_text())
            for key in REQUIRED_YAML:
                if not isinstance(data, dict) or key not in data:
                    err(f.relative_to(root), "missing key '%s'" % key)
            if isinstance(data, dict) and data.get("severity") not in SEVERITIES:
                err(f.relative_to(root), "severity must be one of %s" % sorted(SEVERITIES))
            qf = ((data or {}).get("logic") or {}).get("query_file") if isinstance(data, dict) else None
            if qf and not (f.parent / qf).exists():
                err(f.relative_to(root), "query_file '%s' does not exist" % qf)

    reg = root / "use-case-management" / "use-case-register.csv"
    if reg.exists():
        with reg.open() as fh:
            rows = list(csv.DictReader(fh))
        reg_ids = {row["id"] for row in rows}
        for row in rows:
            if row["id"] in paths and row.get("path") != paths[row["id"]]:
                err("use-case-register.csv", "%s path column '%s' does not match '%s'" % (row["id"], row.get("path"), paths[row["id"]]))
        for missing in sorted(set(ids) - reg_ids):
            err("use-case-management/use-case-register.csv", "%s has a rule file but no register row" % missing)
        for extra in sorted(reg_ids - set(ids)):
            err("use-case-register.csv", "%s is registered but has no rule file" % extra)

    if errors:
        print("LINT FAILED")
        for e in errors:
            print(" -", e)
        sys.exit(1)
    print("lint: OK (%d rule files)" % len(ids))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
