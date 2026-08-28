# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Canon is a canonicalization, formatting, and comparison library for serialization formats (XML, HTML, JSON, YAML). It produces standardized forms suitable for comparison, testing, digital signatures, and human-readable output.

## Common Commands

```bash
# Install dependencies
bundle install

# Run all tests
bundle exec rake spec        # or: bundle exec rspec

# Run a single test file
bundle exec rspec spec/canon/comparison/xml_comparator_spec.rb

# Run tests with specific pattern
bundle exec rspec spec/canon/comparison --tag focus

# Lint (rubocop)
bundle exec rake rubocop

# Default task (runs tests + lint)
bundle exec rake

# Performance benchmarks (takes ~5 minutes)
bundle exec rake performance:run

# Quick benchmark (~30 seconds)
bundle exec rake performance:quick
```

### Size Limits

Canon protects against pathologically large files with configurable limits:
- **File size**: Default 5MB (`CANON_MAX_FILE_SIZE`)
- **Node count**: Default 10,000 (`CANON_MAX_NODE_COUNT`)
- **Diff output**: Default 10,000 lines (`CANON_MAX_DIFF_LINES`)

```bash
export CANON_MAX_FILE_SIZE=10485760  # 10MB
export CANON_MAX_NODE_COUNT=50000
bundle exec rspec
```

## Architecture

### Core Entry Points

- `lib/canon.rb` — Main module entry point. Provides `Canon.format`, `Canon.parse`, and shorthand methods like `Canon.format_xml`, `Canon.parse_json`. Defines `SUPPORTED_FORMATS = [:xml, :yaml, :json, :html, :html4, :html5, :string]`.
- `lib/canon/cli.rb` — Thor-based CLI. Two commands: `canon format` (canonicalize/pretty-print) and `canon diff` (semantic comparison). See CLI long descriptions for full option documentation.
- `exe/canon` — CLI entry point (runs the Thor CLI).

### Two Comparison Algorithms — Distinct by Design

Canon provides two **fundamentally different** comparison algorithms. They are NOT alternative implementations of the same approach. They use different methods, accept different options, produce different intermediate representations, and solve different problems. The pipelines must never be merged or "unified."

#### DOM Algorithm (`diff_algorithm: :dom`, default)

Position-based recursive tree walk. Compares children by position, attributes by name, namespace by URI.

- **Method**: Positional recursive descent through the DOM tree
- **Code path**: `dom_diff` → format comparators (`XmlComparator`, `HtmlComparator`, `JsonComparator`, `YamlComparator`)
- **Algorithm-specific options**: Filtering (`ignore_children`, `ignore_text_nodes`, `ignore_attrs`, `ignore_nodes`, `ignore_attr_content`, `diff_children`)
- **Intermediate representation**: Integer comparison-result codes (EQUIVALENT, MISSING_NODE, UNEQUAL_TEXT_CONTENTS, etc.)
- **Output**: DiffNodes with diff codes
- **Strength**: Deterministic positional comparison with fine-grained filtering; O(n) performance
- **Location**: `lib/canon/comparison/`

#### Semantic Tree Algorithm (`diff_algorithm: :semantic`)

Signature-based tree matching. Computes node signatures, uses hash matching + similarity matching + structural propagation to find node correspondences even when nodes have moved. Produces insert/update/delete/move operations.

- **Method**: Signature computation → three-phase matching (hash, similarity, structural propagation) → operation detection
- **Code path**: `semantic_diff` → `TreeDiffIntegrator` → format adapters → `OperationConverter` → DiffNodes
- **Algorithm-specific options**: Matching strategy (`similarity_threshold`, `hash_matching`, `similarity_matching`, `propagation`)
- **Intermediate representation**: Operations (INSERT, DELETE, UPDATE, MOVE)
- **Output**: Operations → converted to DiffNodes
- **Strength**: Detects moved/renamed nodes and structural reorganization
- **Location**: `lib/canon/tree_diff/`

#### Shared Infrastructure (safe to consolidate)

Both algorithms share these pipeline steps — this is the ONLY layer where consolidation makes sense:
- Format detection (`FormatDetector`)
- Config resolution (`Canon::Config`)
- Match option resolution (`MatchOptions` resolvers, profiles, dimensions)
- Preprocessing (`:none`, `:c14n`, `:normalize`, `:format`)
- Parsing (format-specific `.parse` methods)
- DiffNode output format — both produce DiffNodes
- Diff formatting (`by_line` / `by_object`) — both feed into the same formatters

#### NOT Shared (do NOT merge)

