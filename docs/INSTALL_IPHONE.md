# Install Street Companion on an iPhone (free, with a Mac)

Apple only lets apps onto an iPhone when they are signed. Without a paid Apple Developer account, the free way is to install the app from a Mac with your own Apple ID. **The app then works for 7 days**; after that, connect the iPhone to the Mac again and repeat step 6 (takes about a minute).

You need:
- a Mac (macOS 15 or newer) with about 30 GB free space
- your Apple ID
- your iPhone and its USB cable

## One-time setup on the Mac (about 1 hour, mostly downloading)

1. **Install Xcode** from the Mac App Store (free, large download). Open it once and let it install its extra components. When it asks which platforms to install, tick **iOS**.

2. **Open Terminal** (press Cmd + Space, type `Terminal`, press Enter). Copy each line below into Terminal and press Enter, one at a time. Type your Mac password when asked (it does not show while typing).

   Install Homebrew (a tool installer for the Mac):
   ```
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```
   At the end Homebrew prints two or three lines under "Next steps" starting with `echo` / `eval`. Copy and run those too.

   Install Flutter and CocoaPods:
   ```
   brew install --cask flutter
   brew install cocoapods
   ```

   Download the app's code:
   ```
   cd ~
   git clone https://github.com/ziczaczony-bot/street-companion.git
   cd street-companion
   flutter pub get
   ```

3. **Sign in to Xcode with your Apple ID**: in Terminal run
   ```
   open ios/Runner.xcworkspace
   ```
   Xcode opens. In the left column click **Runner** (the blue icon at the top), then the **Signing & Capabilities** tab.
   - **Team**: choose *Add an Account…*, sign in with your Apple ID, then pick **"Your Name (Personal Team)"**.
   - **Bundle Identifier**: change `de.streetcompanion.streetCompanion` to something unique, e.g. `de.sudhi.streetcompanion`.
   Close Xcode.

## Prepare the iPhone (one time)

4. Connect the iPhone to the Mac with the cable. On the iPhone tap **Trust** and enter your code.
5. On the iPhone: **Settings → Privacy & Security → Developer Mode → On**. The iPhone restarts; confirm **Turn On** afterwards.

## Install (and every 7 days)

6. In Terminal:
   ```
   cd ~/street-companion
   git pull
   flutter run --release
   ```
   If several devices are listed, type the number of your iPhone. The first build takes a few minutes.

7. The first time only, the iPhone says "Untrusted Developer". Go to **Settings → General → VPN & Device Management**, tap your Apple ID, then **Trust**. Open Street Companion again.

Now you can unplug the iPhone; the app keeps working until the 7 days are over.

`git pull` in step 6 also fetches the newest version of the app, so you get all changes each time you reinstall.

## If something goes wrong

- *"No profiles for … were found"* or a signing error: repeat step 3 and make sure a Team is selected and the Bundle Identifier is unique.
- *"Developer Mode disabled"*: do step 5.
- Anything else: copy the red error text from Terminal and send it to me.
