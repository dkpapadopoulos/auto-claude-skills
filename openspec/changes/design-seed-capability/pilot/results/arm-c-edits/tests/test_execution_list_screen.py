"""The execution-list screen must stay self-contained and faithful to its envelope.

`scripts/build_execution_list.py` renders the frozen report envelope into a single HTML
file. The two properties worth guarding are the ones a reader cannot check by looking at
the page: that the payload is embedded byte-for-byte (so the screen can be audited
against the source), and that the page reaches for nothing outside itself.
"""

from __future__ import annotations

import importlib.util
import json
import re
from pathlib import Path
from types import ModuleType

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
GENERATOR = REPO_ROOT / "scripts" / "build_execution_list.py"
ENVELOPE = REPO_ROOT / "tests" / "fixtures" / "design_seed_pilot" / "review_report_envelope.json"


def _load_generator() -> ModuleType:
    """Import the generator by path — `scripts/` is not an importable package."""
    spec = importlib.util.spec_from_file_location("dion_build_execution_list", GENERATOR)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def generator() -> ModuleType:
    return _load_generator()


@pytest.fixture(scope="module")
def envelope_text() -> str:
    return ENVELOPE.read_text(encoding="utf-8")


@pytest.fixture(scope="module")
def html(generator: ModuleType, envelope_text: str) -> str:
    return generator.build_html(envelope_text)


def test_envelope_is_embedded_verbatim(html: str, envelope_text: str) -> None:
    assert envelope_text in html, "envelope must be embedded byte-for-byte, not re-serialised"


def test_exactly_one_embedding_element(html: str) -> None:
    assert html.count('<script type="application/json" id="dion-report">') == 1
    assert html.count('id="dion-report"') == 1


def test_embedded_payload_parses_back_to_the_source_envelope(html: str) -> None:
    start = html.index('id="dion-report">') + len('id="dion-report">')
    embedded = html[start : html.index("</script>", start)]
    assert json.loads(embedded) == json.loads(ENVELOPE.read_text(encoding="utf-8"))


def test_no_external_references(html: str) -> None:
    """Openable from disk means no network: no remote URLs, no src/href, no fetch."""
    body = html.replace(ENVELOPE.read_text(encoding="utf-8"), "")
    forbidden = (
        r"https?://", r"\bsrc\s*=", r"\bhref\s*=", r"\bfetch\s*\(", r"XMLHttpRequest", r"@import",
    )
    for pattern in forbidden:
        assert re.search(pattern, body) is None, f"page must not contain {pattern!r}"


def test_generator_refuses_a_payload_that_would_break_out_of_the_script_element(
    generator: ModuleType,
) -> None:
    hostile = json.dumps({"note": "</script><img>"})
    with pytest.raises(generator.EnvelopeNotEmbeddable):
        generator.build_html(hostile)


def test_generator_refuses_unparseable_input(generator: ModuleType) -> None:
    with pytest.raises(json.JSONDecodeError):
        generator.build_html("{not json")


def test_writes_the_file_it_is_asked_for(generator: ModuleType, tmp_path: Path) -> None:
    out = tmp_path / "nested" / "execution-list.html"
    assert generator.main(["--envelope", str(ENVELOPE), "--out", str(out)]) == 0
    assert ENVELOPE.read_text(encoding="utf-8") in out.read_text(encoding="utf-8")


def test_screen_does_not_hard_code_the_order_data(html: str) -> None:
    """Rendering must come from the embedded payload, not from baked-in literals."""
    body = html.replace(ENVELOPE.read_text(encoding="utf-8"), "")
    for literal in ("FFLC", "inst-aggs", "59.1498", "ARCA", "119680"):
        assert literal not in body, f"{literal!r} is baked into the template instead of rendered"
