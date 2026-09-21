"""The execution-list screen must be self-contained and must not restate the envelope.

Two properties carry the whole design and neither is visible by eye in a 38 kB file:

1. The envelope is embedded VERBATIM in exactly one element. If the generator ever
   starts pretty-printing, re-serialising or escaping it, the page stops being a
   faithful copy of what `dion report` returned and silently becomes a second source
   of truth. Byte equality is the only assertion that catches that.
2. The page opens from disk. A single `<link>`, `fetch(` or `https://` makes it depend
   on a network it is not allowed to touch, and that failure is invisible on a machine
   that happens to be online.
"""

from __future__ import annotations

import importlib.util
import re
from pathlib import Path
from types import ModuleType

import pytest

FIXTURE = Path("tests/fixtures/design_seed_pilot/review_report_envelope.json")
GENERATOR = Path("scripts/build_execution_list.py")


def _load_generator() -> ModuleType:
    """Import the generator by path: `scripts/` is not on the test pythonpath."""
    spec = importlib.util.spec_from_file_location("build_execution_list", GENERATOR)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def generator() -> ModuleType:
    return _load_generator()


@pytest.fixture(scope="module")
def html(generator: ModuleType) -> str:
    return generator.render(FIXTURE.read_text(encoding="utf-8"))


def test_envelope_is_embedded_in_exactly_one_element(html: str) -> None:
    assert html.count('<script type="application/json" id="dion-report">') == 1
    assert html.count('id="dion-report"') == 1


def test_embedded_envelope_is_byte_identical_to_the_fixture(html: str) -> None:
    match = re.search(
        r'<script type="application/json" id="dion-report">\n(.*?)\n</script>',
        html,
        re.DOTALL,
    )
    assert match is not None, "the report element is missing or reshaped"
    assert match.group(1) == FIXTURE.read_text(encoding="utf-8")


def test_page_reaches_no_network(html: str) -> None:
    for token in ("http://", "https://", "<link", "fetch(", "XMLHttpRequest", "@import"):
        assert token not in html, f"{token!r} would make the page depend on a network"


def test_design_tokens_and_renderer_are_inlined(html: str) -> None:
    assert "--status-block-fg" in html, "design/tokens.css was not inlined"
    assert "execution_list.css" in html, "the screen stylesheet was not inlined"
    assert "getElementById('dion-report')" in html, "the renderer was not inlined"


def test_screen_renders_from_the_embedded_json_only(html: str) -> None:
    """No envelope value may be templated into the markup at build time.

    The page must read its own embedded copy. A generator that also interpolated
    values into the HTML could drift from the element it claims to render, and the
    drift would be undetectable from the page itself.
    """
    markup = html.split('<script type="application/json" id="dion-report">')[0]
    for value in ("rev-b7bd753c33f9", "rpt-a3ade10d6cf9", "inst-aggs", "SPMO", "119680"):
        assert value not in markup, f"{value!r} was templated into the markup"


def test_a_payload_that_would_break_out_of_the_element_fails_closed(
    generator: ModuleType,
) -> None:
    """Escaping is not an option when the contract says verbatim, so this must raise."""
    with pytest.raises(generator.EnvelopeNotEmbeddable):
        generator.render('{"x": "</script><img>"}')


def test_generator_opens_no_database_and_no_network(generator: ModuleType) -> None:
    source = GENERATOR.read_text(encoding="utf-8")
    for banned in ("duckdb", "urllib", "requests", "httpx", "socket"):
        assert banned not in source, f"the generator must not use {banned}"


def test_build_writes_a_file_that_opens_from_disk(
    generator: ModuleType, tmp_path: Path
) -> None:
    out = generator.build(FIXTURE, tmp_path / "nested" / "execution-list.html")
    assert out.exists()
    text = out.read_text(encoding="utf-8")
    assert text.startswith("<!doctype html>")
    assert text.rstrip().endswith("</html>")
