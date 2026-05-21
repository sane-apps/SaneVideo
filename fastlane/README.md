fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

SaneVideo intentionally does not bundle fastlane in `Gemfile` because current
fastlane releases still constrain `jwt` below the patched 3.x line for
GHSA-c32j-vqhx-rx3x. Use the system/Homebrew fastlane only when you explicitly
need these legacy lanes; the canonical SaneApps release path is
`./scripts/SaneMaster.rb`.

# Available Actions

## Mac

### mac verify

```sh
fastlane mac verify
```

Verify build and run tests

### mac verify_full

```sh
fastlane mac verify_full
```

Run full test suite including UI tests (requires graphical session)

### mac doctor

```sh
fastlane mac doctor
```

Run project health check (modularity audit)

### mac lint

```sh
fastlane mac lint
```

Run SwiftLint audit

### mac quality

```sh
fastlane mac quality
```

Generate Ruby quality report

### mac coverage

```sh
fastlane mac coverage
```

Generate code coverage report

### mac changelog

```sh
fastlane mac changelog
```

Generate release notes from git commits

### mac screenshots

```sh
fastlane mac screenshots
```

Automate macOS app screenshots

### mac release

```sh
fastlane mac release
```

Perform a full production release preparation

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
