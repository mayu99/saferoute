# SafeRoute — Jac / Jaseci hackathon project

## Environment
- jaclang 0.16.7, byllm 0.6.19, Python 3.12 venv at ~/jacenv
- Run: `jac run <file>.jac`  | Check: `jac check <file>.jac`
- Serve: `jac start` (NOT `jac serve` — removed)
- Config in jac.toml; LLM model set there, not in code
- Demo files: `schema.jac` (archetypes + `find_junctions()` /
  `find_shelters()` helpers), `seed.jac` (idempotent — builds the
  8-junction SF graph only if not already there), `match.jac` (demo
  scenario: 3 households matched to shelters via `MatchWalker`),
  `reset.jac` (wipes households/needs/assignments/hazards, resets
  shelter occupancy and road status, keeps topology), `hazard.jac`
  (closes a named road, marks affected Assignments stale, reroutes
  them via `RerouteWalker` — imports and reuses `MatchWalker`
  unchanged). Run the whole cycle with `./demo.sh` (reset -> seed ->
  match) or `./demo.sh --hazard` (+ close Bay St -> reroute) to get
  back to a known state before rehearsing — safe to re-run any
  number of times.

## VERIFIED WORKING on 0.16.7 (do not change these forms)
- `node X { has field: str; }` / `edge Y { has f: str = "d"; }`
- `walker W { can name with NodeType entry { ... } }`  — typed entry,
  fires correctly on every node of that type the walker visits,
  including across multiple `visit` hops and mixed node types
  (one `can ... with TypeA entry` + one `can ... with TypeB entry`
  in the same walker chains fine).
- `a ++> b;`  plain connect
- `visit [-->];`  untyped traversal (queuing works; see BROKEN below
  for why the *ability* still needs to be typed)
- `with entry:__main__ { ... }`  entry block
- f-strings, `here`, `root`, `spawn`
- Typed edge with bound attrs: `a +>:Road:label="x", status="y":+> b;`
  — **every `has` field on the edge archetype must have a default**
  (`edge Road { has label: str = ""; has status: str = "open"; }`).
  Without a default on ALL fields, you get
  `Road.__init__() missing 1 required positional argument: 'label'`
  even though the connect syntax itself is correct.
- Typed traversal filter: `visit [->:Road:status == "open":->];`
- Reading bound edge attrs (not just nodes): prefix with `edge` —
  `edges = [edge here ->:Road:status == "open":->];` then `e.label`.
  Plain `[->:Road:...:->]` (no `edge` prefix) returns the target
  nodes, not edge objects.
- Reverse-direction lookup (who points at me): `[here <-:Edge:<-]`
  — put the node first, then the reversed arrows.
- Bidirectional typed connect: `a <+:Road:label="x":+> b;` creates
  a real traversable edge both ways (confirmed at runtime, not just
  a formatter fixture).
- Tuple-unpacking for loop: `for (e, n) in zip(edges, nodes) { ... }`
  — the parens around `(e, n)` are required; `for e, n in zip(...)`
  is a parse error ("Expected 'in', got ','").
- `continue;` / `disengage;` / bare `return;` all work inside walker
  abilities exactly like Python/the fixtures show.
- A walker `has` field typed to a custom node archetype (no default),
  e.g. `has household: Household;`, works fine when the walker is
  always constructed with an explicit keyword arg:
  `start spawn MatchWalker(household=hh);`. The "every field needs a
  default" rule is specific to **edges** bound via the connect
  operator, not walker construction.
- Printing/using a node's related neighbors (e.g. shelters attached
  to a junction) should be done with a **query**, not a `visit` hop,
  when order/grouping matters: `for n in [here ->:LocatedAt:->] { ... }`
  runs synchronously inside the current ability, so output stays
  grouped under the right node. Doing it by giving Shelter/Depot their
  own typed `with entry` ability and letting the walker `visit` into
  them prints in BFS-dequeue order instead, which reads as attached to
  whatever junction happened to be dequeued near it — looked like a
  wiring bug, wasn't (see `seed.jac` ShowGraph history).
- `dict[str, float]` / `dict[str, list]` on `has` fields (instead of
  bare `dict`) is needed for `jac check` to type-check `.get()`
  results cleanly downstream (e.g. passing into `len()` or into a
  `list`-typed node field) — `jac run` works either way, but `jac
  check` throws `E1053: Cannot assign <any> to parameter ...`.
- `del node_ref;` (or `del here;`) deletes a node **and its own incident
  edges only** — it does NOT cascade to nodes on the far end of those
  edges. Deleting a Household does not delete its Need/Assignment
  children; you must `del` each of those explicitly too, or they
  become permanent orphaned garbage in the anchor store (still
  resolvable by jid, just unreachable).
- Mutating an edge attribute (`e.status = "closed";`) persists across
  separate `jac run` invocations exactly like node attribute mutation.
- Walker archetypes import across files like any other archetype:
  `import from match { MatchWalker }` then spawn it normally. A
  module's `with entry:__main__ { ... }` block behaves exactly like
  Python's `if __name__ == "__main__":` guard — it does NOT re-run
  when the file is imported rather than being the one passed to
  `jac run`. Confirmed: importing a file whose entry block prints
  something produces no output unless that file is the one directly
  run.
