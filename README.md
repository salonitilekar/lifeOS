# lifeOS tracks daily execution to handle a productive schedule all week round

The whole app is a single static file: [`index.html`](index.html) (vanilla JS + Supabase sync). Open it in a browser or add it to your home screen as a PWA.

## Install as a native iPhone app (.ipa via SideStore)

`index.html` is wrapped in a tiny native WKWebView app (`ios/`) so it can be sideloaded with [SideStore](https://sidestore.io). SideStore re-signs the app with your own Apple ID at install time, so the build produced here is **unsigned**.

### Option A — Build in GitHub Actions (no Xcode needed locally)

1. Push this repo to GitHub.
2. Go to the repo's **Actions** tab → **Build iOS IPA** → **Run workflow** (or just push a change to `index.html`/`ios/`).
3. When it finishes, download the **`LifeOS-ipa`** artifact and unzip it to get `LifeOS.ipa`.
4. AirDrop `LifeOS.ipa` to your iPhone (or use the SideStore "Files" import) and install it from SideStore.

### Option B — Build locally (requires full Xcode)

Needs full **Xcode** (not just Command Line Tools) and **XcodeGen** (`brew install xcodegen`):

```bash
./ios/build-ipa.sh
```

This produces `ios/LifeOS.ipa`. Install it via SideStore.

### Notes

- Bundle id: `com.saloni.lifeos` · display name: **Life OS** (change in `ios/project.yml`).
- The page is bundled offline; cross-device sync and Google Fonts still need network.
- No custom app icon yet — it ships with the default icon until one is added to `ios/`.
