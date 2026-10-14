# ForeverGuide

Group leveling companion for WoW Forever: a party panel, [Keep] marks on items you or
your party need, and an optional step-by-step guide. `/fg options` turns each part on or off.

Step-by-step leveling guide addon for WoW Forever.

## Install
**WowUp (recommended, updates automatically):** Get Addons -> Install from URL ->
`https://github.com/msneeley/ForeverGuide` -> Install. New versions show up as an Update.

**By hand:** download `ForeverGuide-vX.Y.Z.zip` from the
[Releases](https://github.com/msneeley/ForeverGuide/releases) page and unzip it into
`World of Warcraft/<flavor>/Interface/AddOns/` (you should end up with `AddOns/ForeverGuide/ForeverGuide.toc`).
If it shows "out of date", run `/dump select(4, GetBuildInfo())` in game and put that
number on the `## Interface:` line of `ForeverGuide.toc`.

## Commands
| Command | What it does |
|---|---|
| `/fg` | Show / hide the window |
| `/fg list`, `/fg set <name>` | List / load guides (auto-picked by race + level on login) |
| `/fg skip`, `/fg back`, `/fg reset` | Skip a step, undo the last skip, clear skips |
| `/fg auto` | Toggle auto accept / turn-in (hold **Shift** at an NPC to bypass) |
| `/fg rec start` / `stop` / `clear` | Record your route while you play |
| `/fg note <text>` | Add a waypoint step at your position while recording |
| `/fg export` | Show the recorded steps as Lua to paste into a guide |
| `/fg talents` | Talent build and your progress (next point also shows in the window) |
| `/fg legacy` | Legacy perk spending plan for leveling |
| `/fg camp` | Group profession plan for camp buffs |
| `/fg prof` | First Aid / Cooking / Fishing targets by level, and trainers on the route |
| `/fg keep` | What the green [Keep] line in item tooltips marks |
| `/fg pots` | Best elixirs and potions you can make for your level and Alchemy skill |
| `/fg share` | Toggle auto-sharing guide quests with your group (on by default) |
| `/fg reward` | Toggle picking quest rewards by your class's stats when a step has no pick (on by default) |

## Step format
```lua
{ accept = 788,   title = "Cutting Teeth", npc = "Gornek", x = 42.1, y = 68.3 },
{ complete = 788, title = "Cutting Teeth", x = 44.0, y = 62.0, text = "Kill boars" },
{ turnin = 788,   title = "Cutting Teeth", npc = "Gornek", x = 42.1, y = 68.3 },
{ travel = true,  x = 52.0, y = 44.0, radius = 10, text = "Run to Razor Hill" },
{ level = 6 },
{ text = "Train skills" },               -- manual: click Skip
{ turnin = 765, reward = 4964 },         -- auto-pick this reward item
{ bind = "Bloodhoof Village" },          -- done when your hearth is set there
{ hearth = "Bloodhoof Village", x = 46.5, y = 63.0 },  -- shows hearth cooldown
{ deathskip = "Red Cloud Mesa", x = 42.6, y = 78.4, maxLevel = 10 },
{ train = "Narm Skychaser" },            -- done when you close the trainer
{ skill = { "Cooking", 10 } },           -- profession / weapon skill rank
{ item = 2678, count = 10 },             -- have N of an item
{ buff = "Well Fed" },
```
- `maxLevel` on any step: skipped automatically above that level (no res sickness at 10 or below).
- `classes = { "SHAMAN" }` on a guide: auto-picked over a race-only guide.
- `map` = uiMapID (defaults to the guide's `map`). Durotar 1411, Mulgore 1412, Tirisfal 1420,
  Barrens 1413, Orgrimmar 1454, Thunder Bluff 1456, Undercity 1458.
- `title` matters: old-style quest NPCs only give titles, so auto-accept matches on it.
- Steps complete from live game state, so steps you've already done are skipped automatically.

## Workflow
1. Each of you plays your own start zone with `/fg rec start`.
2. `/fg rec stop`, `/fg export`, Ctrl+C, paste into `Guides/Horde_<Zone>.lua`.
3. Tidy the text, add `travel` steps where the route needs them, `/reload`.

The sample guides contain only the first few quests, from memory - verify IDs on Wowhead.

## Group panel
Shows every party member who has the addon: level, XP bar with rested XP,
professions with ranks, Well Fed and food stock, hearthstone, durability, free
bag slots, zone, and guide step (if they use the guide). The title warns when
levels spread 2+ apart. `/fg group` shows/hides it. Members without the addon
show just their level.

## Options
`/fg options` (or the ? button on the guide window) switches each part on or off:
guide window, arrow, auto accept/turn-in, auto rewards, auto share, group panel,
bag icons. Someone who only wants the group panel can turn everything else off.

## Group play (5-man)
Everyone installs the addon. Each player follows their own starting-zone guide,
then everyone meets at **the Crossroads at level 12** and loads the same group
guides (12-35). Steps marked for a class or race only show for those players.
Quests you accept from the guide are shared with the group automatically.

## Guides
| Who | Guides |
|---|---|
| Tauren Shaman, Tauren Druid | `Tauren 1-7: Camp Narache` -> `Tauren 7-12: Bloodhoof` |
| Skyborne (any class) | `Skyborne 1-12: Zephras Isle` -> `Skyborne 12: Orgrimmar to the Crossroads` |
| Everyone | `Group 12-16` -> `Group 16-21` -> `Group 21-25` -> `Group 25-30` -> `Group 30-33` -> `Group 33-35` |

The right guide is picked automatically on login (by the map you're on, your
class and race). `/fg list` and `/fg set <name>` switch by hand.

## Camp professions
One camp object per player. A Basic Campfire Kit (Cooking 1) holds 3; a
Journeyman Campfire Kit holds 5 (learned at Cooking 90, placeable at 140 in the beta).

| Slot | Player | Professions | Camp object (skill 20) |
|---|---|---|---|
| 1 | Skyborne Rogue | Leatherworking + Skinning | Camp Tent: rested XP up to 5% of a level |
| 2 | Warrior | Fishing 20 (everyone has it) | Fish Bowl: +8% all stats |
| 3 | Tauren Druid | Skinning (+ his pick) | Camp Chair: +2% crit |
| 4 | Paladin | First Aid 20 (everyone has it) | First Aid Kit: +Stamina |
| 5 | You (Tauren Shaman) | Herbalism + Alchemy | Mana Well: mana for you and the Paladin |

Group: Druid, Shaman, Rogue, Paladin, Warrior. The Paladin gives Might to the
melee and Wisdom to the druid, so the Lodestone (= Might) is skipped.

Each camp buff is skipped if its class twin is up: Fish Bowl / Blessing of Kings,
Lodestone / Blessing of Might, Mana Well / Blessing of Wisdom, First Aid Kit /
Power Word: Fortitude. Skip the Enchanted Lute (= Mark of the Wild) and
Sharpening Wheel (= Strength of Earth).
Camp objects are taught by "Camping 101": talk to the profession's trainer at skill 20.

## Food
Everyone cooks their own (`/fg food`). Any cooked food gives Well Fed (+5% XP
from kills); the window tells you what to eat when you aren't Well Fed.
- Melee: Brilliant Smallfish (+2 AP), then Longjaw Mud Snapper (+10 AP) from Cooking 50.
  Recipes: Harn Longcast (Bloodhoof) or Naal Mistrunner (Thunder Bluff).
- Druid: Herb Baked Egg (+1 Sta), then Crispy Lizard Tail (+3 Sta) from Cooking 50.
  Recipe: Tari'qa (Crossroads).

## Cozy Sleeping Bag (after 30)
The group guide picks up "... and that note you found" at the burnt tower in the
southern Barrens (46, 74) on the way to Thousand Needles. The rest of the chain
(Westfall, Stonetalon, Loch Modan dam, Thoradin's Wall) goes through Alliance
zones and is planned for right after 30. The bag: lie in it 3 minutes for +3% XP
for an hour, stacks with camp and food buffs, one-hour cooldown, any party member
can use a placed bag.

## Group profession sessions
Everyone levels First Aid, Cooking and Fishing together at set stops (Stonebull
Lake or Valanaar, the Crossroads, Lushwater Oasis, Zoram Strand, the zeppelin
tower, Freewind Post). Each session lists targets and ticks itself off once your
skills are there - being ahead never holds you up. The window also tracks your own
food stock (cooked + raw for your class's best recipe) and warns below 10.

## [Keep] marks
Bag slots get small dots in the top-left corner (built-in bags, combined or separate):
- gold = you need it (your food, materials, recipes, guide items)
- blue = a party member needs it ("[Keep for] Cairne (food)")
- green = an upgrade for a party member ("[Upgrade for] Cairne (+14)"): scored with
  their class's stat weights against what they're wearing, only if their class/race can
  use it and they're high enough level.
- purple = an upgrade for you ("Upgrade for you: +9 over what you're wearing").
Soulbound items only ever show purple - nothing else, since you can't pass them on.
Hover over a marked item and its tooltip repeats each dot with what it means and who
it's for ("Keep for party: Cairne (food)"). Party members' needs and gear come from
their own copy of the addon.

## [Keep] tooltip line
Items worth holding onto get a green "[Keep]" line in their tooltip with the
reason: your class food (cooked and raw), food recipes, First Aid cloth, campfire
wood, Alchemy herbs and vials (alchemists), leather (leatherworkers - everyone
else sees "trade to your leatherworker"), and items your guide still needs.

## Secondary professions as you level
First Aid, Cooking and Fishing have targets by level so you use materials while
they still give skill-ups (finish linen bandages before wool drops, etc.). The
window shows each learned skill as current/target: green on pace, orange a
little behind, red well behind, plus "Train Journeyman/Expert" when you're near
a rank cap. Chat warns once when wool (15) and silk (23) start dropping.
Everyone levels all three. Targets by 30: First Aid 180, Cooking 125, Fishing 150. Expert Cooking and
Fishing come from books in Desolace and Booty Bay - off this route.

## Potions (Shaman's Alchemy)
`/fg pots` lists the best Strength, Agility, Defense, Health and Mana elixir or
potion you can make right now, and what unlocks next (skill + level + recipe).
The window tracks an Alchemy target by level so each new tier is ready when you
can drink it. Expert Alchemy (150+) is in the Undercity, on the 25-30 trip.
Healing potions are First Aid in Forever. No mp5 elixir exists before 30, so mana
comes from Elixir of Wisdom (+Int) and mana potions.

## Buff bar (/fg buffs)
A Pally Power-style bar (drag to move). Top row is you: green edge = you have it,
yellow = under 2 minutes left, red = missing. A buff only appears when someone in
your party can give it (Arcane Intellect only with a mage, blessings only with a paladin).
Checks: Well Fed, the campfire buff, Mark of the Wild, Thorns, paladin blessing + aura,
Fortitude, Arcane Intellect, Battle Shout / totems (off by default), Lightning Shield,
Omen of Clarity, weapon imbue / poison, battle elixir, defensive elixir, mana potions in bags.
Shaman: Strength of Earth Totem and your air totem (Windfury once you have it, else
Grace of Air) are grey out of combat and turn red in combat when they aren't down.
Click to drop, or bind keys in Key Bindings > AddOns > ForeverGuide.
Click a missing one of your own to fix it (eat, drink the elixir, cast the shield / imbue).

Rows below are buffs YOU give, one button per party member: click to cast it on them,
or for elixirs, to open a trade (on yourself it drinks one).

- Roles: everyone is Tank, Healer, Melee or Caster (defaults: warrior tank, priest healer,
  druid/mage/warlock caster, the rest melee). Anyone can change anyone's role in /fg buffs
  or with /fg role tank [name]; it's shared with the party. Each check has T/H/M/C boxes
  for which roles get it - Thorns is tank-only by default.
- /fg buffs - turn each check on/off, set roles, and pick the paladin blessing you want
  (shared with the party, so the paladin's row casts what each person picked).
- /fg buffs blessing might|wisdom|kings|salvation|light
- /fg buffs learn - sit at the campfire with its buff up, then run this if the check stays red.
- /fg buffs reset - put the bar back at the top of the screen.

## Credits
Route additions in the 12-25 group guide (the Barrens elite and group quests, Chen's Empty Keg,
Ignition / The Escape, Stolen Silver, the Camp Taurajo hunts, Counterattack!, Stonetalon's Kaya
and Grimtotem quests, the Forever Ashenvale quests, and the first parts of Call of Water) were
worked out by comparing against RestedXP's free Forever guides
(https://github.com/RestedXP/RXPGuides). Those guides are licensed CC BY-NC-SA 4.0, so the
adapted guide files are shared under the same licence: free, non-commercial, credit kept.

## 30-35 (Classic data)
The guide now runs to level 35. WoW Forever's beta stopped at 30, so 30-35 uses the Classic quest
database, routed the way RestedXP's guides go at these levels: Shimmering Flats, Razorfen Kraul
(level 33-34 quests in Forever), the Ratchet boat to Booty Bay and north through Stranglethorn
(Nesingwary, Grom'gol), then the Grom'gol zeppelin to Tarren Mill, Alterac and Arathi.
Class chains: Shaman Call of Air -> Elemental Aid (Charlga in Razorfen Kraul) -> Eyes on the Sky
(the 20-totem and level 40 parts come later); Warrior The Islander -> The Affray -> The Windwatcher
-> Cyclonian (carried past 35). If an NPC doesn't offer a quest in Forever, the guide skips it.

## Leveling estimate
The timing simulator (Forever XP: dungeon quests 2.375x Classic, dungeon mobs ~1/4 of an
open-world mob) puts 1-35 at about 23-24 hours of group play, with no grinding. Ruins of
Lordaeron (optional) adds about an hour - skip it unless someone wants its gear.

## Optional dungeons
Ruins of Lordaeron (on the 25 Shadowfang trip) and Excavation Site (from Hammerfall at ~34, quests
level 31: Dragonmaw Rumors -> Open the Maw, Changing Tastes from Borstan in Orgrimmar, Elder
Knowledge -> Earthen Echo back in Thunder Bluff / Mulgore) are optional detours. Press Skip on any
of their steps to skip the whole detour; /fg back brings it back. Both are roughly break-even on
XP (Forever's dungeon quests give 2.375x Classic, but the mobs give very little), so run them when
the group wants a dungeon.

## Recommendations only
The addon never spends a talent point, Legacy point or trainer gold. It recommends:
- Talents: the next talent glows gold in the talent window (or its tree's tab glows if you're
  looking at another tree). `/fg talents` lists the whole build.
  Both are separate switches in /fg options ("Talent recommendations", "Talent glow"),
  or `/fg talents on|off` and `/fg glow`.
- Class trainers: the guide window says when you have new ranks to buy, and the route has a
  trainer step at each Orgrimmar / Thunder Bluff / Undercity visit. Buy what you want.
- Legacy points: `/fg legacy` prints the suggested plan.

## First login
The first time each character loads ForeverGuide, a welcome page opens: what the addon does,
which guide it picked, and two buttons - "Choose my settings" (every on/off switch plus the
buff bar, roles and blessing) or "Start with everything on". It only shows once per character;
`/fg welcome` brings it back, `/fg options` (or the ? button) opens the settings.

## Crafting for the party (/fg craft)
Open your profession window once (and again after learning recipes) - ForeverGuide reads your
recipes from the game, so they're always WoW Forever's, for every profession.
- Leatherworking / Tailoring / Blacksmithing / Engineering: `/fg craft` lists what you can make
  that would upgrade someone in the party (you included), best first, with materials have/need and
  whether it still gives skill. The guide window says when one is ready to make. Materials get the
  gold [Keep] dot; party members see the blue dot on them. At your profession trainer, recipes that
  make an upgrade glow and are named in chat. Party gear comes from members running ForeverGuide.
- Alchemy / Cooking / First Aid: `/fg pots`, `/fg food` and [Keep] switch from Classic fallback data
  (grey) to Forever's real reagents once you've opened that profession window.
- Crafters share their best craft per person and slot. If another crafter can make something better
  for that slot and has the materials, yours drops off the list; if they're still missing materials,
  yours stays as a stopgap ("Smithy's craft is better once they have materials").
- Gathering: for upgrades you can't make yet, the guide window says what's missing ("Gather for
  upgrades: 3 Light Leather, 1 Coarse Thread") and /fg craft lists it. The list is shared: party members
  see what each crafter is waiting on - leather for skinners, herbs for herbalists, ore for miners,
  everything else (cloth, drops, vendor goods) for everyone - with who the upgrade is for.
- It counts the whole party: everyone's addon reports what they carry of the wanted materials
  whenever their bags change, so the "still to gather" numbers drop no matter who loots. The crafter
  sees "Party has: Skinny 2 Light Leather - ask for a trade"; the carrier sees "Trade to Sneaky".
- Suggestions only - nothing is crafted, learned or bought for you. Toggle: "Crafting for the party".

## Cloth: party bags first, then First Aid (/fg cloth)
The bag plan only exists once it's been set up on the group's tailoring (bank) alt - other players'
tailoring alts are never used. Log in once on that alt; it records the alt's level, Tailoring skill,
cloth (bags + bank) and Tailoring recipes. Everyone's addon shares their bag sizes. Two tiers, and
only what the alt's CHARACTER level can train:
1. Red Linen Bag (8 slots, Tailoring 70, Apprentice - any level): Linen goes to the alt until it can
   level there and make one for every party bag slot under 8. Then Linen goes to First Aid.
2. Small Silk Pack (10 slots, Tailoring 150, Journeyman - level 10): once the alt is level 10, Wool
   goes to it for Tailoring 75-150 and Silk for the packs. Before that nobody gathers for it.
Linen/Wool/Silk tooltips, bag dots and the guide window say where each cloth goes. /fg cloth shows
the math; /fg cloth bags|firstaid|auto overrides Linen.

## Crafting guide (/fg craftguide)
On a character with Tailoring / Leatherworking / Blacksmithing / Engineering, the guide window shows
the cheapest recipe that still gives skill (from your own Forever recipes) and about how much
material it takes to reach the goal - the bag plan on the bag alt, otherwise the most you can train
at your level. Reopen the profession window as you level so recipe colors stay current.

## Solo
The guide works solo too: group features stay quiet when you're not in a group, and step text that
talks to "the group" is reworded. Dungeons stay in the route: before each one there's a "Look for a
group" step (Dungeon Finder, /lfg, trade chat) that finishes as soon as you join a group. Can't find
one? Skip on it skips that dungeon and its quests - including follow-up quests that need the
dungeon - in one go (/fg back to undo). Elite quests (Lakota'mani, Counterattack!) are optional
solo the same way. In a group none of this shows. Solo, the route still reaches 35 without grinding.
Note: full solo starts exist for Tauren (shaman, druid) and Skyborne; other races have 1-6 starters.

## Going off-script (/fg sync, /fg nearby)
Leveled somewhere else for a while? Log in (or type /fg sync) and the guide catches up: quests you've
already done are skipped, and so are quests you've outleveled - once a quest would give reduced XP
(6+ levels below you). It keeps grey quests that lead to a quest still worth doing (short chains) and
always keeps class quests and finished quests waiting to be handed in. Sections you're well past also
skip their travel / flight path / session steps, so you land where you should be. Toggle: "Skip
quests you've outleveled". Quest levels come from Classic data; Forever-only quests fall back to the
section's level range.
When you're away from the route, the guide window suggests quests around you that suit your level
and aren't on the route ("Off the route? Nearby: ..."); /fg nearby lists more. Toggle: "Nearby quests".

## XP tracking (/fg xp)
A brand-new character starts tracking when you accept your first quest, so time spent setting up your
UI doesn't count. Characters already past level 1 (or with quests) track from login.
Every character logs, level by level: time in the open world vs dungeons, XP from quests, dungeon
quests, kills and dungeon kills, and deaths. Every dungeon run is logged with its time inside, its kill
XP and its quests' XP when you hand them in. Saved account-wide, so any character can compare.
- /fg xp - this character by level  ·  /fg xp runs - dungeon runs  ·  /fg xp compare 20 30 - all
  your characters side by side for those levels  ·  /fg xp reset - clear this character's log
- /fg xp verdict - each dungeon run's XP per hour (time inside + finding a group, from the guide's
  "Look for a group" step) against your open-world questing at the same levels (+-1), and which wins.
- Checkpoints: at levels 22 and 25 (change with /fg xp milestones 22 25) a report window pops up by
  itself with the verdict, the per-level log and your runs - copy it (Ctrl+A, Ctrl+C) or screenshot.
  /fg xp report opens it any time. Leaving a dungeon prints a one-line summary of the run.

## License
ForeverGuide is free and non-commercial, shared under
[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) (see LICENSE), because parts of
the guides are adapted from RestedXP's CC BY-NC-SA guides.
