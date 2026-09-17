# shell/plugin

Two C++ types the packaged Caelestia plugin does not provide, without which the
`ai` and `ocr` extensions will not load.

## How this came to be reconstructed

The plugin these types came from existed only as a locally built binary at
`~/.local/share/caelestia-preview/`. Its source tree was gone: not on disk, not
in any package, not pushed to any remote.

What it *did* leave behind was `.qmltypes` - Qt's machine-readable type metadata,
emitted next to every QML module. That records, for each type: its declaring
file, its declaration's line number, every property with its type, accessor
names, notify signal and declaration order, every method with its parameters and
defaults, and every signal. That is enough to reconstruct the source.

The QML that consumes these types supplied the rest: which values each property
takes, what the status strings mean, and when `finished` has to fire.

## What the reconstruction is verified against

Rebuilding from `shell/plugin/src/` and diffing the resulting `.qmltypes`
against the lost binary's gives a **byte-identical** result for both types,
including the recorded source line numbers. Every property name, type, accessor,
notify signal, declaration index, method signature and default argument matches,
and each declaration lands on the line the original recorded for it.

Read that claim precisely. `.qmltypes` describes a type's **interface**, so what
matches is the interface and the line each declaration sat on - strong evidence
that these files have the same shape as the originals. It is not evidence that
they have the same contents. A `.cpp` body, a helper, a comment, a private
member: none of that reaches `.qmltypes`, and `airequest.cpp` in particular is
new code written to satisfy an observed contract.

**These files are a reimplementation that matches a recovered interface. They
are not the lost source recovered, and nothing here should be read as a claim
that the original implementation looked like this.**

This comparison was possible because the old binary was still on the machine at
the time. **You do not need it, and it is not distributed here** - it was
evidence, not a dependency. What you can reproduce is that the plugin builds and
that the shell resolves both types:

```sh
./shell/build.sh --no-install
grep -c 'caelestia::config::AiConfig' \
    build/plugin-install/lib/qt6/qml/Caelestia/Config/caelestia-config.qmltypes
grep -c 'caelestia::AiRequest' \
    build/plugin-install/lib/qt6/qml/Caelestia/caelestia-core.qmltypes
qs -p build/shell-src -n        # must reach "Configuration Loaded" with no errors
```

If you still have an older build of the plugin, the original check was a diff of
the `Component { ... }` block for each type between its `.qmltypes` and the
freshly built one.

## What is verified, and what is inferred

Verified from the type metadata and confirmed by rebuilding:

- both types' full public surface, and the line each declaration sits on
- `AiConfig`'s seven properties, their types, and their order
- `AiRequest`'s four readonly properties, the two `send` overloads, `cancel`,
  and the `changed` / `finished` signals

Inferred from the consuming QML, and therefore the part to check if behaviour
differs from before:

- **Default values.** `.qmltypes` does not record them. `ocrLanguages` defaults
  to `"eng"` because `AiSettings.qml` falls back to that string; `backendUrl`
  defaults to a local llama.cpp-style endpoint; the rest default empty or false.
  A wrong default is invisible once `shell.json` has a value, which it does.
- **`CONFIG_GLOBAL_PROPERTY` rather than `CONFIG_PROPERTY`.** `.qmltypes` does
  not distinguish them. Global is right for these settings - an AI endpoint
  should not vary per monitor - and matches how `ServiceConfig` treats
  `weatherLocation`.
- **`timeoutMs` defaulting to 0, meaning no timeout.** The metadata records that
  a default exists, not its value. Neither caller passes one, and both surface a
  prominent Cancel control, so no timeout is the behaviour that matches the UI.
- **The streaming implementation.** Server-sent event framing, `[DONE]`
  handling, accumulating `choices[0].delta.content` while also accepting a
  non-streaming `choices[0].message.content`, and settling exactly once. This is
  written to the observable contract, not recovered; it is the largest inferred
  piece.

## Building

`shell/build.sh` does this as part of a normal install. Standalone:

```sh
./shell/build.sh --no-install          # build, leave it in build/
./shell/build.sh                       # build and install
```

Needs `cmake`, `ninja`, `git`, Qt 6 development packages and `libqalculate` -
the same set the upstream shell needs, because this builds the upstream plugin
with two files added.

Output goes to `$XDG_DATA_HOME/caelestia-mod/qml`, which `shell.qml` points at
through `QML_IMPORT_PATH`.

## Validating a build

```sh
qs -p build/shell-src -n            # loads the shell against the built plugin
```

A missing or mismatched plugin shows up immediately as
`GlobalConfig.ai is undefined` or `AiRequest is not a type`.
