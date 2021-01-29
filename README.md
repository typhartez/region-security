# Region security

Kick and ban management for owned region

Typhaine Artez 2021 <typhaine.artez @grid.sacrarium.su:8888>

Provided under Creative Commons Attribution-Non-Commercial-ShareAlike 4.0 International license.

Please be sure you read and adhere to the terms of this license: https://creativecommons.org/licenses/by-nc-sa/4.0/

## Features

* flexable ban list (name, partial name, key, IP, grid name)
* many kick rules (age, size, scripts, force flying)
* automatic ban after an amount of kicks
* white list
* simple menu to check avatars information on the region and do actions (whiltelist, kick, ban)

## Setup

Copy the content of the folder in a prim on a region you own. The script is reset as soon as it is put in a rezzed object.

By default, it is not active because of the presence of the `.inactive` notecard. Delete this notecard, the script will
generate needed notecards.

Open the `config` notecard that the script has generated. It contains default values :

* **scan_time**

  Time in seconds between two region scans. Don't use too small values. For example, scanning your region
  every second will overload your simulator. 15 is a good compromise between performances and responsiveness.

* **ban_partial_names**

  Set to `true` if you want names loaded from the `banlist` notecard matching partially avatar names make them banned.
  For example, putting a line with typhaine in the `banlist` notecard will ban all Typhaine Artez !
  See below for the format to use in this notecard

* **max_kicks**

  Number of times an avatar can be kicked before it is automatically banned.
  When not on `banlist`, there are some rules you can set for avatars. If they are not respected, the avatar is kicked from
  the region, but not totally banned. After *max_kicks* kicks, it will be added to the `banlist` notecard

* **fallback_teleport**

  Name of a region or hypergrid URL to teleport kicked and banned avatars to, if they do not have a home set.
  By default the security script teleport avatars to their home, but if they do not have one, it fails. This value is to tell
  the security where the avatar should go in this case.

  You can put a simple region name (like the welcome region of the grid) or a full hypergrid URL, for example
  `hg.osgrid.org:80:Lbsa Plaza`

  **Important**: if the avatar do not has access to the region, the teleport will fail ;-)

Next are kicking rules, meaning the possible reasons an avatar would be automatically kicked.
For each rule, setting it to 0 disables the rule check.

* **min_age**

  Avatars younger than this value are kicked.

* **max_prims**

  It is a partial region flooding attack security. If rezzing is allowed for avatars and they rez more prims than specified,
  they are kicked.

* **allow_flying**

  Maybe you don't allow flying on your region. But some force the ability to fly with their viewer.
  If you want to kick those doing this, set this value to `false`.

* **max_scripts**

  Maximum number of running scripts an avatar can wear. If it wears more, it is kicked.

* **max_memory**

  Maximum amount of memory (in bytes) running scripts of an avatar can use. If it uses more memory, it is kicked.

* **min_size**

  Minimum height of an avatar in centimeters. If smaller, it is kicked.

* **max_size**

  Maximum height of an avatar in centimeters. If taller, it is kicked.

## Scanning

The security script scans avatars present on the region regularly, and compare them to several lists in notecard:
* `banlist` : a list of banned avatar
* `kicklist` : a list of avatar that have been kicked, and how many times (it is used to promote to ban after max_kicks)
* `whitelist` : those avatars are not checked (it's a list of avatar keys)

Each time you change any of those notecards, the script reload them (avoid to edit `kicklist` manually).

## Bans

The `banlist` notecard takes one entry per line. It is very flexable, allowed different kind of entries :

* **@grid-name**

    Lines starting with `@` ban a whole grid

* **UUID**

    Avatar keys (works if they reuse their key on an new avatar with a different name)

* **firstname lastname**
* **firstname.lastname**
* **firstname.lastname @grid**

    Avatar names, any format is correct, and check will always be done on firstname and lastname only.
    That means avatars with the same name on several grids are all banned.

    If `ban_partial_name = true` in `config` notecard, any name partially matching one entry will ban the avatar
    For example for an avatar named *firstname.lastname @grid*, all those entries will ban this avatar :
    *firstname*, *first*, *lastname*

## Menu

If you touch your device containing the security script, you get a menu with a list of avatars on the region.

By clicking on a button for one avatar, you get a dialog with information about this avatar, as well as action
buttons to:
* add the avatar to the whitelist
* kick the avatar
* ban the avatar (that will add 2 entries in the banlist notecard: its key and its IP)
* arrows to navigate to the previous or next avatar in the list
* go back to the list
