# Info.plist keys this build needs

Xcode's default new-project Info.plist doesn't have these — add them in
your target's **Info** tab (or as raw XML in Info.plist) before running,
or the app will crash the first time it touches the camera/photo library:

| Key | Suggested value |
|---|---|
| `NSCameraUsageDescription` | "Used to scan motor nameplates and measure rotational/linear speed of equipment on site." |
| `NSPhotoLibraryUsageDescription` | "Used as a fallback if the camera isn't available when scanning a nameplate." |
| `NSLocationWhenInUseUsageDescription` | "Used to tag saved fault lookups with a site location, and to check whether you've logged faults near your current spot before. Never used to track your movement." |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | "If you turn on Background Site Alerts in Settings, used to notify you when you enter the area of a site you've saved fault history for — even with the app closed. Not used to track your movement otherwise." |

**This one is only needed if you use the "Background Site Alerts" toggle
in Settings** (`Location/SiteGeofenceManager.swift`) — everything else in
the app works fine with only `NSLocationWhenInUseUsageDescription`.
Ironically, this IS the "Always and When In Use" key that caused so much
confusion earlier when it was added by mistake instead of the plain
"When In Use" one — now it's genuinely needed, in addition to (not
instead of) the When In Use key above. Both must be present together;
iOS's two-step upgrade flow requires it.

**Be careful with the location key specifically** — Xcode's autocomplete
shows several very similar-looking options ("Privacy - Location Always
and When In Use Usage Description" is a different key from "Privacy -
Location When In Use Usage Description"). This app only calls
`requestWhenInUseAuthorization()`, so it needs the plain "When In Use"
one, not the "Always and When In Use" one — picking the wrong one causes
no error or crash, it just silently never shows the permission dialog,
which took a while to track down once already.

Not needed: raw accelerometer access (used by Vibration Analysis) does
**not** require an Info.plist privacy key on iOS — only step-counting /
activity APIs do, which this app doesn't use.

## Google Sign-In additions (not needed right now)

**Not currently required** — Sign in with Apple/Google is parked until
you're ready to go online (see README.md section 26); the app currently
uses a local email/password stub that needs none of this. Keep this here
for when you bring real sign-in back:

Two more entries, needed once you've created your OAuth client ID (see
README.md "Setting up Sign in with Apple and Google"):

1. Add a new row: key `GIDClientID` (String), value: your OAuth client ID
   from Google Cloud Console (looks like
   `123456789-abc...apps.googleusercontent.com`).
2. Add a URL Type: in the Info tab, find/add "URL Types", add a new entry
   with URL Schemes set to your client ID **reversed** — Google Cloud
   Console shows this exact reversed value on the same credentials page as
   your client ID (looks like `com.googleusercontent.apps.123456789-abc...`).

Both of these come directly from the credentials page Google Cloud
Console shows you after creating the OAuth client ID — copy them from
there rather than typing by hand.
