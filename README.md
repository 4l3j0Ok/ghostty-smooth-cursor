# ghostty-smooth-cursor

A single Ghostty shader that combines:

- **Smooth cursor blink** (VS Code `smooth` style): the cursor fades in and out instead of toggling. It stays solid for a moment after you type or move.
- **Warp trail** (Neovide-like), based on [sahaj-b/cursor-shaders](https://github.com/sahaj-b/cursor-shaders) (MIT).
- Hollow outline cursor when the window is unfocused.

## Setup

```ini
cursor-style = bar          # block and underline also work
cursor-style-blink = false  # the shader does the blinking
cursor-opacity = 0          # hides the native cursor; the shader draws it
custom-shader = /path/to/smooth_cursor.glsl
custom-shader-animation = always
```

If the cursor disappears, remove the `custom-shader` line and set `cursor-opacity = 1`.

## Tuning

All constants are at the top of `smooth_cursor.glsl`:

| Constant | Effect |
|---|---|
| `BLINK_ENABLED` | `0.0` for a steady cursor |
| `BLINK_HOLD` | seconds solid after typing/moving |
| `BLINK_PERIOD` | seconds per fade cycle |
| `BLINK_MIN_ALPHA` | dimmest opacity (e.g. `0.15` never fully hides) |
| `BLINK_PLATEAU` | longer solid/hidden stretches (`0.5` = pure sine) |
| `DURATION`, `TRAIL_SIZE`, ... | trail, same as cursor_warp |

Limitations: programs that request a blinking cursor (DECSCUSR) still toggle Ghostty's cursor visibility, so they get a hard blink.
