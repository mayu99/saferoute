# SafeRoute

A disaster-response coordination demo built in [Jac](https://www.jac-lang.org/), modeling a city's roads, shelters, and displaced households as a live graph — and using mobile, graph-traversing computations (**walkers**, Jac's object-spatial programming primitive) to match households to shelters, and to re-route them the moment a road goes down.

## What it does, and why it matters

After a disaster, the two questions that matter most are: *who needs to go where*, and *can they actually get there*. Both are graph questions — "where" is a network of roads and junctions, "who" has requirements (wheelchair access, pets, capacity limits) that only some destinations satisfy, and the network itself is failing in real time as roads close.

SafeRoute models an 8-junction San Francisco road network (Marina, Presidio, Fort Mason, Russian Hill, Cow Hollow, Pac Heights, North Beach, Nob Hill) with three shelters of differing capacity and capabilities, and:

- **Matches** an incoming household to the *nearest shelter that actually satisfies its hard requirements* — not just the nearest shelter, and not just any shelter with a free bed. A wheelchair user doesn't get routed to an inaccessible building because it happened to be closer.
- **Reroutes** automatically when a road closes: every household whose assigned route depended on that road gets a fresh path computed against the *new* topology, freeing their old bed and taking a new one.
- **Serves all of this live** over a REST API with zero authentication required, with a framework-free browser front-end wired directly to it — so the whole scenario (submit a household, close a road, watch it reroute) is watchable in real time, not just in a terminal.

This is a small, complete instance of a pattern that shows up constantly in emergency management, logistics, and network operations software: entities and their relationships *are* a graph, the operations over them *are* traversals, and the state changes *live* under you while you're computing over it.

## Architecture

### Graph schema (`schema.jac`)

| Archetype | Kind | Fields |
|---|---|---|
| `Junction` | node | `name`, `x`, `y` (screen coordinates for the front-end map) |
| `Shelter` | node | `name`, `total_beds`, `occupied`, `wheelchair_accessible`, `pets_allowed`, `medical_staff`, `languages` |
| `Depot` | node | `name`, `cots`, `water_cases`, `med_kits` |
| `Household` | node | `ref`, `raw_request`, `size`, `status` |
| `Need` | node | `kind` (`"wheelchair"`, `"pets"`), `detail`, `severity` |
| `Assignment` | node | `shelter_name`, `route` (list of road labels), `reason`, `stale` |
| `Hazard` | node | `label`, `blocked_roads` |
| `Road` | edge | `label`, `distance`, `status` (`"open"`/`"closed"`) |
| `LocatedAt` | edge | Junction → Shelter/Depot |
| `OriginAt` | edge | Household → Junction (where the household is) |
| `Requires` | edge | Household → Need |
| `ResultedIn` | edge | Household → Assignment |

Every `Road` field has a default (`edge Road { has label: str = ""; has distance: float = 0.0; has status: str = "open"; }`) — a hard requirement in this Jac version for the connect-operator's keyword-attribute binding to work at all (see Engineering Notes). `schema.jac` also exposes two lookup helpers, `find_junctions()` and `find_shelters()`, used everywhere else in the project instead of re-querying the graph by hand.

### Walkers — the object-spatial core

| Walker | File | Role |
|---|---|---|
| `MatchWalker` | `match.jac` | Given a household and a starting junction, runs a real Dijkstra over `Road` edges filtered to `status == "open"`, checking each junction's shelter against the household's hard requirements, and stops at the first (i.e. nearest) one that qualifies and has room. Creates the `Assignment`. |
| `HazardWalker` | `hazard.jac` | Closes every `Road` edge with a given label, then walks every household looking for an `Assignment` whose route used that road and marks it `stale`. |
| `RerouteWalker` | `hazard.jac` | Picks up every stale `Assignment`, frees the old shelter's bed, deletes the stale record, and re-spawns `MatchWalker` (unmodified) against the now-changed topology. |
| `ResetWorld` | `reset.jac` | Wipes households/needs/assignments/hazards, reopens every road, zeroes shelter occupancy — leaves the topology (junctions, roads, shelters, depots) untouched. |
| `ShowGraph` | `seed.jac` | CLI-only: prints the whole graph, grouped correctly by junction. |

`HazardWalker` and `RerouteWalker` import and reuse `MatchWalker` exactly as written for the initial match — rerouting is not a special case in the code, it's the same walker run again against different graph state. This composability (walkers as reusable verbs over a shared graph) is one of the more concrete payoffs of the object-spatial model; see **Built with Jac** below.

### byLLM

The project has [byLLM](https://www.jac-lang.org/) configured (`jac.toml`'s `[plugins.byllm.model]`, currently pointed at `groq/llama-3.3-70b-versatile`) and demonstrates the canonical Jac LLM-function pattern in `llmtest.jac`:

```jac
def summarize(text: str) -> str by llm();
```

**The core matching/routing pipeline deliberately does not call an LLM.** `submit_request`'s need-detection (does this household need wheelchair access or allow pets?) is a plain keyword check on the free-text description — correct, auditable, and instant, which matters more than flexibility for a "does this household get a wheelchair-accessible shelter" decision. `def f(...) -> R by llm();` is the natural extension point if you wanted to replace that keyword check with a real classifier (or add a natural-language dispatcher note generator, an after-action report summarizer, etc.) — the byLLM wiring is proven to work in this project, it's just not on the critical path where a hallucination would mean routing someone wrong.

### `:pub` endpoints (`api.jac`)

Four `walker:pub` walkers, each `POST /walker/<name>` under `jac start`, no authentication required (`:pub` walkers run on a shared anonymous graph — verified with plain `curl`, no `Authorization` header, against the live server):

| Endpoint | Body | Returns |
|---|---|---|
| `submit_request` | `{raw_text, junction_name}` | The new household's assignment (shelter, route, reason) |
| `trigger_hazard` | `{road_label}` | What changed: roads closed, assignments staled, before/after routes for each rerouted household |
| `get_state` | `{}` | The full graph shaped for a front-end: junctions with coordinates, deduplicated roads, shelters with occupancy, households with their current assignment |
| `reset_world` | `{}` | Clean-slate confirmation |

All four call `ensure_seeded()` first, so the server builds its topology on first use — you don't have to run any CLI script before starting it.

### Front-end (`viz/index.html`)

A single static HTML file, no build step, no framework — plain `fetch()` against `API_BASE = "http://localhost:8000"`. `get_state()`'s response is reshaped client-side to what the SVG renderer expects (junction coordinates straight through, a road's list of labels walked into `{from, to}` segments for highlighting). The household form posts to `submit_request`; the fire button posts to `trigger_hazard` and briefly flashes each affected household's old route in red before the rerouted one draws in; Reset posts to `reset_world`. An "Assignments" panel lists every household's short label, description, shelter, distance, and route in plain text, so the routing logic is legible without squinting at the map.

## Setup, from scratch

```bash
# 1. Python 3.12+ and a venv
python3.12 -m venv .venv
source .venv/bin/activate

# 2. Jac itself
pip install jaclang==0.16.7 byllm==0.6.19

# 3. Clone/enter this repo — jac.toml is already configured
cd saferoute
```

That's it for the core demo — it needs no database (the graph persists to a gitignored `.jac/data/` SQLite file, created automatically) and no API key.

**Optional** — only needed if you want to run `llmtest.jac` or wire an LLM into `submit_request` yourself: `jac.toml` points byLLM at `groq/llama-3.3-70b-versatile` and expects a `GROQ_API_KEY` environment variable (`export GROQ_API_KEY=...` or a `.env` file). Without it, everything except `llmtest.jac` works exactly the same — the core pipeline never calls an LLM.

## Running the demo

### Option A — CLI walkthrough

```bash
./demo.sh            # reset -> seed (idempotent) -> match 3 households
./demo.sh --hazard    # ...then close Bay St and reroute whoever was using it
```

Or drive it by hand, one script at a time:

```bash
jac run reset.jac     # clean slate
jac run seed.jac      # build the 8-junction graph (skips if already built)
jac run match.jac     # match 3 sample households
jac run hazard.jac    # close Bay St, reroute the affected households
```

Each script is a normal `.jac` file — `jac check <file>.jac` type-checks any of them independently.

### Option B — Live API + browser

```bash
jac start api.jac --no_client   # note the underscore, not a hyphen — see Engineering Notes
```

This starts a REST API on `http://localhost:8000` (Swagger UI at `/docs`). Then just open `viz/index.html` directly in a browser (double-click it, or `xdg-open viz/index.html` / `open viz/index.html`) — it talks to `localhost:8000` over plain `fetch()`, no build step, no dev server required. If your browser's local-file security settings ever block that, serve the directory instead: `python3 -m http.server 8080 --directory viz` and open `http://localhost:8080/index.html`.

From the page: use the **Add Household** form to submit a free-text request at a chosen junction, click **🔥 Fire closes Bay Street** to trigger a hazard and watch the affected households reroute, and **↺ Reset All** to return to a clean state.

Or drive the same API directly:

```bash
curl -X POST http://localhost:8000/walker/get_state -H "Content-Type: application/json" -d '{}'

curl -X POST http://localhost:8000/walker/submit_request -H "Content-Type: application/json" \
  -d '{"raw_text": "wheelchair user with a service dog", "junction_name": "NobHill"}'

curl -X POST http://localhost:8000/walker/trigger_hazard -H "Content-Type: application/json" \
  -d '{"road_label": "Bay St"}'

curl -X POST http://localhost:8000/walker/reset_world -H "Content-Type: application/json" -d '{}'
```

## Project layout

```
schema.jac    Node/edge archetypes + find_junctions()/find_shelters() helpers
seed.jac      Idempotent graph builder (ensure_seeded()) + ShowGraph CLI walker
match.jac     MatchWalker — the Dijkstra-based nearest-qualifying-shelter search
hazard.jac    HazardWalker + RerouteWalker — close a road, reroute the affected
reset.jac     ResetWorld — clean dynamic state, keep the topology
api.jac       Four walker:pub REST endpoints for `jac start`
demo.sh       reset -> seed -> match [-> hazard], one command
viz/index.html  Framework-free front-end wired to the live API
jac.toml      Project config: byLLM plugin + model
CLAUDE.md     Working notes on this Jac version's verified/broken syntax
```

## Built with Jac — why object-spatial programming fits this problem

Object-spatial programming (OSP) inverts the usual relationship between data and computation: instead of pulling rows out of a store and looping over them, you send a mobile unit of computation (a **walker**) *into* a persistent graph, and it moves through the graph the way the thing it's modeling actually moves.

That fits emergency coordination specifically, not just incidentally:

- **The domain already is a graph.** Roads connect junctions; shelters sit at junctions; households need a path along roads to reach one. Modeling that as rows in tables (a `roads` table, a `shelters` table, joined by foreign keys) requires reconstructing the graph structure at query time, every time. In Jac it's already there — `[cur ->:Road:status == "open":->]` *is* "this junction's open roads," not a join.
- **Walkers mirror the real operation.** "Find the nearest shelter this household can actually use" is a search that moves outward from a starting point, checking a stopping condition at each place it reaches. `MatchWalker` does exactly that — it's a dispatcher, not a query. The code reads like the operational reasoning a human coordinator would do.
- **Reuse by spawning, not by rewriting.** `RerouteWalker` doesn't reimplement matching — it deletes the stale `Assignment` and spawns the *same* `MatchWalker` again. A new scenario (a new hazard type, a new resource category) is a new small walker that spawns existing ones, not a rewrite of a monolithic matching function. That composability held up in practice across three rounds of feature work in this project without ever touching `MatchWalker`'s internals.
- **The graph is live and shared.** The state genuinely mutates while you're working with it — a road closes mid-demo, a bed fills up — and OSP's model (persistent nodes/edges you read and write in place, walkers you spawn on demand) matches that directly. There's no "recompute the whole report" step; `trigger_hazard` mutates exactly the edges and nodes affected and nothing else.
- **It's also unforgiving in a way that matters here.** A silently-wrong nearest-shelter search is not an acceptable failure mode for software that's deciding where a wheelchair user gets sent. Getting real value from OSP meant taking its traversal semantics — reachability, queue order, query alignment — as seriously as the domain logic itself. The three bugs below are the direct result of that: each one would have produced a plausible-looking, silently wrong answer if it had shipped.

## Engineering notes: three correctness bugs found building this

These were all found empirically — reproduced in isolation, fixed, and re-verified against the live system — not caught by any type checker. Full write-ups with minimal repros live in `CLAUDE.md`; summarized here because each is a genuine Jac/OSP-specific gotcha, not a generic programming mistake.

### 1. Root-reachability silently drops edges on indirect reference

A node not directly reachable via forward traversal from `root` loses **some** of its edges when queried through an indirect reference (a walker's `has` field, e.g. `self.household`) from an ability running on a *different* node — as opposed to querying it as a local variable in the scope where it was created, or as the walker's own `here`.

**Symptom:** `MatchWalker`'s hard-requirement filtering (wheelchair, pets) silently stopped working. `self.household ->:Requires:->` returned `[]` even though the `Need` edges were definitely there — no error, no warning. The walker fell back to "nearest available shelter," which often happened to equal "nearest qualifying shelter" for the original test layout, so the bug hid behind coincidentally-correct output until a test case was picked where the two diverge.

**Root cause:** households were attached to the graph only via `Household +>:OriginAt:+> Junction` — never directly to `root`. `Household` itself was therefore not root-reachable, and once a *different* walker ability (running on a `Junction`, referencing the household only through `self.household`) tried to read its edges, the query silently came back empty.

**Fix:** attach every household directly under `root` (`root ++> hh;`) *in addition to* its `OriginAt` edge. Rule of thumb adopted project-wide: any node whose edges will be queried from more than one hop away, or through a stored field rather than direct traversal, gets attached under `root` too.

### 2. `visit`'s hop-order queue vs. distance-order search

`visit`'s traversal queue is FIFO by **hop count**, not by cumulative edge weight. If two neighbors are discovered from the same node at the same hop — e.g. Marina (0.6mi) and Presidio (1.9mi), both one hop from Cow Hollow — whichever happens to be enqueued/dequeued first "wins" as the first-found match, regardless of which is actually closer.

**Symptom:** the same reroute scenario (Bay St closed, a household searching from Russian Hill) returned Presidio at 3.5mi on one run and Marina at 2.2mi — the genuinely correct answer — on another. Non-deterministic, because "hop order" happened to depend on internal edge storage order, which shifted after a delete-and-recreate cycle.

**Root cause:** the original `MatchWalker` drove its search with `visit`, relying on BFS hop order as a proxy for "nearest." That proxy holds only when hop count and cumulative distance happen to agree — true for the original three test households, false in general, and false for this specific reroute case.

**Fix:** rewrote `MatchWalker` to run a real Dijkstra — a `while` loop that always pops the global minimum-distance *unvisited* node from a `dist` dict — entirely inside one ability call, not driven by `visit` at all. If you need "nearest by weighted distance" in Jac, don't let `visit`'s queue decide search order; compute it explicitly.

### 3. `zip()` on two unfiltered parallel edge/node queries isn't reliably aligned

Reading an edge's target node in Jac requires two side-by-side queries zipped together (there's no single query that returns edge-and-target pairs directly): `edges = [edge j ->:Road:->]; nodes = [j ->:Road:->]; zip(edges, nodes)`. This pair is **not reliably order-aligned when unfiltered** — but the identical pattern **with an equality predicate** on the edge (`status == "open"`) **is** reliably aligned.

**Symptom:** `get_state()`'s road list (built with the unfiltered form, since it needs both open and closed roads) occasionally paired a road label with the wrong neighboring junction — e.g. "Chestnut/Columbus" reported as connecting to Nob Hill instead of North Beach. Confirmed with an A/B probe added temporarily as a debug endpoint: the unfiltered pair silently swapped which node two same-length edges corresponded to, while the same two edges queried with `status == "open"` paired correctly.

**Root cause:** `MatchWalker`'s Dijkstra always used the filtered form already (it only ever needs open roads), so it was never affected. `get_state()` was the one place that needed *all* roads regardless of status, and used the unfiltered form to get them — which turned out to be the one pattern that isn't guaranteed to align.

**Fix:** query `status == "open"` and `status == "closed"` as two separate filtered passes and merge the results, instead of one unfiltered pair. Rule of thumb: never `zip()` two side-by-side node/edge queries unless both carry the same equality-style predicate; if you need "no filter," iterate every literal value the field can take instead of dropping the predicate entirely.
