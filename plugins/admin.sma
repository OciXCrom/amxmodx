// vim: set ts=4 sw=4 tw=99 noet:
//
// AMX Mod X, based on AMX Mod by Aleksander Naszko ("OLO").
// Copyright (C) The AMX Mod X Development Team.
//
// This software is licensed under the GNU General Public License, version 3 or higher.
// Additional exceptions apply. For full license details, see LICENSE.txt or visit:
//     https://alliedmods.net/amxmodx-license

//
// Admin Base Plugin
//

// Uncomment for SQL version
// #define USING_SQL

#include <amxmodx>
#include <amxmisc>

#pragma semicolon 1

#if defined USING_SQL
	#include <sqlx>
#endif

new g_admin_count;
new PLUGINNAME[] = "AMX Mod X";

enum (<<= 1)
{
	ADMIN_NONE = 0,
	ADMIN_LOOKUP = 1,
	ADMIN_NORMAL,
	ADMIN_STEAM,
	ADMIN_IPADDR,
	ADMIN_NAME,
};

new bool:g_case_sensitive_name[MAX_PLAYERS + 1];

new g_amx_mode;
new g_amx_password_field[10];
new g_amx_default_access[32];

public plugin_init()
{
#if defined USING_SQL
	register_plugin("Admin Base (SQL)", AMXX_VERSION_STR, "AMXX Dev Team");
#else
	register_plugin("Admin Base", AMXX_VERSION_STR, "AMXX Dev Team");
#endif

	register_dictionary("admin.txt");
	register_dictionary("common.txt");

	bind_pcvar_num(create_cvar(   "amx_mode",           "1",   FCVAR_PROTECTED, "Mode of logging to the server",       true, 0.0, true, 2.0), g_amx_mode);
	bind_pcvar_string(create_cvar("amx_password_field", "_pw", FCVAR_PROTECTED, "Name of setinfo which should store a password on a client"), g_amx_password_field, charsmax(g_amx_password_field));
	bind_pcvar_string(create_cvar("amx_default_access", "",    FCVAR_PROTECTED, "Default access for all non admin players"),                  g_amx_default_access, charsmax(g_amx_default_access));

	create_cvar("amx_vote_ratio", "0.02");
	create_cvar("amx_vote_time", "10");
	create_cvar("amx_vote_answers", "1");
	create_cvar("amx_vote_delay", "60");
	create_cvar("amx_last_voting", "0");
	create_cvar("amx_show_activity", "2", FCVAR_PROTECTED, _, true, 0.0, true, 5.0);
	create_cvar("amx_votekick_ratio", "0.40");
	create_cvar("amx_voteban_ratio", "0.40");
	create_cvar("amx_votemap_ratio", "0.40");

	set_cvar_float("amx_last_voting", 0.0);

#if defined USING_SQL
	register_srvcmd("amx_sqladmins", "adminSql");
	create_cvar("amx_sql_table", "admins", FCVAR_PROTECTED);
#endif
	create_cvar("amx_sql_host", "127.0.0.1", FCVAR_PROTECTED);
	create_cvar("amx_sql_user", "root", FCVAR_PROTECTED);
	create_cvar("amx_sql_pass", "", FCVAR_PROTECTED);
	create_cvar("amx_sql_db", "amx", FCVAR_PROTECTED);
	create_cvar("amx_sql_type", "mysql", FCVAR_PROTECTED);
	create_cvar("amx_sql_timeout", "60", FCVAR_PROTECTED);

	register_concmd("amx_reloadadmins", "cmdReload", ADMIN_CFG);
	register_concmd("amx_addadmin", "addadminfn", ADMIN_RCON, "<playername|auth> <accessflags> [password] [authtype] - add specified player as an admin to users.ini");

	remove_user_flags(0, read_flags("z"));		// Remove 'user' flag from server rights

	new configsDir[64];
	get_configsdir(configsDir, charsmax(configsDir));
	server_cmd("exec %s/sql.cfg", configsDir);
	
#if defined USING_SQL
	server_cmd("amx_sqladmins");
#else
	format(configsDir, 63, "%s/users.ini", configsDir);
	loadSettings(configsDir);					// Load admins accounts
#endif
}

