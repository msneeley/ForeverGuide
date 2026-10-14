-- Undead start: Deathknell, Tirisfal Glades (uiMapID 1420)
-- SAMPLE ONLY: IDs and coords are from memory - verify on Wowhead
-- (wowhead.com/forever/quest=<id>) or replace with a /fg rec export.
ForeverGuide:RegisterGuide({
    name = "Tirisfal 1-6",
    races = { "Scourge" },
    minLevel = 1, maxLevel = 6,
    map = 1420,
    steps = {
        { accept = 363, title = "Rude Awakening", npc = "Undertaker Mordo", x = 30.2, y = 71.7 },
        { turnin = 363, title = "Rude Awakening", npc = "Shadow Priest Sarvis", x = 30.9, y = 66.3,
          text = "Inside the church" },
        { accept = 364, title = "The Mindless Ones", npc = "Shadow Priest Sarvis", x = 30.9, y = 66.3 },
        { complete = 364, title = "The Mindless Ones", x = 32.0, y = 62.0,
          text = "Kill Mindless Zombies and Wretched Zombies" },
        { turnin = 364, title = "The Mindless Ones", npc = "Shadow Priest Sarvis", x = 30.9, y = 66.3 },
        { text = "Sample ends here. Record the rest with /fg rec start" },
    },
})
