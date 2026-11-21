# Changelog

## 0.1.0

First version.

**Where a quest leads**

- Under a quest's rewards, in the quest window and the quest log: how
  many quests follow it, and the total XP and money for the rest of the
  chain. Hovering the totals lists each step with its level and rewards.
- The rest of the chain's reward items, with their tooltips. Choices are
  shown after "One of" and aren't added to the totals.
- One line on the tooltips of Questie's quest-giver icons, with the same
  totals.

**How chains are worked out**

- Chains come from QuestieDB, which comes with Questie, read while the
  game runs.
- Steps your character can't take (another race's or class's version,
  repeatable quests, one of two quests that shut each other out) are left
  out, and quests already done are skipped.
- Where a quest opens several at once and a later quest needs all of
  them, they count as one chain. Otherwise the others are listed as
  "Also opens".
- XP is figured for your level, from XP measured on Forever.
- Worth It remembers the rewards of quests you open, what a hand-in paid at
  the level cap, and which quest the game offered straight after another,
  so chains get more complete as you play.

**In lists and on the map**

- "+4" after each quest in the quest log and in a quest giver's list, for
  four more quests in its chain.
- A small number beside Questie's "!" on the world map and minimap.

**Worth doing or safe to skip**

- "Worth doing" when the chain opens a dungeon or raid, is a class quest,
  gives a rare or epic item, pays half a level of XP or more, or leads
  from grey quests to ones at your level. "Safe to skip" when the quest is
  grey for you and so is everything after it. The reason shows with it.
- In lists, a tick for worth doing and a grey "skip".

**The Worth It window**

- `/worth` or the minimap's addon menu opens a window of quests worth a
  second look: ones you dropped and can take again, ones below your level
  you never did that still lead somewhere, and chains you can start now,
  best first.
- Each row shows the chain's count, totals and verdict, where the giver
  is, and the first reward items. Clicking it marks the giver on your map.
- Abandoned quests come from Questie's journey and from Worth It's own
  record from now on. Quests dropped before either can't be known.

**Marks**

- Class quests, attunements (Molten Core, Onyxia's Lair, Blackwing Lair,
  Naxxramas) and dungeon keys (Upper Blackrock Spire, Scholomance,
  Blackrock Depths), spells a quest teaches, and epic rewards, for the
  quest itself or further along its chain.

**Other**

- A minimap button with the game's quest "!": left-click opens the
  window, right-click the options. Drag it round the edge, or hide it in
  the options.

- Options under Options > AddOns > Worth It, the window's Options button,
  or `/worth options`.
- `/worth probe` and `/worth chain` print what Worth It sees for a quest,
  for bug reports.
