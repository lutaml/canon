# Canon OO Refactoring - Complete Implementation Plan

## Background

The Canon gem currently has two large monolithic classes that violate MECE (Mutually Exclusive, Collectively Exhaustive) and Single Responsibility principles:

1. **DiffFormatter** (~2800 lines): Handles formatting, tree visualization, line diffs, DOM parsing, token highlighting, and color management all in one class
2. **Comparison** (~700 lines): Contains 4 nested modules (Xml, Html, Json, Yaml) with duplicated logic

### Current State
- ✅ Bug Fix: Compressed multiline content bug FIXED
- ✅ MECE Test Scenarios: 5/5 PASSING
- ✅ OO Classes Created: DiffBlock, DiffContext, DiffReport
- ✅ Phase 1 Complete: Foundation OO Class Specs (107 tests)
- ✅ Test Coverage: 436/442 passing (98.6%)
- ⚠️ 6 Failing Tests: Need expectation updates for new output format (Phase 4)
- ⚠️ Monolithic Classes: Need MECE refactoring (Phases 2-3)

## Refactoring Goals

1. **Orchestrator Pattern**: Both DiffFormatter and Comparison become pure orchestrators
2. **Line Count Limits**:
   - DiffFormatter: Under 200 lines (pure delegation)
   - Comparison: Under 150 lines (pure delegation)
3. **MECE Compliance**: Each extracted class has ONE clear responsibility
4. **Format Separation**: By-object and by-line formatters separated by format
5. **Spec Migration**: Move specs to new files, delete from old files
6. **Complete Coverage**: Every class has its own comprehensive spec file

## Target Architecture

### 1. Comparison Module Structure

```
lib/canon/comparison.rb                 (~150 lines - orchestrator)
lib/canon/comparison/
├── xml_comparator.rb                   (~400 lines)
├── html_comparator.rb                  (~100 lines)
├── json_comparator.rb                  (~150 lines)
├── yaml_comparator.rb                  (~50 lines)
├── node_filters.rb                     (~100 lines)
├── node_comparators.rb                 (~200 lines)
└── difference_tracker.rb               (~50 lines)
```

**Comparison.rb Responsibilities (orchestrator only):**
- Format detection (`detect_format`, `detect_string_format`)
- Format compatibility checking
- Delegation to format-specific comparators
- Public API (`equivalent?` method)

### 2. DiffFormatter Class Structure

```
lib/canon/diff_formatter.rb             (~200 lines - orchestrator)
lib/canon/diff_formatter/
├── by_object/
│   ├── base_formatter.rb               (~100 lines)
│   ├── xml_formatter.rb                (~150 lines)
│   ├── html_formatter.rb               (~100 lines)
│   ├── json_formatter.rb               (~100 lines)
│   └── yaml_formatter.rb               (~80 lines)
├── by_line/
│   ├── base_formatter.rb               (~100 lines)
│   ├── xml_formatter.rb                (~600 lines - DOM-guided)
│   ├── json_formatter.rb               (~200 lines - semantic)
│   ├── yaml_formatter.rb               (~150 lines - semantic)
│   └── simple_formatter.rb             (~200 lines - fallback)
└── shared/
    ├── line_formatter.rb               (~150 lines)
    ├── token_highlighter.rb            (~200 lines)
    ├── character_visualizer.rb         (~100 lines)
    ├── color_manager.rb                (~80 lines)
    └── tree_renderer.rb                (~300 lines)
```

**DiffFormatter.rb Responsibilities (orchestrator only):**
- Initialize with options (use_color, mode, context_lines, etc.)
- Manage visualization map
- Dispatch to mode-specific formatters based on `@mode`
- Provide public `format()` method
- Success message generation

### 3. Spec File Structure

```
spec/canon/comparison_spec.rb           (Keep orchestration tests only)
spec/canon/comparison/
├── xml_comparator_spec.rb
├── html_comparator_spec.rb
├── json_comparator_spec.rb
├── yaml_comparator_spec.rb
├── node_filters_spec.rb
├── node_comparators_spec.rb
└── difference_tracker_spec.rb

spec/canon/diff_formatter_spec.rb       (Keep orchestration tests only)
spec/canon/diff_formatter/
├── by_object/
│   ├── base_formatter_spec.rb
│   ├── xml_formatter_spec.rb
│   ├── html_formatter_spec.rb
│   ├── json_formatter_spec.rb
│   └── yaml_formatter_spec.rb
├── by_line/
│   ├── base_formatter_spec.rb
│   ├── xml_formatter_spec.rb
│   ├── json_formatter_spec.rb
│   ├── yaml_formatter_spec.rb
│   └── simple_formatter_spec.rb
└── shared/
    ├── line_formatter_spec.rb
    ├── token_highlighter_spec.rb
    ├── character_visualizer_spec.rb
    ├── color_manager_spec.rb
    └── tree_renderer_spec.rb

spec/canon/diff/
├── diff_block_spec.rb                  (✅ COMPLETE - 26 tests)
├── diff_context_spec.rb                (✅ COMPLETE - 41 tests)
└── diff_report_spec.rb                 (✅ COMPLETE - 40 tests)
```

