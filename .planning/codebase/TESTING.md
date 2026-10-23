---
last_mapped_commit: 64405acfa13ec78cf102cb081212fd931bb8a4e4
last_mapped_at: 2026-10-11
---
# Testing Patterns

**Analysis Date:** 2026-10-11

## Test Framework

### Runner

**Dart (Flutter):**
- Framework: `flutter_test` (built into Flutter SDK)
- Config: `pubspec.yaml` dev_dependencies section
- Version: Latest compatible with Flutter SDK 3.11+

**Python:**
- No test framework detected in codebase
- Backend lacks automated tests currently
- Tests would need pytest or unittest if added

### Run Commands

**Dart:**

```bash
flutter test                          # Run all tests
flutter test test/ppg_delivery_note/  # Run tests in specific directory
flutter test --watch                  # Watch mode for continuous testing
flutter test --coverage               # Generate coverage report
```

**Python:**
- Not applicable (no tests found)

### Assertion Library

**Dart:**
- Built into `flutter_test` as `expect()` function
- Matcher library provides rich matchers: `hasLength()`, `containsAll()`, `anyOf()`, `greaterThan()`, etc.
- No custom assertion builders observed

## Test File Organization

### Location & Naming

**Dart:**
- Tests co-located with source in mirror structure
- Pattern: `test/` directory mirrors `lib/` directory layout
- Files: `{module}_test.dart`

Example structure:

```
frontend/lib/features/ppg_delivery_note/
  domain/models.dart
  parser/ppg_template_parser.dart
  ocr/total_qty_field_reader.dart

frontend/test/ppg_delivery_note/
  can_article_reader_test.dart        # Tests domain/can_article_reader
  ppg_parser_test.dart                # Tests parser/ppg_template_parser
  total_qty_field_reader_test.dart    # Tests ocr/total_qty_field_reader
```

**Python:**
- Not applicable (no tests found)

### Directory Structure

```
frontend/test/
├── ppg_delivery_note/              # Main feature test suite
│   ├── can_article_reader_test.dart
│   ├── dn_5319358250_parser_test.dart
│   ├── image_preprocessing_test.dart
│   ├── ppg_parser_test.dart
│   ├── ppg_receiving_workflow_test.dart
│   ├── ppg_session_resume_test.dart
│   ├── total_qty_field_reader_test.dart
│   └── dn_5319364114_synthetic_ocr.json    # Test fixtures
├── review_provenance_helpers_test.dart
└── [test data files as .json]
```

## Test Structure

### Suite Organization

Dart tests use `void main()` with test cases defined directly (no `group()` nesting in current codebase):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:label_reader/features/ppg_delivery_note/domain/models.dart';

