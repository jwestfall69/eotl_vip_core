#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include "eotl_vip_core.inc"

#define PLUGIN_AUTHOR  "ack"
#define PLUGIN_VERSION "2.01"

#define DB_CONFIG      "default"
#define DB_TABLE       "vip_users"
#define DB_COL_ICONID  "iconID"
#define DB_COL_STEAMID "steamID"


#define RETRY_LOADVIPMAPS_TIME  10.0

public Plugin myinfo = {
	name = "eotl_vip_core",
	author = PLUGIN_AUTHOR,
	description = "eotl vip plugin that contains core vip related function calls",
	version = PLUGIN_VERSION,
	url = ""
};

enum struct PlayerState {
	bool isVip;
	char steamID[EOTL_STEAMID_LENGTH];
	char iconID[EOTL_ICONID_MAX_LENGTH];
}

GlobalForward g_EotlOnPostClientVipCheckForward;
PlayerState g_playerStates[MAXPLAYERS + 1];
ConVar g_cvDebug;
StringMap g_vipMap;
StringMap g_vipIconMap;

public void OnPluginStart() {
	LogMessage("version %s starting", PLUGIN_VERSION);
	g_cvDebug = CreateConVar("eotl_vip_debug", "0", "0/1 enable debug output", FCVAR_NONE, true, 0.0, true, 1.0);
	g_EotlOnPostClientVipCheckForward = CreateGlobalForward("EotlOnPostClientVipCheck", ET_Event, Param_Cell, Param_Cell);
}

public void OnMapStart() {
	for (int client = 1; client <= MaxClients; client++) {
		g_playerStates[client].isVip = false;
		g_playerStates[client].steamID[0] = '\0';
		g_playerStates[client].iconID[0] = '\0';
    }

	if(!SQL_CheckConfig(DB_CONFIG)) {
        SetFailState("Database config \"%s\" doesn't exist", DB_CONFIG);
    }

	g_vipMap = CreateTrie();
	g_vipIconMap = CreateTrie();

	if(!LoadVipMaps()) {
		LogError("Database issue, will retry every %f seconds", RETRY_LOADVIPMAPS_TIME);
		CreateTimer(RETRY_LOADVIPMAPS_TIME, RetryLoadVipMaps);
	}
}

public void OnMapEnd() {
    CloseHandle(g_vipMap);
    CloseHandle(g_vipIconMap);
}

public void OnClientDisconnect(int client) {
	g_playerStates[client].isVip = false;
	g_playerStates[client].steamID[0] = '\0';
	g_playerStates[client].iconID[0] = '\0';
}

public void OnClientAuthorized(int client, const char[] auth) {

	if(IsFakeClient(client)) {
		return;
	}

	strcopy(g_playerStates[client].steamID, EOTL_STEAMID_LENGTH, auth);

	int junk;
	if(GetTrieValue(g_vipMap, auth, junk)) {
		g_playerStates[client].isVip = true;
		GetTrieString(g_vipIconMap, auth, g_playerStates[client].iconID, EOTL_ICONID_MAX_LENGTH);
	}

	LogMessage("client %N (%s) vip: %s", client, auth, (g_playerStates[client].isVip ? "YES" : "NO"));

	LogDebug("Calling EotlOnPostClientVipCheck forwards");
	Call_StartForward(g_EotlOnPostClientVipCheckForward);
	Call_PushCell(client);
	Call_PushCell(g_playerStates[client].isVip);
	Call_Finish();
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	RegPluginLibrary("eotl_vip_core");
	CreateNative("EotlIsClientVip", Native_EotlIsClientVip);
	CreateNative("EotlIsSteamIDVip", Native_EotlIsSteamIDVip);
	CreateNative("EotlGetClientVipIcon", Native_EotlGetClientVipIcon);
	return APLRes_Success;
}

// native bool EotlIsClientVip(int client);
public int Native_EotlIsClientVip(Handle hPlugin, int numParams) {
	int client = GetNativeCell(1);

	if(client < 1 || client > MaxClients) {
		LogError("EotlIsClientVipp: called with invalid client number: %d", client);
		return false;
	}
	return g_playerStates[client].isVip;
}