## Implementation Phases

### Phase 1: Foundation - OO Class Specs ✅ COMPLETE

**Objective**: Create comprehensive specs for existing OO foundation classes

**Tasks**:
1. ✅ Create `spec/canon/diff/diff_block_spec.rb`
   - ✅ Test initialization with start_idx, end_idx, types
   - ✅ Test size calculation
   - ✅ Test includes_type? method
   - ✅ Test to_h serialization
   - ✅ Test equality comparison

2. ✅ Create `spec/canon/diff/diff_context_spec.rb`
   - ✅ Test initialization with start_idx, end_idx, blocks
   - ✅ Test size and block_count calculations
   - ✅ Test includes_type? method
   - ✅ Test gap_to calculation
   - ✅ Test overlaps? detection
   - ✅ Test to_h serialization
   - ✅ Test equality comparison

3. ✅ Create `spec/canon/diff/diff_report_spec.rb`
   - ✅ Test initialization with element_name, file names, contexts
   - ✅ Test add_context method
   - ✅ Test context_count, block_count, change_count
   - ✅ Test has_differences?
   - ✅ Test includes_type? and contexts_with_type
   - ✅ Test summary generation
   - ✅ Test to_h serialization
   - ✅ Test equality comparison

**Verification**:
- ✅ All 3 new spec files created
- ✅ 100% coverage for DiffBlock, DiffContext, DiffReport
- ✅ All 107 new tests passing
- ✅ Full suite: 436/442 tests passing (98.6%)
- ✅ Rubocop: 505 offenses auto-corrected

**Status**: **COMPLETE** - Ready to commit

---

### Phase 2: Extract Comparison Components

**Objective**: Refactor Comparison module to orchestrator pattern with extracted comparators

#### Phase 2A: Extract Comparators

**Tasks**:
1. Create `lib/canon/comparison/xml_comparator.rb`
   - Move all `Comparison::Xml` logic
   - Make it a class with `equivalent?` class method
   - Keep DEFAULT_OPTS constant

2. Create `lib/canon/comparison/html_comparator.rb`
   - Move all `Comparison::Html` logic
   - Reuse logic from XmlComparator where possible

3. Create `lib/canon/comparison/json_comparator.rb`
   - Move all `Comparison::Json` logic
   - Extract Ruby object comparison logic

4. Create `lib/canon/comparison/yaml_comparator.rb`
   - Move all `Comparison::Yaml` logic
   - Delegate to JsonComparator for object comparison

#### Phase 2B: Extract Utilities

**Tasks**:
1. Create `lib/canon/comparison/node_filters.rb`
   - Extract `filter_attributes` logic
   - Extract `filter_children` logic
   - Extract `node_excluded?` logic
   - Methods: `filter_attributes`, `filter_children`, `should_exclude_node?`

2. Create `lib/canon/comparison/node_comparators.rb`
   - Extract element comparison logic
   - Extract text node comparison logic
   - Extract comment comparison logic
   - Extract attribute comparison logic
   - Methods for each node type comparison

3. Create `lib/canon/comparison/difference_tracker.rb`
   - Extract `add_difference` logic
   - Manage differences array in verbose mode
   - Methods: `track`, `differences`, `has_differences?`

#### Phase 2C: Update Orchestrator

**Tasks**:
1. Update `lib/canon/comparison.rb` to orchestrator
   - Keep only format detection
   - Keep only delegation logic
   - Remove all nested modules (Xml, Html, Json, Yaml)
   - Delegate to extracted comparators
   - Target: ~150 lines

#### Phase 2D: Migrate Specs

**Tasks**:
1. Create `spec/canon/comparison/xml_comparator_spec.rb`
   - Move all XML comparison tests from `comparison_spec.rb`
   - Add tests for new class structure

2. Create `spec/canon/comparison/html_comparator_spec.rb`
   - Move all HTML comparison tests from `comparison_spec.rb`