public client_connect(id)
{
	g_case_sensitive_name[id] = false;
}

public addadminfn(id, level, cid)
{
	if (!cmd_access(id, level, cid, 3))
	{
		return PLUGIN_HANDLED;
	}
		
	new idtype = ADMIN_STEAM | ADMIN_LOOKUP;

	if (read_argc() >= 5)
	{
		new t_arg[16];
		read_argv(4, t_arg, charsmax(t_arg));
		
		if (equali(t_arg, "steam") || equali(t_arg, "steamid") || equali(t_arg, "auth"))
		{
			idtype = ADMIN_STEAM;
		}
		else if (equali(t_arg, "ip"))
		{
			idtype = ADMIN_IPADDR;
		}
		else if (equali(t_arg, "name") || equali(t_arg, "nick"))
		{
			idtype = ADMIN_NAME;
			
			if (equali(t_arg, "name"))
			{
				idtype |= ADMIN_LOOKUP;
			}
		}
		else
		{
			console_print(id, "[%s] Unknown id type ^"%s^", use one of: steamid, ip, name", PLUGINNAME, t_arg);
			return PLUGIN_HANDLED;
		}
	}

	new arg[33];
	read_argv(1, arg, charsmax(arg));
	new player = -1;
	
	if (idtype & ADMIN_STEAM)
	{
		if (containi(arg, "STEAM_0:") == -1)
		{
			idtype |= ADMIN_LOOKUP;
			player = cmd_target(id, arg, CMDTARGET_ALLOW_SELF | CMDTARGET_NO_BOTS);
		}
		else
		{
			new _steamid[44];
			static _players[MAX_PLAYERS], _num, _pv;
			get_players(_players, _num);

			for (new _i = 0; _i < _num; _i++)
			{
				_pv = _players[_i];
				get_user_authid(_pv, _steamid, charsmax(_steamid));

				if (!_steamid[0])
				{
					continue;
				}
				if (equal(_steamid, arg))
				{
					player = _pv;
					break;
				}
			}	
			if (player < 1)
			{
				idtype &= ~ADMIN_LOOKUP;
			}		
		}
	}
	else if (idtype & ADMIN_NAME)
	{
		player = cmd_target(id, arg, CMDTARGET_ALLOW_SELF | CMDTARGET_NO_BOTS);
		
		if (player)
		{
			idtype |= ADMIN_LOOKUP;
		}
		else
		{
			idtype &= ~ADMIN_LOOKUP;
		}
	}
	else if (idtype & ADMIN_IPADDR)
	{
		new len = strlen(arg);
		new dots, chars;
		
		for (new i = 0; i < len; i++)
		{
			if (arg[i] == '.')
			{
				if (!chars || chars > 3)
				{
					break;
				}
				
				if (++dots > 3)
				{
					break;
				}
				
				chars = 0;
			}
			else
			{
				chars++;
			}
			
			if (dots != 3 || !chars || chars > 3)
			{
				idtype |= ADMIN_LOOKUP;
				player = find_player("dh", arg);
			}
		}
	}
	
	if (idtype & ADMIN_LOOKUP && !player)
	{
		console_print(id, "%L", id, "CL_NOT_FOUND");
		return PLUGIN_HANDLED;
	}
	
	new flags[64], password[64];
	read_argv(2, flags, charsmax(flags));

	if (read_argc() >= 4)
	{
		read_argv(3, password, charsmax(password));
	}

	new auth[33];
	new comment[MAX_NAME_LENGTH]; // name of player to pass to comment field

	if (idtype & ADMIN_LOOKUP)
	{
		get_user_name(player, comment, charsmax(comment));

		if (idtype & ADMIN_STEAM)
		{
			get_user_authid(player, auth, charsmax(auth));
		}
		else if (idtype & ADMIN_IPADDR)
		{
			get_user_ip(player, auth, charsmax(auth), 1);
		}
		else if (idtype & ADMIN_NAME)
		{
			get_user_name(player, auth, charsmax(auth));
		}
	}
	else
	{
		copy(auth, charsmax(auth), arg);
	}
	
	new type[16], len;
	
	if (idtype & ADMIN_STEAM)
	{
		len += format(type[len], charsmax(type) - len, "c");
	}
	else if (idtype & ADMIN_IPADDR)
	{
		len += format(type[len], charsmax(type) - len, "d");
	}
	
	if (strlen(password) > 0)
	{
		len += format(type[len], charsmax(type) - len, "a");
	}
	else
	{
		len += format(type[len], charsmax(type) - len, "e");
	}
	
	AddAdmin(id, auth, flags, password, type, comment);
	cmdReload(id, ADMIN_CFG, 0);

	if (player > 0)
	{
		new name[MAX_NAME_LENGTH];
		get_user_info(player, "name", name, charsmax(name));
		accessUser(player, name);
	}

	return PLUGIN_HANDLED;
}

