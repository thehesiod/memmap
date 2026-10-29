# Contributing

## Layout

| Path | Contents |
|-|-|
| `Sources/MemmapCore` | Process collection, memory accounting, grouping, treemap layout, and navigation. It has no UI code, so it can be unit-tested. |
| `Sources/Memmap` | The SwiftUI app. |
| `Tests/MemmapCoreTests` | Tests for `MemmapCore`. |
| `scripts/bundle.sh` | Builds and signs `memmap.app`. |
| `collector.py`, `memmap.py`, `index.html` | The original Python and browser version. |
| `docs/` | The app's design and implementation plan. |

## Build and test

```sh
swift build
swift test
```

Test fixtures use placeholder names such as `Example.app` and `/Users/example/project`. Never put real usernames, paths, or process data in the repository.

## Pull requests

`main` accepts changes only through pull requests:

- The `python` and `swift` CI checks must pass.
- Every commit must be signed, and the signing key must be registered on your GitHub account.
- Pull requests are squash-merged, so the PR title and description become the commit on `main`.

## Releasing

Pushing a tag that starts with `v` runs the release workflow. It runs the tests, builds `memmap.app`, and attaches `memmap-<tag>.zip` to a new GitHub release with generated notes. Tag a commit that is already on `main`:

```sh
git switch main
git pull --ff-only
git tag -s v0.1.0 -m "memmap 0.1.0"
git push origin v0.1.0
```
