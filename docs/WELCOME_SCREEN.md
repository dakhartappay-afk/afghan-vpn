# Official welcome screen (AFGHAN VPN identity image)

## Your requirements and how each is met
| # | Requirement | How |
|---|-------------|-----|
| 1 | Image appears first when the app opens | `MainActivity` starts on the Welcome screen; it is the first thing drawn. The window background is the same dark colour, so there is no white flash. |
| 2 | Whole image, no cropping/stretching | `ContentScale.Fit` inside the available space. It scales the picture down evenly to fit; nothing is cut off, nothing is stretched. Empty space is the app's dark background. |
| 3 | Face and everything else unchanged | The original file is used as-is (your upload, 1123 x 1401 pixels). The code applies no filter, colour change, blur, crop or transparency. |
| 4 | Flags, mountains, logo, text kept | Same: it is the original picture, never redrawn or recreated. |
| 5 | Green CONTINUE button below | Green gradient rounded button under the image. |
| 6 | Smooth transition to the dashboard | 0.7-second cross-fade. |
| 7 | Appears whenever the app is opened | Every fresh start of the app (tap the icon when it is not running, after a restart, after Android closed it). See "Behaviour" below. |
| 8 | Works on Redmi Note 12R and other sizes | The image area takes all space left above the button, and the picture is scaled to fit it, on phones, small phones and tablets, portrait or landscape (smaller in landscape, still complete). |
| 9 | No AI-generated image or placeholder | The file in the project is byte-identical to the one you uploaded (checked). |

## Automatic checks during the Android build
1. **Before every build** (Gradle): compares the image with its stored fingerprint (`app/welcome_art.sha256`). If it was changed or replaced, the build STOPS with a clear message.
2. **After the APK is built** (both workflows): `tools/verify-welcome-image.sh` opens the finished APK and confirms your image is inside it unchanged
   (identical bytes, or at least every pixel identical). A single changed pixel fails the build.
3. The release build never re-compresses PNGs (`isCrunchPngs = false`).
I tested the APK checker with fake APKs: identical copy passes, renamed copy passes, re-packed copy passes, one-pixel change fails, corrupted file fails, missing file fails.
**Not yet run:** the Gradle check and the real APK check (they run on GitHub when you build). The look on your phone is also not yet seen by me.

## Behaviour to know
- Android does not restart an app that is already open in the background when you tap its icon or come back from the recent-apps list: you return to the screen where you left. This is normal Android behaviour and keeps a running connection screen from being interrupted. The welcome image shows on every fresh start.
- If you want the image to show again after the app was in the background for a while (for example 30 minutes), I can add that. Tell me.
- Your VPN keeps running in a system service when the app is closed; reopening the app shows the true connection state after the welcome screen.

## Check on your phone (30 seconds)
Open the app from its icon. You must see: both flags, the mountains, the fortress, your face, "Proud to be Afghan", the Pashto line, the shield logo, "AFGHAN VPN", "SECURE - FAST - GLOBAL", and the tagline "Connect with the world, Stay Private", with nothing cut off at any edge, then the green CONTINUE button below. Tap it: the picture fades into the dashboard.

## Changing the image on purpose later
The build will refuse a different image. To change it deliberately, ask me: the file and its fingerprint (`app/welcome_art.sha256`) must be updated together.

## Not done
The launcher icon (the small picture on your home screen) is still Android's default. It is not your welcome image. If you want, I can make an icon from the shield logo cut out of your own image (that is a crop for a small icon, so I will not do it without your OK).
