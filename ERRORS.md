# PushBar error codes

Every error PushBar shows has a code like `PB-204`. Find your code below to see
what happened and what to try.

**Getting help from an AI assistant:** click **Copy Details** (in the popover)
or **Copy Error Details** (in an alert), then paste it into your assistant
together with a link to this page (or its plain-text version:
https://raw.githubusercontent.com/jonpikereally/Push3InterfaceControl/main/ERRORS.md). The
details include the code, what went wrong, and your PushBar and macOS versions.

Where errors show up:

- **The popover banner** at the top of PushBar's menu shows connection
  problems with their code and a **Copy Details** button.
- **Alerts** show the code, plus **Copy Error Details** and **Open Error List**
  buttons. Hovering over the error text points you here.
- **Background problems** appear as a **⚠️ Problem PB-xxx** row in the menu.
- **The installers** (install.sh, Install PushBar.command) print their code in
  the Terminal window.
- Every error is also logged to `~/Library/Application Support/PushBar/errors.log`.

## Updates (1xx)

| Code | What happened | What to try |
|---|---|---|
| PB-101 | No update source is set. | Set one with **Update Source…** in the menu, or leave it empty to use the built-in source. |
| PB-102 | The update source isn't a web link or a file path. | Fix it with **Update Source…**, or empty it to use the built-in source. |
| PB-103 | Couldn't reach the update source. | Check your internet connection and try again. |
| PB-104 | The update server returned an error. | Try again in a few minutes. If it keeps happening, download the latest version from GitHub. |
| PB-105 | The update information is damaged or in the wrong format. | The published update is broken. Download the latest version from GitHub instead. |
| PB-106 | Couldn't download the update. | Try again in a few minutes, or download the latest version from GitHub. |
| PB-107 | Couldn't unpack the downloaded update. | Download the latest version from GitHub instead. |
| PB-108 | The downloaded update doesn't contain PushBar. | Download the latest version from GitHub instead. |
| PB-109 | The downloaded update is a different app. | Download the latest version from GitHub instead. |
| PB-110 | The downloaded update is damaged. | Download the latest version from GitHub instead. |
| PB-111 | Couldn't start installing the update. | Make sure PushBar is in ~/Applications and that the folder isn't locked, then try again. |
| PB-112 | Installing the update failed, so the previous version was kept. | Make sure PushBar is in ~/Applications and that the folder isn't locked, then try again. |

## Push 3's audio interface (2xx)

| Code | What happened | What to try |
|---|---|---|
| PB-201 | Push 3's audio interface isn't connected. | Make sure Push is plugged in over USB-C and switched on. If you just quit Live, Push may have gone to sleep: unplug its USB cable and plug it back in. |
| PB-202 | Push 3 didn't accept a volume or mute change. | Unplug Push and plug it back in, then try again. If Live is open, it may be holding the setting. |
| PB-203 | Couldn't change Push 3's sample rate. | Another app (Live, a DAW) may be locking the rate. Quit it, or change the rate in Audio MIDI Setup. |
| PB-204 | Couldn't make Push 3 the Mac's sound output or input. | Choose Push yourself in **System Settings → Sound**. |

## Login item (4xx)

| Code | What happened | What to try |
|---|---|---|
| PB-401 | Couldn't change Open at Login. | Add PushBar yourself in **System Settings → General → Login Items**. |

## Installers (6xx)

| Code | What happened | What to try |
|---|---|---|
| PB-601 | The installer couldn't copy PushBar into ~/Applications. | Check that ~/Applications exists and isn't locked, then run the installer again. |
| PB-602 | The installer couldn't sign PushBar for this Mac. | Install Apple's Command Line Tools (`xcode-select --install`) and run the installer again. |
| PB-603 | PushBar was installed but couldn't be opened. | Open PushBar from ~/Applications yourself. |

## Anything else (9xx)

| Code | What happened | What to try |
|---|---|---|
| PB-999 | Something unexpected went wrong. | Try again. If it keeps happening, copy the details and ask for help. |
