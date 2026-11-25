#!/usr/bin/env python3
"""Add an "Ironbark" profile to EllesmereUI that mirrors the Ironbark UI layout.

Clones one of your EllesmereUI profiles (default "Jesk Minimal": its look, fonts
and bar contents carry over), then moves the frames to where Ironbark UI puts
them and flips the EllesmereUI options that have an Ironbark equivalent.

    python tools/eui-ironbark-profile.py              # add / refresh the profile
    python tools/eui-ironbark-profile.py --dry-run    # show what would change
    python tools/eui-ironbark-profile.py --remove     # take the profile out again

Then in game: /eui > Profiles > Ironbark.

WoW must be closed: the game rewrites SavedVariables on exit and would throw the
change away. The file is backed up to .\\backups first, and the rewritten file is
parsed back and compared before it replaces the original. Your other profiles
and the active profile are left alone.

Coordinates are UIParent units at EllesmereUI's 0.64 scale (a 1200-unit-tall
screen), the same space Ironbark's own layout (IronbarkUI/Presets.lua) uses.
Like that layout, everything hangs off a screen edge - the center column off
the BOTTOM edge - so it holds up on any aspect ratio.

Not covered, because EllesmereUI leaves them to Blizzard's Edit Mode in this
setup: XP bar, micro menu, bag bar. They follow whichever Edit Mode layout is
active (keep "Ironbark UI" selected to have them where Ironbark puts them).
"""
import argparse
import copy
import datetime
import os
import re
import shutil
import subprocess
import sys

DEFAULT_GAME = r"C:\Program Files (x86)\World of Warcraft\_forever_"
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---------------------------------------------------------------------------
#  SavedVariables <-> Python. Strings keep their Lua escapes verbatim, so
#  writing back is lossless.
# ---------------------------------------------------------------------------
TOK = re.compile(
    r'\s*(?:--[^\n]*\n\s*)*(?:("(?:[^"\\]|\\.)*")|(-?(?:0x[0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+))'
    r'|(true|false|nil)\b|([A-Za-z_]\w*)|([{}\[\]=,;]))', re.S)


class LuaStr(str):
    """A string as written in the file (escapes untouched)."""


def parse(text):
    pos = 0

    def tok():
        nonlocal pos
        m = TOK.match(text, pos)
        if not m:
            if text[pos:].strip():
                raise ValueError("can't read SavedVariables near offset %d: %r" % (pos, text[pos:pos + 40]))
            return None
        pos = m.end()
        return m

    def peek():
        nonlocal pos
        p = pos
        m = tok()
        pos = p
        return m

    def value():
        m = tok()
        if m.group(1) is not None:
            return LuaStr(m.group(1)[1:-1])
        if m.group(2) is not None:
            s = m.group(2)
            if s.lower().startswith(("0x", "-0x")):
                return int(s, 16)
            return float(s) if any(c in s for c in ".eE") else int(s)
        if m.group(3) is not None:
            return {"true": True, "false": False, "nil": None}[m.group(3)]
        if m.group(5) == "{":
            d, n = {}, 1
            while True:
                p = peek()
                if p.group(5) == "}":
                    tok()
                    break
                if p.group(5) == "[":
                    tok()
                    k = value()
                    tok()
                    tok()
                    v = value()
                elif p.group(4) is not None:
                    tok()
                    tok()
                    k, v = LuaStr(p.group(4)), value()
                else:
                    k, v = n, value()
                    n += 1
                if isinstance(k, bool) or isinstance(k, float) or k in d:
                    raise ValueError("unsupported or duplicate table key %r" % (k,))
                if v is not None:   # "nil, -- [1]" holes: absent either way
                    d[k] = v
                p = peek()
                if p.group(5) in (",", ";"):
                    tok()
            return d
        raise ValueError("unexpected %r at offset %d" % (m.group(0), pos))

    out = {}
    while True:
        m = tok()
        if m is None:
            break
        if m.group(4) is None:
            raise ValueError("expected a variable name at offset %d" % pos)
        tok()  # =
        out[m.group(4)] = value()
    return out


