# SafeRoute — Jac / Jaseci hackathon project

## Environment
- jaclang 0.16.7, byllm 0.6.19, Python 3.12 venv at ~/jacenv
- Run: `jac run <file>.jac`  | Check: `jac check <file>.jac`
- Serve: `jac start` (NOT `jac serve` — removed)
- Config in jac.toml; LLM model set there, not in code

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

## Rules for you
- ALWAYS read ./_jac_examples/ before writing unfamiliar syntax
- ALWAYS run the file and show real output before saying it works
- If syntax fails twice, fall back to a form in VERIFIED WORKING
- Never write LLM prompt strings; use `def f(x: T) -> R by llm();`
- Small files, one concern each. Commit after each green run.
