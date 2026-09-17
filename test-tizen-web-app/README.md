# Tizen API Probe — packaged web app

Wraps `../tizen_api_test_microsite.html` as a signed Tizen web app so the Samsung
Product APIs can actually be reached. The same HTML served as a plain microsite
URL gets **none** of these APIs — see [Why packaging is required](#why-packaging-is-required).

Self-contained: `index.html` and `icon.png` are committed, so you can copy this
folder to a build machine as-is.

## What you can test without Samsung approval

Privilege levels are from the Samsung API references, not assumed:

| API | Privilege level | Privilege URI | Reachable with a self-issued dev cert? |
|---|---|---|---|
| **AdInfo** — `getTIFA()`, `isLATEnabled()` | Public | `http://developer.samsung.com/privilege/adinfo` | **Yes** |
| **ProductInfo** — `getDuid()`, `getModel()`, … | Public | `http://developer.samsung.com/privilege/productinfo` | **Yes** |
| **SSO** — `getLoginStatus()`, `getLoginUid()`, … | **Partner** | `http://developer.samsung.com/privilege/sso.partner` | No — needs a Partner cert |
| **SSO** — `getSsoState()` | **Platform** | `http://developer.samsung.com/privilege/sso.platform` | No — see below |

So step 1 gets you real TIFA and device values today. SSO stays blocked until the
certificate is upgraded, and the probe records that denial as evidence you can use
to justify the partner request.

`getSsoState()` is the method the get-coupon container actually uses, and it sits a
level **above** partner: `sso.platform`. Platform privileges are for Samsung-internal
and preloaded apps, so a Partner certificate is not expected to unlock it either —
which is exactly why the postMessage bridge below matters. It returns
`{ bLogin, id, authToken, uid, guid }` (some firmware returns the equivalent
`"login_id?auth_token?uid?guid"` string instead; the probe decodes both and reports
which shape it got).

> `authToken` is a bearer credential. The probe masks it everywhere — on screen and
> in the JSON dump — showing only the first/last 4 characters and a length. Keep it
> that way if you edit the page; the dump is meant to be photographed.

## Prerequisites

- **Tizen Studio** with the TV Extension — <https://developer.samsung.com/smarttv/develop/tools/tizen-studio.html>
- Add its tools to `PATH`:
  ```bash
  export PATH="$PATH:<tizen-studio>/tools/ide/bin:<tizen-studio>/tools"
  ```
- A Samsung TV on the same network, in Developer Mode
- Python (optional — only for regenerating `index.html` / `icon.png`)

## Setup

### 1. Certificate

Tizen Studio → **Tools → Certificate Manager → + → Samsung → TV**, and create an
Author certificate plus a **Public** distributor certificate. You'll need the TV's
**DUID** from *Menu → Support → About This TV*; the distributor certificate is
bound to it.

Note the profile name — it defaults to `tvprofile`, which is what `build.sh`
assumes. Override with `CERT_PROFILE=<name>`.

> The privilege *level* lives in the distributor certificate, not in `config.xml`.
> Declaring `sso.partner` in the manifest does not grant it.

### 2. TV Developer Mode

On the TV: **Apps** → press **1-2-3-4-5** on the remote → *Developer mode* **ON** →
enter your PC's IP → **restart the TV**.

### 3. Build and install

```bash
./build.sh all 192.168.1.50      # package + install + launch
```

Or step by step:

```bash
./build.sh package               # build + sign the .wgt
./build.sh install 192.168.1.50  # connect to the TV and install
./build.sh launch
./build.sh log                   # follow console output over sdb
```

## Reading the results

The app renders every probe on screen with its source code and real return value,
colour-coded:

| Badge | Meaning |
|---|---|
| **OK** | Returned a value |
| **BLOCKED** | Module exists, threw `SecurityError` → privilege not granted |
| **NO ACCOUNT** | Threw `InvalidStateError`, or the bridge returned `bLogin:false` → the call got *past* the privilege check; nobody is signed in |
| **MISSING** | Namespace never injected → wrong container or module absent |
| **ERROR** | Threw something unexpected |

NO ACCOUNT is the one to read carefully: it is much better news than BLOCKED. It
means the privilege was granted and only the sign-in is missing, so signing in to a
Samsung Account on the TV and pressing **Return** should flip it to OK.

Remote: **↑/↓** scroll · **←/→** move between buttons · **Enter** activate ·
**Return** re-run all probes.

There's a JSON dump at the bottom of the page for photographing the panel. For
copy-pasteable output use Chrome DevTools:

```bash
sdb forward tcp:7011 tcp:7011      # then open http://localhost:7011 in Chrome
```

### Expected outcome signed with a Public certificate

- AdInfo → **OK**, with a real TIFA UUID and LAT boolean
- ProductInfo → **OK**, real DUID / model / firmware
- SSO → **BLOCKED** or **MISSING**, `getSsoState` included
- The parent-bridge section → **MISSING** ("not inside an iframe"), since the packaged
  app is the top-level document. That section only produces results when the page is
  loaded as a URL inside the container's iframe — the two runs are complementary
- `tizen.application.getCurrentApplication().appInfo.id` → `AdgApiPrb1.ApiProbe`,
  confirming you're in the app container rather than the browser

If AdInfo comes back BLOCKED too, the certificate didn't apply — check that the
install actually used your signed `.wgt` and that the DUID matches the TV.

## SSO by proxy — the postMessage bridge

The probe cannot hold `sso.platform`, but the container that frames it can. So when
the page detects it is inside an iframe it asks the parent instead, using the real
contract from `get-coupon-microsite`
(`src/components/MicrositeFrame/micrositeBridge.js`):

| Direction | Message |
|---|---|
| microsite → container | `{"getSsoState": 1}` |
| container → microsite | `{ type: 'ssoState', bLogin, id, uid, guid, authToken }` |
| microsite → container | `{"getGuid": 1}` (legacy) |
| container → microsite | `{ guid, ssoid, co, lang, firmcode, model }` (untagged) |

Both are probed, because they differ in ways that show up in the results:

- **`getSsoState` is read live** per request from `webapis.sso.getSsoState()`.
  **`getGuid` is a snapshot** taken once at container start-up, so it can be stale —
  if the user signs in after launch, `getSsoState` reflects it and `getGuid` does not.
- The `getSsoState` reply is sent to a **specific `targetOrigin`** (the origin of the
  iframe `src`), never `'*'`, because it carries `authToken`. **If you serve this page
  from a different origin than the one the container has in its iframe `src`, the
  reply is silently dropped and the probe times out.** That is the most likely cause
  of an unexplained timeout here.
- The two replies are told apart by `type`, not by their fields — the `ssoState` reply
  also contains `guid`, so matching on field names alone would confuse them.

**`bLogin: false` is ambiguous by design.** The container catches
`InvalidStateError` (not signed in), `SecurityError` (no `sso.platform`) and
`NotSupportedError` and collapses all three into `false`. Nothing inside the iframe
can distinguish them, so the probe says so rather than guessing. To narrow it down,
read the container's own log line:

```bash
sdb dlog -v time | grep -i "Tizen.*getSsoState"
```

`[Tizen][getSsoState] bLogin: …, hasAuthToken: …` means the call succeeded;
`[Tizen][getSsoState] error: …` carries the real exception name.

Since the container reaches SSO and this page does not, a microsite that needs the
account identity should go through this bridge rather than waiting on a certificate
upgrade that platform-level privileges will not deliver anyway.

## Getting `sso.partner`

Partner-level distributor certificates are only issued to Samsung accounts granted
partner status; you cannot select Partner level yourself in Certificate Manager.
Samsung's docs state the requirement (*"Privilege Level : Partner"*) without
documenting the request flow, so there's no self-serve path to link here.

For Samsung Ads, an internal route via whoever owns the Seller Office account or
the TV platform relationship is likely faster than the public developer channel.
Partner certs are DUID-bound, so request it for specific test panels.

Once you have it, re-sign and reinstall — **no code changes**; the SSO rows flip
to OK on their own.

## Why packaging is required

Privileges attach to a signed, packaged app, not to a web origin. A page loaded
over HTTPS in the TV browser or an ad web view has no privilege container, and
`$WEBAPIS/webapis/webapis.js` is a Web-Runtime virtual path that only resolves
inside an app package — over HTTP it just 404s against your own origin. So
`window.webapis` is `undefined` and all probes report MISSING.

That negative result is worth capturing deliberately: load
`../tizen_api_test_microsite.html` from a URL in the TV browser and screenshot it
alongside the packaged run. The two together are the actual answer to "can a
microsite reach SSO/AdInfo?"

## Files

| File | Purpose |
|---|---|
| `config.xml` | Tizen manifest — app id, privileges, TV profile |
| `index.html` | Generated from the parent microsite + static `webapis.js` tag |
| `icon.png` | 512×512 app icon |
| `build.sh` | Build / install / launch / log driver |
| `sync_index.py` | Regenerates `index.html` when the parent microsite changes |
| `make_icon.py` | Regenerates `icon.png` |

`index.html` is generated — edit `../tizen_api_test_microsite.html` and re-run
`./build.sh sync` (or `python sync_index.py`) rather than editing it directly.
The only difference between the two is the injected static `webapis.js` tag;
`diff ../tizen_api_test_microsite.html index.html` should show just those lines.

## App identifiers

| | |
|---|---|
| Package ID | `AdgApiPrb1` |
| Application ID | `AdgApiPrb1.ApiProbe` |
| `required_version` | `2.4` — installs on a wide range of TVs; raise if needed |