- The comparison engines are entirely separate codepaths with no shared comparison logic
- DOM-specific filtering options (`ignore_*`) have no meaning in semantic matching
- Semantic-specific matching options (`similarity_threshold`, `hash_matching`) have no meaning in DOM comparison
- Intermediate representations differ: diff codes vs tree-matching operations

#### Two Activation Paths

Semantic diff can be activated two ways:
1. `diff_algorithm: :semantic` — caught by `Comparison.equivalent?`, routes to `Comparison.semantic_diff` (owns full pipeline end-to-end)
2. `match: { semantic_diff: true }` — passes through `dom_diff` to the format comparator, which detects the flag and calls its own `perform_semantic_tree_diff`

Path 1 is the primary API. Path 2 exists for direct comparator calls and is tested in `spec/canon/tree_diff/canon_integration_spec.rb`.

### Four-Layer Architecture

The comparison pipeline flows through four independent layers:

1. **Preprocessing** — Optional normalization (`:none`, `:c14n`, `:normalize`, `:format`)
2. **Algorithm Selection** — `:dom` (position-based, stable) or `:semantic` (signature-based, experimental)
3. **Match Options** — Dimension behaviors per format (`:text_content`, `:structural_whitespace`, `:attribute_values`, etc.) controlled via profiles (`:strict`, `:spec_friendly`, `:rendered`, `:content_only`)
4. **Diff Formatting** — `by_line` or `by_object` output mode

**Critical distinction**: Do NOT use `Canon.format_xml` output for string comparison in tests. The formatting process changes line counts and causes false failures. Use `Canon::Comparison.equivalent?` or RSpec matchers instead.

### Key Modules

- `lib/canon/comparison/` — DOM-based comparison logic. `comparison.rb` is the main facade; comparators live in submodules. `MatchOptions::Xml` defines profiles (`:strict`, `:spec_friendly`, `:rendered`, `:content_only`) and per-dimension behaviors.
- `lib/canon/tree_diff/` — Semantic tree diff engine. Separate from the DOM comparators. Integrates back into the main pipeline via `OperationConverter`.
- `lib/canon/diff_formatter/` — Output formatters for diff results. Two modes: `by_line` (line-by-line, used for HTML and strings) and `by_object` (semantic/object-level, used for XML/JSON/YAML). Contains format-specific formatters for XML, HTML, JSON, YAML output.
- `lib/canon/formatters/` — Pretty-printers for canonicalization/formatting (distinct from diff formatters). `XmlFormatter` supports Canonical XML (C14N).
- `lib/canon/config.rb` — Global configuration with per-format settings (profiles, preprocessing, diff options). Read at runtime via `Canon::Config.instance`.
- `lib/canon/rspec_matchers.rb` — RSpec matchers (`be_xml_equivalent_to`, `be_json_equivalent_to`, etc.). These delegate to `Canon::Comparison.equivalent?` with the global config. Automatically included in RSpec.
- `lib/canon/xml/sax_builder.rb` — SAX-based canon-tree builder (~6x faster than DOM parsing for large documents). Engine-neutral; `lib/canon/xml/sax.rb` selects the driver (`NokogiriDriver` on CRuby, `MoxmlDriver` under Opal).

### XML Engines

Canon is engine-agnostic across three seams (MECE — one concern per module):

- `Canon::XmlBackend` — XML engine selection. The default follows moxml's resolved adapter: **leptris whenever it is installed** (parse ~1.6x, serialize ~3.8x vs Nokogiri), raw Nokogiri otherwise (wrapping Nokogiri in moxml buys nothing — the wrapper adds 2-3x overhead). `:moxml` under Opal. `CANON_XML_BACKEND=nokogiri|moxml` forces either engine.
- `Canon::XmlParsing` — the only place that talks to engines for XML parse/serialize (moxml parses pass `readonly: true` — canon never mutates engine documents); node type queries answer for ANY recognized node (Nokogiri or moxml) by type, never by active backend — user-supplied Nokogiri nodes keep working under the moxml engine.
- `Canon::Html::NokogiriSupport` — HTML is always Nokogiri on CRuby (moxml has no HTML adapter, leptris no HTML parser); independent of the XML engine.
- `Canon::Xml::Sax` — SAX driver selection: `NokogiriDriver` on CRuby (per-event C callbacks beat FFI SAX today), `MoxmlDriver` under Opal. The builder (`SaxBuilder`) is engine-neutral.

