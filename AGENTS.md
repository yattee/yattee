# Yattee Development Guide for AI Agents

## Deployment Targets

**iOS:** 18.0+ | **macOS:** 15.0+ | **tvOS:** 18.0+

This project targets the latest OS versions only - use newest APIs freely without availability checks.

## Build & Test Commands

**Build:** `xcodebuild -scheme Yattee -configuration Debug`  
**Test (all):** `xcodebuild test -scheme Yattee -destination 'platform=macOS'`  
**Test (single):** `xcodebuild test -scheme Yattee -destination 'platform=macOS' -only-testing:YatteeTests/TestSuiteName/testMethodName`  
**Lint:** `periphery scan` (config: `.periphery.yml`)

## Code Style

**Language:** Swift 5.0+ with strict concurrency (Swift 6 mode enabled)  
**UI:** SwiftUI with `@Observable` macro for view models (not `ObservableObject`)  
**Concurrency:** Use `actor` for services, `@MainActor` for UI-related code, `async/await` everywhere  
**Testing:** Swift Testing framework (`@Test`, `@Suite`, `#expect`) - NOT XCTest

## Imports & Organization

**Import order:** Foundation first, then SwiftUI, then @testable imports  
**File headers:** Include `//  FileName.swift`, `//  Yattee`, and brief comment describing purpose  
**MARK comments:** Use `// MARK: - Section Name` to organize code sections  
**Sendable:** All models, errors, and actors must conform to `Sendable`

## Types & Naming

**Models:** Immutable structs with `Codable, Hashable, Sendable` conformance  
**Services:** Use `actor` for thread-safe services, `final class` for `@Observable` view models  
**Enums:** Use associated values for typed errors (see `APIError.swift`)  
**Optionals:** Prefer guard-let unwrapping; use `if let` for simple cases  
**Naming:** camelCase for variables/functions, PascalCase for types, clear descriptive names

## Error Handling

**Errors:** Define typed enum errors conforming to `Error, LocalizedError, Equatable, Sendable`  
**Async throws:** All async network/IO operations should throw typed errors  
**Logging:** Use `LoggingService.shared` for all logging (see `HTTPClient.swift` for patterns)  
**User feedback:** Provide localized error descriptions via `errorDescription`

## Testing & Debugging

**Add logging/visual clues** (borders, backgrounds) when debugging issues - then ask user for results  
**If first fix doesn't work:** Add debug code before second attempt to understand the issue better

## UI Testing (Ruby/RSpec with AXe CLI)

**Run UI tests:** `./bin/ui-test --skip-build --keep-simulator`  
**Run single spec:** `SKIP_BUILD=1 KEEP_SIMULATOR=1 bundle exec rspec spec/ui/smoke/search_spec.rb`

**Accessibility labels vs identifiers:** On iOS 26+, `.accessibilityIdentifier()` doesn't work reliably on `Group`, `ScrollView`, and some container views (AXUniqueId comes back empty). Use `.accessibilityLabel()` instead, which maps to `AXLabel` and can be detected via AXe's `text_visible?()` method.

**iOS 26 TabView search:** The search field is integrated into the bottom tab bar with `Tab(role: .search)`. Typing `\n` doesn't submit - use hardware key press via `press_return` (AXe key 40).

**ScrollView children:** Video rows inside `LazyVStack`/`ScrollView` aren't exposed in the accessibility tree. Use coordinate-based tapping instead.