3. Create `spec/canon/comparison/json_comparator_spec.rb`
   - Move all JSON comparison tests from `comparison_spec.rb`

4. Create `spec/canon/comparison/yaml_comparator_spec.rb`
   - Move all YAML comparison tests from `comparison_spec.rb`

5. Create `spec/canon/comparison/node_filters_spec.rb`
   - Create tests for filtering logic

6. Create `spec/canon/comparison/node_comparators_spec.rb`
   - Create tests for node comparison logic

7. Create `spec/canon/comparison/difference_tracker_spec.rb`
   - Create tests for difference tracking

8. Update `spec/canon/comparison_spec.rb`
   - Keep only format detection tests
   - Keep only delegation tests
   - Keep only public API tests
   - Delete all moved tests

**Verification**:
- `lib/canon/comparison.rb` under 150 lines
- All extracted classes have specs
- All tests passing (no regressions)
- No duplicate tests between old and new files
- Run Rubocop and fix violations
- Commit when complete

**Status**: **PENDING**

---

### Phase 3: Extract DiffFormatter Components

#### Phase 3A: Extract By-Object Formatters

**Tasks**:
1. Create `lib/canon/diff_formatter/by_object/base_formatter.rb`
   - Shared tree building logic
   - Common initialization
   - Factory method `for_format`

2. Create `lib/canon/diff_formatter/by_object/xml_formatter.rb`
   - Extract XML tree building from `by_object_diff`
   - Handle DOM node paths
   - Format element differences

3. Create `lib/canon/diff_formatter/by_object/html_formatter.rb`
   - Extract HTML tree building
   - Similar to XML but for HTML nodes

4. Create `lib/canon/diff_formatter/by_object/json_formatter.rb`
   - Extract JSON tree building
   - Handle hash/array paths
   - Format JSON-specific differences

5. Create `lib/canon/diff_formatter/by_object/yaml_formatter.rb`
   - Extract YAML tree building
   - Similar to JSON but YAML-specific

**Spec Migration**:
1. Create `spec/canon/diff_formatter/by_object/base_formatter_spec.rb`
2. Create `spec/canon/diff_formatter/by_object/xml_formatter_spec.rb`
   - Move XML tree visualization tests
3. Create `spec/canon/diff_formatter/by_object/html_formatter_spec.rb`
4. Create `spec/canon/diff_formatter/by_object/json_formatter_spec.rb`
5. Create `spec/canon/diff_formatter/by_object/yaml_formatter_spec.rb`

#### Phase 3B: Extract By-Line Formatters

**Tasks**:
1. Create `lib/canon/diff_formatter/by_line/base_formatter.rb`
   - Shared LCS logic
   - Common hunk building
   - Factory method `for_format`

2. Create `lib/canon/diff_formatter/by_line/xml_formatter.rb`
   - Extract `dom_guided_xml_diff` logic
   - DOM parsing and element matching
   - Line range mapping
   - Context expansion

3. Create `lib/canon/diff_formatter/by_line/json_formatter.rb`
   - Extract `semantic_json_diff` logic
   - Pretty printing
   - Token highlighting

4. Create `lib/canon/diff_formatter/by_line/yaml_formatter.rb`
   - Extract `semantic_yaml_diff` logic
   - Pretty printing
   - Token highlighting

5. Create `lib/canon/diff_formatter/by_line/simple_formatter.rb`
   - Extract `simple_line_diff` logic
   - Basic LCS diff
   - Hunk building

**Spec Migration**:
1. Create `spec/canon/diff_formatter/by_line/base_formatter_spec.rb`
2. Create `spec/canon/diff_formatter/by_line/xml_formatter_spec.rb`
   - Move DOM-guided XML diff tests
   - Move MECE scenario tests
3. Create `spec/canon/diff_formatter/by_line/json_formatter_spec.rb`
   - Move semantic JSON diff tests
4. Create `spec/canon/diff_formatter/by_line/yaml_formatter_spec.rb`
   - Move semantic YAML diff tests
5. Create `spec/canon/diff_formatter/by_line/simple_formatter_spec.rb`
   - Move fallback diff tests

#### Phase 3C: Extract Shared Components

**Tasks**:
1. Create `lib/canon/diff_formatter/shared/line_formatter.rb`
   - Extract `format_unified_line` logic
   - Extract `format_changed_line` logic
   - Handle line number formatting

2. Create `lib/canon/diff_formatter/shared/token_highlighter.rb`
   - Extract `tokenize_xml`, `tokenize_json`, `tokenize_yaml`
   - Extract `build_token_highlighted_text`
   - Token-level diff highlighting

