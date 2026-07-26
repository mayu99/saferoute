"""Reset the SafeRoute world to a clean demo-ready state.

Wipes all Household, Need, and Assignment nodes (and any Hazard nodes
attached directly to root), resets every Shelter's occupied count to 0,
and reopens every Road. Junctions, Depots, and the road topology itself
are left untouched.

Convention assumed for future hazard-injection scripts: a Hazard node is
attached directly under root (`root ++> hazard;`), since it's a
world-level fact rather than something owned by one Junction.
"""

import from schema {
    Junction, Shelter, Depot, Household, Need, Assignment, Hazard,
    Road, LocatedAt, OriginAt, Requires, AssignedTo, ResultedIn
}

walker ResetWorld {
    has seen: dict[str, bool] = {};

    can reset_root with Root entry {
        visit [-->];
    }

    can reset_junction with Junction entry {
        key = jid(here);
        if key in self.seen {
            return;
        }
        self.seen[key] = True;

        for e in [edge here ->:Road:->] {
            e.status = "open";
        }

        for n in [here ->:LocatedAt:->] {
            if isinstance(n, Shelter) {
                n.occupied = 0;
            }
        }

        for hh in [here <-:OriginAt:<-] {
            for need in [hh ->:Requires:->] {
                del need;
            }
            for asg in [hh ->:ResultedIn:->] {
                del asg;
            }
            del hh;
        }

        visit [->:Road:->];
    }

    can reset_hazard with Hazard entry {
        del here;
    }
}

with entry:__main__ {
    root spawn ResetWorld();
    print("World reset: households/needs/assignments/hazards cleared, shelters emptied, roads reopened.");
}