def lua_value(v, out, depth):
    if isinstance(v, dict):
        out.append("{\n")
        tabs = "\t" * (depth + 1)
        for k, x in v.items():
            if x is None:
                continue
            out.append('%s[%s] = ' % (tabs, k if isinstance(k, int) else '"%s"' % k))
            lua_value(x, out, depth + 1)
            out.append(",\n")
        out.append("\t" * depth + "}")
    elif isinstance(v, bool):
        out.append("true" if v else "false")
    elif isinstance(v, str):
        out.append('"%s"' % v)
    elif isinstance(v, float):
        if v != v or v in (float("inf"), float("-inf")):
            raise ValueError("non-finite number")
        out.append(repr(int(v)) if v == int(v) and abs(v) < 1e15 else repr(v))
    elif isinstance(v, int):
        out.append(repr(v))
    else:
        raise ValueError("can't write %r" % (v,))


def serialize(data):
    out = []
    for name, v in data.items():
        out.append("\n%s = " % name)
        lua_value(v, out, 0)
        out.append("\n")
    return "".join(out)


# ---------------------------------------------------------------------------
#  The layout. 1200-unit-tall screen; y from BOTTOM unless stated.
# ---------------------------------------------------------------------------
BTN, PAD = 44.8, 2                    # action button size / spacing (Jesk Minimal's)
BAR_Y = [4, 4 + BTN + PAD, 4 + 2 * (BTN + PAD)]   # Bar3, Bar2, Action Bar 1
COLUMN_Y = 375                        # cast bar / player / target center line
CAST_W, CAST_H = 220, 20              # cast bar (its icon adds CAST_H to the width)
UF_W = 181 + 46 + 6                   # unit frame width: bar + attached portrait
GAP = 12                              # cast bar <-> player / target
PARTY_TOP = 275
CHAT = dict(x=46, y=15, w=372, h=295)
METER_W, METER_H = 150, 152


def pos(point, rel, x, y):
    return {"point": point, "relPoint": rel, "x": x, "y": y}


def sub(t, *keys):
    for k in keys:
        if not isinstance(t.get(k), dict):
            t[k] = {}
        t = t[k]
    return t


