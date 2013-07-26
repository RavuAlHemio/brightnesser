static MainLoop theloop;
static int retcode = 0;

static const string SERVICE_NAME = "com.ondrahosek.Brightnesser";

[DBus(name = "com.ondrahosek.Brightnesser.Enumerator")]
public class Enumerator : Object
{
	public static const string OBJECT_NAME = "/com/ondrahosek/Brightnesser/Enumerator";

	static const string BRIGHTNESS_BASEPATH = "/sys/class/backlight";
	static const string PERM_ENUMERATE = "com.ondrahosek.brightnesser.enumerate";

	private DBusConnection conn;
	private HashTable<string, Adjustable> adjustables;
	private File blpath;
	private FileMonitor blmon;
	private uint regnr;

	public Enumerator(DBusConnection connection) throws Error
	{
		conn = connection;
		adjustables = new HashTable<string, Adjustable>(str_hash, str_equal);
		blpath = File.new_for_path(BRIGHTNESS_BASEPATH);
		blmon = blpath.monitor_directory(FileMonitorFlags.NONE);
		blmon.changed.connect(_dir_changed);

		// populate the hashtable
		FileEnumerator enr = blpath.enumerate_children(
			FileAttribute.STANDARD_NAME,
			FileQueryInfoFlags.NONE
		);
		FileInfo? fi;
		while ((fi = enr.next_file()) != null)
		{
			string childname = fi.get_name();
			File file = blpath.get_child(childname);
			var adj = new Adjustable(conn, file);
			adjustables.set(childname, (owned)adj);
		}

		// register us
		regnr = conn.register_object(
			OBJECT_NAME,
			this
		);
	}

	~Enumerator()
	{
		conn.unregister_object(regnr);
	}

	private void _dir_changed(File file, File? other_file, FileMonitorEvent type)
	{
		if (file.query_file_type(FileQueryInfoFlags.NONE) != FileType.DIRECTORY)
		{
			return;
		}
		if (type == FileMonitorEvent.CREATED)
		{
			Adjustable adj;
			try
			{
				adj = new Adjustable(conn, file);
			}
			catch (Error e)
			{
				stderr.printf("Error creating Adjustable for '%s': %s\n", file.get_path(), e.message);
				return;
			}
			adjustables.set(file.get_basename(), (owned)adj);
		}
		else if (type == FileMonitorEvent.DELETED)
		{
			adjustables.remove(file.get_basename());
		}
	}

	public string[] enumerate()
	{
		string[] ret = new string[0];
		foreach (string s in adjustables.get_keys())
		{
			ret += s;
		}
		return ret;
	}
}

[DBus(name = "com.ondrahosek.Brightnesser.Adjustable")]
public class Adjustable : Object
{
	public static const string ADJUSTABLES_PREFIX = "/com/ondrahosek/Brightnesser/Adjustables/";

	private DBusConnection conn;
	private uint regnr;
	private string name;
	private File brightfile;
	private File maxfile;

	static const string PERM_GET = "com.ondrahosek.brightnesser.get";
	static const string PERM_SET = "com.ondrahosek.brightnesser.set";

	public Adjustable(DBusConnection connection, File brightdir) throws IOError
	{
		conn = connection;
		name = brightdir.get_basename();
		brightfile = brightdir.get_child("brightness");
		maxfile = brightdir.get_child("max_brightness");

		// register me
		regnr = conn.register_object(
			ADJUSTABLES_PREFIX + name,
			this
		);
	}

	~Adjustable()
	{
		if (regnr > 0)
		{
			conn.unregister_object(regnr);
		}
	}

	private void assert_auth(string perm, GLib.BusName sender) throws BrightnesserError
	{
		Polkit.Authority aity;
		Polkit.AuthorizationResult res;

		try
		{
			aity = Polkit.Authority.get_sync();
		}
		catch (GLib.Error err)
		{
			stderr.printf("Failed to fetch authority while checking '%s'.\n", sender);
			throw new BrightnesserError.AUTHENTICATION_FAILED("Authentication failed!");
		}

		try
		{
			res = aity.check_authorization_sync(
				Polkit.SystemBusName.new(sender),
				perm,
				null,
				Polkit.CheckAuthorizationFlags.NONE
			);
			if (!res.get_is_authorized())
			{
				throw new BrightnesserError.UNAUTHORIZED("Authorization unsuccessful!");
			}
		}
		catch (GLib.Error err)
		{
			stderr.printf("Failed to check authorization of '%s'.\n", sender);
			throw new BrightnesserError.AUTHENTICATION_FAILED("Authentication failed!");
		}
	}

