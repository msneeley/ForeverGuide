# Changelog

## v0.12.8
- Buff bar: the weapon imbue check (shaman imbues, rogue poisons) works in Forever. Forever's weapon
  enchant API returns nothing, so the addon reads the weapon's tooltip ("Rockbiter 1 (58 min)") - it
  was red even with Rockbiter on.
- Buff checks window (/fg buffs): long names no longer run into the T/H/M/C boxes.
- Party panel: party members from other realms no longer show "(no ForeverGuide)". Forever writes
  cross-realm names as "Name Realm", so the addon now matches people by first name.
- Party panel: roomier layout - name / level / XP on one line, Fed / Food / HS / Dur / Bags under the
  XP bar, rows sized to their text, a divider between people.
- Party panel in Dungeon Finder groups: addon messages now use the instance channel, so ForeverGuide
  users in a queued group can see each other.
- XP report reminders at the end of each guide section (levels 12, 16, 21, 25, 30, 35): the report
  window opens, a raid-warning style message and a sound. Switch off in /fg options.

## v0.12.7
- First public release.
- XP tracker: /fg xp report ends with spreadsheet rows, /fg xp export, /fg xp run 1|2|solo.
- Small groups: before each dungeon the guide says "Find N more" until the party has 5 (or you
  enter); the time spent finding a group is tracked.