def apply_layout(profile, notes):
    addons = sub(profile, "addons")

    # -- action bars: three 12-wide bars stacked on the bottom edge ----------
    ab = sub(addons, "EllesmereUIActionBars")
    bp = sub(ab, "barPositions")
    for key, y in zip(("Bar3", "Bar2", "MainBar"), BAR_Y):
        bp[key] = pos("BOTTOM", "BOTTOM", 0, round(y, 1))
        bar = sub(ab, "bars", key)
        bar.update(enabled=True, alwaysHidden=False, barVisibility="always", orientation="horizontal",
                   numIcons=12, overrideNumIcons=12, numRows=1, overrideNumRows=1,
                   buttonWidth=BTN, buttonHeight=BTN, buttonPadding=PAD)
    # Ironbark shows bars 1-3 only
    for key in ("Bar4", "Bar5", "Bar6", "Bar7", "Bar8"):
        bar = sub(ab, "bars", key)
        if bar.get("barVisibility", "always") != "never" or not bar.get("alwaysHidden"):
            notes.append("hid %s (Ironbark shows bars 1-3 only)" % key)
        bar.update(alwaysHidden=True, barVisibility="never")
    # gryphons flanking the block, on the middle bar so they center on it
    sub(ab, "bars", "Bar2").update(endCapLeft=True, endCapRight=True, endCapArt="forever", endCapScale=150)
    ab.pop("endCapSpanLeft", None)
    ab.pop("endCapSpanRight", None)

    # -- cast bar centered, player and target hugging its ends ---------------
    cb = sub(addons, "EllesmereUIResourceBars", "castBar")
    cb.update(enabled=True, width=CAST_W, height=CAST_H, showIcon=True, showTimer=True, alwaysShow=True)
    cb["unlockPos"] = pos("CENTER", "BOTTOM", 0, COLUMN_Y)
    half = (CAST_W + CAST_H) / 2 + GAP + UF_W / 2

    uf = sub(addons, "EllesmereUIUnitFrames")
    old = dict(uf.get("positions") or {})
    P = sub(uf, "positions")
    P["player"] = pos("CENTER", "BOTTOM", -half, COLUMN_Y)
    P["target"] = pos("CENTER", "BOTTOM", half, COLUMN_Y)
    # satellites keep clear of the column: target-of-target up and right of the
    # target, pet mirrored on the player's side, focus out to the left
    P["targettarget"] = pos("CENTER", "BOTTOM", half + 151.5, COLUMN_Y + 38)
    P["pet"] = pos("CENTER", "BOTTOM", -(half + 151.5), COLUMN_Y + 65)
    focus = pos("CENTER", "BOTTOM", -(half + UF_W + 40), COLUMN_Y)
    P["focus"] = focus
    P["focustarget"] = pos("CENTER", "BOTTOM", focus["x"] + 50, COLUMN_Y - 48)
    # their small cast bars stay linked under each frame (unlockLayout.anchors)
    for k in ("playerCastbar", "targetCastbar", "focusCastbar", "petCastbar"):
        P.pop(k, None)
    for unit in ("player", "target", "focus"):
        u = sub(uf, unit)
        u["healthClassColored"] = True
    for unit in ("player", "target"):
        u = sub(uf, unit)
        u.update(frameWidth=181, healthHeight=46, powerHeight=6, powerPosition="below",
                 showPortrait=True, portraitStyle="attached", portraitSize=0,
                 rightTextContent="both")   # "961 | 100%"
    # your buffs left of the minimap, debuffs under them
    pab = sub(uf, "playerAuraBars")
    pab["buffsPos"] = pos("TOPRIGHT", "TOPRIGHT", -244, -22)
    pab["debuffsPos"] = pos("TOPRIGHT", "TOPRIGHT", -244, -142)

    links = sub(profile, "unlockLayout", "anchors")
    for k in ("player", "target", "focus", "pet", "targettarget", "focustarget", "MainBar", "Bar2", "Bar3",
              "ERB_CastBar", "RF_PartyFrames", "RF_RaidFrames", "EBS_Minimap", "EQT_Tracker", "ECHAT_MainChat",
              "EDM_Win1", "EDM_Win2", "PAB_Buffs", "PAB_Debuffs"):
        links.pop(k, None)   # a link would override the positions set here
    for cbar, unit in (("playerCastbar", "player"), ("targetCastbar", "target"),
                       ("focusCastbar", "focus"), ("petCastbar", "pet")):
        links[cbar] = {"target": unit, "side": "BOTTOM", "offsetX": 0, "offsetY": 0}
    # spec / condition layers would re-apply their own snapshots over all this
    for k in ("specUnlockOverrides", "condUnlockOverrides"):
        if profile.pop(k, None):
            notes.append("dropped %s from the copy (it would move frames back)" % k)

    # -- cooldown bars sat right of the target: keep them there ---------------
    cdm = addons.get("EllesmereUICooldownManager") or {}
    old_target = old.get("target") or {}
    if isinstance(cdm.get("cdmBarPositions"), dict) and old_target.get("relPoint") == "CENTER":
        dx = half - old_target.get("x", half)
        for p in cdm["cdmBarPositions"].values():
            if isinstance(p, dict) and p.get("relPoint") == "CENTER" and isinstance(p.get("x"), (int, float)):
                p["x"] = round(p["x"] + dx, 1)

    # -- party row under the column, raid above the chat ----------------------
    rf = sub(addons, "EllesmereUIRaidFrames")
    rf["partyUnlockPos"] = pos("TOP", "BOTTOM", 0, PARTY_TOP)
    rf.update(partyHorizontal=True, partyFlipGrowth=False, partySortMode="ROLE",
              healthColorMode="class", powerShowForTank=True, powerShowForHealer=True, powerShowForDPS=True,
              unitGrowth="RIGHT", groupGrowth="DOWN")   # raid: groups as rows of 5
    rf["unlockPos"] = pos("BOTTOMLEFT", "BOTTOMLEFT", CHAT["x"] - 4, CHAT["y"] + CHAT["h"] + 34)

    # -- chat bottom-left ----------------------------------------------------
    chat = sub(addons, "EllesmereUIChat", "chat")
    chat["chatPosition"] = pos("BOTTOMLEFT", "BOTTOMLEFT", CHAT["x"], CHAT["y"])
    chat["chatSize"] = {"w": CHAT["w"], "h": CHAT["h"]}
    chat.pop("chatScreenPoint", None)
    chat.update(_chatPosOwnership=1, sidebarVisibility="mouseover", idleFadeEnabled=True, idleFadeDelay=30,
                classColorNames=True, abbreviateChannels=True)

    # -- minimap top-right, quest tracker under it ---------------------------
    mm = sub(addons, "EllesmereUIMinimap", "minimap")
    mm["position"] = pos("TOPRIGHT", "TOPRIGHT", -4, -4)
    mm["_capturedOnce"] = True
    size = mm.get("mapSize", 230)
    qt = sub(addons, "EllesmereUIQuestTracker", "questTracker")
    qt["customPos"] = pos("TOPRIGHT", "TOPRIGHT", -8, -(4 + size + 66))
    qt["position"] = pos("TOPRIGHT", "TOPRIGHT", -8, -(4 + size + 66))

    # -- meters bottom-right: damage, healing to its left --------------------
    dm = sub(addons, "EllesmereUIDamageMeters", "dm")
    wins = sub(dm, "windows")
    w1 = wins[1] if isinstance(wins.get(1), dict) else {}
    w1.update(curDMType=0, width=METER_W, height=METER_H)
    w1["position"] = pos("BOTTOMRIGHT", "BOTTOMRIGHT", -8, 8)
    w2 = copy.deepcopy(w1)
    w2["curDMType"] = 2
    w2["position"] = pos("BOTTOMRIGHT", "BOTTOMRIGHT", -(8 + METER_W + 6), 8)
    wins[1], wins[2] = w1, w2
    for k in [k for k in wins if isinstance(k, int) and k > 2]:
        del wins[k]
    dm["windowCount"] = 2