void main() {
  late Map<String, dynamic> expected;
  late Map<String, dynamic> synthetic;
  late PpgTemplateParser parser;

  setUpAll(() {
    // Expensive setup: load test data files once for all tests
    expected = jsonDecode(
      File('test/ppg_delivery_note/dn_5319364114.expected.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    synthetic = jsonDecode(
      File('test/ppg_delivery_note/dn_5319364114_synthetic_ocr.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  setUp(() {
    // Per-test setup: fresh instances
    parser = PpgTemplateParser();
    consolidator = PpgConsolidator();
  });

  test('T01 parse complete sample product evidence', () {
    // Arrange
    final pages = parseAll();
    
    // Act
    final doc = consolidator.consolidate(sessionId: 'sess', pages: pages);
    
    // Assert
    expect(pages.first.pieceCount, expected['header_piece_check']);
    expect(doc.lines.length, 7);
  });
}
```

### Setup & Teardown

**setUpAll():**
- Called once before all tests in the suite
- Used for expensive one-time operations: loading test data files, creating database connections
- Example from `ppg_parser_test.dart`:
  ```dart
  setUpAll(() {
    expected = jsonDecode(
      File('test/ppg_delivery_note/dn_5319364114.expected.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
  });
  ```

**setUp():**
- Called before each individual test
- Used for per-test initialization: creating fresh parser instances, resetting mocks
- Example:
  ```dart
  setUp(() {
    parser = PpgTemplateParser();
    consolidator = PpgConsolidator();
  });
  ```

**tearDown() / tearDownAll():**
- Not observed in current tests
- Not necessary for stateless parsers and in-memory mocks

### Test Naming

Tests use descriptive names with optional prefixes:

- Numbered prefix: `T01`, `T02` (optional, used for logical grouping)
- Descriptive: Matches the behavior being tested
- Examples:
  - `T01 parse complete sample product evidence`
  - `T02 page 2 has two qty rows and set headers without quantities`
  - `field crop starts after colour code and above batch quantities`
  - `reopening a page keeps a saved 445386 Total Qty correction resolved`
  - `distractors, low confidence and image-edge clipping cannot form a candidate`

### Assertion Patterns

**Basic Equality:**

```dart
expect(doc.lines.length, 7);
expect(result, 'expected_value');
```

**Null Checks:**

```dart
expect(crop, isNotNull);
expect(value, isNull);
```

**Collection Matchers:**

```dart
expect(qty, hasLength(2));
expect(qty.map((o) => o.documentQuantity), everyElement(15));
expect(qty.map((o) => o.articleNumber), containsAll(['445235', '445182']));
expect(read([line(text)]), isEmpty);
```

**Numeric Matchers:**

```dart
expect(crop.left, greaterThan(713));
expect(crop.left, lessThanOrEqualTo(720));
expect(crop.bottom, lessThan(1390));
```

**Disjunctive Matchers:**

```dart
expect(ctx.articleNumber, anyOf('179061', '446789'));
```

**Map/Object Matchers:**

```dart
expect(
  {
    for (final occurrence in page2.occurrences)
      occurrence.articleNumber: occurrence.productContext,
  },
  {
    '179061': "S'COVER 456 SET GREY",
    '445235': 'S COVER 456 BAS GREY',
  },
);
```

## Mocking

### Mock Pattern

Tests use **lightweight mock implementations** by extending real classes and overriding methods:

**Memory Repository Mock:**

```dart
class _MemoryRepository extends PpgRepository {
  _MemoryRepository(this.savedSession, this.page, this.savedLines);
  
  ScanSession savedSession;
  final PageCapture page;
  List<DocumentLine> savedLines;
  final adjustments = <PhysicalAdjustment>[];
  SubmittedForm? savedSubmission;
  bool failNextWrite = false;
  Completer<void>? nextWriteGate;

  @override
  Future<ScanSession?> getSession(String id) async => savedSession;

  @override
  Future<List<DocumentLine>> getLines(String sessionId) async =>
      savedLines.map((line) => line.copy()).toList();

  @override
  Future<void> savePhysicalCount({...}) async {
    final gate = nextWriteGate;
    nextWriteGate = null;
    if (gate != null) await gate.future;
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('disk full');
    }
    await saveLine(line);
    savedSession = session;
    adjustments.add(adjustment);
  }
}
```

From `ppg_receiving_workflow_test.dart`.

**Parser Mock:**

```dart
class _AmbiguousPageParser extends PpgTemplateParser {
  _AmbiguousPageParser(this.rawPage);

  final ParsedPageResult rawPage;

  @override
  ParsedPageResult parse({
    required OcrObservation observation,
    required int printedPageHint,
  }) => rawPage;
}
```

### Mock Capabilities

Mocks support:
- **State mutation:** `failNextWrite = true` triggers error on next write
- **Async gates:** `Completer<void>? nextWriteGate` allows tests to pause/resume async operations
- **Inspection:** `final adjustments = <PhysicalAdjustment>[]` collects calls for assertion
- **Copying:** `.copy()` method on models returns independent instances for state isolation

### What to Mock

**Mock These:**
- Repository/persistence layer (PpgRepository)
- Expensive I/O (file system, network) via mocked adapters
- External dependencies when testing coordination logic
- Service implementations when testing controllers (e.g., PpgSessionController)

**DON'T Mock These:**
- Domain models (ScanSession, PageCapture, etc.) — use them directly
- Parsers and validators — test them directly with real data
- Enums and constants
- Utility functions

## Fixtures and Test Data

### Test Data Pattern

**File-Based Fixtures:**
Test data loaded from JSON files in `test/ppg_delivery_note/`:
- `dn_5319364114.expected.json` — Expected parsing result
- `dn_5319364114_synthetic_ocr.json` — Synthetic OCR output (word-level elements)

Loaded in `setUpAll()`:

```dart
setUpAll(() {
  expected = jsonDecode(
    File('test/ppg_delivery_note/dn_5319364114.expected.json')
        .readAsStringSync(),
  ) as Map<String, dynamic>;
  synthetic = jsonDecode(
    File('test/ppg_delivery_note/dn_5319364114_synthetic_ocr.json')
        .readAsStringSync(),
  ) as Map<String, dynamic>;
});
```

**Builder Fixtures:**
Helper functions create test objects inline:

```dart
OcrElement line(
  String text, {
  double x = 20,
  double y = 20,
  double right = 260,
  double confidence = .95,
}) => OcrElement(
  text: text,
  left: x,
  top: y,
  right: right,
  bottom: y + 20,
  confidence: confidence,
);

OcrObservation page({Map<String, int> fieldReads = const {}}) =>
    OcrObservation(
      ocrRunId: 'ocr',
      pageCaptureId: 'page3',
      captureRevision: 1,
      engineName: 'test',
      engineVersion: '1',
      imageWidth: 1224,
      imageHeight: 1584,
      elements: [
        word('Delivery Note', 600, 20, 790),
        word('5319364114', 800, 20, 970),
        word('3 / 4', 1040, 20, 1110),
      ],
      fieldQuantityReads: fieldReads,
      createdAt: DateTime.utc(2026),
    );
```

From `total_qty_field_reader_test.dart`.

**Real Model Instances:**
Domain models created with real values for integration tests:

```dart
final now = DateTime.utc(2026, 9, 25);
final session = ScanSession(
  id: 'session',
  status: ScanSessionStatus.reviewing,
  deliveryNoteNumber: '5319364114',
  declaredPageCount: 4,
  formRevision: 3,
  createdAt: now,
  updatedAt: now,
);
final page = PageCapture(
  pageCaptureId: 'page3',
  sessionId: session.id,
  printedPage: 3,
  captureRevision: 1,
  isActive: true,
  createdAt: now,
  ocrStatus: PageOcrStatus.succeeded,
);
```

## Coverage

### Requirements

- **Enforcement:** Not enforced by build or CI
- **Target:** No formal target (pragmatic coverage)
- **Focus:** Core parsing, validation, OCR integration logic

### What's Tested

**Well-Covered (Unit Tests):**
- `domain/models.dart` — Model creation and computed properties
- `domain/validation.dart` — Input validation functions
- `domain/can_article_reader.dart` — Article number recognition
- `ocr/total_qty_field_reader.dart` — Field crop and quantity extraction
- `parser/ppg_template_parser.dart` — Document parsing and interpretation

**Covered (Integration Tests):**
- `services/ppg_session_controller.dart` — Full workflow coordination
- Persistence layer via mocked repository
- Session lifecycle (create → scan → review → submit)

**Not Covered:**
- Widget tests (UI layer)
- E2E tests
- Network/API calls (mocked implicitly via dependency injection)
- Android/iOS platform-specific code
- Error handling edge cases for production deployment

## Test Types

### Unit Tests

**Scope:** Single class/function in isolation

**Examples:**
- `can_article_reader_test.dart` — Tests `CanArticleReader.candidates()` with various OCR patterns
- `total_qty_field_reader_test.dart` — Tests field crop logic and quantity parsing
- `ppg_parser_test.dart` — Tests `PpgTemplateParser.parse()` with real delivery note data

**Pattern:**

```dart
test('all supplied article strings are preserved exactly with anchor variations', () {
  for (final article in articles) {
    for (final anchor in ['Article no.', 'ARTICLE NO : ', ...]) {
      expect(read([line('$anchor$article')]), {article});
    }
  }
});
```

### Integration / Workflow Tests

**Scope:** Multiple components coordinating to complete a workflow

**Example:** `ppg_receiving_workflow_test.dart`

Tests the full PPG delivery note receiving workflow:
1. User scans pages and captures images
2. OCR extracts data
3. Parser identifies delivery note number and quantities
4. User reviews and corrects data
5. User enters physical counts
6. Session is submitted

Uses mocked repository (`_MemoryRepository`) to simulate persistence without actual SQLite.

**Pattern:**

```dart
testWidgets('scan → review → count → submit workflow', (WidgetTester tester) async {
  final app = MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => controller),
      Provider(create: (_) => repository),
    ],
    child: const MaterialApp(home: PpgHubScreen()),
  );
  await tester.pumpWidget(app);

  // Verify initial state
  expect(find.byType(PpgSessionScreen), findsNothing);

  // Trigger session creation
  await tester.tap(find.byIcon(Icons.add));
  await tester.pumpAndSettle();

  // Verify screen transitions
  expect(find.byType(PpgCaptureScreen), findsOneWidget);
  
  // ... more interactions ...
});
```

### Widget Tests

**Current Status:** None found in codebase

**When to Add:** As UI coverage expands, widget tests should:
- Test screen navigation and state transitions
- Verify form validation displays errors
- Test user interactions (tap, scroll, type)
- Mock PpgSessionController via Provider

**Template:**

```dart
testWidgets('physical quantity control shows error for invalid input', 
    (WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PpgCountSheet(
          controller: mockController,
          occurrenceId: 'id',
          onScan: () {},
        ),
      ),
    ),
  );
  
  await tester.enterText(find.byType(TextField), 'invalid');
  await tester.tap(find.text('Confirm'));
  await tester.pumpAndSettle();
  
  expect(find.text('Enter a whole number'), findsOneWidget);
});
```

### E2E Tests

**Current Status:** None found

**When to Add:** 
- After app goes to production
- For critical user workflows (scan → submit)
- Use `integration_test` package or Firebase Test Lab

## Test Execution

### Single Test

```bash
flutter test test/ppg_delivery_note/ppg_parser_test.dart
```

### Watch Mode

```bash
flutter test --watch
```

### Coverage Report

```bash
flutter test --coverage
open coverage/lcov.html  # macOS
```

### CI Integration

- Not configured in this codebase
- Would run via GitHub Actions or similar

---

*Testing analysis: 2026-10-11*
