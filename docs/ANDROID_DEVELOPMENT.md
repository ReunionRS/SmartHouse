# Android development

To update the debug application on the running emulator without deleting the
current SmartHouse session, run from the `frontend` directory:

```powershell
.\tool\install_android_debug.ps1
```

The script builds the debug APK and installs it using `adb install -r -t`.
The `-r` flag replaces the application package while preserving its data.

Do not use `flutter install` for routine emulator updates in this project. That
command may uninstall the previous debug package first and therefore erase
`SharedPreferences`, including the local login session and setup flags.

To install an APK that has already been built:

```powershell
.\tool\install_android_debug.ps1 -SkipBuild
```

To target another emulator or Android device:

```powershell
.\tool\install_android_debug.ps1 -DeviceId emulator-5556
```
