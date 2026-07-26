node Shelter {
    has name: str;
    has beds: int;
}

walker Seed {
    can go with entry {
        visit [-->];
    }
    can show with Shelter entry {
        print(f"{here.name}: {here.beds} beds");
    }
}

with entry:__main__ {
    root ++> Shelter(name="Marina", beds=60);
    root ++> Shelter(name="Presidio", beds=120);
    root spawn Seed();
}
