# shell/plugin

Two C++ types the packaged Caelestia plugin does not provide, without which the
`ai` and `ocr` extensions will not load: `AiConfig`, a config node, and
`AiRequest`, a streaming client for OpenAI-compatible chat completions.

## These files are a reimplementation, not recovered source

The plugin these types came from existed only as a locally built binary. Its
source tree was gone: not on disk, not in any package, not pushed anywhere.

What it left behind was `.qmltypes`, Qt's machine-readable type metadata, which
records for each type its declaring file, the line number of each declaration,
every property with its type, accessor, notify signal and declaration order, and
every method and signal with parameters and defaults. That is enough to
reconstruct a type's interface, and the QML that consumes these types supplied
the rest: which values each property takes, what the status strings mean, and
when `finished` has to fire.

Rebuilding from `src/` and diffing the resulting `.qmltypes` against the lost
binary's gives a **byte-identical** result for both types, including the
recorded source line numbers.

Read that precisely. `.qmltypes` describes an **interface**, so what matches is
the interface and the line each declaration sat on. It is not evidence that the
contents match. A `.cpp` body, a helper, a comment, a private member: none of
that reaches `.qmltypes`, and `airequest.cpp` in particular is new code written
to satisfy an observed contract. **Nothing here should be read as a claim that
the original implementation looked like this.**

The old binary is not distributed and is not needed: it was evidence, not a
dependency.

## What is inferred rather than recovered

This is the part to check first if behaviour differs from before.

- **Default values.** `.qmltypes` does not record them. `backendUrl` defaults to
  a local llama.cpp-style endpoint; `ocrLanguages` defaults to empty, meaning
  every installed Tesseract language; the rest default empty or false.
- **`CONFIG_GLOBAL_PROPERTY` rather than `CONFIG_PROPERTY`.** The metadata does
  not distinguish them. Global is right for these settings, and matches how
  `ServiceConfig` treats `weatherLocation`.
- **`timeoutMs` defaulting to 0, meaning no timeout.** The metadata records that
  a default exists, not its value. Neither caller passes one and both surface a
  Cancel control, so no timeout is what matches the UI.
- **The streaming implementation.** Server-sent event framing, `[DONE]`
  handling, accumulating `choices[0].delta.content` while also accepting a
  non-streaming `choices[0].message.content`, and settling exactly once. This is
  the largest inferred piece.

## Building and checking

```sh
./shell/build.sh --no-install          # build, leave it in build/
./shell/build.sh                       # build and install
```

Needs `cmake`, `ninja`, `git`, Qt 6 development packages and `libqalculate`:
the same set upstream needs, because this builds the upstream plugin with two
files added. Output goes to `$XDG_DATA_HOME/0xide/qml`, which
`shell.qml` points at through `QML_IMPORT_PATH`.

```sh
grep -c 'caelestia::config::AiConfig' \
    build/plugin-install/lib/qt6/qml/Caelestia/Config/caelestia-config.qmltypes
grep -c 'caelestia::AiRequest' \
    build/plugin-install/lib/qt6/qml/Caelestia/caelestia-core.qmltypes
qs -p build/shell-src -n        # must reach "Configuration Loaded" with no errors
```

A missing or mismatched plugin shows up immediately as `GlobalConfig.ai is
undefined` or `AiRequest is not a type`.