3. Create `lib/canon/diff_formatter/shared/character_visualizer.rb`
   - Extract `apply_visualization` logic
   - Extract `detect_non_ascii` logic
   - Manage visualization map

4. Create `lib/canon/diff_formatter/shared/color_manager.rb`
   - Extract `colorize` logic
   - ANSI color code management
   - Color mode handling

5. Create `lib/canon/diff_formatter/shared/tree_renderer.rb`
   - Extract `render_tree` logic
   - Extract `render_diff_node` logic
   - Box-drawing character rendering

**Spec Migration**:
1. Create `spec/canon/diff_formatter/shared/line_formatter_spec.rb`
   - Move line formatting tests
2. Create `spec/canon/diff_formatter/shared/token_highlighter_spec.rb`
   - Move token highlighting tests
3. Create `spec/canon/diff_formatter/shared/character_visualizer_spec.rb`
   - Move visualization tests
4. Create `spec/canon/diff_formatter/shared/color_manager_spec.rb`
   - Move color management tests
5. Create `spec/canon/diff_formatter/shared/tree_renderer_spec.rb`
   - Move tree rendering tests

#### Phase 3D: Update Orchestrator

**Tasks**:
1. Update `lib/canon/diff_formatter.rb` to orchestrator
   - Keep only initialization
   - Keep only mode/format dispatch logic
   - Delegate to by_object or by_line formatters
   - Keep success_message method
   - Remove all formatting logic
   - Target: ~200 lines

2. Update `spec/canon/diff_formatter_spec.rb`
   - Keep only initialization tests
   - Keep only dispatch tests
   - Keep only public API tests
   - Delete all moved tests

**Verification**:
- `lib/canon/diff_formatter.rb` under 200 lines
- All extracted classes have specs
- All tests passing (no regressions)
- No duplicate tests
- Run Rubocop and fix violations
- Commit when complete

**Status**: **PENDING**

---

### Phase 4: Integration and Testing

**Objective**: Fix failing tests and ensure complete integration

**Tasks**:
1. Fix duplicate key warning in visualization map (line 33-34)

2. Fix 6 failing tests:
   - `diff_formatter_spec.rb:393` - Update visualization expectations
   - `diff_formatter_spec.rb:437` - Update visualization expectations
   - `rspec_matchers_spec.rb:400` - Update regex for ANSI codes
   - `rspec_matchers_spec.rb:854` - Remove "Element:" header expectations
   - `rspec_matchers_spec.rb:893` - Remove "Element:" marker expectations
   - `rspec_matchers_spec.rb:929` - Update context line count expectations

3. Run full test suite
   - Verify all 442 tests passing (100%)
   - Verify MECE scenarios still passing
   - Verify compressed multiline bug still fixed

4. Verify orchestrator line counts:
   - `lib/canon/comparison.rb` < 150 lines
   - `lib/canon/diff_formatter.rb` < 200 lines

5. Run Rubocop and fix any violations:
   ```bash
   bundle exec rubocop -A --auto-gen-config
   ```

**Verification**:
- 442/442 tests passing (100%)
- All MECE scenarios passing
- Orchestrators under line limits
- No Rubocop violations
- Commit when complete

**Status**: **PENDING**

---

### Phase 5: Documentation

**Objective**: Update documentation to reflect new architecture

**Tasks**:
1. Update `README.adoc`:
   - Add "Architecture" section with diagrams
   - Document orchestrator pattern
   - Provide examples of new class usage
   - Update comparison examples
   - Update diff formatter examples
   - Add data flow diagrams

2. Update `REFACTORING_STATUS.md`:
   - Mark all phases complete
   - Update metrics (line counts, test coverage)
   - Document final architecture
   - Add class responsibility matrix

3. Create architecture diagrams:
   - Comparison module diagram
   - DiffFormatter module diagram
   - Data flow diagrams using AsciiDoc syntax

4. Add inline documentation:
   - Document all public methods
   - Add usage examples in class comments
   - Document options and parameters

**Verification**:
- README.adoc updated with new architecture
- REFACTORING_STATUS.md complete
- All new classes have comprehensive documentation
- Commit when complete

**Status**: **PENDING**

---

## Success Criteria

### Code Quality
- [ ] DiffFormatter under 200 lines
- [ ] Comparison under 150 lines
- [ ] All classes follow MECE principles
- [ ] No code duplication

### Test Coverage
- [x] Phase 1: 107 foundation tests (100% passing)
- [ ] Phase 2: All Comparison tests passing
- [ ] Phase 3: All DiffFormatter tests passing
- [ ] Phase 4: 442/442 tests passing (100%)
- [ ] All MECE scenarios passing
- [ ] Every class has its own spec file
- [ ] No orphaned tests in old files

