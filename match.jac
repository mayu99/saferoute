"""Match households to the nearest qualifying open shelter by road distance."""

import from schema {
    Junction, Shelter, Depot, Household, Need, Assignment, Hazard,
    Road, LocatedAt, OriginAt, Requires, AssignedTo, ResultedIn,
    find_junctions
}

walker MatchWalker {
    has household: Household;

    # A true Dijkstra, run entirely inside this one ability call — deliberately
    # NOT driven by `visit`/multiple ability firings. jac's `visit` queue is
    # FIFO by hop count, not by cumulative distance: when two neighbors are
    # discovered from the same node at the same hop (e.g. Marina at 0.6mi and
    # Presidio at 1.9mi, both reachable from CowHollow), whichever happens to
    # be dequeued first would "win" even if it's farther. Always popping the
    # global minimum-distance unvisited node avoids that entirely.
    can search with Junction entry {
        needs_wheelchair = False;
        needs_pets = False;
        for n in [self.household ->:Requires:->] {
            if n.kind == "wheelchair" {
                needs_wheelchair = True;
            }
            if n.kind == "pets" {
                needs_pets = True;
            }
        }

        start_key = jid(here);
        dist: dict[str, float] = {start_key: 0.0};
        path: dict[str, list] = {start_key: []};
        node_by_id: dict = {start_key: here};
        visited: dict[str, bool] = {};
        found = False;

        while not found {
            best_key = "";
            best_dist = -1.0;
            for k in dist.keys() {
                if k not in visited {
                    if best_dist < 0 or dist[k] < best_dist {
                        best_dist = dist[k];
                        best_key = k;
                    }
                }
            }
            if best_key == "" {
                print(f"{self.household.ref}: no qualifying shelter reachable.");
                break;
            }
            visited[best_key] = True;
            cur = node_by_id[best_key];
            d = dist[best_key];
            p = path[best_key];

            for s in [cur ->:LocatedAt:->] {
                if isinstance(s, Shelter) {
                    if needs_wheelchair and not s.wheelchair_accessible {
                        continue;
                    }
                    if needs_pets and not s.pets_allowed {
                        continue;
                    }
                    if s.occupied >= s.total_beds {
                        continue;
                    }
                    s.occupied = s.occupied + 1;
                    reason = (
                        "Nearest open-road shelter meeting hard requirements "
                        f"(wheelchair={needs_wheelchair}, pets={needs_pets}): "
                        f"{d}mi over {len(p)} road(s)."
                    );
                    assignment = Assignment(shelter_name=s.name, route=p, reason=reason);
                    self.household +>:ResultedIn:+> assignment;
                    print(
                        f"{self.household.ref} -> {s.name} "
                        f"(distance={d}mi, route={p})"
                    );
                    found = True;
                }
            }

            if not found {
                edges = [edge cur ->:Road:status == "open":->];
                nodes = [cur ->:Road:status == "open":->];
                for (e, n) in zip(edges, nodes) {
                    nk = jid(n);
                    nd = d + e.distance;
                    if nk not in dist or nd < dist[nk] {
                        dist[nk] = nd;
                        path[nk] = p + [e.label];
                        node_by_id[nk] = n;
                    }
                }
            }
        }
    }
}

with entry:__main__ {
    city = find_junctions();
    if len(city) == 0 {
        print("ERROR: graph not seeded. Run seed.jac first.");
    } else {
        nob_hill = city["NobHill"];
        cow_hollow = city["CowHollow"];
        russian_hill = city["RussianHill"];

        # Households must be directly root-reachable (not just via OriginAt to
        # their junction) — otherwise a node referenced through a walker's `has`
        # field (self.household), rather than visited as `here`, silently fails
        # to resolve some of its non-traversal-path edges. See CLAUDE.md.

        # (a) wheelchair + pets -> only FortMason satisfies both. Starts at NobHill.
        hh_a = Household(ref="HH-A", raw_request="wheelchair user with a service dog", size=2);
        root ++> hh_a;
        hh_a +>:Requires:+> Need(kind="wheelchair");
        hh_a +>:Requires:+> Need(kind="pets");
        hh_a +>:OriginAt:+> nob_hill;

        # (b) pets only -> Marina and FortMason both allow pets, but Marina is closer
        # from CowHollow (0.6mi direct vs 1.3mi to FortMason via Marina).
        hh_b = Household(ref="HH-B", raw_request="family with two dogs", size=3);
        root ++> hh_b;
        hh_b +>:Requires:+> Need(kind="pets");
        hh_b +>:OriginAt:+> cow_hollow;

        # (c) no special needs -> nearest by distance. From RussianHill, FortMason
        # (1.9mi via NorthBeach) beats Marina (2.2mi) and Presidio (3.5mi).
        hh_c = Household(ref="HH-C", raw_request="single adult, no special needs", size=1);
        root ++> hh_c;
        hh_c +>:OriginAt:+> russian_hill;

        for hh in [hh_a, hh_b, hh_c] {
            start = [hh ->:OriginAt:->][0];
            start spawn MatchWalker(household=hh);
        }
    }
}
