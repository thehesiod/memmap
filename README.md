# memmap

memmap is a macOS app that draws per-process memory as a treemap. Related processes are grouped together, so you can see which app or process tree is using memory right now.

## Build and install

You need macOS 14 or later and the Swift toolchain from Xcode or the Command Line Tools.

```sh
scripts/bundle.sh            # builds memmap.app at the repository root
scripts/bundle.sh --install  # also copies it to ~/Applications
```

The bundle is signed ad hoc. It is not notarized, so it is meant for the machine that built it.

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

The original version, `./memmap.py`, is still in the repository. It serves the same view to a browser tab from a local server.
