"""Close a road and reroute households whose assignments depended on it.

HazardWalker takes a road label, closes every Road edge with that label
(checked from both endpoint junctions, so both directions are covered
regardless of how the bidirectional connect is represented internally),
then walks every root-attached Household looking for an Assignment whose
route used that road, marking it stale=True.

RerouteWalker then walks every root-attached Household, and for each
stale Assignment: frees up the old shelter's bed, prints the old
assignment for the demo record, deletes it, and re-spawns MatchWalker
(imported from match.jac, unmodified) to find a fresh route against the
now-closed-road topology.
"""

import from schema {
    Junction, Shelter, Depot, Household, Need, Assignment, Hazard,
    Road, LocatedAt, OriginAt, Requires, AssignedTo, ResultedIn,
    find_junctions, find_shelters
}
import from match { MatchWalker }

walker HazardWalker {
    has road_label: str;
    has closed_count: int = 0;
    has staled_count: int = 0;

    can start with Root entry {
        visit [-->];
    }

    can close_roads with Junction entry {
        for e in [edge here ->:Road:->] {
            if e.label == self.road_label {
                e.status = "closed";
                self.closed_count = self.closed_count + 1;
            }
        }
    }

    can mark_stale with Household entry {
        for a in [here ->:ResultedIn:->] {
            if self.road_label in a.route and not a.stale {
                a.stale = True;
                self.staled_count = self.staled_count + 1;
                print(
                    f"STALE: {here.ref}'s assignment to {a.shelter_name} "
                    f"used '{self.road_label}' (route={a.route}) — marked for reroute."
                );
            }
        }
    }
}

walker RerouteWalker {
    has rerouted_count: int = 0;

    can start with Root entry {
        visit [-->];
    }

    can reroute with Household entry {
        assignments = [here ->:ResultedIn:->];
        for a in assignments {
            if a.stale {
                old_shelter_name = a.shelter_name;
                old_route = a.route;

                shelters: dict[str, Shelter] = find_shelters();
                key: str = str(old_shelter_name);
                if key in shelters {
                    old_shelter: Shelter = shelters[key];
                    old_shelter.occupied = old_shelter.occupied - 1;
                }

                print(f"REROUTE: {here.ref} was at {old_shelter_name} via {old_route}");
                del a;

                start = [here ->:OriginAt:->][0];
                start spawn MatchWalker(household=here);
                self.rerouted_count = self.rerouted_count + 1;
            }
        }
    }
}

with entry:__main__ {
    ROAD_LABEL = "Bay St";

    print(f"== Closing road: {ROAD_LABEL} ==");
    root spawn HazardWalker(road_label=ROAD_LABEL);

    print(f"== Rerouting households affected by: {ROAD_LABEL} ==");
    root spawn RerouteWalker();
}