AddAdmin(id, auth[], accessflags[], password[], flags[], comment[]="")
{
#if defined USING_SQL
	new error[128], errno;

	new Handle:info = SQL_MakeStdTuple();
	new Handle:sql = SQL_Connect(info, errno, error, charsmax(error));
	
	if (sql == Empty_Handle)
	{
		server_print("[AMXX] %L", LANG_SERVER, "SQL_CANT_CON", error);
		//backup to users.ini
#endif
		// Make sure that the users.ini file exists.
		new configsDir[64];
		get_configsdir(configsDir, charsmax(configsDir));
		format(configsDir, charsmax(configsDir), "%s/users.ini", configsDir);

		if (!file_exists(configsDir))
		{
			console_print(id, "[%s] File ^"%s^" doesn't exist.", PLUGINNAME, configsDir);
			return;
		}

		// Make sure steamid isn't already in file.
		new line = 0, textline[256], len;
		const SIZE = 63;
		new line_steamid[SIZE + 1], line_password[SIZE + 1], line_accessflags[SIZE + 1], line_flags[SIZE + 1], parsedParams;
		
		// <name|ip|steamid> <password> <access flags> <account flags>
		while ((line = read_file(configsDir, line, textline, charsmax(textline), len)))
		{
			if (len == 0 || equal(textline, ";", 1))
			{
				continue; // comment line
			}

			parsedParams = parse(textline, line_steamid, SIZE, line_password, SIZE, line_accessflags, SIZE, line_flags, SIZE);
			
			if (parsedParams != 4)
			{
				continue;	// Send warning/error?
			}
			
			if (containi(line_flags, flags) != -1 && equal(line_steamid, auth))
			{
				console_print(id, "[%s] %s already exists!", PLUGINNAME, auth);
				return;
			}
		}

		// If we came here, steamid doesn't exist in users.ini. Add it.
		new linetoadd[512];
		
		if (comment[0] == 0)
		{
			formatex(linetoadd, charsmax(linetoadd), "^r^n^"%s^" ^"%s^" ^"%s^" ^"%s^"", auth, password, accessflags, flags);
		}
		else
		{
			formatex(linetoadd, charsmax(linetoadd), "^r^n^"%s^" ^"%s^" ^"%s^" ^"%s^" ; %s", auth, password, accessflags, flags, comment);
		}

		console_print(id, "Adding:^n%s", linetoadd);

		if (!write_file(configsDir, linetoadd))
		{
			console_print(id, "[%s] Failed writing to %s!", PLUGINNAME, configsDir);
		}
#if defined USING_SQL
	}
	
	new table[32];
	get_cvar_string("amx_sql_table", table, charsmax(table));
	
	new Handle:query = SQL_PrepareQuery(sql, "SELECT * FROM `%s` WHERE (`auth` = '%s')", table, auth);

	if (!SQL_Execute(query))
	{
		SQL_QueryError(query, error, charsmax(error));
		server_print("[AMXX] %L", LANG_SERVER, "SQL_CANT_LOAD_ADMINS", error);
		console_print(id, "[AMXX] %L", LANG_SERVER, "SQL_CANT_LOAD_ADMINS", error);
	}
	else if (SQL_NumResults(query))
	{
		console_print(id, "[%s] %s already exists!", PLUGINNAME, auth);
	}
	else
	{
		console_print(id, "Adding to database:^n^"%s^" ^"%s^" ^"%s^" ^"%s^"", auth, password, accessflags, flags);
		SQL_QueryAndIgnore(sql, "REPLACE INTO `%s` (`auth`, `password`, `access`, `flags`) VALUES ('%s', '%s', '%s', '%s')", table, auth, password, accessflags, flags);
	}
	
	SQL_FreeHandle(query);
	SQL_FreeHandle(sql);
	SQL_FreeHandle(info);
#endif
}

