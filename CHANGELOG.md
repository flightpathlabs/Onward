# Changelog

## Unreleased

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
- Onward remembers the rewards of quests you open, what a hand-in paid at
  the level cap, and which quest the game offered straight after another,
  so chains get more complete as you play.

**Marks**

- Class quests, attunements (Molten Core, Onyxia's Lair, Blackwing Lair,
  Naxxramas) and dungeon keys (Upper Blackrock Spire, Scholomance,
  Blackrock Depths), spells a quest teaches, and epic rewards, for the
  quest itself or further along its chain.

**Other**

- Options under Options > AddOns > Onward, or `/onward`.
- `/onward probe` and `/onward chain` print what Onward sees for a quest,
  for bug reports.
