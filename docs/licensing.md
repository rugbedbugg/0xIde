# Licensing

**This repository is GPL-3.0-or-later. A permissive licence is not available to
it.**

| Upstream | Licence |
| --- | --- |
| caelestia-dots/shell | GPL-3.0 |
| caelestia-cli | GPL-3.0 |
| caelestia-dots/caelestia (dots) | no `LICENSE` file in the tree |

`shell/patches/` are diffs against GPL-3.0 source and `shell/extensions/` are
QML written to be linked into that GPL-3.0 program. Both are derivative works,
so GPL-3.0 propagates and MIT, BSD, or Apache-2.0 would be incompatible.

The parts that are genuinely independent - the adapters, the orchestration hook,
the installer - could be licensed permissively in a separate repository. Keeping
them here under one licence is simpler and costs nothing unless someone wants to
reuse an adapter in a non-GPL project.

`shell/plugin/src/` is original work but implements an API shape recovered from a
previously built plugin and is compiled into the GPL-3.0 plugin, so it is
GPL-3.0 as well.

No third-party assets are bundled. The Caelestia fonts this setup uses are
installed separately, by the distribution or by the Caelestia dots, and are not
redistributed from here, so no font licence applies to this repository.
