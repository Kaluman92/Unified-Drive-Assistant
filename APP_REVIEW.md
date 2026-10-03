# App Store submission — Unified Drive Assistant 1.0

## 1. Before you press "Submit for Review" (App Store Connect)

- [ ] **Business → Agreements**: Paid Apps Agreement shows **Active** (banking + tax forms done).
      Without it, the Pro products never load and the paywall is empty.
- [ ] **App → Monetization → Subscriptions**: subscription group **Pro** with two
      auto-renewable subscriptions, IDs typed *exactly*:
      - `com.silcore.uda.pro.monthly` — 1 month
      - `com.silcore.uda.pro.yearly` — 1 year
      Each needs a price, a display name + description (localization), and a
      **review screenshot** of the Upgrade to Pro screen. Status must read
      **Ready to Submit**.
- [ ] Subscription group localization filled in (group display name).
- [ ] **Version 1.0 page → In-App Purchases and Subscriptions**: tick both
      subscriptions so they're reviewed with this build (first subscriptions
      can only be submitted alongside an app version).
- [ ] **Privacy Policy URL**: https://kaluman92.github.io/Unified-Drive-Assistant/privacy.html
- [ ] **Support URL**: https://kaluman92.github.io/Unified-Drive-Assistant/
- [ ] **App Privacy** answers match `UnifiedDriveAssistant/App/PrivacyInfo.xcprivacy` —
      all "Linked to you", "Not used for tracking", purpose "App Functionality":
      Name, Email Address, Phone Number, User ID, Photos or Videos,
      Customer Support, Purchase History, Other Diagnostic Data.
- [ ] **App Information → Content Rights**: confirm no third-party content you
      lack rights to (fault data is from public manufacturer documentation;
      trademark disclaimer is on the Home screen and support page).
- [ ] **Sign-In Information**: leave "Sign-in required" **unticked** — no account is needed.
- [ ] Paste the Review Notes below, adding a temporary AI key if you have one.
- [ ] New build uploaded from Xcode (Product → Archive → Distribute App), selected on the version page.

## 2. Review Notes (paste into App Review Information → Notes)

```
Thank you for reviewing Unified Drive Assistant.

ACCOUNT: No account is needed. Every feature works without signing in.
Sign in with Apple is optional (Settings → Account) and only links expert
requests to the person. Account deletion: Settings → Account → Delete account.

PRO SUBSCRIPTION (Settings → Upgrade to Pro):
Pro unlocks "Ask a human expert": a Silcore Engineering drives engineer
replies by email to fault tickets (drive, fault code, urgency, site, photos).
After purchasing in the sandbox, open Settings → Ask a human expert (or
"Ask a human expert" on any fault code), fill in the form and tap
"Send to an expert". This opens the iOS Mail compose sheet
addressed to Silcore.engineering@gmail.com (or the default email app if Mail
isn't set up). Restore Purchases and Manage Subscription are in Settings → Pro.

AI-GUIDED TROUBLESHOOTING (optional, off by default):
Settings → Assistant → turn on, choose a provider, enter an API key. Users
bring their own key from Anthropic, OpenAI or Google; the app has no built-in
key and we don't resell AI access. Then open any fault code and tap
"Ask for step-by-step guidance" in the AI GUIDANCE box.
[If providing one: "A temporary Anthropic test key for review: <KEY>"]

LOCATION:
"When In Use" tags a saved site visit (open a fault → Save as site visit).
"Always" is only requested if the user turns on Settings → Privacy →
Background site alerts, which uses region monitoring to notify them when they
arrive at one of their own saved sites (max 20). It's never used for tracking.

CAMERA / MOTION: Tools → Speed Measurement (optical RPM / linear speed) and
Tools → Vibration Analysis (accelerometer, with motor nameplate scanning).
All processing is on-device. Readings are indicative, as stated in the app.

Fault data is compiled from public manufacturer documentation. The app is
independent and not affiliated with Siemens, Schneider Electric, ABB or Danfoss
(disclaimer on the Home screen).
```

## 3. Later: turning on Google Sign-In

1. Google Cloud Console → Credentials → create an **iOS OAuth client** for this bundle ID.
2. In `Unified-Drive-Assistant-Info.plist`, replace `YOUR-CLIENT-ID…` in both
   `GIDClientID` and the URL scheme.
3. The Google button and the "Apple or Google" wording in Settings come back
   automatically. Update the support page FAQ (`docs/index.html`) to match.
