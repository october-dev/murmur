"""Tests for tool/check_licensing.py."""

from __future__ import annotations

import copy
import json
import unittest
from typing import Any

import check_licensing
from check_licensing import validate

COMMIT = "0123456789abcdef0123456789abcdef01234567"
OTHER_COMMIT = "89abcdef0123456789abcdef0123456789abcdef"
SHA = "ab" * 32
FIXTURE = "conformance/fixtures/runtime-events.jsonl"
NOTICES = "# Third-party notices\n\n## Example Engine\n\nApache-2.0 text.\n"
BASE_EVIDENCE = f"https://github.com/example/base/blob/{OTHER_COMMIT}/LICENSE"


def base_hop(**changes: Any) -> dict[str, Any]:
    """An identified upstream hop whose evidence is bound to its own repository and revision."""
    hop = {"name": "Base", "source": "https://github.com/example/base", "revision": OTHER_COMMIT, "license": "MIT",
           "evidence": BASE_EVIDENCE}
    hop.update(changes)
    return hop


def approve(entry: dict[str, Any]) -> dict[str, Any]:
    """Record an approval bound to the entry's current reviewed fields."""
    entry["review"]["legal"] = {
        "status": "approved", "reference": "LR-1", "date": "2026-09-28",
        "fingerprint": check_licensing.fingerprint(entry),
    }
    return entry


def base_entry() -> dict[str, Any]:
    """An approved bundled engine, pinned only by revision, with a notice."""
    return approve({
        "id": "example-engine",
        "kind": "engine",
        "name": "Example Engine",
        "version": "v1.0.0",
        "source": "https://github.com/example/engine",
        "revision": COMMIT,
        "downloads": [],
        "paths": [],
        "configuration": "v1.0.0 default build, macOS arm64",
        "requires": [],
        "usedBy": ["#42"],
        "license": {
            "code": "Apache-2.0",
            "content": None,
            "name": None,
            "evidence": f"https://github.com/example/engine/blob/{COMMIT}/LICENSE",
        },
        "upstream": [],
        "terms": {
            "redistribution": "allowed",
            "commercialUse": "allowed",
            "modification": "allowed",
            "attribution": "Apache-2.0 license text",
            "download": {"access": "public", "presentation": "none"},
            "termsUrl": "https://www.apache.org/licenses/LICENSE-2.0",
        },
        "distribution": "bundle",
        "review": {
            "date": "2026-09-28",
            "notes": "Synthetic test entry.",
            "legal": {"status": "pending", "reference": None, "date": None},
        },
    })


def model_entry() -> dict[str, Any]:
    """An approved user-downloaded model with per-platform downloads."""
    entry = base_entry()
    entry.update({
        "id": "example-model",
        "kind": "model",
        "name": "Example Model",
        "source": "https://huggingface.co/example/model",
        "configuration": None,
        "downloads": [
            {"url": f"https://huggingface.co/example/model/resolve/{COMMIT}/a.bin", "sha256": SHA, "size": 10,
             "platform": "apple"},
            {"url": f"https://huggingface.co/example/model/resolve/{COMMIT}/b.bin", "sha256": SHA, "size": 20,
             "platform": "linux"},
        ],
        "distribution": "user-download",
    })
    entry["license"] = {
        "code": None,
        "content": "CC-BY-4.0",
        "name": None,
        "evidence": f"https://huggingface.co/example/model/blob/{COMMIT}/README.md",
    }
    entry["terms"]["download"] = {"access": "public", "presentation": "link"}
    return approve(entry)


def fixture_entry() -> dict[str, Any]:
    return {
        "id": "example-fixtures",
        "kind": "fixture",
        "name": "Example fixtures",
        "paths": [FIXTURE],
        "synthetic": True,
        "method": "hand-authored synthetic ProtoJSON",
        "review": {"notes": "Murmur-authored."},
    }


def manifest(*entries: dict[str, Any]) -> dict[str, Any]:
    return {"manifestVersion": 1, "artifacts": [*entries, fixture_entry()]}


def run(value: dict[str, Any], notices: str = NOTICES, tracked: list[str] | None = None) -> list[str]:
    return validate(value, notices, [FIXTURE] if tracked is None else tracked)


