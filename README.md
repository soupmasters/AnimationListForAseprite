# Aseprite Animation List

Aseprite Animation List is a small Lua extension that displays animation tags
in a compact dialog and jumps to the first frame of a tag with one click.

This is a clean rewrite inspired by Soupmasters' original internal Animation
List script. It fixes the old package's empty script and plugin-registration
issues, avoids deprecated API names, and does not recolor or otherwise edit
sprite tags.

## Features

- Opens from **File > Scripts > Animation List...**.
- Uses `Shift+Alt+E` as the default shortcut.
- Shows each animation tag together with its frame range.
- Refreshes the list without closing the workflow.
- Keeps the dialog modeless and scrollable for sprites with many tags.
- Ignores Soupmasters metadata tags whose names start with `-`, `*`, `//`, or
  `'`.

## Install with Aseprite Extension Manager

1. Open **Aseprite Extension Manager...** in Aseprite.
2. Choose **Install from GitHub**.
3. Enter `https://github.com/soupmasters/AsepriteAnimationList`.
4. Confirm Aseprite's native extension installation prompt.

The repository has one Aseprite manifest at its root, and releases attach a
single asset named `AsepriteAnimationList.aseprite-extension`. Keeping that
asset name stable allows the Extension Manager to find future updates.

You can also install the release asset directly from Aseprite's Extensions
preferences with **Add Extension**.

## Development

Run the Lua tests with Lua 5.4:

```sh
lua5.4 tests/run.lua
```

On macOS, the installed Aseprite runtime can run the same tests:

```sh
./scripts/test.sh
```

When it uses Aseprite, the test script also exercises real `Sprite`, `Tag`, and
`Frame` objects.

Build the release asset:

```sh
./scripts/package.sh
```

Packaging requires `jq`, `zip`, and `unzip`.

The output is `dist/AsepriteAnimationList.aseprite-extension`. To release a new
version, update `package.json` and `CHANGELOG.md`, then push a matching semantic
version tag such as `v1.1.0`.

## Requirements

- Aseprite 1.3.15 or later
- Aseprite scripting API 35 or later

## License

MIT
