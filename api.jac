"""SafeRoute REST API for `jac start` — public (:pub, no-auth) walkers.

Run:   jac start api.jac --no_client
Docs:  http://localhost:8000/docs

Endpoints (all POST /walker/<name>, JSON body maps onto `has` fields):
  submit_request(raw_text, junction_name)  -> household + assignment
  trigger_hazard(road_label)               -> what changed (staled + rerouted)
  get_state()                              -> full graph, shaped for a front-end
  reset_world()                            -> clean slate (re-seeds if needed)

All four self-seed via ensure_seeded() (imported from seed.jac), so calling
any endpoint on a brand-new server (or right after reset_world) works without
first running the CLI scripts.
"""

import from schema {
    Junction, Shelter, Depot, Household, Need, Assignment, Hazard,
    Road, LocatedAt, OriginAt, Requires, AssignedTo, ResultedIn,
    find_junctions, find_shelters
}
import from seed { ensure_seeded }
import from match { MatchWalker }
import from hazard { HazardWalker, RerouteWalker }
import from reset { ResetWorld }
import from intake { intake }

walker:pub submit_request {
    has raw_text: str;
    has junction_name: str;

    can run with Root entry {
        city = ensure_seeded();
        if self.junction_name not in city {
            report {"ok": False, "error": f"Unknown junction: {self.junction_name}"};
            disengage;
        }
        junction: Junction = city[self.junction_name];

        hh = Household(ref="pending", raw_request=self.raw_text);
        root ++> hh;
        hh.ref = f"HH-{jid(hh)[0:8]}";

        # LLM-based intake with an automatic keyword-detection fallback if
        # the LLM call fails or times out — see intake.jac. Never raises.
        intake_result = intake(hh, self.raw_text);
        needs = intake_result["needs"];
        hh +>:OriginAt:+> junction;

        junction spawn MatchWalker(household=hh);

        assignments = [hh ->:ResultedIn:->];
        if len(assignments) > 0 {
            a = assignments[0];
            report {
                "ok": True,
                "household_ref": hh.ref,
                "junction": self.junction_name,
                "needs": needs,
                "parse_method": intake_result["parse_method"],
                "shelter_name": a.shelter_name,
                "route": a.route,
                "reason": a.reason,
            };
        } else {
            report {
                "ok": True,
                "household_ref": hh.ref,
                "junction": self.junction_name,
                "needs": needs,
                "parse_method": intake_result["parse_method"],
                "shelter_name": None,
                "route": [],
                "reason": "No qualifying shelter reachable.",
            };
        }
    }
}

walker:pub trigger_hazard {
    has road_label: str;

    can run with Root entry {
        ensure_seeded();

        hazard_result = root spawn HazardWalker(road_label=self.road_label);
        reroute_result = root spawn RerouteWalker();

        report {
            "ok": True,
            "road_label": self.road_label,
            "roads_closed": hazard_result.closed_count,
            "assignments_staled": hazard_result.staled_count,
            "staled": hazard_result.staled,
            "rerouted": reroute_result.changes,
        };
    }
}

walker:pub get_state {
    can run with Root entry {
        city = ensure_seeded();

        junctions: list = [];
        roads: list = [];
        seen_roads: dict[str, bool] = {};

        for j in city.values() {
            shelter_view = None;
            for n in [j ->:LocatedAt:->] {
                if isinstance(n, Shelter) {
                    shelter_view = {
                        "name": n.name,
                        "total_beds": n.total_beds,
                        "occupied": n.occupied,
                        "wheelchair_accessible": n.wheelchair_accessible,
                        "pets_allowed": n.pets_allowed,
                        "medical_staff": n.medical_staff,
                    };
                }
            }
            junctions.append({
                "name": j.name, "x": j.x, "y": j.y, "shelter": shelter_view,
            });

            # Two filtered queries per status value, NOT one unfiltered pair —
            # `zip([edge j ->:Road:->], [j ->:Road:->])` (no predicate) is NOT
            # reliably aligned (verified: it silently swapped which node two
            # same-length edges paired with). The equality-filtered form
            # (`status == "..."`) IS reliably aligned — the same form
            # MatchWalker's Dijkstra already relies on. See CLAUDE.md.
            for status_value in ["open", "closed"] {
                edges = [edge j ->:Road:status == status_value:->];
                nodes = [j ->:Road:status == status_value:->];
                for (e, n) in zip(edges, nodes) {
                    ek = jid(e);
                    if ek not in seen_roads {
                        seen_roads[ek] = True;
                        roads.append({
                            "from": j.name, "to": n.name,
                            "label": e.label, "distance": e.distance, "status": e.status,
                        });
                    }
                }
            }
        }

        households: list = [];
        for hh in [root -->] {
            if isinstance(hh, Household) {
                needs: list = [];
                for n in [hh ->:Requires:->] {
                    needs.append(n.kind);
                }
                origin = [hh ->:OriginAt:->];
                junction_name = origin[0].name if len(origin) > 0 else None;

                assignments = [hh ->:ResultedIn:->];
                assignment_view = None;
                if len(assignments) > 0 {
                    a = assignments[0];
                    assignment_view = {
                        "shelter_name": a.shelter_name, "route": a.route,
                        "reason": a.reason, "stale": a.stale,
                    };
                }
                households.append({
                    "ref": hh.ref, "raw_request": hh.raw_request,
                    "junction": junction_name, "needs": needs,
                    "assignment": assignment_view,
                });
            }
        }

        report {"junctions": junctions, "roads": roads, "households": households};
    }
}

walker:pub reset_world {
    can run with Root entry {
        root spawn ResetWorld();
        ensure_seeded();
        report {"ok": True, "message": "World reset: households/needs/assignments/hazards cleared, shelters emptied, roads reopened."};
    }
}