Known remaining engine gaps are tracked upstream and surfaced as engine-conditional `pending`s in the C14N specs plus `spec/canon/xml/engine_parity_spec.rb` — the executable gate. Fixed upstream so far (libleptris 1.9.7 / leptris-ruby 1.9.28 / moxml 0.5.10): attribute-value normalization, prolog/epilog PIs and comments, batched SAX, materialize with namespace declarations, readonly parse, document-node children. Canon's moxml conversion is record-based (`build_from_moxml` consumes `materialize` records — no per-node wrapper allocation; ~0.55x the Nokogiri conversion). Still open: leptris#606 (DTD ATTLIST defaults applied by default — the only remaining C14N pending), moxml#129 (serializer byte parity — last blocker for pretty-printing on leptris), moxml#134 (Document#free), moxml#140 (materialize scope inconsistency — canon defensively skips depth-0 non-element records). leptris SAX is at parity with Nokogiri SAX, not faster (leptris#594) — the SAX driver stays Nokogiri until that changes. Pretty-printers (`PrettyPrinter::Xml`, `XmlNormalized`) deliberately stay on the Nokogiri pipeline — pretty-printed bytes are canon's product.

Engine A/B testing: `CANON_XML_BACKEND=nokogiri bundle exec rspec` (or `=moxml` to force leptris when it isn't the resolved default). The default suite must stay green under BOTH values; the only expected pendings are the upstream-tracked ones. The benchmark header (`rake performance:quick`) reports the active engine.

### Format Detection

`Canon::Comparison::FormatDetector` auto-detects format from string content or object type (Moxml::Node → XML, Nokogiri::HTML → HTML, Hash → JSON, etc.). HTML4 vs HTML5 is determined by DOCTYPE.

### Difference Result Format

When `verbose: true`, comparison returns `Canon::Comparison::ComparisonResult` (or legacy Hash/Array). The result exposes:
- `differences` — array of `DiffNode` objects
- `equivalent?` — boolean
- `preprocessed_strings` / `original_strings` — for diff display
- `tree_diff_operations` / `tree_diff_statistics` / `tree_diff_matching` — only when using semantic algorithm

### Difference Classification

Differences are classified into three tiers:
- **Normative** — Affects equivalence (documents not equivalent if different)
- **Informative** — Tracked but doesn't affect equivalence
- **Formatting-only** — Pure whitespace/formatting differences when normalized content matches

Use `show_diffs: :normative` to display only equivalence-affecting differences.

### Testing Notes

- Tests use a shared fixture system (`spec/canon/fixtures/`). `spec/canon/fixtures_integrity_spec.rb` validates fixture references.
- `spec/spec_helper.rb` disables monkey-patching and uses `expect` syntax.
- Specs named `*_spec.rb` under `spec/canon/` map to `lib/canon/`.

## Architectural Rules

These rules are non-negotiable. Violations must be fixed before merge.

### No `respond_to?` — use proper types

`respond_to?` is a type-system bypass. It means the code does not know what it is working with, which is a failure of the model. Every object flowing through the comparison pipeline is one of a known set of types (`Canon::Xml::Node` and subclasses, `Nokogiri::XML::Node` and subclasses, `ComparisonResult`, `DiffNode`, `Hash`, `String`). Use `is_a?` for type dispatch, or better yet, design the classes so that polymorphism handles dispatch automatically (e.g., a shared base class or module providing the same interface).

If you find yourself writing `respond_to?`, stop and introduce a proper type check or a shared protocol instead.

### No `send` to bypass visibility — make the method public

Using `send` to call a private method from another module or class is an encapsulation violation. If another object needs to call a method, that method must be public. Private means "internal implementation detail of this class" — if it is needed externally, it is not private. Either make it public or rethink the boundary.

### No duplicated type-checking logic

Backend-agnostic node queries (text node?, text content, whitespace check) must live in one place. The `Canon::Comparison::NodeInspector` module provides a single source of truth for cross-backend node type operations. All code that needs to query node properties must use it — never re-implement type dispatch inline.

### Single module for cross-cutting utilities

When multiple modules need the same capability (e.g., checking if a node is a whitespace-only text node), extract a single utility module. Do not duplicate the logic in each consumer.

### Two algorithm pipelines must remain separate

DOM and Semantic comparison are fundamentally different algorithms with different option sets, different intermediate representations, and different codepaths. Proposals to "unify" or "merge" the algorithm pipelines are always wrong. The correct approach is to extract shared infrastructure (format detection, config, parsing, output formatting) into reusable methods while keeping the algorithm cores independent. See "Two Comparison Algorithms — Distinct by Design" above.