- `while cond { ... }` and `dict.keys()` both work exactly like
  Python — useful for writing a real Dijkstra inside a single
  ability call instead of relying on `visit` for traversal order
  (see BROKEN below for why that matters).
- Node lookup by name pattern for idempotent scripts:
  `def find_junctions() -> dict[str, Junction] { found: dict[str,
  Junction] = {}; for n in [root -->] { if isinstance(n, Junction) {
  found[n.name] = n; } } return found; }` — check `len(found) > 0`
  before rebuilding a graph so re-running a seed script doesn't
  duplicate the topology.
- `.jac/` (cache + `data/anchor_store.db`) is gitignored, disposable,
  and **persists the object graph under `root` across separate
  `jac run` invocations in the same directory**. If you rename/move
  a node or edge archetype between runs (e.g. moving `Junction` from
  a script into an imported module), old anchors saved under the
  previous class path become unresolvable ("Refused to deserialize
  unregistered class", "quarantined"). `rm -rf .jac/data` before a
  fresh run whenever archetypes moved or renamed, or when a
  multi-run script should start from an empty graph each time.

## KNOWN BROKEN — never generate these
- `can name with `root entry` → runtime issubclass() crash
  Use untyped `with entry` and seed inside `with entry:__main__`
- Edge archetype with any `has` field lacking a default, then
  connecting with keyword attrs on that field → same
  "missing required positional argument" crash as above.
- `walker W { can name with entry { ... visit [-->]; } }` (UNTYPED
  entry ability) fires once for the walker's starting node, then
  silently stops — it does NOT re-fire as the walker hops to
  further nodes via `visit`, even though the same untyped `-->`
  query does queue them. No error, no crash — the walker just runs
  0 more abilities and returns. Confirmed with minimal repro
  (single node type, single edge type): typed `with J entry` visits
  every hop; untyped `with entry` visits only the first node.
  Always give a graph-walking walker one typed `can ... with
  SomeNodeType entry` ability per node type it needs to handle,
  never a catch-all untyped one with isinstance branches.
- **A node not directly reachable via forward traversal from `root`
  silently loses SOME of its edges when queried through an indirect
  reference** (e.g. a walker's `has some_node: SomeType;` field —
  `self.some_node`) from an ability running on a *different* node,
  as opposed to querying it as a local variable in the same scope
  where it was created, or as the walker's own `here`. Confirmed
  minimal repro: a node with two outgoing edge types, connected to
  the graph ONLY via one of those edge types (never `root ++> node;`
  directly) — querying the edge type that does NOT lead toward the
  walker's current traversal region returns an empty list from
  inside a different ability, even though the exact same query
  returns correctly if run in the entry block right after creation,
  or if the node IS root-reachable. No error, no warning — it just
  silently returns `[]`, which reads as "this household has no
  needs" instead of a bug. This is why match.jac's households do
  `root ++> hh;` in addition to `hh +>:OriginAt:+> junction;` — drop
  the direct root attachment and hard-requirement filtering silently
  stops working while everything still runs and looks fine (it just
  falls back to "nearest available," which often coincidentally
  matches the "nearest qualifying" answer, so pick test starting
  points that make the two diverge if you want a test to actually
  catch a filtering regression). Rule of thumb: any node whose edges
  a walker will query from more than one hop away, or through a
  stored field rather than direct traversal, should be attached
  under `root` too.
- **`visit`'s queue is FIFO by hop count, not by cumulative distance
  — do not use it to drive a "find the nearest X" search over a
  weighted graph.** If two neighbors are discovered from the same
  node at the same hop (e.g. from CowHollow, Marina at 0.6mi and
  Presidio at 1.9mi are both one hop away), whichever gets
  enqueued/dequeued first "wins" as the first-found qualifying
  match, regardless of which one is actually closer. This is
  invisible in a lot of test cases because "nearest by hop count"
  and "nearest by distance" often coincide, and it doesn't error —
  it just silently returns a farther shelter sometimes, depending on
  internal edge storage order (which can differ between runs of the
  identical script, e.g. after a delete+recreate cycle). Caught it
  via `hazard.jac`'s reroute: with Bay St closed, the same
  household's nearest-shelter search returned Presidio (3.5mi) on
  one run and Marina (2.2mi, the actually-correct answer) on
  another. Fixed by rewriting `MatchWalker` to run a real Dijkstra —
  a `while` loop that always pops the global minimum-distance
  *unvisited* node from a `dist` dict — entirely inside one ability
  call, not spread across multiple `visit`-triggered firings. If you
  need "nearest by weighted distance," don't use `visit` for the
  search order at all; only use it (or skip it entirely, as here) —
  do the whole search with plain queries/dicts in one ability.

## Rules for you
- ALWAYS read ./_jac_examples/ before writing unfamiliar syntax
- ALWAYS run the file and show real output before saying it works
- If syntax fails twice, fall back to a form in VERIFIED WORKING
- Never write LLM prompt strings; use `def f(x: T) -> R by llm();`
- Small files, one concern each. Commit after each green run.
