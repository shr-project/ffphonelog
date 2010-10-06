/* ffphonelog -- finger friendly phone log
 * Copyright (C) 2009-2010 Łukasz Pankowski <lukpank@o2.pl>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

using Elm;

const string ICONS_DIR = "/usr/share/ffphonelog/icons";

extern long clock();
extern const int CLOCKS_PER_SEC;

[DBus (name = "org.freesmartphone.GSM.Call")]
interface GSMCall : GLib.Object
{
    public abstract int initiate(string number, string type)
    throws DBus.Error;
}

[DBus (name = "org.freesmartphone.PIM.Calls")]
interface Calls : GLib.Object
{
    public abstract async string query(HashTable<string,Value?> query)
    throws DBus.Error;
}

[DBus (name = "org.freesmartphone.PIM.CallQuery")]
interface CallQuery : GLib.Object
{
    public abstract void Dispose() throws DBus.Error;
    public abstract int get_result_count() throws DBus.Error;
    public abstract async HashTable<string,Value?>[]
    get_multiple_results(int i) throws DBus.Error;
}

[DBus (name = "org.freesmartphone.PIM.Contact")]
interface Contact : GLib.Object
{
    public abstract async HashTable<string,Value?> get_content()
    throws DBus.Error;
}

[DBus (name = "org.shr.phoneui.Contacts")]
interface PhoneuiContacts : GLib.Object
{
    public abstract void edit_contact(string path) throws DBus.Error;
    public abstract string create_contact(HashTable<string,Value?> values)
    throws DBus.Error;
}

enum Mode
{
    INCOMING=0,
    OUTGOING,
    MISSED,
    ALL
}

enum RetrivingStatus
{
    NOT_STARTED,
    STARTED
}


DBus.Connection conn;
bool verbose = false;


void die(string msg)
{
    printerr("%s: %s\n", Environment.get_prgname(), msg);
    Posix.exit(1);
}

void print_hash_table(HashTable<string,Value?> ht)
{
    ht.foreach((key, val) => {
	    unowned Value? v = (Value?) val;
	    string s = "?";
	    string type = v.type_name() ?? @"(null type name)";
	    if (v.holds(typeof(string)))
		s = (string) v;
	    else if (v.holds(typeof(int)))
		s = v.get_int().to_string();
	    print(@"  $((string)key) : $type = $s\n");
	});
    print("\n");
}

class CallItem
{
    string peer;
    int contact;
    string name;
    public Mode mode;
    bool answered;
    time_t timestamp;
    time_t duration;
    public int subitems;
    public unowned CallItem next_subitem;

    public CallItem(HashTable<string,Value?> res)
    {
	if (verbose) print_hash_table(res);
	unowned Value? v = res.lookup("Peer");
	if (v != null && v.holds(typeof(string)))
	    peer = v.get_string();
	timestamp = res.lookup("Timestamp").get_int();
	answered = res.lookup("Answered").get_int() != 0;
	duration = (answered) ?
	    res.lookup ("Duration").get_string().to_int() : 0;
	v = res.lookup("@Contacts");
	contact = (v != null && v.holds(typeof(int))) ? v.get_int() : -1;
    }

    public async void resolve_phone_number()
    {
	if (contact != -1) {
	    var path = @"/org/freesmartphone/PIM/Contacts/$contact";
	    if (verbose) print(@"$path\n");
	    var o = (Contact) conn.get_object("org.freesmartphone.opimd",
					      path);
	    var r = yield o.get_content();
	    if (verbose) print_hash_table(r);
	    var v = r.lookup("Name");
	    if (v != null && v.holds(typeof(string)))
		name = v.get_string();
	    v = r.lookup("Surname");
	    if (v != null && v.holds(typeof(string))) {
		var surname = v.get_string();
		name = (name != null) ? @"$name $surname" : surname;
	    }
	    if (name == null) {
		v = r.lookup("Nickname");
		name = (v != null && v.holds(typeof(string))) ?
		    v.get_string() : "???";
	    }
	}
	// XXX may also use Timezone from CallQuery result
    }

    public bool maybe_add_subitem(CallItem next, CallItem? last_subitem)
    {
	if (mode == next.mode &&
	    (contact != -1 && next.contact == contact ||
	     peer != null && next.peer == peer)) {
	    if (next_subitem == null)
		next_subitem = next;
	    else
		last_subitem.next_subitem = next;
	    subitems += 1;
	    next.subitems = -1;
	    return true;
	} else {
	    return false;
	}
    }

    public string? get_label(string part)
    {
	if (part == "elm.text") {
	    var suffix = (subitems > 0) ? " [%d]".printf(subitems + 1) : "";
	    if (name != null)
		return @"$name$suffix    ($peer)";
	    else
		return @"$peer$suffix";
	} else if (part == "elm.text.sub") {
	    var t = GLib.Time.local(timestamp).format("%a %F %T");
	    return (answered) ? "%s,   %02u:%02u".printf(
		t, (uint) duration / 60, (uint) duration % 60) : t;
	} else {
	    return null;
	}
    }

    public void edit_add()
    {
	var o = (PhoneuiContacts) conn.get_object(
	    "org.shr.phoneui", "/org/shr/phoneui/Contacts");
	if (contact != -1) {
	    o.edit_contact(@"/org/freesmartphone/PIM/Contacts/$contact");
	} else {
	    // XXX create_contact seems to be broken in phoneui?
	    var fields = new HashTable<string,Value?>(null, null);
	    fields.insert("Name", "");
	    fields.insert("Phone", peer);
	    o.create_contact(fields);
	}
    }

    public void call()
    {
	if (peer != null)
	    ((GSMCall) conn.get_object(
		"org.freesmartphone.ogsmd",
		"/org/freesmartphone/GSM/Device")).initiate(peer, "voice");
	else
	    message("CallItem.call: will not initiate a call: peer is null\n");
    }
}

[Compact]
class ModeItems
{
    public RetrivingStatus status = RetrivingStatus.NOT_STARTED;
    public CallItem[] items = null;
    public int items_cnt = 0;
}

class CallsList
{
    public Genlist lst;
    GenlistItemClass itc;
    ModeItems mode_items[4];
    Mode cur_mode;

    public CallsList(Elm.Object parent)
    {
	lst = new Genlist(parent);
	itc.item_style = "double_label";
	itc.func.label_get = (GenlistItemLabelGetFunc) get_label;
	lst.smart_callback_add("expand,request", expand);
	lst.smart_callback_add("contract,request", contract);
	for (int i = 0; i < mode_items.length; i++) {
	    mode_items[i] = new ModeItems();
	}
    }

    void expand(Evas.Object obj, void *event_info)
    {
	var it = (GenlistItem *) event_info;
	it->expanded_set(true);
	for (unowned CallItem subitem =
		 ((CallItem) it->data_get()).next_subitem;
	     subitem != null; subitem = subitem.next_subitem) {
	    lst.item_append(itc, subitem, it, GenlistItemFlags.NONE, null);
	}
    }
    void contract(Evas.Object obj, void *event_info)
    {
	var it = (GenlistItem *) event_info;
	it->subitems_clear();
	it->expanded_set(false);
    }

    public void switch_to_mode(Mode mode)
    {
	if (mode == cur_mode)
	    return;
	lst.clear();
	unowned ModeItems m = mode_items[mode];
	cur_mode = mode;
	if (m.status == RetrivingStatus.NOT_STARTED) {
	    fetch_items.begin(mode);
	} else {
	    for (int i = 0; i < m.items_cnt; i++) {
		var item = m.items[i];
		if (item.subitems != -1) {
		    if (item.subitems > 0)
			lst.item_append(itc, item, null,
					GenlistItemFlags.SUBITEMS, null);
		    else
			lst.item_append(itc, item, null,
					GenlistItemFlags.NONE, null);
		}
	    }
	}
    }

    async void fetch_items(Mode mode)
    {
	unowned ModeItems m = mode_items[mode];
	m.status = RetrivingStatus.STARTED;
	
	(void) new Ecore.Idler(fetch_items.callback);
	yield;

	if (conn == null)
	    conn = DBus.Bus.get(DBus.BusType.SYSTEM);

	var t = clock();
	var calls = (Calls) conn.get_object("org.freesmartphone.opimd",
					    "/org/freesmartphone/PIM/Calls");

	var q = new HashTable<string,Value?>(null, null);
	q.insert("_limit", 30);
	q.insert("_sortby", "Timestamp");
	q.insert("_sortdesc", true);
	q.insert("_resolve_phonenumber", true);
	switch (mode) {
	case Mode.INCOMING:
	    q.insert("Direction", "in");
	    q.insert("Answered", 1);
	    break;
	case Mode.OUTGOING:
	    q.insert("Direction", "out");
	    break;
	case Mode.MISSED:
	    q.insert("Direction", "in");
	    q.insert("Answered", 0);
	    break;
	case Mode.ALL:
	    break;
	}
	var path = yield calls.query(q);
	var reply = (CallQuery) conn.get_object("org.freesmartphone.opimd", path);
	int cnt = reply.get_result_count();
	if (verbose) print(@"query: $path $cnt\n\n");
	m.items = new CallItem[cnt];
	int i = 0;
	unowned CallItem parent = null, last_subitem = null;
	unowned GenlistItem parent_gl_item = null;
	while (cnt > 0) {
	    int chunk = (cnt > 10) ? 10 : cnt;
	    var results = yield reply.get_multiple_results(chunk);
	    foreach (var res in results) {
		var item = m.items[i] = new CallItem(res);
		yield item.resolve_phone_number();
		if (cur_mode == mode) {
		    if (parent != null &&
			parent.maybe_add_subitem(m.items[i], last_subitem)) {
			if (last_subitem == null) {
			    parent_gl_item.del();
			    parent_gl_item = lst.item_append(
				itc, parent, null,
				GenlistItemFlags.SUBITEMS, null);
			}
			last_subitem = m.items[i];
		    } else {
			parent = m.items[i];
			parent_gl_item = lst.item_append(
			    itc, m.items[i], null,
			    GenlistItemFlags.NONE, null);
			last_subitem = null;
		    }
		}
		i++;
		m.items_cnt++;
	    }
	    cnt -= chunk;
	}
	print(@"fetch_items: $((double)(clock() - t) / CLOCKS_PER_SEC)s\n");
	reply.Dispose();
    }

    static string get_label(void *data, Elm.Object? obj, string part)
    {
	return ((CallItem) data).get_label(part);
    }

    public unowned CallItem? selected_item_get()
    {
	unowned GenlistItem item = lst.selected_item_get();
	return (item != null) ? (CallItem) item.data_get() : null;
    }

    public void edit_add_selected_item()
    {
	unowned CallItem item = selected_item_get();
	if (item != null)
	    item.edit_add();
    }

    public void call_selected_item()
    {
	unowned CallItem item = selected_item_get();
	if (item != null)
	    item.call();
    }
}

class MainWin
{
    Win win;
    Bg bg;
    Box bx;
    Box bx2;
    Toolbar tb;
    CallsList calls;

    public MainWin()
    {
	win = new Win(null, "main", WinType.BASIC);
	if (win == null)
	    die("cannot create main window");
	win.title_set("PhoneLog");
	win.smart_callback_add("delete-request", Elm.exit);

	bg = new Bg(win);
	bg.size_hint_weight_set(1.0, 1.0);
	bg.show();
	win.resize_object_add(bg);

	bx = new Box(win);
	bx.size_hint_weight_set(1.0, 1.0);
	win.resize_object_add(bx);
	bx.show();

	tb = new Toolbar(win);
	tb.scrollable_set(false);
	tb.size_hint_weight_set(0.0, 0.0);
	tb.size_hint_align_set(Evas.Hint.FILL, 0.0);
	bx.pack_end(tb);
	tb.show();

	calls = new CallsList(win);
	calls.switch_to_mode(Mode.MISSED);
	calls.lst.size_hint_weight_set(1.0, 1.0);
	calls.lst.size_hint_align_set(-1.0, -1.0);
	bx.pack_end(calls.lst);
	calls.lst.show();

	(void) tb.item_add(icon("received.png"), "In",
			   () => calls.switch_to_mode(Mode.INCOMING));
	(void) tb.item_add(icon("made.png"), "Out",
			   () => calls.switch_to_mode(Mode.OUTGOING));
	((ToolbarItem *) tb.item_add(
	    icon("missed.png"), "Missed",
	    () => calls.switch_to_mode(Mode.MISSED)))->select();
	(void) tb.item_add(icon("general.png"), "All",
			   () => calls.switch_to_mode(Mode.ALL));

	bx2 = new Box(win);
	bx2.size_hint_align_set(-1.0, -1.0);
	bx2.horizontal_set(true);
	bx2.homogenous_set(true);
	bx2.show();

	add_button("Edit/Add", calls.edit_add_selected_item);
	add_button("Call", calls.call_selected_item);

	bx.pack_end(bx2);

	win.resize(480, 640);
    }

    public void show()
    {
	win.show();
    }

    Elm.Icon *icon(string name)
    {
	Elm.Icon *ic = new Elm.Icon(win);
	ic->file_set(Path.build_filename(ICONS_DIR, name));
	return ic;
    }

    void add_button(string label, Evas.Callback cb)
    {
	Button *bt = new Button(win);
	bt->label_set(label);
	bt->smart_callback_add("clicked", cb);
	bt->size_hint_weight_set(1.0, 0.0);
	bt->size_hint_align_set(-1.0, -1.0);
	bx2.pack_end(bt);
	bt->show();
    }
}

void main(string[] args)
{
    Environment.set_prgname(Path.get_basename(args[0]));
    verbose = ("-v" in args) || ("--verbose" in args);
    Elm.init(args);
    Ecore.MainLoop.glib_integrate();
    var mw = new MainWin();
    mw.show();
    Elm.run();
    Elm.shutdown();
}
