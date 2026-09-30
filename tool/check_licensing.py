#!/usr/bin/env python3
"""Validate the default-deny engine dependency and model licensing manifest."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
from datetime import date
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = "licensing/manifest.json"
NOTICES_PATH = "THIRD_PARTY_NOTICES.md"
FIXTURE_ROOT = "conformance/fixtures/"

CODE_KINDS = {"engine", "native-library"}
CONTENT_KINDS = {"model", "voice", "tokenizer", "phonemizer"}
KINDS = CODE_KINDS | CONTENT_KINDS | {"fixture"}
DISTRIBUTIONS = {"bundle", "user-download", "blocked"}
PERMISSIONS = ("redistribution", "commercialUse", "modification")
PERMISSION_VALUES = {"allowed", "prohibited", "unknown"}
ACCESS_VALUES = {"public", "gated", "unknown"}
PRESENTATION_VALUES = {"none", "link", "acknowledgement", "unknown"}
LEGAL_STATUSES = {"pending", "approved", "rejected"}

ENTRY_FIELDS = {
    "id", "kind", "name", "version", "source", "revision", "downloads", "paths",
    "configuration", "requires", "usedBy", "license", "upstream", "terms",
    "distribution", "review", "vcs",
}
FIXTURE_FIELDS = {"id", "kind", "name", "paths", "synthetic", "method", "review"}
LICENSE_FIELDS = {"code", "content", "name", "evidence"}
UPSTREAM_FIELDS = {"name", "source", "vcs", "revision", "license", "licenseName", "evidence"}
TERMS_FIELDS = {"redistribution", "commercialUse", "modification", "attribution", "download", "termsUrl"}
DOWNLOAD_FIELDS = {"url", "sha256", "size", "platform"}
REVIEW_FIELDS = {"date", "notes", "legal"}
LEGAL_FIELDS = {"status", "reference", "date", "fingerprint"}
# Every field except these is covered by the reviewed fingerprint an approval is bound to.
FINGERPRINT_EXCLUDED = {"usedBy", "review"}

# Tracked files that look like models, native binaries, or audio must be registered.
SCANNED_SUFFIXES = (
    ".onnx", ".ort", ".mlmodel", ".safetensors", ".gguf", ".pt", ".pth", ".tflite", ".bin",
    ".so", ".dylib", ".a", ".dll",
    ".wav", ".flac", ".mp3", ".ogg", ".opus", ".m4a",
)
SCANNED_DIRECTORIES = (".mlpackage", ".mlmodelc", ".xcframework")
HUGGING_FACE_HOST = "huggingface.co"
REPOSITORY_HOSTS = {"github.com", "gitlab.com", HUGGING_FACE_HOST}
FILE_VIEWS = {"blob", "tree", "raw", "resolve"}
# Views that name a single file; `tree` names a directory and cannot be license evidence.
EVIDENCE_VIEWS = {
    "github.com": {"blob", "raw"}, "gitlab.com": {"blob", "raw"}, HUGGING_FACE_HOST: {"blob", "resolve", "raw"},
}
HUGGING_FACE_DOMAINS = ("huggingface.co", "hf.co")

KEBAB_ID = re.compile(r"^[a-z0-9]+(?:[.-][a-z0-9]+)*$")
COMMIT = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
ISO_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key {key!r}")
        result[key] = value
    return result


def is_text(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def is_one_of(value: Any, choices: set[str]) -> bool:
    return isinstance(value, str) and value in choices


def is_https(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    try:
        parsed = urlparse(value)
    except ValueError:
        return False
    return parsed.scheme == "https" and bool(parsed.netloc)


def parse_location(url: Any) -> tuple[str, str | None, str | None, list[str]] | None:
    """Return (repository, view, commit, path) for a github.com, gitlab.com, or huggingface.co URL."""
    if not is_https(url):
        return None
    parsed = urlparse(url)
    if parsed.netloc not in REPOSITORY_HOSTS:
        return None
    parts = [unquote(part) for part in parsed.path.split("/") if part]
    if any(part in {".", ".."} for part in parts):
        return None
    if parsed.netloc == "github.com":
        split = 2
    elif parsed.netloc == "gitlab.com":
        split = parts.index("-") if "-" in parts else len(parts)
    else:
        split = next((index for index, part in enumerate(parts) if part in FILE_VIEWS), len(parts))
    repository, rest = parts[:split], parts[split:]
    if parsed.netloc == "gitlab.com" and rest:
        rest = rest[1:]
    if len(repository) < 2 or (parsed.netloc == "github.com" and len(parts) < 2):
        return None
    view = rest[0] if rest else None
    commit = rest[1] if len(rest) >= 2 and view in FILE_VIEWS and COMMIT.fullmatch(rest[1]) else None
    if rest and commit is None:
        return None
    return f"{parsed.netloc}/{'/'.join(repository)}".casefold(), view, commit, rest[2:]


def repository_location(url: Any) -> tuple[str, str | None] | None:
    """Return (repository, commit or None) for a repository, directory, or file URL."""
    location = parse_location(url)
    return None if location is None else (location[0], location[2])


def check_evidence(errors: list[str], owner: str, evidence: str, repository: Any, revision: Any) -> None:
    """Evidence must be a file in the reviewed repository at the reviewed revision."""
    location = parse_location(evidence)
    if (
        location is None or location[2] is None or not location[3] or urlparse(evidence).path.endswith("/")
        or location[1] not in EVIDENCE_VIEWS[urlparse(evidence).netloc]
    ):
        errors.append(f"{owner}: must be a file on {', '.join(sorted(REPOSITORY_HOSTS))} "
                      "(a blob, raw, or resolve path) at a 40-hex commit")
        return
    location = (location[0], location[2])
    expected = repository_location(repository)
    if expected is None:
        errors.append(f"{owner}: the reviewed repository (vcs, or else source) must be on "
                      f"{', '.join(sorted(REPOSITORY_HOSTS))}")
    elif location[0] != expected[0]:
        errors.append(f"{owner}: must be in the reviewed repository {expected[0]}, not {location[0]}")
    if not isinstance(revision, str) or location[1] != revision:
        errors.append(f"{owner}: must be at the reviewed revision {revision}, not {location[1]}")


def fingerprint(entry: dict[str, Any]) -> str:
    """SHA-256 of the canonical JSON of every reviewed field of an artifact entry."""
    material = {key: value for key, value in entry.items() if key not in FINGERPRINT_EXCLUDED}
    canonical = json.dumps(material, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def is_date(value: Any) -> bool:
    if not isinstance(value, str) or not ISO_DATE.fullmatch(value):
        return False
    try:
        date.fromisoformat(value)
    except ValueError:
        return False
    return True


def is_identified(license_id: Any) -> bool:
    return is_text(license_id) and license_id.strip() != "NOASSERTION"


def is_custom(license_id: Any) -> bool:
    if not isinstance(license_id, str):
        return False
    tokens = re.split(r"[\s()]+", license_id)
    return any(token == "other" or token.startswith("LicenseRef-") for token in tokens)


def is_scanned(path: str) -> bool:
    parts = path.casefold().split("/")
    if any(part.endswith(SCANNED_DIRECTORIES) for part in parts[:-1]):
        return True
    return parts[-1].endswith(SCANNED_SUFFIXES + SCANNED_DIRECTORIES)


def notice_headings(notices_text: str) -> list[str]:
    return [line[3:].strip() for line in notices_text.splitlines() if line.startswith("## ")]


def check_fields(
    errors: list[str], owner: str, value: Any, expected: set[str], optional: frozenset[str] = frozenset(),
) -> bool:
    if not isinstance(value, dict):
        errors.append(f"{owner}: must be an object")
        return False
    missing = expected - optional - value.keys()
    unknown = value.keys() - expected
    if missing:
        errors.append(f"{owner}: missing fields {sorted(missing)}")
    if unknown:
        errors.append(f"{owner}: unknown fields {sorted(unknown)}")
    return not missing


def check_string_list(errors: list[str], owner: str, value: Any) -> list[str]:
    if not isinstance(value, list) or not all(is_text(item) for item in value):
        errors.append(f"{owner}: must be a list of non-empty strings")
        return []
    if len(set(value)) != len(value):
        errors.append(f"{owner}: contains duplicates")
    return value


def is_hugging_face(url: str) -> bool:
    host = (urlparse(url).hostname or "").casefold()
    return any(host == domain or host.endswith(f".{domain}") for domain in HUGGING_FACE_DOMAINS)


def check_hugging_face_download(errors: list[str], owner: str, entry: dict[str, Any], url: str) -> None:
    """Bind a Hugging Face download to the reviewed repository and revision of its own entry."""
    parsed, source, revision = urlparse(url), entry["source"], entry["revision"]
    if parsed.netloc != HUGGING_FACE_HOST:
        errors.append(f"{owner}: Hugging Face url must use the canonical host https://{HUGGING_FACE_HOST}")
        return
    if not is_https(source) or urlparse(source).netloc != HUGGING_FACE_HOST:
        errors.append(f"{owner}: a Hugging Face download needs a https://{HUGGING_FACE_HOST} source repository")
        return
    if not isinstance(revision, str) or not COMMIT.fullmatch(revision):
        errors.append(f"{owner}: a Hugging Face download needs the entry's 40-hex revision")
        return
    prefix = f"{urlparse(source).path.rstrip('/')}/resolve/{revision}/"
    segments = unquote(parsed.path).split("/")
    if not parsed.path.startswith(prefix) or any(segment in {".", ".."} for segment in segments):
        errors.append(f"{owner}: Hugging Face url must start with https://{HUGGING_FACE_HOST}{prefix}")


def check_downloads(errors: list[str], entry: dict[str, Any]) -> None:
    entry_id, downloads = entry["id"], entry["downloads"]
    if not isinstance(downloads, list):
        errors.append(f"{entry_id}: downloads: must be a list")
        return
    seen: set[tuple[str, str]] = set()
    for index, item in enumerate(downloads):
        owner = f"{entry_id}: downloads[{index}]"
        if not check_fields(errors, owner, item, DOWNLOAD_FIELDS, optional=frozenset({"platform"})):
            continue
        url = item["url"]
        if not is_https(url):
            errors.append(f"{owner}: url must be https://")
        elif is_hugging_face(url):
            check_hugging_face_download(errors, owner, entry, url)
        if not isinstance(item["sha256"], str) or not SHA256.fullmatch(item["sha256"]):
            errors.append(f"{owner}: sha256 must be 64 lowercase hex characters of the file bytes")
        size = item["size"]
        if isinstance(size, bool) or not isinstance(size, int) or size <= 0:
            errors.append(f"{owner}: size must be a positive integer")
        platform = item.get("platform")
        if "platform" in item and not is_text(platform):
            errors.append(f"{owner}: platform must be a non-empty string when present")
        key = (repr(url), repr(platform))
        if key in seen:
            errors.append(f"{owner}: duplicate url and platform")
        seen.add(key)


def check_license(errors: list[str], entry: dict[str, Any], blocked: bool) -> None:
    entry_id, kind, license_record = entry["id"], entry["kind"], entry["license"]
    if not check_fields(errors, f"{entry_id}: license", license_record, LICENSE_FIELDS):
        return
    for field in ("code", "content", "name"):
        value = license_record[field]
        if value is not None and not is_text(value):
            errors.append(f"{entry_id}: license.{field}: must be a non-empty string or null")
    evidence = license_record["evidence"]
    if evidence is not None:
        check_evidence(errors, f"{entry_id}: license.evidence", evidence, entry.get("vcs") or entry["source"],
                       entry["revision"])
    if blocked:
        return
    field = "code" if kind in CODE_KINDS else "content"
    if not is_identified(license_record[field]):
        errors.append(f"{entry_id}: license.{field}: must be identified for kind {kind} unless blocked")
    if evidence is None:
        errors.append(f"{entry_id}: license.evidence: missing evidence requires distribution blocked")
    if any(is_custom(license_record[name]) for name in ("code", "content")) and not (
        is_text(license_record["name"]) and evidence is not None
    ):
        errors.append(f"{entry_id}: license.name: a custom license needs an exact name and evidence unless blocked")


def check_upstream(errors: list[str], entry_id: str, upstream: Any, blocked: bool) -> None:
    if not isinstance(upstream, list):
        errors.append(f"{entry_id}: upstream: must be a list")
        return
    for index, hop in enumerate(upstream):
        owner = f"{entry_id}: upstream[{index}]"
        optional = frozenset({"vcs", "revision", "licenseName"})
        if not check_fields(errors, owner, hop, UPSTREAM_FIELDS, optional=optional):
            continue
        if not is_text(hop["name"]):
            errors.append(f"{owner}: name must be a non-empty string")
        if not is_https(hop["source"]):
            errors.append(f"{owner}: source must be https://")
        if "vcs" in hop and repository_location(hop["vcs"]) is None:
            errors.append(f"{owner}: vcs must be a github.com, gitlab.com, or huggingface.co repository")
        revision = hop.get("revision")
        if revision is not None and (not isinstance(revision, str) or not COMMIT.fullmatch(revision)):
            errors.append(f"{owner}: revision must be a 40-hex commit")
        license_name = hop.get("licenseName")
        if "licenseName" in hop and not is_text(license_name):
            errors.append(f"{owner}: licenseName must be a non-empty string when present")
        evidence = hop["evidence"]
        if evidence is not None:
            check_evidence(errors, f"{owner}: evidence", evidence, hop.get("vcs") or hop["source"], revision)
        if blocked:
            continue
        if not is_identified(hop["license"]) or evidence is None:
            errors.append(f"{owner}: an upstream hop without an identified license and evidence requires blocked")
        elif is_custom(hop["license"]) and not is_text(license_name):
            errors.append(f"{owner}: a custom upstream license needs an exact licenseName unless blocked")


def check_terms(errors: list[str], entry: dict[str, Any], blocked: bool) -> None:
    entry_id, terms = entry["id"], entry["terms"]
    if not check_fields(errors, f"{entry_id}: terms", terms, TERMS_FIELDS):
        return
    for field in PERMISSIONS:
        if not is_one_of(terms[field], PERMISSION_VALUES):
            errors.append(f"{entry_id}: terms.{field}: must be one of {sorted(PERMISSION_VALUES)}")
        elif terms[field] == "unknown" and not blocked:
            errors.append(f"{entry_id}: terms.{field}: unknown requires distribution blocked")
    if not isinstance(terms["attribution"], str):
        errors.append(f"{entry_id}: terms.attribution: must be a string")
    if terms["termsUrl"] is not None and not is_https(terms["termsUrl"]):
        errors.append(f"{entry_id}: terms.termsUrl: must be https:// or null")
    download = terms["download"]
    if not check_fields(errors, f"{entry_id}: terms.download", download, {"access", "presentation"}):
        return
    access, presentation = download["access"], download["presentation"]
    if not is_one_of(access, ACCESS_VALUES):
        errors.append(f"{entry_id}: terms.download.access: must be one of {sorted(ACCESS_VALUES)}")
    elif access == "unknown" and not blocked:
        errors.append(f"{entry_id}: terms.download.access: unknown requires distribution blocked")
    if not is_one_of(presentation, PRESENTATION_VALUES):
        errors.append(f"{entry_id}: terms.download.presentation: must be one of {sorted(PRESENTATION_VALUES)}")
        return
    if presentation == "unknown" and not blocked:
        errors.append(f"{entry_id}: terms.download.presentation: unknown requires distribution blocked")
    if presentation == "none" and entry["distribution"] != "bundle":
        errors.append(f"{entry_id}: terms.download.presentation: none is only valid for bundle")
    if entry["distribution"] == "user-download" and presentation not in {"link", "acknowledgement"}:
        errors.append(f"{entry_id}: terms.download.presentation: user-download requires link or acknowledgement")


def check_review(errors: list[str], entry: dict[str, Any], fixture: bool) -> None:
    entry_id, review = entry["id"], entry["review"]
    if fixture:
        if check_fields(errors, f"{entry_id}: review", review, {"notes"}) and not is_text(review["notes"]):
            errors.append(f"{entry_id}: review.notes: must be a non-empty string")
        return
    if not check_fields(errors, f"{entry_id}: review", review, REVIEW_FIELDS):
        return
    if not is_date(review["date"]):
        errors.append(f"{entry_id}: review.date: must be YYYY-MM-DD")
    if not is_text(review["notes"]):
        errors.append(f"{entry_id}: review.notes: must be a non-empty string")
    legal = review["legal"]
    if not check_fields(errors, f"{entry_id}: review.legal", legal, LEGAL_FIELDS, optional=frozenset({"fingerprint"})):
        return
    status = legal["status"]
    if not is_one_of(status, LEGAL_STATUSES):
        errors.append(f"{entry_id}: review.legal.status: must be one of {sorted(LEGAL_STATUSES)}")
        return
    if legal["reference"] is not None and not is_text(legal["reference"]):
        errors.append(f"{entry_id}: review.legal.reference: must be a non-empty string or null")
    if legal["date"] is not None and not is_date(legal["date"]):
        errors.append(f"{entry_id}: review.legal.date: must be YYYY-MM-DD or null")
    if status in {"approved", "rejected"} and not (is_text(legal["reference"]) and is_date(legal["date"])):
        errors.append(f"{entry_id}: review.legal: {status} requires a reference and date")
    if status == "rejected" and entry["distribution"] != "blocked":
        errors.append(f"{entry_id}: review.legal.status: rejected requires distribution blocked")
    if status == "approved" and entry["distribution"] == "blocked":
        errors.append(f"{entry_id}: review.legal.status: a blocked entry cannot be approved")
    recorded = legal.get("fingerprint")
    if recorded is not None and (not isinstance(recorded, str) or not SHA256.fullmatch(recorded)):
        errors.append(f"{entry_id}: review.legal.fingerprint: must be 64 lowercase hex characters")
    elif status == "approved" and recorded is None:
        errors.append(f"{entry_id}: review.legal.fingerprint: approved requires the reviewed fingerprint")
    elif status == "approved" and recorded != fingerprint(entry):
        errors.append(f"{entry_id}: review.legal.fingerprint: reviewed fields changed since approval; "
                      "a fresh legal review is required")


def check_artifact(errors: list[str], entry: dict[str, Any]) -> None:
    entry_id, kind = entry["id"], entry["kind"]
    for field in ("name", "version"):
        if not is_text(entry[field]):
            errors.append(f"{entry_id}: {field}: must be a non-empty string")
    if not is_https(entry["source"]):
        errors.append(f"{entry_id}: source: must be https://")
    if "vcs" in entry and repository_location(entry["vcs"]) is None:
        errors.append(f"{entry_id}: vcs: must be a github.com, gitlab.com, or huggingface.co repository")
    source_location = repository_location(entry["source"])
    if source_location and source_location[1] is not None and source_location[1] != entry["revision"]:
        errors.append(f"{entry_id}: source: a commit in source must equal the entry revision")
    distribution = entry["distribution"]
    if not is_one_of(distribution, DISTRIBUTIONS):
        errors.append(f"{entry_id}: distribution: must be one of {sorted(DISTRIBUTIONS)}")
    blocked = distribution == "blocked"
    revision = entry["revision"]
    if revision is not None and (not isinstance(revision, str) or not COMMIT.fullmatch(revision)):
        errors.append(f"{entry_id}: revision: must be a 40-hex commit or null")
    check_downloads(errors, entry)
    if revision is None and not entry["downloads"]:
        errors.append(f"{entry_id}: revision: needs a commit revision, downloads, or both")
    configuration = entry["configuration"]
    if kind == "engine" and not is_text(configuration):
        errors.append(f"{entry_id}: configuration: an engine needs a named build configuration")
    if kind != "engine" and configuration is not None:
        errors.append(f"{entry_id}: configuration: only engines have a configuration")
    check_string_list(errors, f"{entry_id}: usedBy", entry["usedBy"])
    check_license(errors, entry, blocked)
    check_upstream(errors, entry_id, entry["upstream"], blocked)
    check_terms(errors, entry, blocked)
    check_review(errors, entry, fixture=False)


def check_fixture(errors: list[str], entry: dict[str, Any]) -> None:
    entry_id = entry["id"]
    if not is_text(entry["name"]):
        errors.append(f"{entry_id}: name: must be a non-empty string")
    if entry["synthetic"] is not True:
        errors.append(f"{entry_id}: synthetic: fixtures must be synthetic")
    if not is_text(entry["method"]):
        errors.append(f"{entry_id}: method: must describe how the fixture was produced")
    if not entry["paths"]:
        errors.append(f"{entry_id}: paths: a fixture entry must list its files")
    check_review(errors, entry, fixture=True)


def find_cycles(errors: list[str], graph: dict[str, list[str]]) -> None:
    state: dict[str, str] = {}

    def visit(node: str, trail: list[str]) -> None:
        state[node] = "visiting"
        for child in graph[node]:
            if child not in graph:
                continue
            if state.get(child) == "visiting":
                cycle = trail[trail.index(child):] + [child]
                errors.append(f"{node}: requires: cycle {' -> '.join(cycle)}")
            elif child not in state:
                visit(child, trail + [child])
        state[node] = "done"

    for node in graph:
        if node not in state:
            visit(node, [node])


def is_approved(entry: dict[str, Any]) -> bool:
    review = entry.get("review")
    if not isinstance(review, dict) or not isinstance(review.get("legal"), dict):
        return False
    return review["legal"].get("status") == "approved"


def check_approval(
    errors: list[str], entry: dict[str, Any], requires: list[str], by_id: dict[str, dict[str, Any]],
    headings: list[str],
) -> None:
    # Unknown answers are already rejected for every entry that is not blocked,
    # and an approved entry is never blocked.
    entry_id, terms = entry["id"], entry["terms"]
    if terms.get("commercialUse") != "allowed":
        errors.append(f"{entry_id}: approval: requires terms.commercialUse allowed")
    if not is_text(terms.get("attribution")):
        errors.append(f"{entry_id}: approval: terms.attribution must be recorded")
    for required in requires:
        if required in by_id and not is_approved(by_id[required]):
            errors.append(f"{entry_id}: approval: requires unapproved {required}")
    if entry["distribution"] == "bundle":
        if terms.get("redistribution") != "allowed":
            errors.append(f"{entry_id}: approval: bundle requires terms.redistribution allowed")
        if not is_text(entry["name"]) or not any(entry["name"] in heading for heading in headings):
            errors.append(f"{entry_id}: approval: bundle requires a {NOTICES_PATH} '## ' heading containing its name")
        if entry["kind"] in CONTENT_KINDS and not entry["downloads"]:
            errors.append(f"{entry_id}: approval: a bundled {entry['kind']} requires downloads with hashes and sizes")
    if entry["distribution"] == "user-download":
        if not is_https(terms.get("termsUrl")):
            errors.append(f"{entry_id}: approval: user-download requires terms.termsUrl")
        if not entry["downloads"]:
            errors.append(f"{entry_id}: approval: user-download requires downloads with hashes and sizes")


def validate(manifest: Any, notices_text: str, tracked_files: list[str]) -> list[str]:
    errors: list[str] = []
    if not check_fields(errors, "manifest", manifest, {"manifestVersion", "artifacts"}):
        return errors
    if manifest["manifestVersion"] != 1:
        errors.append("manifest: manifestVersion: unsupported version")
    artifacts = manifest["artifacts"]
    if not isinstance(artifacts, list) or not artifacts:
        errors.append("manifest: artifacts: must be a non-empty list")
        return errors

    tracked = set(tracked_files)
    by_id: dict[str, dict[str, Any]] = {}
    components: list[dict[str, Any]] = []
    path_owner: dict[str, str] = {}
    for index, entry in enumerate(artifacts):
        if not isinstance(entry, dict):
            errors.append(f"artifacts[{index}]: must be an object")
            continue
        entry_id = entry.get("id")
        if not isinstance(entry_id, str) or not KEBAB_ID.fullmatch(entry_id):
            errors.append(f"artifacts[{index}]: id: must be lowercase kebab-case (dots allowed between alphanumerics)")
            continue
        if entry_id in by_id:
            errors.append(f"{entry_id}: id: duplicate id")
            continue
        by_id[entry_id] = entry
        kind = entry.get("kind")
        if not is_one_of(kind, KINDS):
            errors.append(f"{entry_id}: kind: must be one of {sorted(KINDS)}")
            continue
        fixture = kind == "fixture"
        if fixture and not check_fields(errors, entry_id, entry, FIXTURE_FIELDS):
            continue
        if not fixture and not check_fields(errors, entry_id, entry, ENTRY_FIELDS, optional=frozenset({"vcs"})):
            continue
        for path in check_string_list(errors, f"{entry_id}: paths", entry["paths"]):
            if path in path_owner and path_owner[path] != entry_id:
                errors.append(f"{entry_id}: paths: {path} is already listed by {path_owner[path]}")
            path_owner.setdefault(path, entry_id)
            if path not in tracked:
                errors.append(f"{entry_id}: paths: {path} is not a tracked file")
        if fixture:
            check_fixture(errors, entry)
            continue
        check_string_list(errors, f"{entry_id}: requires", entry["requires"])
        check_artifact(errors, entry)
        components.append(entry)

    graph: dict[str, list[str]] = {}
    for entry in components:
        requires = entry["requires"] if isinstance(entry["requires"], list) else []
        graph[entry["id"]] = [item for item in requires if isinstance(item, str)]
        for required in graph[entry["id"]]:
            target = by_id.get(required)
            if target is None:
                errors.append(f"{entry['id']}: requires: unknown id {required}")
            elif is_one_of(target.get("kind"), {"engine", "fixture"}):
                errors.append(f"{entry['id']}: requires: must not require {target.get('kind')} {required}")
    find_cycles(errors, graph)

    headings = notice_headings(notices_text)
    for entry in components:
        if is_approved(entry) and isinstance(entry["terms"], dict):
            check_approval(errors, entry, graph[entry["id"]], by_id, headings)

    fixture_files = {path for path in tracked if path.startswith(FIXTURE_ROOT)}
    fixture_paths = {
        path for entry in by_id.values() if entry.get("kind") == "fixture"
        for path in (entry.get("paths") if isinstance(entry.get("paths"), list) else [])
        if isinstance(path, str)
    }
    for path in sorted(fixture_files - fixture_paths):
        errors.append(f"tracked: {path}: fixture file has no provenance entry")
    for path in sorted(fixture_paths - fixture_files):
        errors.append(f"tracked: {path}: fixture path is outside {FIXTURE_ROOT} or not tracked")
    for path in sorted(tracked):
        if is_scanned(path) and path not in path_owner:
            errors.append(f"tracked: {path}: model, native binary, or audio file is not registered in {MANIFEST_PATH}")
    return errors


def tracked_files() -> list[str]:
    output = subprocess.run(
        ["git", "ls-files", "-z"], cwd=ROOT, check=True, capture_output=True,
    ).stdout.decode("utf-8")
    return [path for path in output.split("\0") if path]


def main(argv: list[str]) -> None:
    manifest = json.loads(
        (ROOT / MANIFEST_PATH).read_text(encoding="utf-8"), object_pairs_hook=reject_duplicate_keys,
    )
    if argv[:1] == ["--fingerprint"]:
        entries = {entry.get("id"): entry for entry in manifest["artifacts"] if entry.get("kind") != "fixture"}
        if len(argv) < 2 or any(entry_id not in entries for entry_id in argv[1:]):
            sys.exit("usage: check_licensing.py --fingerprint <artifact id>...")
        for entry_id in argv[1:]:
            print(f"{entry_id} {fingerprint(entries[entry_id])}")
        return
    notices = (ROOT / NOTICES_PATH).read_text(encoding="utf-8")
    errors = validate(manifest, notices, tracked_files())
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        sys.exit(1)
    artifacts = manifest["artifacts"]
    counts = {
        distribution: sum(1 for entry in artifacts if entry.get("distribution") == distribution)
        for distribution in ("bundle", "user-download", "blocked")
    }
    approved = sum(1 for entry in artifacts if is_approved(entry))
    fixtures = sum(1 for entry in artifacts if entry["kind"] == "fixture")
    print(
        f"Licensing manifest is consistent ({len(artifacts)} entries: {counts['bundle']} bundle, "
        f"{counts['user-download']} user-download, {counts['blocked']} blocked, {fixtures} fixture; "
        f"{approved} legally approved)."
    )


if __name__ == "__main__":
    main(sys.argv[1:])
