# UI Rules

Rules for every screen, widget and string in this application. Read this before writing UI
code. These rules outrank visual preference: when a rule conflicts with how the screen looks,
the rule wins.

## Principle

The screen reader is the primary interface, not an accessibility feature bolted onto a visual
one. TalkBack on Android and VoiceOver on iOS are how most users will operate this app, so a
widget that works by sight and not by speech is broken, not unpolished.

Visual design is explicitly deprioritised. We do not spend effort on animation, spacing rhythm,
brand colour or decorative imagery.

Legibility is not visual polish and is not deprioritised. Blindness is a spectrum and a large
share of users have residual vision, so they read the screen with large system text and high
contrast. Large text, strong contrast and plain layout stay in scope. Beauty does not.

## 1. Every interactive element carries a text label

A control that a screen reader announces as "button" with no name is unusable. Every tappable
thing needs a label that says what it does.

| Widget shape | How the label is supplied |
| --- | --- |
| Button with a `Text` child | Automatic from the child. Nothing to add |
| `IconButton`, icon-only | `tooltip:` becomes the semantics label. Always set it |
| `Chip` / `ChoiceChip` | Automatic from `label:`. Selected state is announced automatically |
| `SwitchListTile`, `CheckboxListTile` | Automatic from `title:`. State is announced automatically |
| Custom `GestureDetector` or `InkWell` | Wrap in `Semantics(button: true, label: ...)` yourself |

Prefer a standard Material widget over a custom tappable. Material widgets emit correct
semantics, roles and state for free; a `GestureDetector` emits none.

Labels are written for the ear. Write the action the user is about to take, in a full Indonesian
phrase, not a visual noun. `tooltip: 'Panduan penggunaan'` is correct. `tooltip: 'Info'` is not.

## 2. Tap targets are at least 48 by 48

| Platform | Minimum | Source |
| --- | --- | --- |
| Android | 48 x 48 dp | `androidTapTargetGuideline` in `flutter_test` |
| iOS | 44 x 44 pt | `iOSTapTargetGuideline` in `flutter_test` |

Set the floor once in `ThemeData`, not per call site. `filledButtonTheme` and
`outlinedButtonTheme` in `lib/main.dart` already set `minimumSize` to 58 and 56 respectively,
which clears both floors.

Material's default `materialTapTargetSize` is `MaterialTapTargetSize.padded`, which expands the
touch area of a small button to 48 x 48 even when its painted box is shorter. Do not rely on
that alone: a 36 dp painted button passes the touch test and still reads as a thin strip to a
low-vision user. Give every button an explicit `minimumSize` height of at least 48.

## 3. The app's own TTS and the screen reader never speak at once

This is the rule specific to this application, and the easiest one to break.

This app speaks results through its own Text-to-Speech via `NativeBridge.speak`. The screen
reader speaks the same text independently when it reaches the widget. Two voices reading one
sentence over each other produces audio the user cannot parse.

| Channel | Owns | Must not |
| --- | --- | --- |
| App TTS (`_native.speak`) | Recognition results, narration, spoken guidance | Fire while a `liveRegion` is announcing the same string |
| Screen reader | Control labels, focus moves, state changes | Re-read a result the app has already spoken |

The existing pattern in `lib/main.dart` is the correct one and new code follows it:

```dart
Future<void> _say(String text) async {
  _show(text, announce: false);
  _lastNarration = text;
  await _native.speak(text);
}
```

`announce: false` suppresses the `liveRegion` for text the app is about to speak itself. Any new
path that both displays and speaks a string sets the same flag. A path that only displays text
leaves `announce` at its default so the screen reader carries it.

Dialogs that speak on open, such as the usage guide, speak *instead of* relying on screen reader
traversal, never in addition to it.

## 4. State changes use liveRegion, not announce()

Set `liveRegion: true` on the widget whose text changed. Do not call
`SemanticsService.announce`.

As of Flutter 3.32, Android deprecated semantic announcement events at API 36, and the framework
documentation directs implementers to `liveRegion` instead. Source:
`flutter/website`, `sites/www/content/blog/whats-new-in-flutter-3-32/index.md`, accessed
9 November 2026.

Exactly one `liveRegion` is active at a time. Several at once make the screen reader queue or
interrupt itself, and the user hears fragments of each.

