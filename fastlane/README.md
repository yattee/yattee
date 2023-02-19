fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

### bump_build

```sh
[bundle exec] fastlane bump_build
```

Bump build number and commit

### bump_version

```sh
[bundle exec] fastlane bump_version
```

Bump version number and commit

----


## iOS

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Push a new beta build to TestFlight

----


## tvos

### tvos beta

```sh
[bundle exec] fastlane tvos beta
```

Push a new beta build to TestFlight

----


## Mac

### mac beta

```sh
[bundle exec] fastlane mac beta
```

Push a new beta build to TestFlight

### mac build_and_notarize

```sh
[bundle exec] fastlane mac build_and_notarize
```

Build for Developer ID distribution and notarize

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
