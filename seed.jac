"""Seed the SafeRoute graph: SF junctions, roads, shelters, and depots."""

import from schema {
    Junction, Shelter, Depot, Household, Need, Assignment, Hazard,
    Road, LocatedAt, OriginAt, Requires, AssignedTo, ResultedIn
}

walker ShowGraph {
    has seen: dict = {};

    can show_junction with Junction entry {
        key = jid(here);
        if key in self.seen {
            return;
        }
        self.seen[key] = True;
        print(f"Junction: {here.name}");
        for e in [edge here ->:Road:->] {
            print(f"  Road '{e.label}' -> distance={e.distance}mi status={e.status}");
        }
        visit [-->];
    }

    can show_shelter with Shelter entry {
        key = jid(here);
        if key in self.seen {
            return;
        }
        self.seen[key] = True;
        at = [here <-:LocatedAt:<-][0].name;
        print(
            f"  Shelter: {here.name} (at {at}) beds={here.occupied}/{here.total_beds} "
            f"wheelchair={here.wheelchair_accessible} pets={here.pets_allowed} "
            f"medical={here.medical_staff}"
        );
        visit [-->];
    }

    can show_depot with Depot entry {
        key = jid(here);
        if key in self.seen {
            return;
        }
        self.seen[key] = True;
        at = [here <-:LocatedAt:<-][0].name;
        print(f"  Depot: {here.name} (at {at}) cots={here.cots} water_cases={here.water_cases} med_kits={here.med_kits}");
        visit [-->];
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

    nob_hill_depot = Depot(name="Nob Hill Depot", cots=200, water_cases=150, med_kits=40);
    north_beach_depot = Depot(name="North Beach Depot", cots=150, water_cases=100, med_kits=25);

    nob_hill +>:LocatedAt:+> nob_hill_depot;
    north_beach +>:LocatedAt:+> north_beach_depot;

    marina spawn ShowGraph();
}
