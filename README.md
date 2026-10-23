# AI Tube Mobile

Flutter client for the existing AI Tube Python API. It uses the desktop app's
green-and-neutral chat design, streams assistant responses, and keeps chat
history and preferences on the mobile device.

## Connect to the desktop server

1. Restart the desktop app so its server listens on the local network.
2. Find the computer's Wi-Fi IPv4 address (for example, `192.168.1.20`).
3. Connect the phone and computer to the same trusted Wi-Fi network.
4. In mobile **Settings**, enter `http://<computer-ip>:8000` and tap **Test
   connection**. For example: `http://192.168.1.20:8000`.
5. Allow the desktop server through the computer's private-network firewall if
   prompted.

The Android emulator can use `http://10.0.2.2:8000`; a physical phone must use
the computer's LAN IP. The server API currently has no authentication, so it
is exposed to devices on the same network while the desktop app is running.
Use only a trusted private network and do not forward port 8000 to the internet.

## Run

Install Flutter 3.41 or later, then run these commands from this directory:

```sh
flutter pub get
flutter run
```

Build Android with `flutter build apk` or iOS with `flutter build ios` on macOS.