def build(db, base, name, notes):
    profiles = db["profiles"]
    if base not in profiles:
        raise SystemExit("No EllesmereUI profile named %r. Found: %s" % (base, ", ".join(map(str, profiles))))
    profile = copy.deepcopy(profiles[base])
    apply_layout(profile, notes)
    profiles[name] = profile

    order = db.setdefault("profileOrder", {})
    if name not in order.values():
        order[max([k for k in order if isinstance(k, int)] or [0]) + 1] = LuaStr(name)
    # bar contents (cooldown manager spell lists) are stored beside the profile
    sa = sub(db, "spellAssignments", "profiles")
    if base in sa:
        sa[name] = copy.deepcopy(sa[base])
    # keep it in the same module sync groups as its source
    for group in (db.get("syncedModules") or {}).values():
        if isinstance(group, dict) and group.get(base):
            group[name] = True
    # stop the bars' first-run capture overwriting the layout from Edit Mode
    db["_capturedOnce_EAB"] = True
    db["_capturedOnce_RF"] = True


def activate(db, name):
    """Make the profile load at next login, the way an in-game switch would:
    the frame-link tables live outside the profiles and follow the active one."""
    db["activeProfile"] = LuaStr(name)
    layout = db["profiles"][name].get("unlockLayout") or {}
    for live, saved in (("unlockAnchors", "anchors"), ("unlockWidthMatch", "widthMatch"),
                        ("unlockHeightMatch", "heightMatch")):
        db[live] = copy.deepcopy(layout.get(saved) or {})


def remove(db, name):
    found = db["profiles"].pop(name, None) is not None
    order = db.get("profileOrder") or {}
    names = [v for k, v in sorted((k, v) for k, v in order.items() if isinstance(k, int)) if v != name]
    for k in [k for k in order if isinstance(k, int)]:
        del order[k]
    for i, v in enumerate(names, 1):
        order[i] = v
    (db.get("spellAssignments") or {}).get("profiles", {}).pop(name, None)
    for group in (db.get("syncedModules") or {}).values():
        if isinstance(group, dict):
            group.pop(name, None)
    (db.get("profileKeybinds") or {}).pop(name, None)
    for spec, prof in list((db.get("specProfiles") or {}).items()):
        if prof == name:
            del db["specProfiles"][spec]
    return found