Long-running work gets a label. A bare `CircularProgressIndicator` emits no semantics, so the
user hears nothing and assumes the app froze. Give it a `semanticsLabel` stating what is running.

## 5. Visual glyphs stay out of spoken text

A screen reader reads punctuation and symbols literally. `'● Pemindaian aktif'` is announced with
the bullet spoken aloud. `'ONLINE · FOTO ATAS PERMINTAAN'` is announced with the interpunct
spoken, and some screen readers spell all-caps runs letter by letter.

Keep the glyph for the eye and give the ear a clean sentence:

```dart
Semantics(
  label: 'Pemindaian aktif',
  child: ExcludeSemantics(child: Text('● Pemindaian aktif')),
)
```

Never place an emoji, a bullet, an interpunct or a decorative arrow inside a string that a
screen reader will read.

## 6. Text survives a large text scale

Users of this app run system font scale well above 1.0. A layout that clips at 200 percent is a
layout that fails for its primary audience.

- Never wrap text in a fixed-height `SizedBox` or `Container`.
- Never cap or override `textScaler` in a `MediaQuery`.
- Never put `maxLines` with ellipsis overflow on a recognition result. Truncating the answer is
  worse than a long screen.
- Let content scroll. Every screen body sits in a scrollable.

A fixed height is acceptable only for something that carries no text, such as the camera preview.

## 7. Disabled controls explain themselves

A control set to `onPressed: null` is announced as dimmed or disabled with no reason. A sighted
user infers the reason from surrounding state; a screen reader user hears a dead end.

Prefer keeping the control enabled and speaking the reason on activation:

```dart
FilledButton(
  onPressed: _busy ? () => _say('Masih memproses permintaan sebelumnya.') : _primary,
  child: const Text('Mulai pindai'),
)
```

Where disabling is genuinely right, add the condition to the semantics so the user hears why the
control cannot be used.

## 8. Reading order matches logical order

Screen reader traversal follows the widget tree, so a `Column` or `ListView` reads in the order
it is written. Keep informational content in linear parents.

`Stack` children are traversed in paint order, which does not reliably match visual or logical
order. Do not put anything the user needs to hear inside a `Positioned`. Where a `Stack` is
unavoidable, assign `Semantics(sortKey: OrdinalSortKey(n))` to fix the order explicitly.

## 9. Decoration is excluded from the semantics tree

Wrap purely visual elements in `ExcludeSemantics`. This covers the camera framing crosshair,
section ornament icons, and the camera platform view itself, which emits no useful semantics and
should not be a focus stop.

`IgnorePointer` does not do this. It blocks touch and leaves semantics intact.

A platform view is excluded on both sides, not one. `AndroidView` and `UiKitView` put a real
native view into the host hierarchy, so the Flutter-side `ExcludeSemantics` and the native view's
own accessibility flag are two separate declarations. Set both: `isAccessibilityElement = false`
on the iOS `UIView`, and no `contentDescription` on the Android `View`. We have not established
which layer wins when they disagree, and setting both to exclude makes the answer stop mattering.
A one-sided exclusion is how the two platforms drift apart, with VoiceOver stopping on an element
that TalkBack skips.

An `Icon` with no `semanticLabel` emits no semantics node and needs no wrapper. An `Icon` with a
`semanticLabel` becomes a focus stop, so set that label only when the icon carries meaning that
no nearby text already carries.

## 10. Every feature is reachable two ways

Every function is operable through on-screen controls and through Voice Command. Neither path may
be the only route to a feature.

On-screen controls are usable by this audience: a screen reader user finds a control by moving
focus and activates it with a double tap, without memorising positions. Shipping a feature as
voice-only removes it from anyone in a loud room, and control-only removes it from anyone who
cannot hold the phone steady.

## 11. UI strings are Indonesian and pronounceable

Interface strings are Bahasa Indonesia, matching the Text-to-Speech voice.

Model product names and English technical words inside user-facing labels are mangled by an
Indonesian TTS voice. Name the function, not the vendor: `'Jelaskan foto'` rather than
`'Jelaskan foto dengan GPT'`, and `'Mode berpikir lebih lama'` rather than `'Thinking Qwen'`.
This also matches the project rule that models are named by role rather than product.