class RepositoryManifestTest(unittest.TestCase):
    def test_repository_manifest_passes(self) -> None:
        root = check_licensing.ROOT
        value = json.loads(
            (root / check_licensing.MANIFEST_PATH).read_text(encoding="utf-8"),
            object_pairs_hook=check_licensing.reject_duplicate_keys,
        )
        notices = (root / check_licensing.NOTICES_PATH).read_text(encoding="utf-8")
        self.assertEqual(validate(value, notices, check_licensing.tracked_files()), [])

    def test_sherpa_configuration_pins_runtime_and_onnxruntime(self) -> None:
        value = json.loads((check_licensing.ROOT / check_licensing.MANIFEST_PATH).read_text(encoding="utf-8"))
        sherpa = next(entry for entry in value["artifacts"] if entry["id"] == "sherpa-onnx")
        for option in ("SHERPA_ONNX_USE_PRE_INSTALLED_ONNXRUNTIME_IF_AVAILABLE=OFF",
                       "SHERPA_ONNX_LINK_LIBSTDCPP_STATICALLY=OFF", "SHERPA_ONNX_USE_STATIC_CRT=OFF"):
            self.assertIn(option, sherpa["configuration"])
        onnxruntime = next(entry for entry in value["artifacts"] if entry["id"] == "onnxruntime")
        windows = [item["url"] for item in onnxruntime["downloads"] if item.get("platform") == "windows-x64"]
        self.assertEqual(len(windows), 1)
        self.assertIn("-MD-Release-", windows[0])

    def test_duplicate_json_keys_are_rejected(self) -> None:
        with self.assertRaises(ValueError):
            json.loads('{"a": 1, "a": 2}', object_pairs_hook=check_licensing.reject_duplicate_keys)


class ValidCasesTest(unittest.TestCase):
    def assert_valid(self, value: dict[str, Any], **kwargs: Any) -> None:
        self.assertEqual(run(value, **kwargs), [])

    def test_approved_bundle_engine_pinned_by_revision(self) -> None:
        self.assert_valid(manifest(base_entry()))

    def test_approved_custom_license_with_name_and_evidence(self) -> None:
        entry = model_entry()
        entry["license"].update({"content": "LicenseRef-Example", "name": "Example Model License v1"})
        self.assert_valid(manifest(approve(entry)))

    def test_approved_user_download_with_platform_downloads(self) -> None:
        self.assert_valid(manifest(model_entry()))

    def test_rejected_and_blocked_with_reference(self) -> None:
        entry = base_entry()
        entry["distribution"] = "blocked"
        entry["terms"]["download"]["presentation"] = "unknown"
        entry["review"]["legal"] = {"status": "rejected", "reference": "LR-2", "date": "2026-09-28"}
        self.assert_valid(manifest(entry))

    def test_blocked_entry_tolerates_ambiguity(self) -> None:
        entry = model_entry()
        entry["distribution"] = "blocked"
        entry["license"].update({"content": "NOASSERTION", "evidence": None})
        entry["terms"]["redistribution"] = "unknown"
        entry["upstream"] = [{"name": "Unknown", "source": "https://example.com", "license": "NOASSERTION",
                              "evidence": None}]
        entry["review"]["legal"] = {"status": "pending", "reference": None, "date": None}
        self.assert_valid(manifest(entry))

    def test_approved_requirement_chain(self) -> None:
        dependency = base_entry()
        dependency.update({"id": "example-library", "kind": "native-library", "name": "Example Library",
                           "configuration": None})
        engine = base_entry()
        engine["requires"] = ["example-library"]
        self.assert_valid(manifest(approve(engine), approve(dependency)), notices=NOTICES + "\n## Example Library\n")

    def test_registered_tracked_model_passes(self) -> None:
        entry = model_entry()
        entry["paths"] = ["models/example.onnx"]
        self.assert_valid(manifest(approve(entry)), tracked=[FIXTURE, "models/example.onnx"])

    def test_approved_content_bundle_with_downloads(self) -> None:
        entry = model_entry()
        entry["distribution"] = "bundle"
        entry["terms"]["download"]["presentation"] = "none"
        self.assert_valid(manifest(approve(entry)), notices=NOTICES + "\n## Example Model\n")

    def test_raw_and_resolve_file_evidence(self) -> None:
        engine = base_entry()
        engine["license"]["evidence"] = f"https://github.com/example/engine/raw/{COMMIT}/LICENSE"
        model = model_entry()
        model["license"]["evidence"] = f"https://huggingface.co/example/model/resolve/{COMMIT}/LICENSE"
        self.assert_valid(manifest(approve(engine), approve(model)))

    def test_package_source_with_vcs_repository(self) -> None:
        entry = base_entry()
        entry.update({"kind": "native-library", "configuration": None,
                      "source": "https://crates.io/crates/example/1.0.0", "vcs": "https://github.com/example/engine"})
        self.assert_valid(manifest(approve(entry)))

    def test_gitlab_and_source_tree_evidence(self) -> None:
        entry = base_entry()
        entry["source"] = f"https://gitlab.com/example/engine/-/tree/{COMMIT}/src"
        entry["license"]["evidence"] = f"https://gitlab.com/example/engine/-/blob/{COMMIT}/COPYING"
        self.assert_valid(manifest(approve(entry)))

    def test_approved_upstream_custom_license_with_name(self) -> None:
        entry = model_entry()
        entry["upstream"] = [base_hop(source="https://huggingface.co/example/base", license="other",
                                      licenseName="Example Base Model License v2",
                                      evidence=f"https://huggingface.co/example/base/blob/{OTHER_COMMIT}/LICENSE")]
        self.assert_valid(manifest(approve(entry)))

    def test_non_reviewed_fields_keep_approval(self) -> None:
        entry = base_entry()
        entry["usedBy"] = ["#42", "#26"]
        entry["review"]["notes"] = "Edited notes."
        self.assert_valid(manifest(entry))

    def test_fingerprint_ignores_key_order(self) -> None:
        entry = base_entry()
        reordered = dict(reversed(list(entry.items())))
        self.assertEqual(check_licensing.fingerprint(entry), check_licensing.fingerprint(reordered))


