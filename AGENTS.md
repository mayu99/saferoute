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

## KNOWN BROKEN — never generate these
- `can name with `root entry` → runtime issubclass() crash
  Use untyped `with entry` and seed inside `with entry:__main__`
- `a +>:Road:label="x":+> b` → attributes do not bind,
  raises "missing required positional argument"

## Rules for you
- ALWAYS read ./_jac_examples/ before writing unfamiliar syntax
- ALWAYS run the file and show real output before saying it works
- If syntax fails twice, fall back to a form in VERIFIED WORKING
- Never write LLM prompt strings; use `def f(x: T) -> R by llm();`
- Small files, one concern each. Commit after each green run.
