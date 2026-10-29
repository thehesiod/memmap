# memmap

memmap is a macOS app that draws per-process memory as a treemap. Related processes are grouped together, so you can see which app or process tree is using memory right now.

## Download

Each [release](https://github.com/thehesiod/memmap/releases) has a zipped `memmap.app`. Unzip it and move it to `/Applications` or `~/Applications`.

The app is signed ad hoc and not notarized, so macOS blocks it the first time. Right-click it and choose Open, or clear the quarantine flag:

```sh
xattr -d com.apple.quarantine /Applications/memmap.app
```

## Build and install

You need macOS 14 or later and the Swift toolchain from Xcode or the Command Line Tools.

```sh
scripts/bundle.sh            # builds memmap.app at the repository root
scripts/bundle.sh --install  # also copies it to ~/Applications
```

The bundle is signed ad hoc and not notarized.

## Using it

Hover a box to see its details, click to pin it, and double-click to zoom into its group. The breadcrumb above the map zooms back out. Hatching marks the compressed part of a process.

There are three modes:

| Mode | Box size |
|-|-|
| RSS | Resident memory, plus compressed memory if "Include compressed" is checked. |
| Shared split | Private memory plus an even share of each shared region, so shared libraries are not counted once per process. |
| Footprint | The kernel's physical footprint, which already includes compressed memory. |

Shared split reads memory regions only for processes you own. Other processes, such as root-owned ones, show RSS and get a dashed outline.

Processes can be grouped by process tree, by app, or by Claude Code session.

## Python version

The original version is still in the repository. It serves the same view to a browser tab from a local server on `127.0.0.1:8765`, using only the Python standard library:

```sh
./memmap.py
```

## Releasing

Pushing a tag that starts with `v` runs the release workflow. It tests, builds `memmap.app`, and attaches `memmap-<tag>.zip` to a new GitHub release:

```sh
git tag -s v0.1.0 -m "memmap 0.1.0"
git push origin v0.1.0
```

## License

MIT. See [LICENSE](LICENSE).
