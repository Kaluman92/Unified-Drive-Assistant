# Unified Drive Assistant — Backend (no Firebase)

> **Status: not currently used by the app.** The AI assistant switched to
> a "bring your own key" (BYOK) design — every user supplies their own
> personal API key for whichever provider they pick, entered directly in
> the app's Settings and stored in the iOS Keychain. There's no shared
> backend or developer-paid key for AI guidance anymore.
>
> This folder is kept in case you want a backend for something else later
> (e.g. silent review submission instead of the Mail-based flow — see
> README.md section 9), since the multi-provider proxy code here is a
> reasonable reference for that pattern even though it's not wired into
> the app right now.

A single Vercel serverless function that proxies AI-guidance requests to
whichever provider is specified (Claude / ChatGPT / Gemini), keeping API
keys server-side. Nothing here is Firebase — this is a plain Node.js
function deployed on Vercel's free tier.

## Why a backend like this exists (for future reference)

The app used to call Anthropic directly from the device using a key
pasted into Settings. That's fine for your own testing, but not safe to
ship — any key embedded in or entered into a distributed app can
potentially be extracted from the device. This backend fixes that: your
keys live in Vercel's environment variables, never in the app itself.

## 1. Install the Vercel CLI (one-time)

```bash
npm install -g vercel
```

## 2. Deploy

From this `Backend/` folder:

```bash
vercel login
vercel
```

Follow the prompts (link to a new project, accept the defaults). Vercel
will print a URL like:

```
https://unified-drive-assistant-backend.vercel.app
```

Your endpoint is that URL plus `/api/fault-guidance`.

## 3. Add your API keys

In the [Vercel dashboard](https://vercel.com/dashboard) → your project →
Settings → Environment Variables, add:

| Key | Where to get it |
|---|---|
| `ANTHROPIC_API_KEY` | [console.anthropic.com](https://console.anthropic.com) → Settings → API Keys |
| `OPENAI_API_KEY` | [platform.openai.com](https://platform.openai.com/api-keys) |
| `GEMINI_API_KEY` | [aistudio.google.com](https://aistudio.google.com/app/apikey) |

You only strictly need keys for the providers you actually want to offer
— if a user picks a provider whose key isn't set, that request fails
gracefully with an error, the other two still work.

After adding environment variables, redeploy so they take effect:

```bash
vercel --prod
```

## 4. Point the app at your deployment

In the Xcode project, open `AIAssistant/AIAssistantService.swift` and
replace the placeholder:

```swift
private let endpoint = URL(string: "https://YOUR-VERCEL-DEPLOYMENT.vercel.app/api/fault-guidance")!
```

with your real Vercel URL from step 2.

## 5. Test it

```bash
curl -X POST https://YOUR-VERCEL-DEPLOYMENT.vercel.app/api/fault-guidance \
  -H "Content-Type: application/json" \
  -d '{"provider":"claude","brand":"Siemens","family":"S120","code":"F30027","title":"Overcurrent","cause":"Load too high","remedy":"Check motor load"}'
```

You should get back `{"guidance": "..."}`. If you get an error mentioning
a missing API key, double check step 3 and that you redeployed after
adding the environment variables.

## Updating the AI model later

Model names change over time. Rather than edit code, set an optional
override env var in the Vercel dashboard (no code change, no redeploy of
the app needed):

- `ANTHROPIC_MODEL`
- `OPENAI_MODEL`
- `GEMINI_MODEL`

See `.env.example` for current defaults.

## Cost

You (Silcore/ProSil) pay for API usage across all your users once this
is live — each of the three providers bills based on your own account's
usage. Vercel's free tier comfortably covers the function-hosting side
for moderate usage; you'd only need a paid Vercel plan at meaningfully
higher traffic.
