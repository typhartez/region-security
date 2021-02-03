// Region Security - avatars scanning on a region
// Copyright 2021 Typhaine Artez
// Based on ideas from gimisa@yahoo.fr (script testBanIPName140531)
// latest version always available at: https://github.com/typhartez/region-security
//
// Provided under Creative Commons Attribution-Non-Commercial-ShareAlike 4.0 International license.
// Please be sure you read and adhere to the terms of this license: https://creativecommons.org/licenses/by-nc-sa/4.0/
//
// 1.1 2021/02/04 - fixed a bug in grid ban

////////////////////////////////////////////////////////////////////////////////////////////////////
// Options

integer debug = FALSE;   // in debug mode, wont do any action against agents
integer scanTime = 30; // scan each scantime seconds
integer banPartialNames = FALSE;    // ban all avatar matching the beginning with any entry in the banlist
string fallbackTeleport = "";
integer maxKicks = 0; // if more than 0, maximum number of kicks before agent is definitively banned
integer minAge = 0; // if more than 0, age under which agent is kicked
integer maxPrims = 0;   // if more than 0, maximum number of rezzed prims before agent is kicked
integer allowFlying = TRUE; // if FALSE and agent is flying, agent is kicked
integer maxScripts = 0; // if more than 0, maximum number of running scripts
integer maxMemory = 0; // if more than 0, maximum amount of memory
//integer maxARC = 0; // if more than 0, maximum ARC for an agent (opensim does not suppor it yet)
integer minSize = 0; // if more than 0, minimum size of an agent
integer maxSize = 0; // if more than 0, maximum size of an agent

////////////////////////////////////////////////////////////////////////////////////////////////////
// State variables

key ncConfig = NULL_KEY;    // config notecard key for changes detection
key ncBanlist = NULL_KEY;   // banlist notecard key for changes detection
key ncWhitelist = NULL_KEY; // whitelist notecard key for changes detection
key ncKicklist = NULL_KEY;  // kicklist notecard key for changes detection

list banList;   // IP or partial agent name or agent key
list whiteList; // key or IP
list kickList;  // list of kicked agents (key, number of kicks)
list lastScan;  // from osGetAvatarList()
list queries;   // queryID, agent key
list pending;   // notifications for the owner
integer online = -1;    // owner is online (updated by dataserver)
key queryOnline = NULL_KEY; // dataserver query id for owner online status

string menu_cur;    // current menu
list menu_list;     // list of items in the menu
key menu_agent = NULL_KEY;     // selected agent in menu
integer menu_page;  // current page on multi-pages agent list
integer menu_chan;  // listening channel for menu

////////////////////////////////////////////////////////////////////////////////////////////////////
// shortcut to check if a notecard exists
integer isNotecard(string nc) {
    return (integer)(INVENTORY_NOTECARD == llGetInventoryType(nc));
}