	private void _intfail() throws BrightnesserError
	{
		throw new BrightnesserError.INTERNAL_FAILURE("Internal failure");
	}

	private int _get_brightness(File file) throws BrightnesserError
	{
		if (!file.query_exists())
		{
			stderr.printf("Error: brightness file '%s' doesn't exist\n", file.get_path());
			_intfail();
			return -1;
		}

		DataInputStream dis;
		try
		{
			dis = new DataInputStream(file.read());
		}
		catch (GLib.Error err)
		{
			stderr.printf("Error: brightness file '%s' could not be opened: %s\n", file.get_path(), err.message);
			_intfail();
			return -1;
		}

		string ln;
		try
		{
			ln = dis.read_line();
		}
		catch (GLib.Error err)
		{
			stderr.printf("Error: brightness file '%s' could not be parsed: %s\n", file.get_path(), err.message);
			_intfail();
			return -1;
		}
		return int.parse(ln);
	}

	private void _set_brightness(File file, int newbr) throws BrightnesserError
	{
		if (!file.query_exists())
		{
			stderr.printf("Error: brightness file '%s' doesn't exist\n", file.get_path());
			_intfail();
			return;
		}

		DataOutputStream dos;
		try
		{
			dos = new DataOutputStream(file.replace(null, false, FileCreateFlags.NONE));
		}
		catch (GLib.Error err)
		{
			stderr.printf("Error: brightness file '%s' could not be opened: %s\n", file.get_path(), err.message);
			_intfail();
			return;
		}

		try
		{
			dos.put_string("%d\n".printf(newbr));
		}
		catch (GLib.Error err)
		{
			stderr.printf("Error: brightness file '%s' could not be written: %s\n", file.get_path(), err.message);
			_intfail();
			return;
		}
	}

	public void set_brightness(int newval, GLib.BusName sender) throws Error
	{
		assert_auth(PERM_SET, sender);
		int max = _get_brightness(maxfile);
		if (newval < 0 || newval > max)
		{
			throw new BrightnesserError.OUT_OF_BOUNDS("brightness must be between 0 and %d".printf(max));
		}
		_set_brightness(brightfile, newval);
	}

	public void adjust_brightness(int by, GLib.BusName sender) throws Error
	{
		assert_auth(PERM_SET, sender);
		int br = _get_brightness(brightfile);
		int max = _get_brightness(maxfile);
		int newval = br + by;
		if (newval < 0 || newval > max)
		{
			throw new BrightnesserError.OUT_OF_BOUNDS("resulting brightness must be between 0 and %d".printf(max));
		}
		_set_brightness(brightfile, newval);
	}

	public int get_brightness(GLib.BusName sender) throws Error
	{
		assert_auth(PERM_GET, sender);
		return _get_brightness(brightfile);
	}

	public int get_max_brightness(GLib.BusName sender) throws Error
	{
		assert_auth(PERM_GET, sender);
		return _get_brightness(maxfile);
	}
}

[DBus(name = "com.ondrahosek.Brightnesser.Error")]
public errordomain BrightnesserError
{
	AUTHENTICATION_FAILED,
	UNAUTHORIZED,
	INTERNAL_FAILURE,
	OUT_OF_BOUNDS
}

void on_name_got(DBusConnection conn)
{
}

void on_name_lost(DBusConnection conn)
{
	stderr.printf("Lost name on bus.\n");
	if (conn == null)
	{
		stderr.printf("No connection could be established.\n");
	}
	else
	{
		stderr.printf("Connection is valid though.\n");
	}
	retcode = 1;
	theloop.quit();
}

int main(string[] args)
{
	if (args.length != 1)
	{
		stderr.printf("Usage: %s\n", args[0]);
		return 1;
	}

	// fetch the bus
	DBusConnection conn;
	try
	{
		conn = Bus.get_sync(BusType.SYSTEM);
	}
	catch (IOError ioe)
	{
		stderr.printf("Failed to get system bus: %s\n", ioe.message);
		return 1;
	}

	// create the Enumerator
	Enumerator en;
	try
	{
		en = new Enumerator(conn);
	}
	catch (Error ioe)
	{
		stderr.printf("Failed to create enumerator: %s\n", ioe.message);
	}

	// register the name
	Bus.own_name_on_connection(
		conn,
		SERVICE_NAME,
		BusNameOwnerFlags.NONE,
		on_name_got,
		on_name_lost
	);

	theloop = new MainLoop();
	theloop.run();

	return retcode;
}
