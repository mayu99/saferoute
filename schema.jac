"""SafeRoute graph schema: nodes and edges for the disaster-response graph."""

node Junction {
    has name: str;
}

node Shelter {
    has name: str;
    has total_beds: int;
    has occupied: int = 0;
    has wheelchair_accessible: bool = False;
    has pets_allowed: bool = False;
    has medical_staff: bool = False;
    has languages: list = [];
}

node Depot {
    has name: str;
    has cots: int = 0;
    has water_cases: int = 0;
    has med_kits: int = 0;
}

node Household {
    has ref: str;
    has raw_request: str;
    has size: int = 1;
    has status: str = "waiting";
}

node Need {
    has kind: str;
    has detail: str = "";
    has severity: int = 1;
}

node Assignment {
    has shelter_name: str;
    has route: list = [];
    has reason: str = "";
    has stale: bool = False;
}

node Hazard {
    has label: str;
    has blocked_roads: list = [];
}

edge Road {
    has label: str = "";
    has distance: float = 0.0;
    has status: str = "open";
}

edge LocatedAt {}

edge OriginAt {}

edge Requires {}

edge AssignedTo {}

edge ResultedIn {}

def find_junctions() -> dict[str, Junction] {
    found: dict[str, Junction] = {};
    for n in [root -->] {
        if isinstance(n, Junction) {
            found[n.name] = n;
        }
    }
    return found;
}

def find_shelters() -> dict[str, Shelter] {
    found: dict[str, Shelter] = {};
    for j in [root -->] {
        if isinstance(j, Junction) {
            for n in [j ->:LocatedAt:->] {
                if isinstance(n, Shelter) {
                    found[n.name] = n;
                }
            }
        }
    }
    return found;
}
