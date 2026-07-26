"""Match households to the nearest qualifying open shelter by road distance."""

import from schema {
    Junction, Shelter, Depot, Household, Need, Assignment, Hazard,
    Road, LocatedAt, OriginAt, Requires, AssignedTo, ResultedIn
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
    marina = Junction(name="Marina");
    presidio = Junction(name="Presidio");
    fort_mason = Junction(name="FortMason");
    russian_hill = Junction(name="RussianHill");
    cow_hollow = Junction(name="CowHollow");
    pac_heights = Junction(name="PacHeights");
    north_beach = Junction(name="NorthBeach");
    nob_hill = Junction(name="NobHill");

    root ++> marina;
    root ++> presidio;
    root ++> fort_mason;
    root ++> russian_hill;
    root ++> cow_hollow;
    root ++> pac_heights;
    root ++> north_beach;
    root ++> nob_hill;

    marina <+:Road:label="Marina Blvd", distance=0.6:+> cow_hollow;
    marina <+:Road:label="Fort Mason Access", distance=0.7:+> fort_mason;
    marina <+:Road:label="Lincoln Blvd", distance=1.4:+> presidio;
    cow_hollow <+:Road:label="Union St", distance=0.6:+> pac_heights;
    pac_heights <+:Road:label="Broadway", distance=1.0:+> russian_hill;
    russian_hill <+:Road:label="Hyde St", distance=0.5:+> nob_hill;
    russian_hill <+:Road:label="Chestnut/Columbus", distance=0.6:+> north_beach;
    nob_hill <+:Road:label="Powell St", distance=0.6:+> north_beach;
    north_beach <+:Road:label="Bay St", distance=1.3:+> fort_mason;
    presidio <+:Road:label="Lombard St", distance=1.9:+> cow_hollow;

    marina_shelter = Shelter(
        name="Marina Shelter", total_beds=60, occupied=0,
        wheelchair_accessible=False, pets_allowed=True, medical_staff=False
    );
    presidio_shelter = Shelter(
        name="Presidio Shelter", total_beds=120, occupied=0,
        wheelchair_accessible=True, pets_allowed=False, medical_staff=False
    );
    fort_mason_shelter = Shelter(
        name="Fort Mason Shelter", total_beds=20, occupied=0,
        wheelchair_accessible=True, pets_allowed=True, medical_staff=False
    );

    marina +>:LocatedAt:+> marina_shelter;
    presidio +>:LocatedAt:+> presidio_shelter;
    fort_mason +>:LocatedAt:+> fort_mason_shelter;

    # (a) wheelchair + pets -> only FortMason satisfies both. Starts at NobHill.
    hh_a = Household(ref="HH-A", raw_request="wheelchair user with a service dog", size=2);
    hh_a +>:Requires:+> Need(kind="wheelchair");
    hh_a +>:Requires:+> Need(kind="pets");
    hh_a +>:OriginAt:+> nob_hill;

    # (b) pets only -> Marina and FortMason both allow pets, but Marina is closer
    # from CowHollow (0.6mi direct vs 1.3mi to FortMason via Marina).
    hh_b = Household(ref="HH-B", raw_request="family with two dogs", size=3);
    hh_b +>:Requires:+> Need(kind="pets");
    hh_b +>:OriginAt:+> cow_hollow;

    # (c) no special needs -> nearest by distance. From RussianHill, FortMason
    # (1.9mi via NorthBeach) beats Marina (2.2mi) and Presidio (3.5mi).
    hh_c = Household(ref="HH-C", raw_request="single adult, no special needs", size=1);
    hh_c +>:OriginAt:+> russian_hill;

    for hh in [hh_a, hh_b, hh_c] {
        start = [hh ->:OriginAt:->][0];
        start spawn MatchWalker(household=hh);
    }
}
