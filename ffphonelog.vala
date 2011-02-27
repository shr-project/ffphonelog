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

extern const string PKGDATADIR;

extern long clock();
extern const int CLOCKS_PER_SEC;
extern void elm_theme_extension_add(Elm.Theme? th, string item);

[DBus (name = "org.freesmartphone.GSM.Call")]
interface GSMCall : GLib.Object
{
    public abstract int initiate(string number, string type) throws IOError;
}

[DBus (name = "org.freesmartphone.PIM.Call")]
interface PIMCall : GLib.Object
{
    public abstract async
    void update(HashTable<string,Variant> fields) throws IOError;
}

[DBus (name = "org.freesmartphone.PIM.Calls")]
interface PIMCalls : GLib.Object
{
    public abstract async
    string query(HashTable<string,Variant> query) throws IOError;
}

[DBus (name = "org.freesmartphone.PIM.CallQuery")]
interface CallQuery : GLib.Object
{
    public abstract void Dispose() throws IOError;
    public abstract int get_result_count() throws IOError;
    public abstract async
    HashTable<string,Variant>[] get_multiple_results(int i) throws IOError;
}

[DBus (name = "org.shr.phoneui.Contacts")]
interface PhoneuiContacts : GLib.Object
{
    public abstract void edit_contact(string path) throws IOError;
    public abstract
    string create_contact(HashTable<string,Variant> values) throws IOError;
}

[DBus (name = "org.shr.phoneui.Messages")]
interface PhoneuiMessages : GLib.Object
{
    public abstract
    void create_message(HashTable<string,Variant> options) throws IOError;
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


bool verbose = false;


void die(string msg)
{
    printerr("%s: %s\n", Environment.get_prgname(), msg);
    Posix.exit(1);
}

void print_hash_table(HashTable<string,Variant> ht)
{
    ht.foreach((key, val) => {
	    unowned Variant v = (Variant) val;
	    print("%s : %s = %s\n", (string) key, v.get_type_string(),
		  v.print(true));
	});
    stdout.putc('\n');
}

class CallItem
{
    public Mode mode;
    public bool is_new;
    public int subitems;
    public unowned CallItem next_subitem;
    public unowned ModeItems mode_items;

    int entry_id;
    string peer;
    int contact = -1;
    string name;
    bool answered;
    time_t timestamp;
    time_t duration;

    public CallItem(HashTable<string,Variant> res, ModeItems mode_items)
    {
	this.mode_items = mode_items;
	if (verbose) print_hash_table(res);
	unowned Variant? v = res.lookup("Peer");
	if (v != null && v.is_of_type(VariantType.STRING))
	    peer = v.get_string();
	v = res.lookup("EntryId");
	entry_id = (v != null && v.is_of_type(VariantType.INT32)) ? v.get_int32() : -1;
	mode = Mode.ALL;
	timestamp = res.lookup("Timestamp").get_int32();
	answered = ((v = res.lookup("Answered")) != null && v.get_int32() != 0);
	v = res.lookup("Direction");
	if (v != null && v.is_of_type(VariantType.STRING)) {
	    switch (v.get_string()) {
	    case "in":
		mode = (answered) ? Mode.INCOMING : Mode.MISSED;
		if (mode == Mode.MISSED) {
		    v = res.lookup("New");
		    if (v != null && v.is_of_type(VariantType.INT32))
			is_new = v.get_int32() != 0;
		}
		break;
	    case "out":
		mode = Mode.OUTGOING;
		break;
	    }
	}
	duration = (answered) ?
	    res.lookup ("Duration").get_string().to_int() : 0;
	v = res.lookup("@Contacts");
	if (v != null) {
	    if (v.get_type_string() == "a{sv}")
		resolve_phone_number(v);
	    else if (v.get_type_string() == "aa{sv}" && v.n_children() > 0)
		resolve_phone_number(v.get_child_value(0));
	}
    }

    public void resolve_phone_number(Variant contact)
    {
	var r = new HashTable<string,Variant>(str_hash, str_equal);
	foreach (var sv in contact)
	    r.insert(sv.get_child_value(0).dup_string(),
		     sv.get_child_value(1).get_variant());
	if (verbose) print_hash_table(r);
	var v = r.lookup("EntryId");
	if (v != null && v.is_of_type(VariantType.INT32))
	    this.contact = v.get_int32();
	v = r.lookup("Name");
	if (v != null && v.is_of_type(VariantType.STRING))
	    name = v.get_string();
	v = r.lookup("Surname");
	if (v != null && v.is_of_type(VariantType.STRING)) {
	    var surname = v.get_string();
	    name = (name != null) ? @"$name $surname" : surname;
	}
	if (name == null) {
	    v = r.lookup("Nickname");
	    name = (v != null && v.is_of_type(VariantType.STRING)) ?
		v.get_string() : "???";
	}
	// XXX may also use Timezone from CallQuery result
    }

