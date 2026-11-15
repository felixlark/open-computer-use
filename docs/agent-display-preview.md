# Read-only live virtual display preview (macOS)

Open **Open Computer Use Preview.app**. The window shows the entire OCU virtual
display with aspect-fit scaling; resize it freely. The **OCU** menu-bar item
reopens the window after closing it. **Quit Preview** exits only the observer.
The interface is currently in Chinese.

The first launch offers **允许屏幕录制** (Allow Screen Recording) and
**打开权限设置** (Open Privacy Settings). Grant this companion Screen Recording
access, then press **重试** (Retry). macOS may require the account holder's
authentication or an app restart. It does not need Accessibility permission.

With several OCU displays, choose one using the selector. The selection follows
its serial identity when it reconnects. When the selected display disappears,
the image clears and the preview waits for that screen. It never falls back to
a physical display. If no OCU virtual display exists, start the usual OCU
workspace; preview does not create one.

This is a viewing surface: clicks, typing and scrolling are not forwarded.
No screen content is recorded to disk or sent over the network. Frames live in
a single memory slot and replace older frames. Closing the window stops capture
and clears the image; the menu remains available. OCU automation and its hidden
windows continue independently.

## Build, verify and install

The preview is an independent Swift package as well as a root workspace product.
Its tests do not launch GUI applications:

```sh
swift test --package-path apps/OCUPreview --scratch-path "$HOME/Library/Caches/open-computer-use-preview/unit-tests"
./scripts/build-ocu-preview-app.sh
```

The build script uses a Library cache for intermediates and outputs a signed
`Open Computer Use Preview.app` under that cache's `package` directory. It
discovers a Developer ID Application signing identity; set
`OPEN_COMPUTER_USE_CODESIGN_IDENTITY` to select one explicitly.
`OCU_PREVIEW_CACHE_DIR`, `OCU_PREVIEW_OUTPUT_DIR` and `OCU_PREVIEW_CONFIGURATION`
can override the cache, output directory and debug/release configuration.
Install this companion in the system Applications directory and launch it.
The build script does not replace or restart the automation provider.

## Implementation and acceptance

The observer uses CoreGraphics display inventory (OCU vendor/product `0x0CAC`,
nonzero serial, non-main, non-mirrored) and ScreenCaptureKit display streaming.
Incomplete frames are ignored; the preview's windows are excluded from capture.
Pending and active streams are generation-bound so closing during asynchronous
startup cannot leave a newly started capture running. Capture failure clears the
image and exposes Retry. Audio capture is disabled.

Installed acceptance must verify changed content on the hidden screen appears
in the preview, aspect-fit resizing, close/reopen, local-only input, and retained
hidden windows. Source tests and successful signing alone do not establish live
capture permission or installed GUI acceptance.
