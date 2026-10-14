-- Orc / Troll start: Valley of Trials, Durotar (uiMapID 1411)
-- SAMPLE ONLY: IDs and coords are from memory - verify on Wowhead
-- (wowhead.com/forever/quest=<id>) or replace with a /fg rec export.
ForeverGuide:RegisterGuide({
    name = "Durotar 1-6",
    races = { "Orc", "Troll" },
    minLevel = 1, maxLevel = 6,
    map = 1411,
    next = nil,   -- e.g. "Durotar 6-12" once written
    steps = {
        { accept = 4641, title = "Your Place In The World", npc = "Kaltunk", x = 43.3, y = 68.5 },
        { turnin = 4641, title = "Your Place In The World", npc = "Gornek", x = 42.1, y = 68.3,
          text = "Inside the den" },
        { accept = 788,  title = "Cutting Teeth", npc = "Gornek", x = 42.1, y = 68.3 },
        { complete = 788, title = "Cutting Teeth", x = 44.0, y = 62.0,
          text = "Kill Mottled Boars around the valley" },
        { turnin = 788,  title = "Cutting Teeth", npc = "Gornek", x = 42.1, y = 68.3 },
        { text = "Sample ends here. Record the rest with /fg rec start" },
    },
})