def wow_running():
    try:
        out = subprocess.run(["tasklist"], capture_output=True, text=True).stdout.lower()
    except OSError:
        return False
    return any(n in out for n in ("wow.exe", "wowclassic.exe", "wow-64.exe"))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--game-dir", default=DEFAULT_GAME)
    ap.add_argument("--file", help="EllesmereUI.lua to edit (default: every account under the game dir)")
    ap.add_argument("--out", help="write the result here instead of replacing the file (testing)")
    ap.add_argument("--base", default="Jesk Minimal", help="profile to copy (default: %(default)s)")
    ap.add_argument("--name", default="Ironbark", help="name of the new profile (default: %(default)s)")
    ap.add_argument("--remove", action="store_true", help="remove the profile instead of adding it")
    ap.add_argument("--activate", action="store_true", help="also make it the active profile at next login")
    ap.add_argument("--dry-run", action="store_true", help="change nothing; report what would happen")
    a = ap.parse_args()

    if a.file:
        files = [a.file]
    else:
        acct = os.path.join(a.game_dir, "WTF", "Account")
        files = [os.path.join(acct, d, "SavedVariables", "EllesmereUI.lua") for d in sorted(os.listdir(acct))]
        files = [f for f in files if os.path.isfile(f)]
    if not files:
        raise SystemExit("No EllesmereUI.lua found under %s" % a.game_dir)
    if wow_running() and not (a.dry_run or a.out):
        raise SystemExit("World of Warcraft is running. Exit the game completely, then run this again.")

    for path in files:
        text = open(path, encoding="utf-8", newline="").read()
        data = parse(text)
        if parse(serialize(data)) != data:
            raise SystemExit("Refusing to touch %s: it doesn't survive a read/write round trip." % path)
        db = data.get("EllesmereUIDB")
        if not isinstance(db, dict) or not isinstance(db.get("profiles"), dict):
            raise SystemExit("%s has no EllesmereUI profiles." % path)

        notes = []
        if a.remove:
            if db.get("activeProfile") == a.name:
                raise SystemExit("%r is the active profile; switch to another profile in game first." % a.name)
            if not remove(db, a.name):
                print("%s: no profile %r, nothing to do" % (path, a.name))
                continue
            action = "removed profile %r" % a.name
        else:
            if a.name == a.base:
                raise SystemExit("--name and --base must differ.")
            if db.get("activeProfile") == a.name:
                notes.append("%r is the active profile: after logging in, switch to another profile and back "
                             "so EllesmereUI picks up the frame links" % a.name)
            existed = a.name in db["profiles"]
            build(db, a.base, a.name, notes)
            action = "%s profile %r from %r" % ("rebuilt" if existed else "added", a.name, a.base)
            if a.activate:
                activate(db, a.name)
                action += ", now the active profile"

        result = serialize(data)
        if parse(result) != data:
            raise SystemExit("Internal check failed; nothing written.")
        print("%s: %s" % (path, action))
        for n in notes:
            print("    - " + n)
        if a.dry_run:
            print("    (dry run: nothing written)")
            continue
        if a.out:
            open(a.out, "w", encoding="utf-8", newline="").write(result)
            print("    written to %s" % a.out)
            continue
        backups = os.path.join(REPO, "backups")
        os.makedirs(backups, exist_ok=True)
        stamp = datetime.datetime.now().strftime("%Y-%m-%d_%H%M%S")
        acct_name = os.path.basename(os.path.dirname(os.path.dirname(path))).replace("#", "_")
        backup = os.path.join(backups, "%s-EllesmereUI-%s.lua" % (stamp, acct_name))
        shutil.copy2(path, backup)
        tmp = path + ".ibui-tmp"
        open(tmp, "w", encoding="utf-8", newline="").write(result)
        os.replace(tmp, path)
        print("    backup: %s" % backup)
    if not (a.dry_run or a.remove or a.out):
        print("\nDone. Start WoW, then /eui > Profiles > %s." % a.name)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    main()
