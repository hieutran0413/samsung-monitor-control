# LG reconnect, keyboard permission, and Back target

Date: 2026-10-18. Scope: repair the reported LG reconnect failure, recovery after app launch/login, repeated Accessibility prompts, and the small submenu Back target. The ongoing Control Center material investigation is separate; this change does not modify glass styling.

## Observed failure and cause

The app stored disconnected displays by UUID and searched `CGSGetDisplayList` for that UUID when reconnecting. A read-only probe on this Mac returned LG as display ID 3, vendor 7789, model 23499, inactive/offline, but `CGDisplayCreateUUIDFromDisplayID(3)` returned nil. `CGDisplayGetDisplayIDFromUUID` also returned 0. Thus the display was still known to WindowServer, while the UUID-only reconnect lookup could never find it.

Enabling that identified display restored UUID `345E8820-588D-4CEF-A9B8-1A0E5523690B`, active/online state, and the LG display. This discriminates the lookup defect from a disconnected cable or an unsupported enable symbol.

## Recovery implementation

- Record vendor, product/model and numeric serial while the display still has its UUID. Store this independently of the list of disconnected display names.
- Resolve an exact UUID first. When reconnecting an inactive display without a UUID, accept a hardware identity match only if exactly one candidate matches. Do not reuse a persisted transient display ID across sessions. Identical displays with indistinguishable serials deliberately remain unresolved rather than enabling the wrong display.
- Persist recovery intent before disabling. A successful API transaction alone does not clear that intent.
- After the transaction, wait for WindowServer to settle, then check active state and restored UUID. Clear the reconnect row only after both agree. If confirmation fails, keep recovery available and report it.
- Avoid overlapping transactions for the same UUID. Keep the existing last-active-display guard.
- At controller initialization, capture online identities and snapshot recovery entries. Retry those startup entries at 1, 4, 10 and 25 seconds. A newly requested disconnect in the same running session is not automatically undone by these retries.
- Register `SMAppService.mainApp` on macOS 13+ for launch at login. Report registration errors or approval-required state. This is login-time recovery, not a pre-login boot daemon. macOS 12 has no new automatic-login registration in this change.

Compatibility: the actual enable/disable transaction still uses runtime-resolved private SkyLight symbols. This remains OS-dependent. A physically unplugged/unpowered screen cannot be recovered by software; its recovery entry remains available. Four startup retries are bounded; later reconnect can be requested manually.

Migration on this Mac: the previously stuck LG was restored and its hardware identity captured. Existing installations with an already-disabled display and no saved identity may need one cable reconnect to establish identity; the implementation does not guess from the display name.

## Keyboard permission implementation

The old build script signed each build ad-hoc. That does not provide a stable development identity across rebuilt binaries. The old toggle also requested the Accessibility prompt every time and discarded the user's enable intent if permission was not immediately available.

The build now selects a non-revoked Apple Development signing identity when available (or accepts `CODE_SIGN_IDENTITY`). The installed app on this machine was verified to carry Apple Development authority and team `87XYSF34V4`. Ad-hoc signing remains a fallback on machines without a signing identity; persistence of TCC permissions across such builds is not promised.

Keyboard enable intent is persisted separately from event-tap readiness. The toggle can be switched off while waiting for permission. Prompt at most once per app process following an explicit enable action; startup and timed retries are silent. Retry permission/tap creation every two seconds while requested, and stop the timer after successful enable or explicit disable. This does not grant or reset TCC permissions. An old ad-hoc permission record may need to be refreshed once for the new signed app by the user in System Settings.

Computer Use inspection of System Settings showed Samsung Monitor Control's Accessibility switch already on. That UI state by itself is not proof that the currently running binary is trusted; app-process diagnostics are required. Physical F1/F2 and volume-key routing remain a separate acceptance check.

## Back interaction

### Subsequent menu-bar anchoring repair

The next screenshot showed an excessive gap between icon and first widget. The panel position had used its entire frame, including 24 pt of transparent shadow padding, as the visible content bounds. Its SwiftUI height also allocated only 28 pt for 48 pt of vertical padding. The panel now budgets the full 48 pt, positions the visible glass top 6 pt below the status-item anchor, and aligns its visible right edge with the icon's right edge where screen bounds allow. It chooses the screen containing the actual status-item anchor and reapplies the anchor after submenu size changes. The shadow margin can extend beyond content bounds without being mistaken for visible UI. `--qc` emits anchor-gap and right-edge geometry for runtime checking. This repair does not change the glass material; private Control Center material remains a separate decision.

Installed-app runtime QC: `QC_ANCHOR_GAP=6.5`, `QC_GLASS_RIGHT=1469.0`, `QC_ICON_RIGHT=1469.0` (half-point gap difference is window coordinate rounding). Computer Use successfully opened Display detail from the whole module and clicked Back to return to overview. This supersedes the earlier Computer Use timeout for this flow. The screenshot still shows the dark regular material; no visual glass parity is claimed. Build and 10 Python tests passed; Python tests do not verify geometry.

The submenu Back button previously exposed only the chevron image as its hit area. It now has a 44 × 44 pt rectangular content shape and an explicit “Quay lại” accessibility label. The visible chevron remains 14 pt. The existing action returns to overview.

## Verification

- Source build and installation: passed with the existing `onChange` deprecation warnings.
- Manual source-controller LG hardware cycle: passed. Output after disable: `disabled true`, confirmed disconnected message. Output after reconnect: `reconnected true`, confirmed connected message. Independent CoreGraphics probe returned LG active/online with its original UUID.
- Fresh-controller recovery with a persisted disconnected entry: passed on the real LG. A new controller, without calling its reconnect button method, restored the display through its startup recovery schedule. The opt-in harness checks both cleared recovery intent and active UUID resolution.
- Reproducible hardware harness: `swiftc DisplayControl.swift tests/display-reconnect/main.swift -o /tmp/monitor-reconnect-check/check`, then run with `--hardware` for manual reconnect or `--hardware --startup` for controller-startup recovery. It intentionally cycles the attached LG; it is not an ordinary unit test and is not run by Python test discovery.
- Existing Python regression suite: 10 tests passed. These cover Samsung backend behavior, not Accessibility, UI hit testing, login launch or reboot.
- Real reboot/login acceptance: not executed. No machine restart was performed. Launch-at-login status and app-process AX/event-tap diagnostics are recorded below after verification.
- Computer Use could inspect System Settings, but timed out resolving this menu-bar app. Consequently actual pointer hit testing of the enlarged Back target and physical-key behavior are not claimed as verified.

## Remaining acceptance

Final app-process diagnostic (launched as the installed `.app` via LaunchServices): `KEYS_TRUSTED=false KEYS_ENABLED=false`, `LOGIN_ITEM_STATUS=1` (`SMAppService.Status.enabled`, checked against the SDK enum). The login item initially returned `notFound`; registration now handles that state as well as `notRegistered`. This verifies registration, not a real login. The AX blocker is present despite the existing on-switch in System Settings: the current signed binary has not been trusted by TCC. No TCC database reset or automatic grant was performed. Settings now exposes an inline not-ready state and an “Mở Trợ năng…” action while the saved request remains enabled.

1. Confirm current signed app's AX trust and event-tap readiness, refresh the old permission entry only if needed, then test F1/F2 and F10–F12 with the pointer on Samsung and LG.
2. Verify a real user login/reboot restores a deliberately disconnected LG. If macOS requires approval of the login item, approve it in Login Items before claiming automatic recovery.
3. Check Back by clicking around the chevron within its 44 pt region in every submenu.
