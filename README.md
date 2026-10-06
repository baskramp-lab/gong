# Gong

A macOS menu-bar app that makes sure you never miss a meeting. A few minutes before a Google Calendar meeting starts,
Gong covers your screens with a retro 16-bit modal — a ninja strikes a gong — with one-click **Join** for the video
link. Soft notifications come first (30 and 10 minutes before).

- Works with Google Calendar through your calendar's **secret iCal address** — no account sign-in, no OAuth.
- Recognises Google Meet, Zoom and Microsoft Teams links.
- Snooze, pause (15 min … rest of the day), launch at login.
- Follows your Mac's language (20 languages).
- Hidden extra: press <kbd>Space</kbd> in the modal.

Requires macOS 14 or later (Apple silicon or Intel).

## Install

Pre-built downloads are not available yet, so you build Gong on your own Mac. This takes about 30–45 minutes the
first time, most of it downloading Xcode.

1. **Install Xcode** from the App Store (free) and open it once to finish the setup.
2. **Create a free signing certificate** (needed for notifications; a free Apple ID is enough, no paid developer
   account): Xcode → **Settings → Accounts → +** → sign in with your Apple ID → select it → **Manage Certificates…
   → + → Apple Development**.
3. **Build and install:**

   ```bash
   git clone https://github.com/baskramp-lab/gong.git
   cd gong
   scripts/build-app.sh --install
   open /Applications/Gong.app
   ```

Without the certificate from step 2 Gong still runs and still blocks your screen before meetings, but macOS will not
show its notifications. Signing details: [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) (Dutch).

## Updating

To update, run this in the folder you cloned (about 3 minutes; your settings and calendar address are kept):

```bash
git pull && scripts/build-app.sh --install && open /Applications/Gong.app
```

To hear about releases by email: on GitHub, **Watch → Custom → Releases**.

## Set up

1. In Google Calendar on the web: **Settings → your calendar → Integrate calendar → Secret address in iCal format**,
   and copy it.
2. Click the gong in the menu bar → **Set iCal URL…**, paste the address, click **Test**, then **Save**.
3. Allow notifications when macOS asks.

The menu-bar icon shows the state: dimmed = paused, orange dot = calendar not refreshed recently, red dot = no URL or
an error.

## Privacy

- The secret iCal address is stored in your macOS Keychain and is only sent to Google to fetch your calendar.
- Gong talks to no other server and collects nothing.
- Settings and a cached copy of your calendar live in `~/Library/Application Support/Gong/`.

## Settings file

`~/Library/Application Support/Gong/settings.json` holds the thresholds (`softMinutes`, `hardMinutes`,
`snoozeMinutes`, `lateGraceMinutes`), `soundEnabled`, `includeUnaccepted` and `myEmail`. `myEmail` can stay empty:
Gong reads your address from the iCal URL.

## Known limitations

- Only Google Calendar's secret iCal address is supported.
- A booked meeting room counts as another attendee, so a solo block with a room also triggers the modal.
- Recurrence rules with `BYSETPOS`, `BYWEEKNO` or hourly parts are skipped.

## License

[MIT](LICENSE). The bundled Silkscreen pixel font is under the SIL Open Font License (`Resources/Fonts/OFL.txt`).
