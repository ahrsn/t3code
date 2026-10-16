# T3 Native

A personal SwiftUI iOS client for T3 Code, maintained in the `ahrsn/t3code` fork. Requires iOS 26 or later and an upstream server using orchestration protocol 2. The app uses T3’s wordmark, upstream DM Sans and theme palettes, native Liquid Glass controls, adjustable conversation typography, and a native WebSocket client. It has no React Native, Expo, JavaScript engine, or web view dependency.

This is an early client. Direct server pairing, project and conversation navigation, streaming, sending messages and attachments, interrupting runs, request responses, and pageable history are implemented. T3 Connect account discovery and relay login, push notifications, terminal interaction, and full desktop review tools still need implementation. Sent images and files open in the native Quick Look viewer. Downloads use a fresh server-signed asset URL, stay on the selected server, and stop at the 50 MB preview limit. Preview files are temporary and released after closing. Existing server-side provider credentials stay on the server.

The composer's paperclip offers native Photos and Files pickers. Photos supplies compatible representations, including HEIC converted to JPEG. Picked files are copied into protected, backup-excluded storage for that host and conversation, and survive app relaunch. PNG, JPEG, GIF, and WebP files upload as images, capped at 10 MiB each and 80 MiB combined. Other files use the server's advertised file limit, capped at 50 MiB. Uploads require the server's attachment capability. Cancelling or failing a send retains local drafts; confirmed sends remove their copies. Pending upload IDs are retained for retry, and unused server uploads expire through the server's normal cleanup. An unchanged attachment-send retry reuses its command and message IDs. Upload URLs and bearer credentials are never saved with drafts. Leaving the conversation cancels unfinished photo loading and keeps copies already imported. Camera capture, attachment preview inside the composer, and attachments in question responses remain incomplete.

The composer model control selects a provider, model, and server-advertised options such as reasoning effort or fast mode. These choices persist with the local draft and are sent atomically with the next message. Changing them does not alter an active run. The picker respects project provider overrides, authentication, hidden models, and provider update requirements.

Completed messages render native Markdown headings, nested lists, quotes, aligned tables, links, and fenced code with copying. A background actor shares completed message parses within limits of 128 messages and 512 KB of source text. Loaded history keeps its prepared presentations with the open conversation. Streaming text bypasses Markdown parsing; full formatting appears when the message finishes.

## Build

Use Xcode 26 or later and XcodeGen. The checked-in Xcode project can be opened directly. Regenerate it after changing `project.yml`.

```sh
brew install xcodegen
cd apps/ios-native
xcrun simctl list devices available
bash Scripts/build.sh build SIMULATOR_UDID
bash Scripts/build.sh test SIMULATOR_UDID
bash Scripts/build.sh ui-test SIMULATOR_UDID
```

Select an idle existing iOS 26+ simulator. UI tests use explicitly marked preview data. The UI-test script adds two generated images to the selected Simulator library for the native Photos picker flow. The optional pairing UI test requires `TEST_RUNNER_T3_NATIVE_PAIRING_URL` for a scoped test environment; its results can contain that credential and must remain private. Do not pass a production credential to public CI.

To install on your phone, select your own development team in Xcode, choose the phone and run. The personal fork defaults to team `728RATZMAR` and bundle identifier `com.ahrsn.t3native`. Other developers must use their own team and bundle ID. `bash Scripts/build.sh archive` creates a Release archive. Xcode Organizer can distribute it to TestFlight once the matching app record exists in the same personal App Store Connect account.

## Connect

Create a pairing link in the desktop app's Connections settings. Paste that link into T3 Native's Connections sheet. For a Tailscale host, keep Tailscale connected on both devices and use the HTTPS tailnet address. LAN IP and `.local` links use the app's local networking exception. A pairing link needs `orchestration:operate` to send messages or answer requests. Read-only links can browse.

The app exchanges the pairing token for a scoped access token, stores that token in a device-only Keychain item, and obtains a fresh WebSocket ticket on every connection. Saved host metadata contains no credential. Expired credentials require pairing again. Removing a server removes its local credential; revoke its session on the server to remove server-side access too.

Loading an earlier page prepares its completed Markdown before insertion, then restores the visible message and its offset. Failed history requests keep the current conversation open and offer a local retry.

The app disconnects in the background and reloads authoritative snapshots on foreground reconnect. Disconnecting cancels an active attachment transfer and retains its draft, while a dispatched message remains subject to normal acknowledgement handling. A timed-out send is never retried automatically because it may already have reached the server.

Removing a server clears its credential, saved text/model drafts, and owned attachment copies. Other servers' data stays intact. Cleanup failure keeps the server saved for retry. Older attachment manifests without server ownership are migrated when their original conversation opens; if still unassigned during removal, their files are retained and a notice is shown. Cleanup unlinks only owned regular files and empty directories.

## Upstream maintenance

`origin` is the personal fork and `upstream` is `pingdotgg/t3code`. Native code is isolated in this directory so the original mobile client and server remain available. The native development branch is `feat/native-ios-client`.

```sh
git fetch upstream
python3 apps/ios-native/Scripts/check-contracts.py --ref upstream/main
```

The contract check reports changes to the selected contract files and named schemas without changing the checkout. Review the affected definitions, port any needed behavior, run the native tests against the matching server, and only then use `--record` to update its baseline. It is a drift alarm, not proof of full compatibility or a schema generator. New TypeScript features require a Swift implementation.

The native GitHub workflow builds and tests the fork and checks current upstream contracts. Scheduled workflows run only when the workflow exists on the repository's default branch. Automated TestFlight upload still requires a personal App Store Connect app record and distribution credentials. Neither an upstream fetch nor a successful native build means a TestFlight build was delivered.

The icon and wordmark are reused from the upstream repository. This personal fork is not an official T3 Tools release.

DM Sans is distributed under the SIL Open Font License in `App/Fonts/OFL.txt`. The scale follows `apps/mobile/src/lib/typography.ts`; colors come from `packages/shared/src/themePalettes.ts`, and the native wordmark uses the exact upstream SVG geometry.

Regenerate bundled theme colors with `python3 apps/ios-native/Scripts/sync-theme-colors.py`. Its `--check` mode verifies the bundle against the checkout. Verify both appearances after any color change. The overnight implementation reviewed additive upstream changes through `4e85a93b20`; command-output subscriptions remain a separate unimplemented capability.
