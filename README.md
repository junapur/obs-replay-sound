# obs-replay-sound
Play a sound when you save a replay.

## Installation
### 1. Install SDL3
The script uses SDL3 to play audio so that it works cross platform! :]

**Windows**
1. Download `SDL3-<version>-win32-x64.zip` from the [latest SDL release](https://github.com/libsdl-org/SDL/releases/latest).
2. Extract `SDL3.dll` into the same folder as the script.

**macOS**
```sh
brew install sdl3
```

**Linux**
```sh
sudo pacman -S sdl3        # Arch
sudo dnf install SDL3      # Fedora
sudo apt install libsdl3-0 # Debian/Ubuntu

# For others, check with your distro's package manager
```

On any system, you can also skip the system install and put the SDL3 library (`SDL3.dll`, `libSDL3.dylib` or `libSDL3.so.0`) next to the script.

### 2. Add the script to OBS
1. Download [`obs-replay-sound.lua`](obs-replay-sound.lua).
2. In OBS, open **Tools > Scripts**, click **+** and select the script.
3. Pick a WAV file under **Sound file**, set the **Volume**, and press **Test sound**.

## Troubleshooting
Open **Tools > Scripts > Script Log** to see what the script logs.
 
| Message                              | Fix                                                            |
| ------------------------------------ | -------------------------------------------------------------- |
| `could not find SDL3`                | SDL3 isn't installed, or the library isn't next to the script. |
| `... but 3.2.0 or newer is required` | Your SDL3 is too old, update it.                               |
| `could not load <file>`              | The file isn't a valid WAV file.                                    |
 
Only WAV files are supported. To convert a file to WAV, try [FFmpeg](https://ffmpeg.org): `ffmpeg -i sound.mp3 sound.wav`
