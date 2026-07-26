"""Match households to the nearest qualifying open shelter by road distance."""

import from schema {
    Junction, Shelter, Depot, Household, Need, Assignment, Hazard,
    Road, LocatedAt, OriginAt, Requires, AssignedTo, ResultedIn,
    find_junctions
}

walker MatchWalker {
    has household: Household;
    has needs_wheelchair: bool = False;
    has needs_pets: bool = False;
    has initialized: bool = False;
    has seen: dict[str, bool] = {};
    has dist: dict[str, float] = {};
    has path: dict[str, list] = {};

    can search with Junction entry {
        if not self.initialized {
            self.initialized = True;
            for n in [self.household ->:Requires:->] {
                if n.kind == "wheelchair" {
                    self.needs_wheelchair = True;
                }
                if n.kind == "pets" {
                    self.needs_pets = True;
                }
            }
            self.dist[jid(here)] = 0.0;
            self.path[jid(here)] = [];
        }

        key = jid(here);
        if key in self.seen {
            return;
        }
        self.seen[key] = True;
        d = self.dist.get(key, 0.0);
        p = self.path.get(key, []);

        for s in [here ->:LocatedAt:->] {
            if isinstance(s, Shelter) {
                if self.needs_wheelchair and not s.wheelchair_accessible {
                    continue;
                }
                if self.needs_pets and not s.pets_allowed {
                    continue;
                }
                if s.occupied >= s.total_beds {
                    continue;
                }
                s.occupied = s.occupied + 1;
                reason = (
                    "Nearest open-road shelter meeting hard requirements "
                    f"(wheelchair={self.needs_wheelchair}, pets={self.needs_pets}): "
                    f"{d}mi over {len(p)} road(s)."
                );
                assignment = Assignment(shelter_name=s.name, route=p, reason=reason);
                self.household +>:ResultedIn:+> assignment;
                print(
                    f"{self.household.ref} -> {s.name} "
                    f"(distance={d}mi, route={p})"
                );
                disengage;
            }
        }

        edges = [edge here ->:Road:status == "open":->];
        nodes = [here ->:Road:status == "open":->];
        for (e, n) in zip(edges, nodes) {
            nk = jid(n);
            nd = d + e.distance;
            if nk not in self.dist or nd < self.dist[nk] {
                self.dist[nk] = nd;
                self.path[nk] = p + [e.label];
            }
        }
        visit nodes;
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
