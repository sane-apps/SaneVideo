fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Mac

### mac verify

```sh
[bundle exec] fastlane mac verify
```

Verify build and run tests

### mac verify_full

```sh
[bundle exec] fastlane mac verify_full
```

Run full test suite including UI tests (requires graphical session)

### mac doctor

```sh
[bundle exec] fastlane mac doctor
```

Run project health check (modularity audit)

### mac lint

```sh
[bundle exec] fastlane mac lint
```

Run SwiftLint audit

### mac quality

```sh
[bundle exec] fastlane mac quality
```

Generate Ruby quality report

### mac coverage

```sh
[bundle exec] fastlane mac coverage
```

Generate code coverage report

### mac changelog

```sh
[bundle exec] fastlane mac changelog
```

Generate release notes from git commits

### mac screenshots

```sh
[bundle exec] fastlane mac screenshots
```

Automate macOS app screenshots

### mac release

```sh
[bundle exec] fastlane mac release
```

Perform a full production release preparation

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
