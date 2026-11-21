# Ardia on iPad: build it yourself

This fork ([Malgsx/ardia](https://github.com/Malgsx/ardia)) is a personal iPad build of **[Ardia](https://github.com/ardia-browser/ardia)**, the open-source browser made by the Ardia team. Ardia, its design, its engine and nearly all of the code here are theirs. This fork adds a few Arc Search–style features on top of their latest release and documents how to put the result on your own iPad.

It is **not an official Ardia release**, and nothing here is endorsed by the Ardia team. For the real thing, use [ardia.dev](https://ardia.dev) and the [Ardia repo](https://github.com/ardia-browser/ardia). If you want iPad support upstream, the place to say so is the Ardia team's own tracker ([#1230](https://github.com/ardia-browser/ardia/issues/1230)), following their [CONTRIBUTING.md](CONTRIBUTING.md).

- [What this fork adds](#what-this-fork-adds)
- [How it was built](#how-it-was-built)
- [Put it on your iPad](#put-it-on-your-ipad)
- [Turn on the features](#turn-on-the-features)
- [Proving it works](#proving-it-works)
- [Troubleshooting](#troubleshooting)
- [Credits and license](#credits-and-license)

## What this fork adds

Everything else, including iPad support itself (full screen, the wide layout, the phone layout in narrow windows), comes from the Ardia team's work in [#2184](https://github.com/ardia-browser/ardia/pull/2184) and [#2376](https://github.com/ardia-browser/ardia/pull/2376). On top of Ardia **0.2.47**, this fork adds:

| Feature | What it does |
| --- | --- |
| **Arc-style Pinch to Summarize** | Pinch in on a page: it squeezes under your fingers, then collapses into a preview card (top left on iPad) while the summary fills the screen below in large type. Copy, Share and Close sit at the bottom; tap the preview to grow it back into the page. Ardia already had Pinch to Summarize with a small card; this changes how it looks and moves. |
| **ChatGPT summaries** | Uses your own ChatGPT plan. The summary settings page can sign you in through OpenAI's own sign-in page. |
| **Claude summaries** | Uses your own Anthropic API key, billed to your API credits. The key stays in the device's Keychain and goes only to `api.anthropic.com`. |
| **⌘T** | Opens a new tab with search, on an iPad with a keyboard. |

The changes are in two commits: [`6bd42f9ce`](https://github.com/Malgsx/ardia/commit/6bd42f9ce) (the features) and [`05700ab9b`](https://github.com/Malgsx/ardia/commit/05700ab9b) (a fix so the Anthropic key saves). [PR #1](https://github.com/Malgsx/ardia/pull/1) has the full write-up.

### Version history

| Date | Ardia version | Notes |
| --- | --- | --- |
| 21 Nov 2026 | **0.2.47** (latest release, [release notes](https://ardia.dev/release-notes/#0.2.47)) | Updated to the latest release. It merged cleanly with no conflicts and none of the files the fork changes were touched upstream. Rebuilt and installed on the iPad over Wi-Fi. The build script now finds a device paired over Wi-Fi and no longer stalls on a Keychain prompt. |
| 20 Nov 2026 | 0.2.47-nightly.9 | First build with the features above. |

## How it was built

[@Malgsx](https://github.com/Malgsx) directed the work and tested every step on a real iPad Pro 11" (2nd generation, iPadOS 27.3). The code was written with AI coding agents:

- **[Claude Code](https://claude.com/claude-code)** (Anthropic's coding agent, running Claude Opus 5.5) wrote the work in this fork and keeps it updated to Ardia's latest version: the features above, the build script, and the UI tests that drove the installed app on the iPad and captured screenshots as proof.
- **[Amp](https://ampcode.com)** helped with the earlier [`ipad-fills-screen`](https://github.com/Malgsx/ardia/tree/ipad-fills-screen) branch, which made the old native iOS app universal before the Ardia team moved the phones to Expo.

The workflow, if you want to try something similar:

1. Start from Ardia's latest tag (`git fetch --tags`, then branch from a release like `v0.2.47` or a nightly like `v0.2.47-nightly.N`). To update later, merge the newer tag in.
2. Read the Ardia team's docs first. [`AGENTS.md`](AGENTS.md) and [`docs/phone.md`](docs/phone.md) explain how the phone app is laid out and built.
3. Make a change, build it, install it on the iPad, then check it on the device, not just in the simulator.
4. Write a UI test that does what a person would (pinch, type, tap) and saves screenshots, so "it works" means something.

## Put it on your iPad

You need:

- A Mac with **Xcode 27.1 or later** (open it once after installing so it finishes setting up).
- An iPad (or iPhone) on **iPadOS/iOS 27**, and a USB cable that carries data, not just charge.
- A **free Apple ID**. A paid developer account isn't required.
- [Homebrew](https://brew.sh), for `brew install pnpm cocoapods`.

**One-time setup:**

1. In Xcode › Settings › Accounts, click **+** and sign in with your Apple ID. That creates your free "Personal Team".
2. Plug in the iPad, unlock it and tap **Trust**.
3. On the iPad, turn on **Settings › Privacy & Security › Developer Mode** and restart when it asks.

**Build and install:**

```sh
git clone https://github.com/Malgsx/ardia.git
cd ardia
brew install pnpm cocoapods
scripts/ipad/build-for-my-ipad.sh
```

[`scripts/ipad/build-for-my-ipad.sh`](scripts/ipad/build-for-my-ipad.sh) finds your team and the connected device, then:

1. Gives the app your own bundle id, `com.<your Mac username>.ardia` by default; change it with `--bundle-prefix com.yourname.ardia`.
2. Removes the App Group from the entitlements, because a free team can't use App Groups. Ardia keeps its data in its own container instead.
3. Installs the JavaScript packages and CocoaPods.
4. Builds a Release build, with the JavaScript bundled in so no development server is needed.
5. Installs it on the device and opens it.

The first build takes a while. The first time the app opens, the iPad may say **Untrusted Developer**: go to **Settings › General › VPN & Device Management**, tap your Apple ID and choose **Trust**.

**Free-team builds stop opening after 7 days.** Run the script again to renew; your data stays.

The signing changes in steps 1 and 2 exist only in your copy and must never be committed or sent upstream. Before committing anything, put the files back with:

```sh
scripts/ipad/build-for-my-ipad.sh --undo
```

Options: `--team <TEAM ID>` if it can't find your team, `--device <UDID>` to pick a device (`xcrun devicectl list devices` lists them), and `--build-only` to build without installing.

## Turn on the features

Pinch to Summarize is off until you turn it on. On iPad, open **Show Sidebar › More (···) › Settings**, then **Experimental › Pinch to Summarize**, and turn it on. Then choose who writes the summaries:

- **On This Device**: Apple Intelligence on devices that have it. Older iPads without it get the page's key lines instead.
- **ChatGPT**: tap it, then **Continue**. OpenAI's sign-in page opens; sign in with the account that has your ChatGPT plan, and the settings page then shows you as connected.
- **Claude**: create a key at [platform.claude.com](https://platform.claude.com) › API keys › **Create key** and pick **Somewhere else** ("Use an API key"). Copy it; it's shown once. In Ardia, tap **Claude**, paste the key and tap **Save Key and Use Claude**. Ardia checks it with Anthropic (free), saves it to the Keychain and shows "API key ending in …". Each summary costs roughly a cent or two of API credits.

A Claude Pro or Max subscription can't be used here. Anthropic allows subscriptions only in its own apps, and other apps must use an API key ([Anthropic's policy](https://code.claude.com/docs/en/legal-and-compliance)).

Then pinch in on any page that's fully zoomed out. **⌘T** opens a new tab when a keyboard is attached.

## Proving it works

[`scripts/ipad/uitests`](scripts/ipad/uitests) holds the UI tests used to check this build on the iPad. They drive the installed Ardia by its bundle id and save screenshots into the test results.

```sh
brew install xcodegen
cd scripts/ipad/uitests && xcodegen generate
TEST_RUNNER_ARDIA_BUNDLE_ID=com.yourname.ardia xcodebuild test \
  -project ArdiaDeviceTests.xcodeproj -scheme ArdiaDeviceTests \
  -destination 'platform=iOS,id=<UDID>' \
  DEVELOPMENT_TEAM=<TEAM ID> PRODUCT_BUNDLE_IDENTIFIER=com.yourname.ardia.devicetests \
  -allowProvisioningUpdates -resultBundlePath proof.xcresult
xcrun xcresulttool export attachments --path proof.xcresult --output-path proof-screenshots
```

Keep the device unlocked while the tests run.

| Test | What it checks |
| --- | --- |
| `VerifyTests` | Full screen in landscape, Pinch to Summarize, and ⌘T opening search |
| `ArcSummaryTests` | The collapse-to-card layout and growing back, plus the ChatGPT sign-in reaching OpenAI's page |
| `ClaudeSaveTests` | A wrong key is rejected, your key saves, and a pinch returns a summary written by Claude. It needs `TEST_RUNNER_ARDIA_CLAUDE_KEY`, so set it from a file, never paste it into a chat or a commit. It spends about a cent of API credits. |

## Troubleshooting

| Problem | Fix |
| --- | --- |
| "No Accounts" or "No profiles for …" | Sign in to Xcode › Settings › Accounts with your Apple ID. |
| No device found | Use a data cable, unlock the device, tap Trust, and turn on Developer Mode. |
| "Untrusted Developer" | Settings › General › VPN & Device Management › your Apple ID › Trust. |
| The build sits at "Building" for a long time | Xcode is waiting on a hidden Keychain prompt for your github.com password. The script skips that with `-packageAuthorizationProvider netrc`; if you build in Xcode yourself, look for the prompt on the Mac and click Deny. |
| Ardia won't open after a week | The free-team build expired. Run the script again. |
| Too many App IDs | A free team can register only a few new bundle ids per week. Reuse the same `--bundle-prefix`. |
| The Claude key won't save | The red message above the key field says why: a key that Anthropic rejected, no credits left, or no network. |

## Credits and license

**Ardia** is made by the Ardia team and its contributors at [ardia-browser/ardia](https://github.com/ardia-browser/ardia). All credit for the browser goes to them. This fork only adds the iPad features and the build guide above.

Licensing is unchanged from upstream: Ardia as distributed is under the [GNU GPL v3](LICENSE), Ardia's own source files are under the [Apache License 2.0](LICENSE.Apache-2.0), and third-party components are listed in [NOTICE](NOTICE). The additions in this fork are offered under the same terms.
