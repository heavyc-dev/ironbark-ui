# Changelog

## 1.1.1

- Removed "HoT healing on health bars": it only worked some of the time. The
  HoT icons under the frames stay.
- Fixed a stream of "attempt to compare a secret number value" errors from
  the player / target / party health and mana text once you had been in
  combat. The text is now held on during fights through the game's own
  status-text setting.
- Loot pop-ups: every item you pick up flashes mid-screen like the gathering
  pop-ups do, its name in the item's quality color (Options > Loot pop-ups).

## 1.1.0

- UI scale slider (Options > Setup), 64% up to the biggest size your screen
  fits. The cast bar, player/target and party row are now placed from the
  bottom edge instead of the screen's center, so scaling up never pushes them
  into the action bars. Existing users are offered the updated layout at login.
- Quest tracker right-click menus: open, hide objectives, stop tracking,
  link in chat, share and abandon on a quest; pin / collapse on a zone; track
  all again, sort and collapse / expand all on the title.
- Quest tracker scrolls with the mouse wheel when the list is taller than
  its window (it used to stop at "+N more").
- Your HoT icons also show under your own frame, not just party frames.
- HoT healing on health bars: what your HoTs still have to heal, drawn past
  the end of the health fill on your, target, party and raid frames.
- Gathering pop-ups: skinned, mined, picked and fished items flash mid-screen
  like quest progress, with how many you now carry; gathering skill-ups too.
- Buff and dispel reminder icons stay up and clickable in combat (new switch,
  on by default).
- Tooltips in combat: only friendly units and action buttons hide theirs now.
  Enemies, items, loot, buffs and debuffs, minimap pins and interface buttons
  show as usual.
- Plays along with EllesmereUI's QoL modules: Ironbark's bag window stands down
  while EllesmereUI's bags are enabled, and the UI scale stays the one set here.

## 1.0.0

First release.

**Layout**
- One Edit Mode layout, "Ironbark UI": three stacked bars framed by gryphons,
  player and target around a centered cast bar, a classic party row (tank on
  the left, level circles), raid above the chat, XP bar along the top, buffs
  beside the minimap.
- Apply saves a copy of everything it changes; Revert everything puts it back.
  Layout updates are offered at login (`/ibui layout`).

**Bars**
- Bar layouts for every class (`/ibui arrange`), with stance, stealth and
  Shadowform pages, and the keybinds 1-5 Q E R F Z X Tab plus Shift and Ctrl rows.
- Grey keybind text, red icons out of range, macro names hidden.
- Auto loot and press-and-hold casting on.

**Frames**
- Class-colored health, compact health text, cast bar colored by spell type,
  optional always-visible cast bar, class-colored XP bar, mana regen spark.
- Tooltips follow the mouse and hide in combat (hold Alt to see one).

**Group play**
- Buff reminders for every class, dispel icons for every class that can
  dispel: click to cast.
- Your HoTs and shields on teammates' frames, in combat too.
- Damage and healing meters in WoW Forever's bronze HUD frame: top 5 with
  rank and class icon, your row always shown, this fight or overall. Always up
  in dungeons, otherwise only in combat.

**Everything else**
- One bag window with Sections view and category sort.
- Chat: tabs (General, Combat Log, Social, World, Loot), short tags, timestamps,
  links, history, spam and loot filters; group loot rolls in Social; auto-hide.
- Ironbark's own quest tracker, grouped by zone.
- Addon minimap buttons tucked into one slide-out button.
- `/ibui help` lists every command.
