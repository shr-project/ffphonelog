[DBus (name = "org.freesmartphone.PIM.Calls")]
interface Calls : GLib.Object
{
    public abstract string query(HashTable<string,Value?> query)
    throws DBus.Error;
}

[DBus (name = "org.freesmartphone.PIM.CallQuery")]
interface CallQuery : GLib.Object
{
    public abstract void Dispose() throws DBus.Error;
    public abstract int get_result_count() throws DBus.Error;
}

void main()
{
    var conn = DBus.Bus.get(DBus.BusType.SYSTEM);
    var calls = (Calls) conn.get_object("org.freesmartphone.opimd",
					"/org/freesmartphone/PIM/Calls");

    var q = new HashTable<string,Value?>(null, null);
    q.insert("_limit", 3);
    var path = calls.query(q);
    var reply = (CallQuery) conn.get_object("org.freesmartphone.opimd", path);
    int cnt = reply.get_result_count();
    stdout.printf(@"$path $cnt\n");
    reply.Dispose();

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
