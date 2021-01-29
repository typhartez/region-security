// Security Teleport - teleporting avatars to home or a specific region if they do not have a home
// Copyright 2021 Typhaine Artez
//
// Provided under Creative Commons Attribution-Non-Commercial-ShareAlike 4.0 International license.
// Please be sure you read and adhere to the terms of this license: https://creativecommons.org/licenses/by-nc-sa/4.0/
default {
    link_message(integer sender, integer num, string str, key id) {
        if (!(num = llSubStringIndex(str, "teleport "))) {
            llTeleportAgentHome(id);
            str = llGetSubString(str, 9, -1);
            if ("" != str) osTeleportAgent(id, str, ZERO_VECTOR, ZERO_VECTOR);
        }
    }
}