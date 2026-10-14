-- Tauren start: Camp Narache / Red Cloud Mesa, Mulgore (uiMapID 1412)
-- SAMPLE ONLY: IDs and coords are from memory - verify on Wowhead
-- (wowhead.com/forever/quest=<id>) or replace with a /fg rec export.
ForeverGuide:RegisterGuide({
    name = "Mulgore 1-6",
    races = { "Tauren" },
    minLevel = 1, maxLevel = 6,
    map = 1412,
    steps = {
        { accept = 747, title = "The Hunt Begins", npc = "Grull Hawkwind", x = 44.7, y = 77.5 },
        { accept = 752, title = "A Humble Task", npc = "Chief Hawkwind", x = 44.2, y = 76.1 },
        { complete = 747, title = "The Hunt Begins", x = 48.0, y = 81.0,
          text = "Kill Plainstriders for meat and feathers" },
        { turnin = 747, title = "The Hunt Begins", npc = "Grull Hawkwind", x = 44.7, y = 77.5 },
        { text = "Sample ends here. Record the rest with /fg rec start" },
    },
})
