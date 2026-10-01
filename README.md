# Folder Size

A small TreeSize-style Mac app that shows how much disk space every folder uses, as a sortable tree and as a treemap.

- Scans any folder or drive: the startup disk, external USB/Thunderbolt drives, SD cards, disk images and network shares. The drive list updates when drives are connected or ejected.
- Includes hidden files and folders (shown in grey in the tree).
- Sizes are space actually used on disk. Hard-linked files are counted once, and other drives mounted inside a folder are not counted twice, so totals match `du`.
- Runs on macOS 10.13 High Sierra and later: Intel Macs from 10.13, Apple Silicon Macs from macOS 11.

## Build

Needs only the Xcode Command Line Tools (`xcode-select --install`), not full Xcode.

```bash
./build.sh
```

The app is written to `build/Folder Size.app`. Drag it to `/Applications` if you want to keep it.

## Using it

- Choose a drive in the picker and click **Scan**, or click **Choose Folder…** to scan any folder.
- Selecting a folder in the tree shows it in the map. Selecting a file highlights it.
- In the map: click to select, double-click a folder to zoom in, and use **↑ Up** (⌘↑) to go back out. Hover to see the full path and size at the bottom right.
- Right-click an item in the tree or the map for **Open**, **Show in Finder**, **Copy Path**, **Rescan This Folder** and **Move to Trash…**

## Protected folders (Full Disk Access)

Since macOS 10.14, some folders (Mail, Messages, Safari, other apps' containers) can only be read after you allow it. If a scan could not read some folders, the status bar says so and shows a **Grant Full Disk Access…** button:

1. Open System Settings → Privacy & Security → Full Disk Access.
2. Turn on Folder Size, or add it with the **+** button.
3. Quit and reopen the app, then scan again.

Folders that still can't be read are marked "(no access)" in the tree. The app is ad-hoc signed, so after you rebuild it, macOS may ask for this permission again.

## Running it on another Mac

The app is not signed with an Apple Developer ID. When you copy it to another Mac through a download, AirDrop or a USB stick, macOS will refuse to open it the first time:

- **macOS 10.13–14:** Right-click the app, choose **Open**, then click **Open** again.
- **macOS 15 and later:** Try to open it once, then go to System Settings → Privacy & Security and click **Open Anyway**.

## Code layout

| File | What it does |
| --- | --- |
| `Sources/Scanner.m` | Walks the folder tree on a background thread with `fts(3)` and builds the size tree |
| `Sources/FileNode.m` | One file or folder: size, file count, children sorted largest first |
| `Sources/TreemapView.m` | Squarified treemap drawing, hit testing and mouse handling |
| `Sources/MainWindowController.m` | The window: drive picker, tree, map, status bar and actions |
| `Sources/PercentBarView.m` | The bar in the "% of Parent" column |
| `Sources/AppDelegate.m` | App startup and the menu bar |
| `Tools/make_icon.m` | Draws the app icon at build time |

It is written in Objective-C instead of Swift because Swift apps need extra runtime libraries to run on 10.13, and the current toolchain can no longer build them.