loadSettings(szFilename[])
{
	new file = fopen(szFilename,"r");
	
	if (file)
	{
		new text[512], flags[32], access[32], authdata[44], password[32];
		
		while (!feof(file))
		{
			fgets(file, text, charsmax(text));
			trim(text);
			
			// comment
			if (text[0]==';') 
			{
				continue;
			}
			
			flags[0] = 0;
			access[0] = 0;
			authdata[0] = 0;
			password[0] = 0;
			
			// not enough parameters
			if (parse(text, authdata, charsmax(authdata), password, charsmax(password), access, charsmax(access), flags, charsmax(flags)) < 2)
			{
				continue;
			}
			
			admins_push(authdata, password, read_flags(access), read_flags(flags));
			g_admin_count++;
		}
		
		fclose(file);
	}

	if (g_admin_count == 1)
	{
		server_print("[AMXX] %L", LANG_SERVER, "LOADED_ADMIN");
	}
	else
	{
		server_print("[AMXX] %L", LANG_SERVER, "LOADED_ADMINS", g_admin_count);
	}
	
	return 1;
}

#if defined USING_SQL
public adminSql()
{
	new table[32], error[128], type[12], errno;
	
	new Handle:info = SQL_MakeStdTuple();
	new Handle:sql = SQL_Connect(info, errno, error, charsmax(error));
	
	get_cvar_string("amx_sql_table", table, charsmax(table));
	SQL_GetAffinity(type, charsmax(type));
	
	if (sql == Empty_Handle)
	{
		server_print("[AMXX] %L", LANG_SERVER, "SQL_CANT_CON", error);
		
		//backup to users.ini
		new configsDir[64];
		get_configsdir(configsDir, charsmax(configsDir));
		format(configsDir, charsmax(configsDir), "%s/users.ini", configsDir);
		loadSettings(configsDir); // Load admins accounts

		return PLUGIN_HANDLED;
	}

	new Handle:query;
	
	if (equali(type, "sqlite"))
	{
		if (!sqlite_TableExists(sql, table))
		{
			SQL_QueryAndIgnore(sql, "CREATE TABLE %s ( auth TEXT NOT NULL DEFAULT '', password TEXT NOT NULL DEFAULT '', access TEXT NOT NULL DEFAULT '', flags TEXT NOT NULL DEFAULT '' )", table);
		}

		query = SQL_PrepareQuery(sql, "SELECT auth, password, access, flags FROM %s", table);
	}
	else
	{
		SQL_QueryAndIgnore(sql, "CREATE TABLE IF NOT EXISTS `%s` ( `auth` VARCHAR( 32 ) NOT NULL, `password` VARCHAR( 32 ) NOT NULL, `access` VARCHAR( 32 ) NOT NULL, `flags` VARCHAR( 32 ) NOT NULL ) COMMENT = 'AMX Mod X Admins'", table);
		query = SQL_PrepareQuery(sql,"SELECT `auth`,`password`,`access`,`flags` FROM `%s`", table);
	}

	if (!SQL_Execute(query))
	{
		SQL_QueryError(query, error, charsmax(error));
		server_print("[AMXX] %L", LANG_SERVER, "SQL_CANT_LOAD_ADMINS", error);
	}
	else if (!SQL_NumResults(query))
	{
		server_print("[AMXX] %L", LANG_SERVER, "NO_ADMINS");
	}
	else
	{
		g_admin_count = 0;
		
		/** do this incase people change the query order and forget to modify below */
		new qcolAuth = SQL_FieldNameToNum(query, "auth");
		new qcolPass = SQL_FieldNameToNum(query, "password");
		new qcolAccess = SQL_FieldNameToNum(query, "access");
		new qcolFlags = SQL_FieldNameToNum(query, "flags");
		
		new authdata[44], password[44], access[32], flags[32];
		
		while (SQL_MoreResults(query))
		{
			SQL_ReadResult(query, qcolAuth, authdata, charsmax(authdata));
			SQL_ReadResult(query, qcolPass, password, charsmax(password));
			SQL_ReadResult(query, qcolAccess, access, charsmax(access));
			SQL_ReadResult(query, qcolFlags, flags, charsmax(flags));
	
			admins_push(authdata, password, read_flags(access), read_flags(flags));
	
			++g_admin_count;
			SQL_NextRow(query);
		}
	
		if (g_admin_count == 1)
		{
			server_print("[AMXX] %L", LANG_SERVER, "SQL_LOADED_ADMIN");
		}
		else
		{
			server_print("[AMXX] %L", LANG_SERVER, "SQL_LOADED_ADMINS", g_admin_count);
		}
		
		SQL_FreeHandle(query);
		SQL_FreeHandle(sql);
		SQL_FreeHandle(info);
	}
	
	return PLUGIN_HANDLED;
}
#endif

