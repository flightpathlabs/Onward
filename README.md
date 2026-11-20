# Worth Doing

Shows where a quest leads, for World of Warcraft: Forever. Under a
quest's rewards you see how many quests follow it and what the rest of
the chain gives.

Not released yet: this is work in progress.

**What's in it**

- **Leads on:** the quests still to come after this one, with their
  total XP and money. Hover it to see each step.
- **Reward items** from the rest of the chain, with their tooltips. A
  quest that lets you choose shows its choices after "One of".
- **Marks** for quests that matter: class quests, attunements and dungeon
  keys, spells a quest teaches, and epic rewards, also when they come
  further along the chain.
- **Worth doing or safe to skip**, with the reason, so you know which
  quests to pick up and which to leave.
- In the **quest window** and the **quest log**, as one line on
  **Questie's map icons**, and as a short "+4" after each quest in the
  quest log and quest givers' lists. Questie's "!" icons on the map get a
  small number too.

- **The Worth Doing window** (`/worthdoing`): quests you dropped and can take
  again, ones below your level you never did that still lead somewhere,
  and chains worth seeking out. Click one to mark its giver on your map.

**Getting started**

Worth Doing reads Questie's quest data, so have Questie installed. There's
nothing to set up. `/worthdoing` or the minimap button opens the window, and
its Options button the options.

**Notes**

- XP is for your level now, before any bonus. At the level cap XP is paid
  as money, and Worth Doing counts it once it has seen a hand-in.
- Rewards come from the game. Some only show once you've opened the quest
  or it's in your log; Worth Doing remembers what it sees.
- Without Questie, Worth Doing only knows the chains it has seen for itself.
- Found a bug? Open an issue on
  [GitHub](https://github.com/flightpathlabs/WorthDoing/issues).

Worth Doing is a fan-made addon, not affiliated with Blizzard Entertainment.
Chains come from Questie's quest database, read while the game runs;
Worth Doing doesn't copy any of it. Thanks to the Questie team.

MIT licence, see [LICENSE](LICENSE). Changes are in the
[changelog](CHANGELOG.md). AI tooling is used openly in making this
addon; everything is reviewed and tested in game before release.

**More from Flight Path Labs**

Small addons for World of Warcraft: Forever, all at
[github.com/flightpathlabs](https://github.com/flightpathlabs).

- [Gold Wise](https://github.com/flightpathlabs/GoldWise): auction prices for what you carry, and what's worth doing with it.
- [Creel](https://github.com/flightpathlabs/Creel): a fishing log and one-key cast.
- [Temper](https://github.com/flightpathlabs/Temper): how your character fights, and whether a change helped. Coming soon.
- [Encore](https://github.com/flightpathlabs/Encore): helpers for enchanters.