Mode labels follow the architecture naming in `AGENTS.md`. The user-visible status for the
on-device path is phrased around processing location, for example
`'Diproses di perangkat'`, and the online path as `'Online'`. The word `daring` is not used
anywhere in this application.

## 12. Accessibility is tested, not assumed

`flutter_test` ships machine-checkable guidelines. Add `test/a11y_test.dart` and run it with the
rest of the suite:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sahabat_netra/main.dart';

void main() {
  testWidgets('follows accessibility guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const NetraApp());
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
```

`labeledTapTargetGuideline` catches a missing label, which is rule 1, and
`androidTapTargetGuideline` catches an undersized target, which is rule 2. The guidelines cannot
check rules 3, 5, 7, 10 or 11, so those are verified by hand with TalkBack on and the screen off.

Manual check before calling a screen done: turn the screen off, enable TalkBack, and complete the
task using speech alone.

## Known gaps in the current code

Audited `lib/main.dart` at 605894b on 9 November 2026, then worked through the list. The file
has since moved to 952 lines, so the line numbers below are current rather than as-audited.

### Applied

| Rule | What changed |
| --- | --- |
| 2 | `ThemeData` gained `textButtonTheme` at 48 and `iconButtonTheme` at 48 x 48. 8 `TextButton` sites previously relied on Material's padded hit area while painting at 36 dp |
| 4 | `CircularProgressIndicator` gained a `semanticsLabel` that distinguishes recording from processing. `FamilyView`'s status text gained a `liveRegion` driven by a new `_announceMessage` flag, matching the pattern `HomeView` already used |
| 5 | Three glyph strings are now split: a clean `Semantics(label:)` for the ear, the glyph kept under `ExcludeSemantics` for the eye. Covers the mode status row, the scan badge `'● Pemindaian aktif'`, and the all-caps `'HASIL PEMBACAAN'` heading, which also gained `header: true` |
| 6 | Three font sizes raised off the floor: the mode status line 11 to 13, the result heading 12 to 13, the disclaimer 12 to 14 |
| 7 | A `_gated()` helper in `HomeView` and `FamilyView` attaches a `Semantics(hint:)` stating why a control is unavailable, across 12 call sites. The hint distinguishes microphone recording from a pending request |
| 9 | `ExcludeSemantics` now wraps the framing crosshair, which previously used `IgnorePointer` alone, and both platform views inside `CameraPreview` |
| 11 | All 13 product-name sites renamed to role and location: `'Jelaskan foto'`, `'Tanya dengan suara'`, `'Mode berpikir lebih lama'`, `'Model bahasa di perangkat'`, `'Penjelasan oleh layanan online'`, `'API key layanan online'`. Four of these were spoken strings reaching the user through Text-to-Speech, not widget labels. A second pass carried the same renames into `usageGuide` at `lib/domain.dart:3-31`, which the first pass missed because it scanned `lib/main.dart` only. Seven lines there cited a control name that no longer existed or contradicted the design: three renamed labels, the mode wording, the Settings voice entry, "Pendamping dapat mendaftarkan wajah", which told the user a companion registers faces, and a closing line naming TalkBack alone. All 17 control names the guide mentions now match a literal in `lib/main.dart` exactly |
| 12 | Added `test/a11y_test.dart`, running all four guidelines against `HomeView`, `SettingsView` and `FamilyView` |

`FamilyView` rendered `CameraPreview()` unconditionally, with no permission gate and no
`'Aktifkan kamera'` affordance, unlike `HomeView`. Permission was requested only inside
`_capture()`, after an early return on an empty name field, so a first run showed a dead 230 px
box whose only route to a camera grant was to type a nickname and press `'Ambil foto 1 dari 5'`.
Nothing announced why the box was dead. `FamilyView` now carries `_cameraAllowed`, reads it from
`status()` on load, and shows the same labeled affordance `HomeView` uses. Both native layers
refuse to start when unauthorized, at `CameraView.kt:34` and `CameraView.swift:68`, so the dead
box was identical on both platforms rather than an iOS artifact.

Two further fixes outside the numbered rules. `FamilyView`'s opening message said a *pendamping* could
register the photos, which contradicts the single-actor design in `AGENTS.md`: it now addresses
the user directly and states that the system gives camera guidance by voice. Android-specific
wording in `SettingsView` is now platform-neutral, since the project targets both platforms.

The visible mode label changed from `'OFFLINE · DIPROSES DI PERANGKAT'` to
`'DI PERANGKAT · TANPA UNGGAH FOTO'`. The eye and the ear were saying different things once the
spoken label dropped the word *offline*, and the project rules avoid framing the on-device path
as the system's defining mode.

### Still open

| Rule | Location | Gap |
| --- | --- | --- |
| 1 | `lib/main.dart` | Custom composites are unreviewed against a screen reader. Icon-only buttons are labeled via `tooltip`, which is correct |
| 6 | `lib/main.dart:514` | Camera preview is a fixed `SizedBox(height: 230)`. Acceptable, as it holds no text |
| 8 | `lib/main.dart:539` | The scan badge still sits in a `Positioned` inside a `Stack`. It now carries a label, so it is announced, but traversal order is still paint order. Fixing it properly needs `OrdinalSortKey` from `package:flutter/semantics.dart`, and ordering is the one thing here that cannot be checked without running a screen reader |
| 9 | `ios/Runner/CameraView.swift:32`, `android/.../CameraView.kt` | Both native layers and the Flutter layer now exclude the preview, so they agree. Which layer actually governs a platform view is unverified and needs a device with VoiceOver and TalkBack to settle |

The guide remains an `AlertDialog` at `lib/main.dart:408` rather than the `GuideView` screen the
architecture names. That is a structural change, not an accessibility fix, so it stayed out of
this pass.

### What we verified, and what we did not

We did not compile or run anything. No Flutter SDK is installed on this machine.

| Check | Method | Result |
| --- | --- | --- |
| Delimiter balance | Brace and paren scan with strings and comments stripped, `lib/main.dart` and both test files | 0 unclosed, 0 mismatched |
| Product names removed | `grep` for GPT, OpenAI, YOLO, Qwen3, Thinking Qwen, Pendamping, over `lib/main.dart` only | 0 hits in `lib/main.dart`, and 0 over `lib/` once the `usageGuide` pass landed. The scope is stated because an unscoped 0 reads as repo-wide |
| Font floor | `grep` for `fontSize: 1[0-2],` | 0 hits |
| Native preview exclusion | `grep` over `ios/` and `android/` | iOS sets `isAccessibilityElement = false`; Android declares nothing. The two agree with the Flutter-side exclusion |
| Which layer governs a platform view | Not run | Unknown |
| Text contrast | WCAG 2.1 relative-luminance computation over every text-weight colour pair in the theme | Lowest text pair 5.88:1, highest 13.56:1. All clear AA 4.5:1 |
| Compilation | Not run | Unknown |
| The four guidelines | Not run | Unknown |
| Screen reader behaviour | Not run | Unknown |
| Contrast over a live camera preview | Not run, and not reachable by the current suite | Unknown |
| Native view re-binding after a late permission grant | Not run | Unknown |

The contrast computation covers flat theme colours only. Every test mock returns
`cameraPermission: false`, so the `CameraPreview()` branch never renders and the fallback
`0xff172930` container renders instead. A passing `textContrastGuideline` therefore says nothing
about the text drawn over a live preview, which is the one place contrast is genuinely
unpredictable, because the backdrop is camera frames rather than a known colour. The only pair in
the theme that fails any threshold is `0xff2b454e` at 1.48:1 to 1.85:1, used once as `Border.all`
at `lib/main.dart:585`; the guideline walks the semantics tree and evaluates text, so a border is
out of its scope.

The new `FamilyView` gate swaps `ColoredBox` for `CameraPreview()` when `_cameraAllowed` flips,
which constructs a fresh platform view that re-reads the permission. That is how `HomeView`
already behaves, and the native guards run at bind time, so the reasoning holds from source. We
have not confirmed on a device that the stream actually starts after a grant arrives mid-session.

Balanced delimiters are not a type check. A wrong argument name, a missing `const`, or a
`Semantics` property that does not exist would pass every check above and fail at
`flutter analyze`. Run `flutter test` and `flutter analyze` before trusting this pass, and treat
the guideline test as the first thing likely to fail, since it has never executed.