public cmdReload(id, level, cid)
{
	if (!cmd_access(id, level, cid, 1))
	{
		return PLUGIN_HANDLED;
	}

	//strip original flags (patch submitted by mrhunt)
	remove_user_flags(0, read_flags("z"));
	admins_flush();

#if !defined USING_SQL
	new filename[128];
	get_configsdir(filename, charsmax(filename));
	format(filename, charsmax(filename), "%s/users.ini", filename);

	g_admin_count = 0;
	loadSettings(filename);		// Re-Load admins accounts

	if (id != 0)
	{
		if (g_admin_count == 1)
		{
			console_print(id, "[AMXX] %L", LANG_SERVER, "LOADED_ADMIN");
		}
		else
		{
			console_print(id, "[AMXX] %L", LANG_SERVER, "LOADED_ADMINS", g_admin_count);
		}
	}
#else
	g_admin_count = 0;
	adminSql();

	if (id != 0)
	{
		if (g_admin_count == 1)
		{
			console_print(id, "[AMXX] %L", LANG_SERVER, "SQL_LOADED_ADMIN");
		}
		else
		{
			console_print(id, "[AMXX] %L", LANG_SERVER, "SQL_LOADED_ADMINS", g_admin_count);
		}
	}
#endif
	new players[MAX_PLAYERS], num, pv;
	new name[MAX_NAME_LENGTH];
	get_players(players, num);

	for (new i = 0; i < num; i++)
	{
		pv = players[i];
		get_user_name(pv, name, charsmax(name));
		accessUser(pv, name);
	}

	return PLUGIN_HANDLED;
}

