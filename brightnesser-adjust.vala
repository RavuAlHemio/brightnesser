/**
 * brightnesser-adjust: The reference implementation of a Brightnesser client.
 */

static const string DBUS_TARGET = "com.ondrahosek.Brightnesser";

[DBus(name = "com.ondrahosek.Brightnesser.Enumerator")]
interface IEnumerator : Object
{
	public static const string DBUS_IFACE = "com.ondrahosek.Brightnesser.Enumerator";
	public static const string OBJECT_NAME = "/com/ondrahosek/Brightnesser/Enumerator";

	public abstract string[] enumerate() throws Error;
}

[DBus(name = "com.ondrahosek.Brightnesser.Adjustable")]
interface IAdjustable : Object
{
	public static const string DBUS_IFACE = "com.ondrahosek.Brightnesser.Adjustable";
	public static const string ADJUSTABLES_PREFIX = "/com/ondrahosek/Brightnesser/Adjustables/";

	public abstract void set_brightness(int newval) throws Error;
	public abstract void adjust_brightness(int by) throws Error;
	public abstract int get_brightness() throws Error;
	public abstract int get_max_brightness() throws Error;
}

static string? control = null;
static int setval;
static int adjval;
static bool getval = false;
static bool getmax = false;
static bool getlist = false;
static const OptionEntry[] options = {
	{ "control", 'c', 0, OptionArg.STRING, ref control, "Which brightness control to use.", "CONTROL" },
	{ "set", 's', 0, OptionArg.INT, ref setval, "The brightness to which to set the control.", "BRIGHTNESS" },
	{ "adjust", 'a', 0, OptionArg.INT, ref adjval, "The brightness to which to set the control.", "BRIGHTNESS" },
	{ "get", 'g', 0, OptionArg.NONE, ref getval, "Return the brightness of the given control.", null },
	{ "get-max", 'm', 0, OptionArg.NONE, ref getmax, "Return the maximum brightness of the given control.", null },
	{ "list", 'l', 0, OptionArg.NONE, ref getlist, "Return the list of available brightness controls.", null },
	{ null }
};

static void usagehint(string progname)
{
	stderr.printf("Run '%s --help' to see a list of available command line options.\n", progname);
}

int main(string[] args)
{
	setval = int.MAX;
	adjval = int.MAX;

	try
	{
		var opt_context = new OptionContext("-- adjust brightness");
		opt_context.set_help_enabled(true);
		opt_context.add_main_entries(options, null);
		opt_context.parse(ref args);
	}
	catch (OptionError e)
	{
		stderr.printf("error: %s\n", e.message);
		usagehint(args[0]);
		return 1;
	}

	if (getlist)
	{
		if (control != null || setval != int.MAX || adjval != int.MAX || getval || getmax)
		{
			stderr.printf("error: -l/--list must be used without any other options\n");
			usagehint(args[0]);
			return 1;
		}

		// connect
		IEnumerator ien;
		try
		{
			ien = Bus.get_proxy_sync(
				BusType.SYSTEM,
				DBUS_TARGET,
				IEnumerator.OBJECT_NAME
			);
		}
		catch (Error e)
		{
			stderr.printf("Error getting enumerator proxy: %s\n", e.message);
			return 1;
		}

		string[] ctrls;
		try
		{
			ctrls = ien.enumerate();
		}
		catch (Error e)
		{
			stderr.printf("Error getting list: %s\n", e.message);
			return 1;
		}

		foreach (string ctrl in ctrls)
		{
			stdout.printf("%s\n", ctrl);
		}

		return 0;
	}
	else if (control == null)
	{
		stderr.printf("error: -c/--control must be specified unless using -l/--list\n");
		usagehint(args[0]);
		return 1;
	}

	// verify that exactly one option was specified
	int set_options_counter = 0;
	if (setval != int.MAX)
	{
		++set_options_counter;
	}
	if (adjval != int.MAX)
	{
		++set_options_counter;
	}
	if (getval)
	{
		++set_options_counter;
	}
	if (getmax)
	{
		++set_options_counter;
	}
	if (set_options_counter != 1)
	{
		stderr.printf("error: if -c/--control is specified, exactly one of -s/--set, -a/--adjust, -g/--get and -m/--get-max must be specified as well\n");
		usagehint(args[0]);
		return 1;
	}

	// connect
	IAdjustable iad;
	try
	{
		iad = Bus.get_proxy_sync(
			BusType.SYSTEM,
			DBUS_TARGET,
			IAdjustable.ADJUSTABLES_PREFIX + control
		);
	}
	catch (Error e)
	{
		stderr.printf("Error getting Adjustable proxy: %s\n", e.message);
		return 1;
	}

	// now then
	try
	{
		if (setval != int.MAX)
		{
			// set
			iad.set_brightness(setval);
		}
		else if (adjval != int.MAX)
		{
			// adjust
			iad.adjust_brightness(adjval);
		}
		else if (getval)
		{
			stdout.printf("%d\n", iad.get_brightness());
		}
		else if (getmax)
		{
			stdout.printf("%d\n", iad.get_max_brightness());
		}
	}
	catch (Error e)
	{
		stderr.printf("Error! %s\n", e.message);
		return 1;
	}

	return 0;
}