// native bool EotlIsSteamIDVip(const char[] steamID);
public int Native_EotlIsSteamIDVip(Handle hPlugin, int numParams) {

	if(numParams != 1) {
		LogError("EotlIsSteamIDVip: called with incorrect number of params: %d (expected 1)", numParams);
		return false;
	}

	char steamID[EOTL_STEAMID_LENGTH];
	GetNativeString(1, steamID, EOTL_STEAMID_LENGTH);

	int junk;
	if(!GetTrieValue(g_vipMap, steamID, junk)) {
		return false;
	}

	return true;
}

// native bool EotlGetClientVipIcon(int client, char[] iconID, int maxlength);
public int Native_EotlGetClientVipIcon(Handle hplugin, int numParams) {
	if(numParams != 3) {
		LogError("EotlGetClientVipIcon: called with incorrect number of params: %d (expected 3)", numParams);
	}

	int client = GetNativeCell(1);
	if(client < 1 || client > MaxClients) {
		LogError("EotlGetClientVipIcon: called with invalid client number: %d", client);
		return false;
	}

	if(!g_playerStates[client].isVip) {
		LogError("EotlGetClientVipIcon: client %N is not a vip!", client);
		return false;
	}
	int maxlength = GetNativeCell(3);
 	if (maxlength <= 0) {
		LogError("EotlGetClientVipIcon: bogus string length of %d", maxlength);
		return false;
	}

	if(strlen(g_playerStates[client].iconID) == 0) {
		LogError("EotlGetClientVipIcon: client %n is a vip, but doesn't have an icon!?", client);
		return false;
	}

	SetNativeString(2, g_playerStates[client].iconID, maxlength, false);
	return true;
}

public Action RetryLoadVipMaps(Handle timer) {
    if(!LoadVipMaps()) {
        CreateTimer(RETRY_LOADVIPMAPS_TIME, RetryLoadVipMaps);
        return Plugin_Continue;
    }

    return Plugin_Continue;
}

// pull in vip info from the database and store them in a couple maps
bool LoadVipMaps() {
	Handle dbh;
	char error[256];

	dbh = SQL_Connect(DB_CONFIG, false, error, sizeof(error));
	if(dbh == INVALID_HANDLE) {
		LogError("LoadVipMaps: connection to database failed (DB config: %s): %s", DB_CONFIG, error);
		return false;
	}

	char query[128];
	Format(query, sizeof(query), "SELECT %s, %s from %s", DB_COL_STEAMID, DB_COL_ICONID, DB_TABLE);

	DBResultSet results;
	results = SQL_Query(dbh, query);
	CloseHandle(dbh);

	// this seems to be an indication we aren't connected to the database
	if(results == INVALID_HANDLE) {
		LogError("LoadVipMaps: SQL_Query returned INVALID_HANDLE. Something maybe wrong with the connection to the database");
		return false;
	}

	if(results.RowCount <= 0) {
		LogMessage("LoadVipMaps: SQL_Query return no results!");
		CloseHandle(results);
		return true;
	}

	while(results.FetchRow()) {
		char steamID[EOTL_STEAMID_LENGTH];
		if(results.FetchString(0, steamID, sizeof(steamID))) {
			SetTrieValue(g_vipMap, steamID, 1, true);
		}

		char iconID[EOTL_ICONID_MAX_LENGTH];
		if(results.FetchString(1, iconID, sizeof(iconID))) {
			SetTrieString(g_vipIconMap, steamID, iconID);
		}
	}

	LogMessage("Loaded %d vips from database", GetTrieSize(g_vipMap));
	CloseHandle(results);

	LogMessage("Checking VIP for connected clients");
	char steamID[32];
	int junk;
	for(int client = 1;client <= MaxClients;client++) {
		if(!IsClientConnected(client) || IsFakeClient(client)) {
			continue;
		}

		if(GetClientAuthId(client, AuthId_Steam2, steamID, sizeof(steamID))) {
			if(GetTrieValue(g_vipMap, steamID, junk)) {
				LogMessage("%N (%s) is a vip", client, steamID);
				g_playerStates[client].isVip = true;
			}
		}
	}

	return true;
}

void LogDebug(char []fmt, any...) {

    if(!g_cvDebug.BoolValue) {
        return;
    }

    char message[128];
    VFormat(message, sizeof(message), fmt, 2);
    LogMessage(message);
}