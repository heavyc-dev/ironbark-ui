# Ironbark UI

A light polish for the **default** WoW Forever UI. No replacement frames: every
unit frame, action bar, party and raid frame is Blizzard's own. Ironbark
arranges them with an Edit Mode layout named **"Ironbark UI"** and adds a few
small, native-looking touches on top.

## Install

Download `IronbarkUI-x.y.z.zip` from the
[latest release](../../releases/latest) and unzip it into
`World of Warcraft\_forever_\Interface\AddOns\` (you should end up with
`AddOns\IronbarkUI\IronbarkUI.toc`). Restart the game.

## First run

On first login a welcome message explains Ironbark and offers **Apply**:

1. It saves a copy of every setting it's about to change: Edit Mode layout,
   keybinds, action bars, ClickLegend keys, chat tabs and game options
   (UI scale, party/raid, bags, nameplates, chat).
2. It applies everything and reloads once.

**Revert everything** (Options > AddOns > Ironbark UI, or `/ibui revert`) puts
all of it back from that copy. To also turn off Ironbark's own touches, disable
the addon.

## The layout

- Three 12-button bars stacked at the bottom, touching, framed by gryphons
  sized to the stack. Macro names and bar page arrows hidden.
- Cast bar centered, player and target frames hugging its ends; the target is
  scaled to match the player. Forms in a small column left of your portrait.
- Party: Blizzard's classic party frames at 150% in a centered row below,
  tank on the left (assigned role, or a warrior when nobody has one), each with
  a level circle on the portrait.
- Raid: above the chat, groups as rows of 5, class colors and power bars.
- XP bar along the top in your class color. Minimap top-right, quest tracker
  under it, chat bottom-left, micro menu top-left with the bag bar tucked
  away to its right. Your buffs left of the minimap, clear of the XP bar.
- UI scale 0.64 by default, with a slider in the options to make everything
  bigger: each group grows from its own screen edge, so nothing overlaps, and
  the slider stops at the biggest size your screen fits.

## What else it does

- **Frames:** class-colored health; `961 | 100%` text on mouseover and in
  combat; cast bar colored by spell type (heals green, channels blue, damage
  orange, utility gold); a mana regen spark for the 5 second rule.
- **Buff & dispel reminders:** glowing icons on you, party and raid members for
  your buffs they're missing and debuffs you can remove (in their curse /
  poison / magic / disease color). Click one to cast it. In combat too: each
  icon's spot is fixed when the fight starts, bright while needed, hidden
  while not (a hidden spot still casts if clicked). The game hides auras in
  combat, so buffs go by what was missing at the pull; debuffs you can remove
  are drawn by the game's own aura display on top of the dispel button (party
  and your own frame; in raids the dispel buttons sit dim).
  - Druid: Mark of the Wild; Thorns on the tank and you
  - Priest: Fortitude; Divine Spirit on mana users; Inner Fire on you
  - Mage: Arcane Intellect on mana users; an armor on you
  - Paladin: a Blessing on everyone (Wisdom for mana users, Might otherwise;
    any of yours counts); an Aura on you
  - Shaman: Lightning Shield and a weapon imbue on you
  - Hunter: an Aspect and Trueshot Aura on you
  - Warlock: Demon Skin / Armor on you
  - Warrior: Battle Shout on you
  - Dispels: druid (curse, poison), priest (magic, disease), paladin (magic,
    poison, disease), shaman (poison, disease), mage (curse)
- **Your HoTs and shields:** Rejuvenation, Regrowth, Renew and Power Word:
  Shield you've cast show under the left side of your own and each teammate's
  frame with a timer sweep, in combat too.
- **HoT healing on health bars:** a lighter green stretch past the end of
  someone's health shows what your Rejuvenation, Regrowth or Renew still has
  to heal, stopping at full. Counted from your own casts (works in combat);
  other healers' HoTs aren't included.
- **Game options:** auto loot on; hold a key to keep casting its spell.
- **Action buttons:** grey keybind text; the whole icon turns red when out of
  range.
- **Minimap:** zoom buttons hidden, mouse wheel zooms.
- **Bags:** one bag window: your real slot layout, or a Sections view
  (Equipment, Consumables, Quest, Gathering, Reagents, Other, Junk). The broom
  sorts items into that order. New items glow until hovered.
- **Chat:** General | Combat Log | Social | World | Loot tabs (Social also gets
  group loot rolls and green-or-better gear); short channel
  tags, buttons and background on mouseover, class-colored names, timestamps,
  clickable links, sticky whispers, Up/Down history, spam filter, and loot from
  your group only.
- **Quest tracker:** Ironbark's own, from your quest log, grouped by zone.
  Background on hover; mouse wheel scrolls a long list; click to collapse, Ctrl-click a zone to pin it;
  right-click a quest for a menu (open, hide objectives, stop tracking, link
  in chat, share, abandon), a zone or the title for theirs; only dungeon quests inside
  dungeons; fades in combat. Questie's and Blizzard's tracker windows are hidden
  while it's on (their settings aren't touched).
- **Gathering pop-ups:** what you skin, mine, pick or fish flashes mid-screen
  the way quest progress does (`Light Leather +2 (14)`: gained, and how many
  you now carry), and so do gathering skill-ups (`Skinning: 76`).
- **Minimap:** addon buttons tucked into one button that slides them out.
- **Meters:** two small windows at the bottom-right framed in WoW Forever's
  own bronze HUD line (the micro menu's box), Healing over Damage. Top 5 with
  rank, class icon and class-colored bars (same texture as your health bar), total and per
  second; you in gold, and always on the last row if you're further down. Bars
  slide smoothly; text is outlined. Totals run until you reset (Shift-click a
  title); right-click a title for this fight only. Always shown in dungeons
  and raids (half faded between pulls until hovered); elsewhere only in combat
  (and 5 seconds after), so never in town. Blizzard's own meter window is
  switched off while they're on.
- **Nameplates:** Blizzard's, with class colors, stacking and faded non-targets.
- **Bar layouts for every class** (`/ibui arrange`, undoable), on the keybinds
  1-5 Q E R F Z X Tab, with Shift and Ctrl for the bars below. Top row: your
  main attacks and heals; Shift row: buffs, utility and cooldowns; Ctrl row:
  hearthstone, professions and pet. Tab is Att (target + auto-attack), or
  Shoot for wand users. Spells you haven't learned yet are skipped.
  - Druid: F = Bear, Z = Cat on every form page
  - Warrior: a full bar per stance; F / Z / X = Battle / Defensive / Berserker
  - Rogue: its own Stealth page; F = Stealth, Z = Evasion, X = Vanish
  - Priest: its own Shadowform page; F = Shadowform, X = Fade
  - Hunter: F / Z = Hawk / Monkey, X = Feign Death
  - Mage, Warlock, Paladin, Shaman: one page each
  - Druid damage spells are plain spells, so holding the key keeps casting
    (ClickLegend's mouse rules for them start auto-attack if installed).

## Options

Esc > Options > AddOns > Ironbark UI, or `/ibui`: Apply, Revert everything, UI
scale, class colors, compact health text, tooltips follow mouse, fewer tooltips in
combat (friendly units and action buttons hide theirs; Alt shows one), buff reminders,
one bag window, chat polish, quest tracker, gathering pop-ups, minimap buttons, meters.

`/ibui help` lists every command. Slash: `/ibui apply`, `/ibui revert`. Single steps: `/ibui chatsetup`,
`/ibui keybinds [undo]`, `/ibui arrange [undo]`. Support: `/ibui debug`,
`/ibui layout` (re-apply just the layout), `/ibui bars`, `/ibui buffs test`, `/ibui probe` (40 seconds of
notes on what the client shows about heals and auras, saved on /reload), `/ibui meters` (show the meters any time,
with sample data if there's no fight yet; again to hide), `/ibui reset`.

## Testing vs. EllesmereUI

`tools\ui-switch.ps1` (PowerShell, with WoW **fully closed**) backs up `WTF` and
switches between the two: `status`, `backup -Label name [-IncludeAddOns]`,
`ironbark`, `hybrid`, `ellesmere`, `restore -Zip <file>`. `hybrid` is Ironbark for
the look with EllesmereUI's QoL modules and bags left on (Ironbark's own bag
window stands down, and the UI scale stays Ironbark's). Before switching back, run
**Revert everything** in game: Edit Mode layouts and some settings are stored on
Blizzard's servers.

## License

MIT, see [LICENSE](LICENSE). Changes: [CHANGELOG](CHANGELOG.md).