### Architecture
- [x] Foundation OO classes (DiffBlock, DiffContext, DiffReport)
- [ ] Clear separation of concerns
- [ ] Format-specific logic properly separated
- [ ] Orchestrator pattern implemented
- [ ] OO classes properly utilized

### Documentation
- [ ] README.adoc updated
- [ ] Architecture documented with diagrams
- [ ] Classes documented with examples
- [ ] REFACTORING_STATUS.md complete

---

## Implementation Notes

### Key Principles

1. **One Change at a Time**: Complete each phase before moving to next
2. **Test After Each Step**: Run tests after each file creation/modification
3. **Delete Old Code**: Remove code from old files after moving to new files
4. **Delete Old Tests**: Remove tests from old files after moving to new files
5. **Preserve Functionality**: No behavior changes, only structural refactoring

### Workflow for Each Phase

1. **Create Files**: Create new class and spec files
2. **Move Code**: Extract code from monolithic classes
3. **Update Orchestrator**: Make old class delegate to new classes
4. **Migrate Specs**: Move tests from old spec to new spec files
5. **Delete Old Code**: Remove moved code and tests from old files
6. **Run Tests**: Verify all tests passing
7. **Run Rubocop**: Fix any style violations
8. **Commit**: Commit changes with semantic message

### Common Patterns

**Extraction Pattern**:
1. Create new class file
2. Move code from old class
3. Update old class to delegate to new class
4. Create spec file for new class
5. Move tests from old spec
6. Delete moved code/tests from old files
7. Run tests to verify

**Spec Migration Pattern**:
1. Identify tests related to extracted class
2. Copy tests to new spec file
3. Update test context/descriptions as needed
4. Verify new tests pass
5. Delete tests from old spec file
6. Verify old spec still passes

### Risk Mitigation

- Commit after each successful phase
- Keep old code commented out temporarily if uncertain
- Run full test suite after each file change
- Use git to track all changes
- Create backup branch before major changes

---

## Current Project State

### Files Created (Phase 1)
- ✅ `spec/canon/diff/diff_block_spec.rb` (26 tests)
- ✅ `spec/canon/diff/diff_context_spec.rb` (41 tests)
- ✅ `spec/canon/diff/diff_report_spec.rb` (40 tests)

### Files Created (Previous Work)
- ✅ `lib/canon/diff/diff_block.rb`
- ✅ `lib/canon/diff/diff_context.rb`
- ✅ `lib/canon/diff/diff_report.rb`
- ✅ `lib/canon/xml/whitespace_normalizer.rb`
- ✅ `spec/canon/compressed_multiline_bug_spec.rb`
- ✅ `spec/canon/mece_scenarios_spec.rb`
- ✅ `spec/canon/context_grouping_spec.rb`
- ✅ `MECE_TEST_ANALYSIS.md`
- ✅ `REFACTORING_STATUS.md`

### Test Results
- **Total Tests**: 442
- **Passing**: 436 (98.6%)
- **Failing**: 6 (pre-existing, to be fixed in Phase 4)
- **Phase 1 Tests**: 107 (all passing)
- **MECE Scenarios**: All passing
- **Compressed Multiline Bug**: Fixed

### Rubocop Status
- ✅ 505 offenses auto-corrected
- ✅ `.rubocop_todo.yml` generated
- Ready for Phase 2

---

## Next Steps

**Current Phase**: Phase 1 Complete ✅

**Next Action**: Commit Phase 1 changes

**Commit Message**:
```
feat(tests): add comprehensive specs for foundation OO classes

- Add diff_block_spec.rb with 26 tests
- Add diff_context_spec.rb with 41 tests
- Add diff_report_spec.rb with 40 tests
- All 107 new tests passing
- Full suite: 436/442 passing (98.6%)
- Rubocop: 505 offenses auto-corrected
```

**After Commit**: Begin Phase 2 - Extract Comparison Components

---

## Tracking

| Phase | Status | Tests | Commits |
|-------|--------|-------|---------|
| Phase 1: Foundation | ✅ COMPLETE | 107/107 | Pending |
| Phase 2: Comparison | ⏳ PENDING | - | - |
| Phase 3: DiffFormatter | ⏳ PENDING | - | - |
| Phase 4: Integration | ⏳ PENDING | - | - |
| Phase 5: Documentation | ⏳ PENDING | - | - |

**Overall Progress**: 20% (1/5 phases complete)
