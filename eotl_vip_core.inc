#define EOTL_STEAMID_LENGTH   32
#define EOTL_ICONID_MAX_LENGTH 32

native bool EotlIsClientVip(int client);
native bool EotlIsSteamIDVip(const char[] steamID);
native bool EotlGetClientVipIcon(int client, char[] iconID, int maxlength);

// will be called once a connected client has been checked for vip status
forward void EotlOnPostClientVipCheck(int client, bool isVip);