    public bool maybe_add_subitem(CallItem next, CallItem? last_subitem)
    {
	if (mode == next.mode &&
	    (contact != -1 && next.contact == contact ||
	     contact == -1 && peer == null && next.peer == null ||
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

    public async void mark_new_item_as_read()
    {
	if (entry_id != -1) {
	    var path = @"/org/freesmartphone/PIM/Calls/$entry_id";
	    PIMCall o = Bus.get_proxy_sync(
		BusType.SYSTEM, "org.freesmartphone.opimd", path);
	    var fields = new HashTable<string,Variant>(str_hash, str_equal);
	    fields.insert("New", 0);
	    o.update(fields);
	}
    }

    public string? get_label(string part)
    {
	if (part == "elm.text") {
	    var suffix = (subitems > 0) ? " [%d]".printf(subitems + 1) : "";
	    if (name != null)
		return @"$name$suffix    ($peer)";
	    else
		return (peer != null) ? @"$peer$suffix" : @"(unknown)$suffix";
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
	PhoneuiContacts o = Bus.get_proxy_sync(BusType.SYSTEM,
	    "org.shr.phoneui", "/org/shr/phoneui/Contacts");
	if (contact != -1) {
	    o.edit_contact(@"/org/freesmartphone/PIM/Contacts/$contact");
	} else {
	    // XXX create_contact seems to be broken in phoneui?
	    var fields = new HashTable<string,Variant>(str_hash, str_equal);
	    fields.insert("Name", "");
	    fields.insert("Phone", peer);
	    o.create_contact(fields);
	}
    }

    public void call()
    {
	if (peer != null) {
	    GSMCall o = Bus.get_proxy_sync(BusType.SYSTEM,
					   "org.freesmartphone.ogsmd",
					   "/org/freesmartphone/GSM/Device");
	    o.initiate(peer, "voice");
	} else {
	    message("CallItem.call: will not initiate a call: peer is null\n");
	}
    }

    public void create_message()
    {
	if (peer != null) {
	    var q = new HashTable<string,Variant>(str_hash, str_equal);
	    q.insert("Phone", peer);
	    PhoneuiMessages o = Bus.get_proxy_sync(
		BusType.SYSTEM, "org.shr.phoneui", "/org/shr/phoneui/Messages");
	    o.create_message(q);
	} else {
	    message("create_message: skipped: peer is null\n");
	}
    }
}

[Compact]
class ModeItems
{
    public RetrivingStatus status = RetrivingStatus.NOT_STARTED;
    public CallItem[] items = null;
    public int items_cnt = 0;
    public CallQuery reply;
    public unowned CallsList list;

    public ModeItems(CallsList list) {
	this.list = list;
    }
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
	lst.horizontal_mode_set(ListMode.COMPRESS);
	itc.item_style = "double_label";
	// XXX could libeflvala be fixed to avoid these casts
	itc.func.label_get = (GenlistItemLabelGetFunc) get_label;
	itc.func.icon_get = (GenlistItemIconGetFunc) get_icon;
	lst.smart_callback_add("expand,request", expand);
	lst.smart_callback_add("contract,request", contract);
	for (int i = 0; i < mode_items.length; i++) {
	    mode_items[i] = new ModeItems(this);
	}
    }

    public void dispose_resources()
    {
	for (int i = 0; i < mode_items.length; i++) {
	    if (mode_items[i].reply != null)
		mode_items[i].reply.Dispose();
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
		if (m.items[i].subitems != -1)
		    append_item(m.items[i]);
	    }
	}
    }

    async void fetch_items(Mode mode)
    {
	unowned ModeItems m = mode_items[mode];
	m.status = RetrivingStatus.STARTED;
	
	(void) new Ecore.Idler(fetch_items.callback);
	yield;

	var t = clock();
	PIMCalls calls = Bus.get_proxy_sync(BusType.SYSTEM,
					    "org.freesmartphone.opimd",
					    "/org/freesmartphone/PIM/Calls");

	var q = new HashTable<string,Variant>(str_hash, str_equal);
	q.insert("_limit", 30);
	q.insert("_sortby", "Timestamp");
	q.insert("_sortdesc", true);
	q.insert("_resolve_phonenumber", true);
	q.insert("_retrieve_full_contact", true);
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
	m.reply = Bus.get_proxy_sync(BusType.SYSTEM,
				     "org.freesmartphone.opimd", path);
	int cnt = m.reply.get_result_count();
	if (verbose) print(@"query: $path $cnt\n\n");
	m.items = new CallItem[cnt];
	int i = 0;
	unowned CallItem parent = null, last_subitem = null;
	while (cnt > 0) {
	    int chunk = (cnt > 10) ? 10 : cnt;
	    var results = yield m.reply.get_multiple_results(chunk);
	    foreach (var res in results) {
		var item = m.items[i] = new CallItem(res, m);
		if (parent != null &&
		    parent.maybe_add_subitem(item, last_subitem)) {
		    last_subitem = item;
		} else {
		    if (parent != null && cur_mode == mode)
			append_item(parent);
		    parent = item;
		    last_subitem = null;
		}
		i++;
		m.items_cnt++;
	    }
	    cnt -= chunk;
	}
	if (parent != null && cur_mode == mode)
	    append_item(parent);
	if (mode == Mode.MISSED) {
	    for (i = 0; i < m.items_cnt; i++) {
		if (m.items[i].is_new)
		    m.items[i].mark_new_item_as_read();
	    }
	}
	print(@"fetch_items: $((double)(clock() - t) / CLOCKS_PER_SEC)s\n");
	m.reply.Dispose();
	m.reply = null;
    }

    void append_item(CallItem item)
    {
	if (item.subitems > 0)
	    lst.item_append(itc, item, null,
			    GenlistItemFlags.SUBITEMS, null);
	else
	    lst.item_append(itc, item, null,
			    GenlistItemFlags.NONE, null);
    }

    static string get_label(void *data, Elm.Object? obj, string part)
    {
	return ((CallItem) data).get_label(part);
    }

    static Elm.Object? get_icon(void *data, Elm.Object? obj, string? part)
    {
	CallItem *item = ((CallItem) data);
	if ((item->mode_items.list.cur_mode != Mode.ALL && !item->is_new) ||
	    part != "elm.swallow.icon")
	    return null;
	string s;
	switch (item->mode) {
	case Mode.INCOMING: s = "received-call-mini"; break;
	case Mode.OUTGOING: s = "made-call-mini"; break;
	case Mode.MISSED: s = "missed-call-mini"; break;
	default: return null;
	}
	var ic = new Elm.Icon(obj);
	ic.standard_set(s);
	// elm.swallow.icon will not display without call to scale_set
	ic.scale_set(false, false);
	return ic;
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

    public void create_message_to_selected_item()
    {
	unowned CallItem item = selected_item_get();
	if (item != null)
	    item.create_message();
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
	win.smart_callback_add("delete-request", close);

	bg = new Bg(win);
	bg.size_hint_weight_set(1.0, 1.0);
	bg.show();
	win.resize_object_add(bg);

	bx = new Box(win);
	bx.size_hint_weight_set(1.0, 1.0);
	win.resize_object_add(bx);
	bx.show();

	tb = new Toolbar(win);
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

	(void) tb.append("received-call", "In",
			 () => calls.switch_to_mode(Mode.INCOMING));
	(void) tb.append("made-call", "Out",
			 () => calls.switch_to_mode(Mode.OUTGOING));
	((ToolbarItem *) tb.append(
	    "missed-call", "Missed",
	    () => calls.switch_to_mode(Mode.MISSED)))->selected_set(true);
	(void) tb.append("general-call", "All",
			 () => calls.switch_to_mode(Mode.ALL));

	bx2 = new Box(win);
	bx2.size_hint_align_set(-1.0, -1.0);
	bx2.horizontal_set(true);
	bx2.homogenous_set(true);
	bx2.show();

	add_button("Edit/Add", calls.edit_add_selected_item);
	add_button("Call", calls.call_selected_item);
	add_button("SMS", calls.create_message_to_selected_item);

	bx.pack_end(bx2);

	win.resize(480, 640);
    }

    public void show()
    {
	win.show();
    }

    void close()
    {
	calls.dispose_resources();
	Elm.exit();
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
    elm_theme_extension_add(
	null, Path.build_filename(PKGDATADIR, "ffphonelog.edj"));
    Ecore.MainLoop.glib_integrate();
    var mw = new MainWin();
    mw.show();
    Elm.run();
    Elm.shutdown();
}
