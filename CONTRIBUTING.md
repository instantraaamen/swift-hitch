# Contributing

Thank you for helping out.

## Before you open a pull request

- Open an issue first for anything larger than a small fix, so the approach can be agreed on.
- Run `swift test`. The package builds for iOS as well; `xcodebuild build -scheme Hitch -destination 'generic/platform=iOS Simulator'` checks that.
- Run `swift format lint --strict -r Sources Tests Package.swift`. `swift format -i -r Sources Tests Package.swift` fixes most findings.
- Add or update tests for the behaviour you change. A fix for a measurement that once misled someone gets a test that reproduces it.
- Add a line to the Unreleased section of `CHANGELOG.md`.

## Style

- Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
- Metric names follow Apple's terms (hitch, hitch time ratio).
- Every source file starts with the license header. Copy it from an existing file.
- The recorder (`Hitch`) runs inside someone's app while it is being measured. Keep it small, keep work off the main thread, and never let a failure in it reach the app.
- The `Hitch` target depends on Apple's frameworks only. Analysis belongs in `HitchAnalysis`, which apps do not link.
- Write code, comments, commits and issues in English.

## License

By contributing, you agree that your contribution is licensed under the Apache License 2.0.

## Reviews

Pull requests from branches in this repository get an automated review comment in addition to a maintainer's review. Pull requests from forks do not, because the workflow has no access to secrets there; a maintainer reviews those by hand.
