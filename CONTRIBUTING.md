# Contributing

Thank you for helping out.

## Before you open a pull request

- Open an issue first for anything larger than a small fix, so the approach can be agreed on.
- Run `swift test`. The package builds for iOS as well; `xcodebuild build -scheme Hitch -destination 'generic/platform=iOS Simulator'` checks that.
- Add or update tests for the behaviour you change.
- Add a line to the Unreleased section of `CHANGELOG.md`.

## Style

- Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
- Metric names follow Apple's terms (hitch, hitch time ratio).
- Write code, comments, commits and issues in English.

## Reviews

Pull requests from branches in this repository get an automated review comment in addition to a maintainer's review. Pull requests from forks do not, because the workflow has no access to secrets there; a maintainer reviews those by hand.
