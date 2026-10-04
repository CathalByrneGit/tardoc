---
title: Design notes
---

Records of decisions that shaped tardoc, kept because the reasoning is worth
more than the conclusion. Each one was written against measurements taken in
this repository, not from documentation.

- [React Flow pipeline graph](visualisation-prototypes.html) — why the graph is
  React Flow and not mermaid (3,489 KB against 152 KB), what a node exposes, and
  where the branching fields come from.
- [Quack remote access](quack-remote-access.html) — how tier 3 serves the
  database over the Quack protocol, the three bugs that stopped it, and the one
  constraint still outstanding: which DuckDB WASM builds can attach.
- [Publishing a whole targets project to the browser](webr-feasibility.html) —
  `targets` runs under webR, a built pipeline ships in 26 KB, a reader can edit
  the code and get a correct incremental rebuild. What that costs and what it
  would take to make a product of it.
