---
title: Selector guide
---

The box above the viewer's overview graph filters it with **selectors**. The
syntax is deliberately close to dbt's `--select`, so if you have used that you
already know most of it. This page is the whole grammar.

```
clean+ -report        what clean feeds, except the report
+drift_flags          everything drift_flags depends on
ingest_*,+report      ingest targets that sit upstream of the report
```

Filtering *hides* the nodes it does not select and refits the view. To keep the
whole graph and only fade the rest, click a node instead — see
[Follow a chain](viewer.html#sec:follow-a-chain). The two share one definition
of upstream and downstream.

## The pieces

A selector is made of **terms**. A term is a name, optionally with a `+` on
either side saying how far to follow the dependency edges from it.

| Term | Selects |
|---|---|
| `clean` | that target |
| `+clean` | `clean` and **everything upstream** of it |
| `clean+` | `clean` and **everything downstream** of it |
| `+clean+` | `clean`, everything upstream and everything downstream |
| `2+clean` | `clean` and what is up to **2 steps upstream** |
| `clean+2` | `clean` and what is up to 2 steps downstream |
| `ingest_*` | every target whose name matches (`*` matches any run of characters) |
| `*_flags` | the same, anchored at the end |
| `-raw_path` | **removes** `raw_path` from the result |
| `-clean+` | removes `clean` and everything downstream of it |

"Upstream" follows the edges backwards only, and "downstream" forwards only. A
helper function shared by a dozen targets is upstream of each of them, but it
does not make the other eleven upstream of one another.

Names are matched exactly and case-sensitively; only `*` is special.

## Combining terms

| Write | Meaning |
|---|---|
| `a b` — **a space** | **union**: what `a` selects *or* what `b` selects |
| `a,b` — **a comma** | **intersection**: only what *both* select |
| `-x` anywhere | removed from the final result |

Spaces bind loosest, so `a,b c` is `(a and b) or c`.

An intersection is how you ask for the nodes **on the way between** two
points. Downstream of `clean` and upstream of `report` is exactly the chain
connecting them:

```
clean+,+report
```

If nothing is left to select, the box says *nothing matches* and leaves the
graph as it was.

## Recipes

| To see | Write |
|---|---|
| Everything affected if `clean` changes | `clean+` |
| Everything `report` is built from | `+report` |
| The path from `clean` to `report` | `clean+,+report` |
| One stage of a larger pipeline | `model_*` |
| A stage and what it directly feeds | `model_*+1` |
| Everything except the ingest stage | `-ingest_*` |
| The neighbourhood of one target, 2 steps each way | `2+drift_model+2` |
| Two unrelated areas side by side | `ingest_* report` |

## Differences from dbt

The syntax is a subset, adapted to a box rather than command-line flags.

| | dbt | tardoc |
|---|---|---|
| Union | space | space |
| Intersection | comma | comma |
| Exclusion | a separate `--exclude` flag | a leading `-` on a term |
| `+` and depth (`2+x`, `x+2`) | yes | yes |
| `@x` (x, its descendants, and *their* ancestors) | yes | no |
| Selecting by tag, path, resource type, `config.*` | yes | no — names and wildcards only |
| Graph operators between whole selections | yes | no |

A target's *name* is the only thing a selector can see. Grouping by the file a
target is declared in is the [group toggle](viewer.html#sec:grouping-the-graph),
not a selector.

## Behaviour worth knowing

- **Functions are not selected unless they are shown.** With **show functions**
  off, a selector sees targets only; switch it on and functions become valid
  names, and the box is evaluated again.
- **A term that names nothing is reported**, beside the box, rather than
  ignored: `clean nope` shows `clean` and says *no match for nope*.
- **The box is disabled while the graph is grouped**, because a group is
  already a selection.
- **It is evaluated in your browser** against the pipeline as it was when the
  docs were built. Nothing is sent anywhere, and it works from `file://`.
