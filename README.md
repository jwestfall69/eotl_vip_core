# eotl_vip_core
This is a TF2 sourcemod plugin I wrote for the [EOTL](https://www.endofthelinegaming.com/) community.

This plugin provides an API that other EOTL plugins can use when they need to determine if a client or steamID is a VIP.

### Dependencies
<hr>

**Database**<br>

This plugin is expecting the following to exist (hardcoded as its what we need)

* Database config named 'default'
* Table on that database named 'vip_users'
* Columns in that table named 'streamID' and 'iconID'

vip info is reloaded from the database at the start of each map.

### Exported Functions
<hr>

**bool EotlIsClientVip(int client)**<br>

Returns true if the passed client is a VIP, otherwise false.


**bool EotlIsSteamIDVip(const char[] steamID)**<br>

Returns true if the passed steamID is a VIP, otherwise false.


**bool EotlGetClientVipIcon(int client, char[] iconID, int maxlength)**

Populates the passed iconID string with the VIP's iconID from the database.  It will return true if successful or false if there was an issue (ie: passed a client thats not a VIP).


### Forwarded Functions
<hr>

**void EotlOnPostClientVipCheck(int client, bool isVip)**

This forward function will be called once a connected client has been checked for vip status.

### Using The Functions
<hr>
In order to use the functions in your code you will need to include 'eotl_vip_core.inc' in your plugin code.  Additionally the eotl_vip_core.smx plugin must be installed on the server.