class InvalidCasesTest(unittest.TestCase):
    def assert_error(self, value: dict[str, Any], fragment: str, **kwargs: Any) -> None:
        errors = run(value, **kwargs)
        self.assertTrue(any(fragment in error for error in errors), f"{fragment!r} not in {errors}")

    # Pins and shape

    def test_tag_revision(self) -> None:
        entry = base_entry()
        entry["revision"] = "v1.0.0"
        self.assert_error(manifest(entry), "example-engine: revision: must be a 40-hex commit")

    def test_short_sha_revision(self) -> None:
        entry = base_entry()
        entry["revision"] = COMMIT[:7]
        self.assert_error(manifest(entry), "example-engine: revision: must be a 40-hex commit")

    def test_no_revision_and_no_downloads(self) -> None:
        entry = base_entry()
        entry["revision"] = None
        self.assert_error(manifest(entry), "needs a commit revision, downloads, or both")

    def test_download_without_sha256(self) -> None:
        entry = model_entry()
        del entry["downloads"][0]["sha256"]
        self.assert_error(manifest(entry), "downloads[0]: missing fields ['sha256']")

    def test_download_without_size(self) -> None:
        entry = model_entry()
        del entry["downloads"][0]["size"]
        self.assert_error(manifest(entry), "downloads[0]: missing fields ['size']")

    def test_download_with_non_positive_size(self) -> None:
        entry = model_entry()
        entry["downloads"][0]["size"] = 0
        self.assert_error(manifest(entry), "downloads[0]: size must be a positive integer")

    def assert_download_error(self, url: str, fragment: str) -> None:
        entry = model_entry()
        entry["downloads"][0]["url"] = url
        self.assert_error(manifest(entry), f"example-model: downloads[0]: Hugging Face url {fragment}")

    def test_hugging_face_resolve_main(self) -> None:
        self.assert_download_error("https://huggingface.co/example/model/resolve/main/a.bin",
                                   f"must start with https://huggingface.co/example/model/resolve/{COMMIT}/")

    def test_hugging_face_other_revision(self) -> None:
        self.assert_download_error(f"https://huggingface.co/example/model/resolve/{OTHER_COMMIT}/a.bin",
                                   f"must start with https://huggingface.co/example/model/resolve/{COMMIT}/")

    def test_hugging_face_other_repository(self) -> None:
        self.assert_download_error(f"https://huggingface.co/example/other/resolve/{COMMIT}/a.bin",
                                   f"must start with https://huggingface.co/example/model/resolve/{COMMIT}/")

    def test_hugging_face_repository_prefix(self) -> None:
        self.assert_download_error(f"https://huggingface.co/example/model-fork/resolve/{COMMIT}/a.bin",
                                   f"must start with https://huggingface.co/example/model/resolve/{COMMIT}/")

    def test_hugging_face_path_traversal(self) -> None:
        for url in (
            f"https://huggingface.co/example/model/resolve/{COMMIT}/../../other/resolve/main/a.bin",
            f"https://huggingface.co/example/model/resolve/{COMMIT}/%2e%2e/a.bin",
        ):
            self.assert_download_error(url, "must start with https://huggingface.co/example/model/resolve/")

    def test_hugging_face_host_variants(self) -> None:
        for host in ("huggingface.co:443", "www.huggingface.co", "hf.co", "HuggingFace.CO", "user@huggingface.co",
                     "cdn-lfs.hf.co"):
            self.assert_download_error(f"https://{host}/example/model/resolve/{COMMIT}/a.bin",
                                       "must use the canonical host https://huggingface.co")

    def test_hugging_face_download_without_revision(self) -> None:
        entry = model_entry()
        entry["revision"] = None
        self.assert_error(manifest(entry), "downloads[0]: a Hugging Face download needs the entry's 40-hex revision")

    def test_hugging_face_download_from_non_hugging_face_source(self) -> None:
        entry = model_entry()
        entry["source"] = "https://github.com/example/model"
        self.assert_error(manifest(entry), "downloads[0]: a Hugging Face download needs a https://huggingface.co")

    def test_duplicate_download_url_and_platform(self) -> None:
        entry = model_entry()
        entry["downloads"][1] = copy.deepcopy(entry["downloads"][0])
        self.assert_error(manifest(entry), "downloads[1]: duplicate url and platform")

    def test_http_source(self) -> None:
        entry = base_entry()
        entry["source"] = "http://github.com/example/engine"
        self.assert_error(manifest(entry), "example-engine: source: must be https://")

    def test_malformed_url(self) -> None:
        entry = base_entry()
        entry["source"] = "https://[::1"
        self.assert_error(manifest(entry), "example-engine: source: must be https://")

    def test_duplicate_id(self) -> None:
        self.assert_error(manifest(base_entry(), base_entry()), "example-engine: id: duplicate id")

    def test_unknown_field(self) -> None:
        entry = base_entry()
        entry["reveiw"] = {}
        self.assert_error(manifest(entry), "example-engine: unknown fields ['reveiw']")

    def test_dangling_requires(self) -> None:
        entry = base_entry()
        entry["requires"] = ["missing-library"]
        self.assert_error(manifest(entry), "example-engine: requires: unknown id missing-library")

    def test_direct_cycle(self) -> None:
        entry = model_entry()
        entry["requires"] = ["example-model"]
        self.assert_error(manifest(entry), "cycle example-model -> example-model")

    def test_indirect_cycle(self) -> None:
        first = model_entry()
        second = model_entry()
        second.update({"id": "example-vocab", "kind": "tokenizer", "name": "Example Vocab"})
        first["requires"] = ["example-vocab"]
        second["requires"] = ["example-model"]
        self.assert_error(manifest(first, second), "cycle example-model -> example-vocab -> example-model")

    def test_model_requires_engine(self) -> None:
        entry = model_entry()
        entry["requires"] = ["example-engine"]
        self.assert_error(manifest(base_entry(), entry), "must not require engine example-engine")

    def test_engine_without_configuration(self) -> None:
        entry = base_entry()
        entry["configuration"] = None
        self.assert_error(manifest(entry), "an engine needs a named build configuration")

    def test_non_engine_with_configuration(self) -> None:
        entry = model_entry()
        entry["configuration"] = "default"
        self.assert_error(manifest(entry), "only engines have a configuration")

    # Ambiguity that is not blocked

    def test_unknown_permission(self) -> None:
        entry = base_entry()
        entry["terms"]["modification"] = "unknown"
        self.assert_error(manifest(entry), "terms.modification: unknown requires distribution blocked")

    def test_unknown_download_access(self) -> None:
        entry = model_entry()
        entry["terms"]["download"]["access"] = "unknown"
        self.assert_error(manifest(entry), "terms.download.access: unknown requires distribution blocked")

    def test_unknown_download_presentation(self) -> None:
        entry = model_entry()
        entry["terms"]["download"]["presentation"] = "unknown"
        self.assert_error(manifest(entry), "terms.download.presentation: unknown requires distribution blocked")

    def test_native_library_without_code_license(self) -> None:
        entry = base_entry()
        entry.update({"kind": "native-library", "configuration": None})
        entry["license"]["code"] = None
        self.assert_error(manifest(entry), "license.code: must be identified for kind native-library")

    def test_tokenizer_with_only_code_license(self) -> None:
        entry = model_entry()
        entry["kind"] = "tokenizer"
        entry["license"].update({"code": "Apache-2.0", "content": None})
        self.assert_error(manifest(entry), "license.content: must be identified for kind tokenizer")

    def test_model_without_content_license(self) -> None:
        entry = model_entry()
        entry["license"]["content"] = "NOASSERTION"
        self.assert_error(manifest(entry), "license.content: must be identified for kind model")

    def test_other_license_without_name(self) -> None:
        entry = model_entry()
        entry["license"]["content"] = "other"
        self.assert_error(manifest(entry), "a custom license needs an exact name and evidence")

    def test_other_license_without_evidence(self) -> None:
        entry = model_entry()
        entry["license"].update({"content": "other", "name": "Example License", "evidence": None})
        self.assert_error(manifest(entry), "a custom license needs an exact name and evidence")

    def test_missing_evidence(self) -> None:
        entry = base_entry()
        entry["license"]["evidence"] = None
        self.assert_error(manifest(entry), "missing evidence requires distribution blocked")

    def test_weak_upstream_hop(self) -> None:
        entry = model_entry()
        entry["upstream"] = [{"name": "Base", "source": "https://example.com", "license": "NOASSERTION",
                              "evidence": None}]
        self.assert_error(manifest(entry), "upstream[0]: an upstream hop without an identified license")

    # Mutable evidence

    def test_blob_main_license_evidence(self) -> None:
        entry = base_entry()
        entry["license"]["evidence"] = "https://github.com/example/engine/blob/main/LICENSE"
        self.assert_error(manifest(entry), "license.evidence: must be a file on github.com, gitlab.com, huggingface.co")

    def test_blob_main_upstream_evidence(self) -> None:
        entry = model_entry()
        entry["upstream"] = [{"name": "Base", "source": "https://github.com/example/base", "license": "MIT",
                              "evidence": "https://github.com/example/base/blob/main/LICENSE"}]
        self.assert_error(manifest(entry), "upstream[0]: evidence: must be a file on github.com, gitlab.com")

    # Evidence binding

    def test_evidence_must_name_a_file(self) -> None:
        for url in (
            f"https://github.com/example/engine/tree/{COMMIT}",
            f"https://github.com/example/engine/tree/{COMMIT}/LICENSE",
            f"https://github.com/example/engine/blob/{COMMIT}",
            f"https://github.com/example/engine/blob/{COMMIT}/",
            f"https://github.com/example/engine/blob/{COMMIT}/docs/",
            f"https://github.com/example/engine/resolve/{COMMIT}/LICENSE",
        ):
            with self.subTest(url=url):
                entry = base_entry()
                entry["license"]["evidence"] = url
                self.assert_error(manifest(approve(entry)), "license.evidence: must be a file on github.com")

    def test_hugging_face_and_gitlab_evidence_must_name_a_file(self) -> None:
        for url in (f"https://huggingface.co/example/model/resolve/{COMMIT}",
                    f"https://huggingface.co/example/model/tree/{COMMIT}/voices"):
            with self.subTest(url=url):
                entry = model_entry()
                entry["license"]["evidence"] = url
                self.assert_error(manifest(approve(entry)), "license.evidence: must be a file on github.com")
        entry = base_entry()
        entry["source"] = "https://gitlab.com/example/engine"
        entry["license"]["evidence"] = f"https://gitlab.com/example/engine/-/tree/{COMMIT}/COPYING"
        self.assert_error(manifest(approve(entry)), "license.evidence: must be a file on github.com")

    def test_upstream_evidence_must_name_a_file(self) -> None:
        entry = model_entry()
        entry["upstream"] = [base_hop(evidence=f"https://github.com/example/base/tree/{OTHER_COMMIT}")]
        self.assert_error(manifest(approve(entry)), "upstream[0]: evidence: must be a file on github.com")

    def test_evidence_in_another_repository(self) -> None:
        entry = base_entry()
        entry["license"]["evidence"] = f"https://github.com/unrelated/project/blob/{COMMIT}/LICENSE"
        self.assert_error(manifest(approve(entry)),
                          "license.evidence: must be in the reviewed repository github.com/example/engine")

    def test_evidence_at_another_revision(self) -> None:
        entry = base_entry()
        entry["license"]["evidence"] = f"https://github.com/example/engine/blob/{OTHER_COMMIT}/LICENSE"
        self.assert_error(manifest(approve(entry)), f"license.evidence: must be at the reviewed revision {COMMIT}")

    def test_evidence_on_non_repository_host(self) -> None:
        for url in (f"https://example.com/{COMMIT}/LICENSE",
                    f"https://raw.githubusercontent.com/example/engine/{COMMIT}/LICENSE",
                    f"https://github.com:443/example/engine/blob/{COMMIT}/LICENSE",
                    f"https://github.com/example/engine/blob/{COMMIT}/../../other/LICENSE"):
            entry = base_entry()
            entry["license"]["evidence"] = url
            self.assert_error(manifest(approve(entry)), "license.evidence: must be a file on github.com")

    def test_evidence_without_entry_revision(self) -> None:
        entry = model_entry()
        entry["revision"] = None
        entry["downloads"] = [{"url": "https://example.com/model.bin", "sha256": SHA, "size": 1}]
        self.assert_error(manifest(approve(entry)), "license.evidence: must be at the reviewed revision None")

    def test_package_source_without_vcs(self) -> None:
        entry = base_entry()
        entry.update({"kind": "native-library", "configuration": None,
                      "source": "https://crates.io/crates/example/1.0.0"})
        self.assert_error(manifest(approve(entry)), "license.evidence: the reviewed repository (vcs, or else source)")

    def test_invalid_vcs(self) -> None:
        entry = base_entry()
        entry["vcs"] = "https://example.com/example/engine"
        self.assert_error(manifest(approve(entry)), "example-engine: vcs: must be a github.com")

    def test_source_commit_differs_from_revision(self) -> None:
        entry = base_entry()
        entry["source"] = f"https://github.com/example/engine/tree/{OTHER_COMMIT}/src"
        self.assert_error(manifest(approve(entry)), "source: a commit in source must equal the entry revision")

    def test_upstream_evidence_in_another_repository(self) -> None:
        entry = model_entry()
        entry["upstream"] = [base_hop(evidence=f"https://github.com/unrelated/project/blob/{OTHER_COMMIT}/LICENSE")]
        self.assert_error(manifest(approve(entry)),
                          "upstream[0]: evidence: must be in the reviewed repository github.com/example/base")

    def test_upstream_evidence_at_another_revision(self) -> None:
        entry = model_entry()
        entry["upstream"] = [base_hop(evidence=f"https://github.com/example/base/blob/{COMMIT}/LICENSE")]
        self.assert_error(manifest(approve(entry)),
                          f"upstream[0]: evidence: must be at the reviewed revision {OTHER_COMMIT}")

    def test_upstream_evidence_without_revision(self) -> None:
        entry = model_entry()
        hop = base_hop()
        del hop["revision"]
        entry["upstream"] = [hop]
        self.assert_error(manifest(approve(entry)), "upstream[0]: evidence: must be at the reviewed revision None")

    # Custom upstream licenses

    def test_approved_upstream_other_license_without_name(self) -> None:
        entry = model_entry()
        entry["upstream"] = [base_hop(license="other")]
        self.assert_error(manifest(approve(entry)), "upstream[0]: a custom upstream license needs an exact licenseName")

    def test_approved_upstream_licenseref_without_name(self) -> None:
        entry = model_entry()
        entry["upstream"] = [base_hop(license="MIT AND LicenseRef-Base")]
        self.assert_error(manifest(approve(entry)), "upstream[0]: a custom upstream license needs an exact licenseName")

    def test_empty_upstream_license_name(self) -> None:
        entry = model_entry()
        entry["upstream"] = [base_hop(license="other", licenseName=" ")]
        self.assert_error(manifest(approve(entry)), "upstream[0]: licenseName must be a non-empty string")

    # Approval bound to the reviewed fields

    def test_approved_without_fingerprint(self) -> None:
        entry = base_entry()
        del entry["review"]["legal"]["fingerprint"]
        self.assert_error(manifest(entry), "review.legal.fingerprint: approved requires the reviewed fingerprint")

    def test_malformed_fingerprint(self) -> None:
        entry = base_entry()
        entry["review"]["legal"]["fingerprint"] = "abc"
        self.assert_error(manifest(entry), "review.legal.fingerprint: must be 64 lowercase hex characters")

    def test_every_reviewed_field_change_invalidates_approval(self) -> None:
        changes = {
            "name": lambda e: e.update(name="Example Engine Fork"),
            "version": lambda e: e.update(version="v2.0.0"),
            "source": lambda e: e.update(source="https://github.com/other/engine"),
            "revision": lambda e: e.update(revision=OTHER_COMMIT),
            "vcs": lambda e: e.update(vcs="https://github.com/example/engine"),
            "downloads": lambda e: e["downloads"][0].update(sha256="cd" * 32),
            "download url": lambda e: e["downloads"][1].update(
                url=f"https://huggingface.co/example/model/resolve/{COMMIT}/c.bin"),
            "paths": lambda e: e.update(paths=["models/example.onnx"]),
            "configuration": lambda e: e.update(configuration="v1.0.0 build with TTS"),
            "requires": lambda e: e.update(requires=["example-vocab"]),
            "license": lambda e: e["license"].update(content="CC-BY-SA-4.0"),
            "license evidence": lambda e: e["license"].update(
                evidence=f"https://huggingface.co/example/model/blob/{COMMIT}/LICENSE"),
            "upstream": lambda e: e["upstream"].append(base_hop()),
            "terms": lambda e: e["terms"].update(attribution="Credit Example."),
            "download terms": lambda e: e["terms"]["download"].update(presentation="acknowledgement"),
            "terms url": lambda e: e["terms"].update(termsUrl="https://example.com/terms"),
            "distribution": lambda e: e.update(distribution="bundle"),
        }
        vocab = model_entry()
        vocab.update({"id": "example-vocab", "kind": "tokenizer", "name": "Example Vocab"})
        approve(vocab)
        tracked = [FIXTURE, "models/example.onnx"]
        for field, change in changes.items():
            with self.subTest(field=field):
                entry = model_entry()
                change(entry)
                self.assert_error(manifest(entry, vocab),
                                  "example-model: review.legal.fingerprint: reviewed fields changed",
                                  notices=NOTICES + "\n## Example Model\n", tracked=tracked)

    def test_rebinding_an_approval_to_another_artifact(self) -> None:
        entry = base_entry()
        entry.update({"version": "v9.9.9", "source": "https://github.com/unrelated/engine", "revision": OTHER_COMMIT})
        entry["license"]["evidence"] = f"https://github.com/unrelated/engine/blob/{OTHER_COMMIT}/LICENSE"
        self.assert_error(manifest(entry), "example-engine: review.legal.fingerprint: reviewed fields changed")

    # Download terms

    def test_user_download_with_presentation_none(self) -> None:
        entry = model_entry()
        entry["terms"]["download"]["presentation"] = "none"
        self.assert_error(manifest(entry), "presentation: user-download requires link or acknowledgement")

    def test_blocked_with_presentation_none(self) -> None:
        entry = base_entry()
        entry["distribution"] = "blocked"
        entry["review"]["legal"]["status"] = "pending"
        self.assert_error(manifest(entry), "presentation: none is only valid for bundle")

    # Legal review and approval

    def test_rejected_without_reference(self) -> None:
        entry = base_entry()
        entry["distribution"] = "blocked"
        entry["terms"]["download"]["presentation"] = "unknown"
        entry["review"]["legal"] = {"status": "rejected", "reference": None, "date": "2026-09-28"}
        self.assert_error(manifest(entry), "review.legal: rejected requires a reference and date")

    def test_rejected_without_date(self) -> None:
        entry = base_entry()
        entry["distribution"] = "blocked"
        entry["terms"]["download"]["presentation"] = "unknown"
        entry["review"]["legal"] = {"status": "rejected", "reference": "LR-2", "date": None}
        self.assert_error(manifest(entry), "review.legal: rejected requires a reference and date")

    def test_rejected_but_not_blocked(self) -> None:
        entry = base_entry()
        entry["review"]["legal"]["status"] = "rejected"
        self.assert_error(manifest(entry), "rejected requires distribution blocked")

    def test_blocked_and_approved(self) -> None:
        entry = base_entry()
        entry["distribution"] = "blocked"
        entry["terms"]["download"]["presentation"] = "unknown"
        self.assert_error(manifest(entry), "a blocked entry cannot be approved")

    def test_approved_without_reference(self) -> None:
        entry = base_entry()
        entry["review"]["legal"]["reference"] = None
        self.assert_error(manifest(entry), "review.legal: approved requires a reference and date")

    def test_approved_without_date(self) -> None:
        entry = base_entry()
        entry["review"]["legal"]["date"] = None
        self.assert_error(manifest(entry), "review.legal: approved requires a reference and date")

    def test_approved_with_invalid_date(self) -> None:
        entry = base_entry()
        entry["review"]["legal"]["date"] = "2026-02-30"
        self.assert_error(manifest(entry), "review.legal.date: must be YYYY-MM-DD or null")

    def test_approved_non_commercial(self) -> None:
        entry = base_entry()
        entry["terms"]["commercialUse"] = "prohibited"
        self.assert_error(manifest(entry), "approval: requires terms.commercialUse allowed")

    def test_approved_without_attribution(self) -> None:
        entry = base_entry()
        entry["terms"]["attribution"] = ""
        self.assert_error(manifest(entry), "approval: terms.attribution must be recorded")

    def test_approved_with_unapproved_requirement(self) -> None:
        dependency = model_entry()
        dependency.update({"id": "example-vocab", "kind": "tokenizer", "name": "Example Vocab"})
        dependency["review"]["legal"] = {"status": "pending", "reference": None, "date": None}
        entry = model_entry()
        entry["requires"] = ["example-vocab"]
        self.assert_error(manifest(entry, dependency), "approval: requires unapproved example-vocab")

    def test_approved_bundle_with_prohibited_redistribution(self) -> None:
        entry = base_entry()
        entry["terms"]["redistribution"] = "prohibited"
        self.assert_error(manifest(entry), "approval: bundle requires terms.redistribution allowed")

    def test_approved_bundle_without_notice(self) -> None:
        self.assert_error(manifest(base_entry()), "approval: bundle requires a THIRD_PARTY_NOTICES.md",
                          notices="# Third-party notices\n\nExample Engine is mentioned but has no heading.\n")

    def test_approved_content_bundle_without_downloads(self) -> None:
        # The shape of silero-vad-coreml: a small model classified as a bundle, pinned only by revision.
        for kind in ("model", "voice", "tokenizer", "phonemizer"):
            with self.subTest(kind=kind):
                entry = model_entry()
                entry.update({"kind": kind, "distribution": "bundle", "downloads": []})
                entry["terms"]["download"]["presentation"] = "none"
                self.assert_error(manifest(approve(entry)),
                                  f"example-model: approval: a bundled {kind} requires downloads with hashes and sizes",
                                  notices=NOTICES + "\n## Example Model\n")

    def test_approved_user_download_without_downloads(self) -> None:
        entry = model_entry()
        entry["downloads"] = []
        self.assert_error(manifest(entry), "approval: user-download requires downloads with hashes and sizes")

    def test_approved_user_download_without_terms_url(self) -> None:
        entry = model_entry()
        entry["terms"]["termsUrl"] = None
        self.assert_error(manifest(entry), "approval: user-download requires terms.termsUrl")

    # Fixtures and tracked files

    def test_non_synthetic_fixture(self) -> None:
        value = manifest(base_entry())
        value["artifacts"][-1]["synthetic"] = False
        self.assert_error(value, "example-fixtures: synthetic: fixtures must be synthetic")

    def test_fixture_without_method(self) -> None:
        value = manifest(base_entry())
        value["artifacts"][-1]["method"] = " "
        self.assert_error(value, "example-fixtures: method: must describe how the fixture was produced")

    def test_tracked_fixture_without_provenance(self) -> None:
        extra = "conformance/fixtures/new.jsonl"
        self.assert_error(manifest(base_entry()), f"tracked: {extra}: fixture file has no provenance entry",
                          tracked=[FIXTURE, extra])

    def test_fixture_path_listed_twice(self) -> None:
        value = manifest(base_entry())
        second = fixture_entry()
        second["id"] = "other-fixtures"
        value["artifacts"].append(second)
        self.assert_error(value, f"other-fixtures: paths: {FIXTURE} is already listed by example-fixtures")

    def test_fixture_path_not_tracked(self) -> None:
        self.assert_error(manifest(base_entry()), f"example-fixtures: paths: {FIXTURE} is not a tracked file",
                          tracked=[])

    def test_unregistered_tracked_onnx(self) -> None:
        self.assert_error(manifest(base_entry()), "tracked: models/example.onnx: model, native binary, or audio",
                          tracked=[FIXTURE, "models/example.onnx"])

    def test_unregistered_file_inside_model_bundle(self) -> None:
        path = "models/Example.mlmodelc/weights/weight.bin"
        self.assert_error(manifest(base_entry()), f"tracked: {path}: model, native binary", tracked=[FIXTURE, path])
        path = "models/Example.mlmodelc/metadata.json"
        self.assert_error(manifest(base_entry()), f"tracked: {path}: model, native binary", tracked=[FIXTURE, path])

    def test_scan_is_case_insensitive(self) -> None:
        for path in ("models/unsafe.ONNX", "test/Voice.WAV", "libs/Engine.DyLib", "models/Model.MLMODELC/model.mil",
                     "vendor/Lib.XCFramework/Info.plist"):
            self.assert_error(manifest(base_entry()), f"tracked: {path}: model, native binary", tracked=[FIXTURE, path])

    def test_unregistered_tracked_audio(self) -> None:
        self.assert_error(manifest(base_entry()), "tracked: test/voice.wav: model, native binary, or audio",
                          tracked=[FIXTURE, "test/voice.wav"])


if __name__ == "__main__":
    unittest.main()
