# SafeRoute — Jac / Jaseci hackathon project

## Environment
- jaclang 0.16.7, byllm 0.6.19, Python 3.12 venv at ~/jacenv
- Run: `jac run <file>.jac`  | Check: `jac check <file>.jac`
- Serve: `jac start` (NOT `jac serve` — removed)
- Config in jac.toml; LLM model set there, not in code

## VERIFIED WORKING on 0.16.7 (do not change these forms)
- `node X { has field: str; }` / `edge Y { has f: str = "d"; }`
- `walker W { can name with entry { ... } }`      # untyped
- `walker W { can name with NodeType entry { ... } }`
- `a ++> b;`  plain connect
- `visit [-->];`  untyped traversal
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

## KNOWN BROKEN — never generate these
- `can name with `root entry` → runtime issubclass() crash
  Use untyped `with entry` and seed inside `with entry:__main__`
- Edge archetype with any `has` field lacking a default, then
  connecting with keyword attrs on that field → same
  "missing required positional argument" crash as above.

## Rules for you
- ALWAYS read ./_jac_examples/ before writing unfamiliar syntax
- ALWAYS run the file and show real output before saying it works
- If syntax fails twice, fall back to a form in VERIFIED WORKING
- Never write LLM prompt strings; use `def f(x: T) -> R by llm();`
- Small files, one concern each. Commit after each green run.