getAccess(id, name[], authid[], ip[], pwd[])
{
	new index = -1;
	new result = 0;
	
	static authdata[44], password[32], count, flags, access;
	g_case_sensitive_name[id] = false;
	count = admins_num();

	for (new i = 0; i < count; ++i)
	{
		flags = admins_lookup(i, AdminProp_Flags);
		admins_lookup(i, AdminProp_Auth, authdata, charsmax(authdata));
		
		if (flags & FLAG_AUTHID)
		{
			if (equal(authid, authdata))
			{
				index = i;
				break;
			}
		}
		else if (flags & FLAG_IP)
		{
			new c = strlen(authdata);
			
			if (authdata[c - 1] == '.')		/* check if this is not a xxx.xxx. format */
			{
				if (equal(authdata, ip, c))
				{
					index = i;
					break;
				}
			}									/* in other case an IP must just match */
			else if (equal(ip, authdata))
			{
				index = i;
				break;
			}
		} 
		else 
		{
			if (flags & FLAG_CASE_SENSITIVE)
			{
				if (flags & FLAG_TAG)
				{
					if (contain(name, authdata) != -1)
					{
						index = i;
						g_case_sensitive_name[id] = true;
						break;
					}
				}
				else if (equal(name, authdata))
				{
					index = i;
					g_case_sensitive_name[id] = true;
					break;
				}
			}
			else
			{
				if (flags & FLAG_TAG)
				{
					if (containi(name, authdata) != -1)
					{
						index = i;
						break;
					}
				}
				else if (equali(name, authdata))
				{
					index = i;
					break;
				}
			}
		}
	}

	if (index != -1)
	{
		access = admins_lookup(index, AdminProp_Access);

		if (flags & FLAG_NOPASS)
		{
			result |= 8;
			new sflags[32];
			
			get_flags(access, sflags, charsmax(sflags));
			set_user_flags(id, access);
			
			log_amx("Login: ^"%s<%d><%s><>^" became an admin (account ^"%s^") (access ^"%s^") (address ^"%s^")", name, get_user_userid(id), authid, authdata, sflags, ip);
		}
		else 
		{
			admins_lookup(index, AdminProp_Password, password, charsmax(password));

			if (equal(pwd, password))
			{
				result |= 12;
				set_user_flags(id, access);
				
				new sflags[32];
				get_flags(access, sflags, charsmax(sflags));
				
				log_amx("Login: ^"%s<%d><%s><>^" became an admin (account ^"%s^") (access ^"%s^") (address ^"%s^")", name, get_user_userid(id), authid, authdata, sflags, ip);
			} 
			else 
			{
				result |= 1;
				
				if (flags & FLAG_KICK)
				{
					result |= 2;
					log_amx("Login: ^"%s<%d><%s><>^" kicked due to invalid password (account ^"%s^") (address ^"%s^")", name, get_user_userid(id), authid, authdata, ip);
				}
			}
		}
	}
	else if (g_amx_mode == 2.0)
	{
		result |= 2;
	} 
	else 
	{
		new defaccess[32];
		copy(defaccess, charsmax(defaccess), g_amx_default_access);
		
		if (!strlen(defaccess))
		{
			copy(defaccess, charsmax(defaccess), "z");
		}
		
		new idefaccess = read_flags(defaccess);
		
		if (idefaccess)
		{
			result |= 8;
			set_user_flags(id, idefaccess);
		}
	}
	
	return result;
}

accessUser(id, name[] = "")
{
	remove_user_flags(id);
	
	new userip[32], userauthid[32], password[32], username[MAX_NAME_LENGTH];
	get_user_ip(id, userip, charsmax(userip), 1);
	get_user_authid(id, userauthid, charsmax(userauthid));
	
	if (name[0])
	{
		copy(username, charsmax(username), name);
	}
	else
	{
		get_user_name(id, username, charsmax(username));
	}
	
	get_user_info(id, g_amx_password_field, password, charsmax(password));
	
	new result = getAccess(id, username, userauthid, userip, password);
	
	if (result & 1)
	{
		engclient_print(id, engprint_console, "* %L", id, "INV_PAS");
	}
	
	if (result & 2)
	{
		server_cmd("kick #%d ^"%L^"", get_user_userid(id), id, "NO_ENTRY");
		return PLUGIN_HANDLED;
	}
	
	if (result & 4)
	{
		engclient_print(id, engprint_console, "* %L", id, "PAS_ACC");
	}
	
	if (result & 8)
	{
		engclient_print(id, engprint_console, "* %L", id, "PRIV_SET");
	}
	
	return PLUGIN_CONTINUE;
}

public client_infochanged(id)
{
	if (!is_user_connected(id) || !g_amx_mode)
	{
		return PLUGIN_CONTINUE;
	}

	new newname[MAX_NAME_LENGTH], oldname[MAX_NAME_LENGTH];
	get_user_name(id, oldname, charsmax(oldname));
	get_user_info(id, "name", newname, charsmax(newname));

	if (g_case_sensitive_name[id])
	{
		if (!equal(newname, oldname))
		{
			accessUser(id, newname);
		}
	}
	else
	{
		if (!equali(newname, oldname))
		{
			accessUser(id, newname);
		}
	}

	return PLUGIN_CONTINUE;
}

public client_authorized(id)
{
	return g_amx_mode ? accessUser(id) : PLUGIN_CONTINUE;
}

public client_putinserver(id)
{
	if (!is_dedicated_server() && id == 1)
	{
		return g_amx_mode ? accessUser(id) : PLUGIN_CONTINUE;
	}
	
	return PLUGIN_CONTINUE;
}
