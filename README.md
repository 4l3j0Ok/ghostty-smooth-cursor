# ghostty-smooth-cursor

A single Ghostty shader that combines:

- **Smooth cursor blink** (VS Code `smooth` style): the cursor fades in and out instead of toggling. It stays solid for a moment after you type or move.
- **Three trails from [sahaj-b/cursor-shaders](https://github.com/sahaj-b/cursor-shaders) (MIT)**, each one toggleable: `warp` (Neovide-like), `sweep` (shrinking parallelogram) and `tail` (kitty-like comet). They are drawn on top of each other.
- **Glide**: the cursor slides between cells (also while typing) instead of jumping.
- Hollow outline cursor when the window is unfocused.

## Requirements

Ghostty 1.3 or newer (the shader uses `iCursorVisible` and `iCurrentCursorStyle`). On Linux, custom shaders need OpenGL 4.2.

## Installation

1. Clone the repo into your Ghostty config folder:

   ```sh
   git clone https://github.com/4l3j0Ok/ghostty-smooth-cursor ~/.config/ghostty/shaders/ghostty-smooth-cursor
   ```

   On macOS, `~/.config/ghostty` also works.

2. Add this to `~/.config/ghostty/config.ghostty`:

   ```ini
   cursor-style = bar          # block and underline also work
   cursor-style-blink = false  # the shader does the blinking
   cursor-opacity = 0          # hides the native cursor; the shader draws it
   custom-shader = shaders/ghostty-smooth-cursor/smooth_cursor.glsl
   custom-shader-animation = always
   ```

3. Check the config and reload it (`ctrl+shift+,` on Linux, `cmd+shift+,` on macOS). Shaders only affect new windows, tabs and splits.

   ```sh
   ghostty +validate-config
   ```

To update, run `git pull` inside the cloned folder.

If the cursor disappears, remove the `custom-shader` line and set `cursor-opacity = 1`. Shader compile errors show up in Ghostty's logs (run `ghostty` from a terminal to see them).

## Tuning

All constants are at the top of `smooth_cursor.glsl`:

| Constant | Effect |
|---|---|
| `BLINK_ENABLED` | `0.0` for a steady cursor |
| `BLINK_HOLD` | seconds solid after typing/moving |
| `BLINK_PERIOD` | seconds per fade cycle |
| `BLINK_MIN_ALPHA` | dimmest opacity (e.g. `0.15` never fully hides) |
| `BLINK_PLATEAU` | longer solid/hidden stretches (`0.5` = pure sine) |
| `GLIDE_ENABLED`, `GLIDE_DURATION` | smooth movement between cells (default 0.09 s) |
| `WARP_ENABLED`, `SWEEP_ENABLED`, `TAIL_ENABLED` | turn each trail on/off |
| `SWEEP_*`, `TAIL_*` | duration, length, blur and threshold of those trails |
| `DURATION`, `TRAIL_SIZE`, ... | warp trail, same as cursor_warp |

Limitations: programs that request a blinking cursor (DECSCUSR) still toggle Ghostty's cursor visibility, so they get a hard blink.
