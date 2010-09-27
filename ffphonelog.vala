void main()
{
    Value x;
    x = "foo";

    string s = (string) x;
    Type t = x.type();
    string name = t.name();
    bool b = x.holds(t);
    bool b2 = t.is_a(Type.from_name("gchararray"));
    stdout.printf(@"$s $name $b $b2\n");

    x = 3;
    int i = (int) x;
    t = x.type();
    name = t.name();
    b = x.holds(t);
    b2 = t.is_a(Type.from_name("gint"));
    stdout.printf(@"$i $name $b $b2\n");
}
