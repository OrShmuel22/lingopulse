// CaretLocator.locate(in:) requires a real AXUIElement from a running app with
// accessibility permission granted to the test runner — not available in a
// headless swift test process. These tests are intentionally skipped.
//
// Manual smoke: run the app with Live Mode ON, focus any text field, and
// observe the overlay anchors near the caret (or falls back to element frame /
// mouse position). Verified in wave #19 manual smoke.
