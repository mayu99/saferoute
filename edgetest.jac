edge Road {
    has label: str = "";
    has status: str = "open";
}

node Junction {
    has name: str;
}

walker Reach {
    can show with Junction entry {
        print(f"reached {here.name}");
        open_edges = [edge here ->:Road:status == "open":->];
        for e in open_edges {
            print(f"edge label: {e.label}");
        }
        visit [->:Road:status == "open":->];
    }
}

with entry:__main__ {
    a = Junction(name="Marina");
    b = Junction(name="Presidio");
    c = Junction(name="FortMason");
    root ++> a;
    a +>:Road:label="Lombard", status="open":+> b;
    a +>:Road:label="Doyle", status="closed":+> c;
    a spawn Reach();
}