////////////////////////////////////////////////////////////////////////////////////////////////////
integer notecardChanged(string nc, key knownKey) {
    return (integer)(llGetInventoryKey(nc) != knownKey);
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// accept strings "1", "true", "t", "on" as boolean TRUE, FALSE otherwise
integer readBool(string str) {
    return llList2Integer([0, 1], (-1 != llListFindList(["1", "true", "t", "on"], [llToLower(str)])));
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// returns a string representation of a boolean
string bool2str(integer b) {
    return llList2String(["false","true"], (integer)(b != 0));
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// transform YYYY-MM-DD to a number of days
integer date2days(string date) {
    integer y = (integer)llGetSubString(date, 0, 3);
    integer m = (integer)llGetSubString(date, 5, 6);
    integer d = (integer)llGetSubString(date, 8, 9);

    m = (m + 9) % 12; // mar=0, feb=11
    y = y - 1600 - m/10; // if Jan/Feb, minus one year
    return y * 365 + y/4 - y/100 + y/400 + (m * 306 + 5)/10 + (d - 1);
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// load configuration from 'config' notecard
loadConfig() {
    if (!isNotecard("config")) saveConfig();
    list content = llParseString2List(osGetNotecard("config"), ["\n","\r"], []);
    integer pos;
    string prm;
    string val;
    integer c = llGetListLength(content);
    while (~(--c)) {
        prm = llStringTrim(llList2String(content, c), STRING_TRIM);
        if ("" != prm && 0 != llSubStringIndex(prm, "#") && -1 != (pos = llSubStringIndex(prm, "="))) {
            val = llStringTrim(llGetSubString(prm, pos+1, -1), STRING_TRIM_HEAD);
            prm = llToLower(llStringTrim(llGetSubString(prm, 0, pos-1), STRING_TRIM_TAIL));
            if ("scan_time" == prm) {
                scanTime = (integer)val;
                if (!scanTime) scanTime = 30; // set default
            }
            else if ("fallback_teleport" == prm) fallbackTeleport = val;
            else if ("debug" == prm) debug = readBool(val);
            else if ("ban_partial_names" == prm) banPartialNames = readBool(val);
            else if ("max_kicks" == prm) maxKicks = (integer)val;
            else if ("min_age" == prm) minAge = (integer)val;
            else if ("max_prims" == prm) maxPrims = (integer)val;
            else if ("allow_flying" == prm) allowFlying = (integer)val;
            else if ("max_scripts" == prm) maxScripts = (integer)val;
            else if ("max_memory" == prm) maxMemory = (integer)val;
            //else if ("max_avatar_render_cost" == prm) maxARC = (integer)val;
            else if ("min_size" == prm) minSize = (integer)val;
            else if ("max_size" == prm) maxSize = (integer)val;
        }
    }
    llOwnerSay("Security configuration loaded");
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// save current configuration into notecard
saveConfig() {
    if (isNotecard("config")) {
        llRemoveInventory("config");
        llSleep(0.2);
    }
    osMakeNotecard("config", [
        "# auto-generated",
        "",
        "# time in seconds between 2 region scans",
        "scan_time = "+(string)scanTime,
        "# detect partial names in ban list",
        "ban_partial_names = "+bool2str(banPartialNames),
        "# ban agent if it has been kicked too much times (0 to disable)",
        "max_kicks = "+(string)maxKicks,
        "# fallback teleport if avatar does not have a home",
        "fallback_teleport = "+fallbackTeleport,
        "",
        "# Kicking rules --------------------------------------------------------------------------",
        "",
        "# agents too young are kicked (0 to disable)",
        "min_age = "+(string)minAge,
        "# agents rezzing too much prims at once are kicked (0 to disable)",
        "max_prims = "+(string)maxPrims,
        "# agents are allowed to fly (using viewer force flying) even if forbidden on the parcel",
        "allow_flying = "+bool2str(allowFlying),
        "# agents having too much scripts running are kicked (0 to disable)",
        "max_scripts = "+(string)maxScripts,
        "# agents using too much script memory are kicked (0 to disable)",
        "max_memory = "+(string)maxMemory,
        //"# agents too complex on render are kicked (0 to disable)",
        //"max_avatar_render_cost = "+(string)maxARC,
        "# agents too small (in cm) are kicked (0 to disable)",
        "min_size = "+(string)minSize,
        "# agents too tall (in cm) are kicked (0 to disable)",
        "max_size = "+(string)maxSize
    ]);
    llSleep(0.2);
    ncConfig = llGetInventoryKey("config");
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// load ban list from 'banlist' notecard
loadBanlist() {
    if (!isNotecard("banlist")) saveBanlist();
    banList = [];
    list content = llParseString2List(osGetNotecard("banlist"), ["\n","\r"], []);
    string line;
    integer c = llGetListLength(content);
    while (~(--c)) {
        line = llStringTrim(llList2String(content, c), STRING_TRIM);
        if ("" != line && 0 != llSubStringIndex(line, "#")) banList += llToLower(line);
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// save current ban list into notecard
saveBanlist() {
    if (isNotecard("banlist")) {
        llRemoveInventory("banlist");
        llSleep(0.2);
    }
    osMakeNotecard("banlist", ["# auto-generated", ""] + banList);
    llSleep(0.2);
    ncBanlist = llGetInventoryKey("banlist");
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// load white list from 'whitelist' notecard
loadWhitelist() {
    if (!isNotecard("whitelist")) saveWhitelist();
    whiteList = [];
    list content = llParseString2List(osGetNotecard("whitelist"), ["\n","\r"], []);
    string line;
    integer c = llGetListLength(content);
    while (~(--c)) {
        line = llStringTrim(llList2String(content, c), STRING_TRIM);
        if ("" != line && 0 != llSubStringIndex(line, "#")) whiteList += line;
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// save current white list into notecard
saveWhitelist() {
    if (isNotecard("whitelist")) {
        llRemoveInventory("whitelist");
        llSleep(0.2);
    }
    osMakeNotecard("whitelist", ["# auto-generated", ""] + whiteList);
    llSleep(0.2);
    ncWhitelist = llGetInventoryKey("whitelist");
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// load kick list from 'kicklist' notecard
loadKicklist() {
    if (!isNotecard("kicklist")) saveKicklist();
    kickList = [];
    list content = llParseString2List(osGetNotecard("kicklist"), ["\n","\r"], []);
    string line;
    integer pos;
    string agent;
    integer c = llGetListLength(content);
    while (~(--c)) {
        line = llStringTrim(llList2String(content, c), STRING_TRIM);
        if ("" != line && 0 != llSubStringIndex(line, "#") && -1 != (pos = llSubStringIndex(line, " "))) {
            agent = llGetSubString(line, pos+1, -1);
            if (osIsUUID(agent)) {
                // get number of kicks in pos
                pos = (integer)llGetSubString(line, 0, pos-1);
                kickList += [(key)agent, pos];
            }
        }
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// save current kick list in 'kicklist' notecard
saveKicklist() {
    if (isNotecard("kicklist")) {
        llRemoveInventory("kicklist");
        llSleep(0.2);
    }
    list kicks;
    integer c = llGetListLength(kickList) - 2;
    for (; -1 < c; c -= 2) kicks += (string)llList2Integer(kickList, c+1)+" "+(string)llList2Key(kickList, c);
    osMakeNotecard("kicklist", ["# auto-generated", ""] + kicks);
    llSleep(0.2);
    ncKicklist = llGetInventoryKey("kicklist");
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// returns the reason of ban any of agent key, name, grid or IP is known to be banned
string isBanned(key agent, string name, string IP) {
    integer c = llGetListLength(banList);
    string entry;
    integer pos;
    name = llToLower(name);
    while (~(--c)) {
        entry = llList2String(banList, c);
        // check agent key, the faster
        if (osIsUUID(entry) && agent == (key)entry) return "agent banned";
        // or IP
        if (entry == IP) return "IP banned";
        // check if the whole grid is banned
        pos = llSubStringIndex(name, " @");
        if (!llSubStringIndex(entry, "@")) {
            if (-1 != pos && llGetSubString(entry, 1, -1) == llGetSubString(name, pos+2, -1))
                return "grid banned";
        }
        // then check name
        else {
            //if (~pos) name = llGetSubString(name, 0, pos-1);
            name = osReplaceString(osReplaceString(name, " ?@.*$", "", 1, 0), "\\.", " ", -1, 0);
            entry = osReplaceString(osReplaceString(entry, " ?@.*$", "", 1, 0), "\\.", " ", -1, 0);
            if ((TRUE == banPartialNames && -1 != ~llSubStringIndex(name, entry)) || name == entry)
                return "name banned";
        }
    }
    return "";
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Report to owner an action taken on an agent
reportToOwner(string reason, key agent, string name, string IP, vector pos) {
//    if (online) llInstantMessage(llGetOwner(), "Region " + llGetRegionName() + ": " +
//        name + " has been " + reason);
    /*else */pending += [agent, name, IP, pos, reason];
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Inform an agent about ban on themselves
informBannedAgent(string reason, key agent, string name, string IP, vector pos) {
    reportToOwner(reason, agent, name, IP, pos);

    if (!debug) {
        llInstantMessage(agent, "You are banned from this region: "+reason);
        llMessageLinked(LINK_SET, 0, "teleport "+fallbackTeleport, agent);
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Check if an agent should be kicked and returns the reason if so
string agentShouldBeKicked(key agent, string name, string IP, vector pos) {
    list l;
    integer i;
    if (maxPrims) {
        l = llGetParcelPrimOwners(pos);
        if (-1 != (i = llListFindList(l, [agent])) && llList2Integer(l, i+1) > maxPrims)
            return "rezzing too much prims";
    }
    if (!allowFlying && (AGENT_FLYING & llGetAgentInfo(agent))) return "force flying when it's not allowed";

    l = llGetObjectDetails(agent, [OBJECT_RUNNING_SCRIPT_COUNT, OBJECT_SCRIPT_MEMORY, OBJECT_RENDER_WEIGHT]);
    if (0 < maxScripts && llList2Integer(l, 0) > maxScripts) return "too many scripts";
    if (0 < maxMemory && llList2Integer(l, 1) > maxMemory) return "too much memory used in scripts";
    //if (0 < maxARC && llList2Integer(l, 2) > maxARC) return "too high avatar render cost";
    if (0 < minSize || 0 < maxSize) {
        vector size = llGetAgentSize(agent);
        if (0 < minSize && size.z*100 < (float)minSize) return "too tiny";
        if (0 < maxSize && size.z*100 > (float)maxSize) return "too tall";
    }
    return "";
}

////////////////////////////////////////////////////////////////////////////////////////////////////
// Kick an agent, and auto ban if kicked more than the maximum allowed
kickAgent(string reason, key agent, string name, string IP, vector pos) {
    // store kick
    integer i = llListFindList(kickList, [agent]);
    if (!~i) {
        kickList += [agent, 1];
        i = llGetListLength(kickList) - 2;
    }
    else {
        kickList = llListReplaceList(kickList, [llList2Integer(kickList, i+1)+1], i+1, i+1);
    }
    if (0 < maxKicks && maxKicks < llList2Integer(kickList, i+1)) {
        // agent has already been kicked too much times, ban by key and IP!
        banList += [agent, IP];
        saveBanlist();
        kickList = llDeleteSubList(kickList, i, i+1);
        saveKicklist();
        informBannedAgent("kicked: "+reason, agent, name, IP, pos);
        return;
    }
    saveKicklist();
    reportToOwner("kicked: "+reason, agent, name, IP, pos);
    if (!debug) {
        llInstantMessage(agent, "You are automatically kicked because " + reason);
        llMessageLinked(LINK_SET, 0, "teleport "+fallbackTeleport, agent);
    }
}


////////////////////////////////////////////////////////////////////////////////////////////////////
// Show the menu
menu() {
    key owner = llGetOwner();
    if (!menu_chan) {
        menu_chan = 0x80000000 | ((integer)("0x"+llGetSubString((string)llGetKey(),0, 7))
            ^ ((integer)llFrand(0x7FFFFFB0) + 1));
        llListen(menu_chan, "", owner, "");
    }
    string txt;
    list b;
    integer i;
    integer c;
    if ("" == menu_cur) {
        // -----------------------------------------------------------------------------------------
        // main menu - list avatars on region
        list avatars = llList2ListStrided(osGetAvatarList(), 0, -1, 3);
        // remove NPCs
        i = llGetListLength(avatars);
        while (~(--i)) if (osIsNpc(llList2Key(avatars, i))) avatars = llDeleteSubList(avatars, i, i);
        // check if list previously retrieved or avatars changed
        if ([] == menu_list || -1 == llListFindList(menu_list, avatars)) {
            menu_list = avatars;
            menu_page = 0;
        }
        c = llGetListLength(menu_list);
        if (!c) {
            txt = "No avatar around";
            b = [" "];
        }
        else {
            txt = "Select an agent in the list:";
            for (i = menu_page*10; i < menu_page*10+9 && i < c; ++i) {
                txt += "\n"+(string)i+" - " + llKey2Name(llList2Key(menu_list, menu_page*10+i));
                b += (string)i;
            }
            if (12 > c) {
                for (i = 10; i < 13 && i < c; ++i) {
                    txt += "\n"+(string)i+" - " + llKey2Name(llList2Key(menu_list, i));
                    b += (string)i;
                }
            }
            else {
                while (10 > llGetListLength(b)) b += " ";
                b += ["◀ PAGE", "PAGE ▶"];
            }
        }
    }
    else if ("DETAILS" == menu_cur) {
        // -----------------------------------------------------------------------------------------
        // Show agent information and give actions
        txt = "Information about " + llKey2Name(menu_agent) + ":";
        txt += "\nIP = " + osGetAgentIP(menu_agent);
        list l = llGetObjectDetails(menu_agent, [
            OBJECT_RUNNING_SCRIPT_COUNT, OBJECT_SCRIPT_MEMORY, OBJECT_RENDER_WEIGHT, OBJECT_POS
        ]);
        txt += "\nRunning scripts = " + (string)llList2Integer(l, 0);
        txt += "\nScripts memory = " + (string)llList2Integer(l, 1);
        //txt += "\nRender cost (ARC) = " + (string)llList2Integer(l, 2);
        vector v = llGetAgentSize(menu_agent);
        txt += "\nSize = " + (string)((integer)(v.z * 100)) + " cm";
        v = llList2Vector(l, 3);
        integer x = (integer)v.x;
        integer y = (integer)v.y;
        integer z = (integer)v.z;
        txt += "\nPosition = <"+(string)x+", "+(string)y+", "+(string)z+">";

        b += [
            "♥ Whitelist", "☢ Kick", "☠ Ban",
            "◀ PREV", "LIST", "NEXT ▶"
        ];
    }
    if ("" != txt) {
        if ([] == b) llTextBox(owner, txt, menu_chan);
        else {
            while (llGetListLength(b) % 3) b += " ";
            llDialog(owner, txt,
                llList2List(b,9,11)+llList2List(b,6,8)+llList2List(b,3,5)+llList2List(b,0,2),
                menu_chan);
        }
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////
default {
    // ---------------------------------------------------------------------------------------------
    attach(key id) {
        if (NULL_KEY != id) llRequestPermissions(llGetOwner(), PERMISSION_ATTACH);
    }
    run_time_permissions(integer p) {
        if (PERMISSION_ATTACH & p) {
            // attaching is not allowed
            llOwnerSay("Attaching this tool to the avatar is not allowed. Rez it!");
            llDetachFromAvatar();
        }
    }
    // ---------------------------------------------------------------------------------------------
    on_rez(integer p) {
        llResetScript();
    }
    // ---------------------------------------------------------------------------------------------
    changed(integer c) {
        if (CHANGED_OWNER & c) {
            llRemoveInventory("config");
            llRemoveInventory("banlist");
            llRemoveInventory("whitelist");
            llRemoveInventory("kicklist");
            llResetScript();
        }
        if (CHANGED_INVENTORY & c) {
            if (INVENTORY_NOTECARD != llGetInventoryType(".inactive")) {
                if (llGetInventoryKey("config") != ncConfig) loadConfig();
                if (llGetInventoryKey("banlist") != ncBanlist) loadBanlist();
                if (llGetInventoryKey("whitelist") != ncWhitelist) loadWhitelist();
                if (llGetInventoryKey("kicklist") != ncKicklist) loadKicklist();
                lastScan = [];
                if (0 < scanTime) llSetTimerEvent(0.5);
            }
        }
        if ((CHANGED_REGION | CHANGED_REGION_RESTART) & c) menu_chan = 0;
    }
    // ---------------------------------------------------------------------------------------------
    state_entry() {
        if (INVENTORY_NOTECARD != llGetInventoryType(".inactive")) {
            loadConfig();
            loadBanlist();
            loadWhitelist();
            loadKicklist();
            if (0 < scanTime) llSetTimerEvent(0.5);
        }
    }
    // ---------------------------------------------------------------------------------------------
    timer() {
        llMessageLinked(LINK_SET, 1, "scan", "");
        llSetTimerEvent(scanTime);
        list avatars = osGetAvatarList();
        if (~llListFindList(lastScan, avatars)) return; // no change

        key agent;
        string name;
        string IP;
        vector pos;
        string reason;
        integer c = llGetListLength(avatars) - 3; // key, position, name
        for (; -1 < c; c -= 3) {
            agent = llList2Key(avatars, c);
            if (osIsNpc(agent)) jump nextAgent; // do not check NPC
            if (~llListFindList(whiteList, [agent])) jump nextAgent; // white listed
            pos = llList2Vector(avatars, c+1);
            name = llList2String(avatars, c+2);
            IP = osGetAgentIP(agent);
            reason = isBanned(agent, name, IP);
            if ("" != reason) {
                informBannedAgent(reason, agent, name, IP, pos);
                jump nextAgent;
            }
@notBanned;
            // following are just kicks depending on agent status
            if ("" != (reason = agentShouldBeKicked(agent, name, IP, pos))) {
                kickAgent(reason, agent, name, IP, pos);
            }
            // check age
            if (0 < minAge) {
                queries = [llRequestAgentData(agent, DATA_BORN), agent, name, IP, pos] + queries;
                if (NULL_KEY == llList2Key(queries, 0)) queries = llDeleteSubList(queries, 0, 4);
            }
@nextAgent;
        }
        if ([] == queries) llMessageLinked(LINK_SET, 0, "scan", "");
        queryOnline = llRequestAgentData(llGetOwner(), DATA_ONLINE);
    }
    // ---------------------------------------------------------------------------------------------
    dataserver(key id, string data) {
        integer i;
        if (queryOnline == id) {
            // check owner online status
            i = online;
            online = (integer)data;
            if (TRUE == online && [] != pending) {
                data = "Region " + llGetRegionName();
                if (FALSE == i) data += " performed the following actions during your absence:";
                else data += " actions on avatars:";
                i = llGetListLength(pending) - 5;
                for (; -1 < i; i -= 5)
                    data += "\n"+llList2String(pending, i+1)+" has been "+llList2String(pending, i+4);
                llInstantMessage(llGetOwner(), data);
                pending = [];
            }
            queryOnline = NULL_KEY;
        }
        else {
            // check pending queries on avatars age
            i = llListFindList(queries, [id]);
            if (~i) {
                key agent = llList2Key(queries, i+1);
                // get agent age 
                integer days = date2days(llGetDate()) - date2days(data);
                if (days < minAge) kickAgent("age", agent, llList2String(queries, i+2),
                    llList2String(queries, i+3), llList2Vector(queries, i+4));
                queries = llDeleteSubList(queries, i, i+4);
                if ([] == queries) llMessageLinked(LINK_SET, 0, "scan", "");
            }
        }
    }
    // ---------------------------------------------------------------------------------------------
    touch_start(integer n) {
        if (llGetOwner() != llDetectedKey(0)) return;
        menu_cur = "";
        menu_list = [];
        menu_agent = NULL_KEY;
        menu_page = 0;
        menu();
    }
    // ---------------------------------------------------------------------------------------------
    listen(integer c, string name, key id, string msg) {
        if (" " == msg) { menu(); return; }
        if ("" == menu_cur) {
            if ("◀ PAGE" == msg) {
                --menu_page;
                if (0 > menu_page) menu_page = 0;
            }
            else if ("PAGE ▶" == msg) {
                ++menu_page;
                if (menu_page*10 > llGetListLength(menu_list)) menu_page = 0;
            }
            else {
                menu_agent = llList2Key(menu_list, (integer)msg);
                menu_cur = "DETAILS";
            }
        }
        else if ("DETAILS" == menu_cur) {
            if ("♥ Whitelist" == msg) {
                if (!~llListFindList(whiteList, [menu_agent])) {
                    whiteList += menu_agent;
                    saveWhitelist();
                }
            }
            else if ("☢ Kick" == msg) {
                kickAgent("owner kicked", menu_agent, llKey2Name(menu_agent),
                    osGetAgentIP(menu_agent),
                    llList2Vector(llGetObjectDetails(menu_agent, [OBJECT_POS]), 0)
                );
            }
            else if ("☠ Ban" == msg) {
                if (!~llListFindList(banList, [menu_agent])) {
                    banList += [menu_agent, osGetAgentIP(menu_agent)];
                    saveBanlist();
                }
            }
            else if ("◀ PREV" == msg) {
                c = llListFindList(menu_list, [menu_agent]);
                if (~c) {
                    --c;
                    if (0 > c) c = llGetListLength(menu_list) - 1;
                    menu_agent = llList2Key(menu_list, c);
                    menu_page = c / 10;
                }
            }
            else if ("LIST" == msg) {
                menu_agent = NULL_KEY;
                menu_cur = "";
            }
            else if ("NEXT ▶" == msg) {
                c = llListFindList(menu_list, [menu_agent]);
                if (~c) {
                    ++c;
                    if (llGetListLength(menu_list) <= c) c = 0;
                    menu_agent = llList2Key(menu_list, c);
                    menu_page = c / 10;
                }
            }
        }
        menu();
    }

}
