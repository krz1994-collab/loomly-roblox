# Bloomly (Roblox) — vertical slice

A fresh, server-authoritative Roblox build of Bloomly's core loop:
**plant → grow → harvest → (server-rolled mutation) → sell.**

This is **not** a port of the web (three.js) game. Roblox has its own rendering, camera, input,
avatars and UI, so none of that carried over. What carried over is the **design and balance** —
the plant values, grow times and mutation rates — ported from the web `economy.js` into data tables.

One biome, six crops, six plots, the full six-tier mutation ladder. Everything else (more biomes,
trade, social, monetization) is added later by **appending rows to the data tables**, not by
changing logic.

---

## 1. Install the tools (one time)

You need two things: **Roblox Studio** and **Rojo** (which syncs these text files into Studio).

**a. Roblox Studio** — install from <https://create.roblox.com/> if you don't have it.

**b. Rokit** — the toolchain manager that installs the correct Rojo version for you.
Install Rokit once by following <https://github.com/rojo-rbx/rokit#installation>
(macOS/Linux: a `curl … | sh` line; Windows: a PowerShell line). Then confirm:

```bash
rokit --version
```

**c. Rojo** — from *inside this project folder*, let Rokit read `rokit.toml` and install the pinned Rojo:

```bash
cd bloomly-roblox
rokit install
```

If Rokit asks you to *trust* the `rojo-rbx/rojo` tool the first time, say yes. Confirm:

```bash
rojo --version      # should print: Rojo 7.7.0
```

**d. The Rojo Studio plugin** — this is the button inside Studio that connects to Rojo:

```bash
rojo plugin install
```

(Restart Studio afterwards if it was open, so the plugin loads.)

---

## 2. Run it

**Terminal** — from this folder, start the Rojo server:

```bash
rojo serve
```

You'll see something like `Rojo server listening on port 34872`. Leave this running.

**Studio** —
1. Open Studio and create a **new Baseplate** place (Home → New → Baseplate).
2. In the toolbar, open the **Rojo** plugin and click **Connect** (it defaults to `localhost:34872`).
   The scripts and data modules stream into the place: check *Explorer* and you should see
   `ReplicatedStorage → Bloomly`, `ServerScriptService → BloomlyServer`, and
   `StarterPlayer → StarterPlayerScripts → BloomlyClient`.
3. Press **Play** (F5).

> While `rojo serve` is running, editing any file in `src/` and saving it live-updates Studio.

---

## 3. What you should see

- A full-screen dark UI overlay (the slice is UI-only; the baseplate/avatar sit behind it — that's
  expected, we're proving the loop, not the art).
- A header: **`coins: 20   lifetime earned: 0   harvests: 0`** (20 is the ported starting balance).
- A **Seeds** row. `radish` and `sunflower` are selectable. `strawberry` and `blueberry` show
  **LOCKED** (they unlock by *lifetime earned* — 100 and 1000). `pumpkin` and `starbloom` are open
  because you own 6 plots (their unlock is "own N plots").
- Six **Plot** buttons, all `(empty)`.
- A **Sell all** button and an **Inventory** area.
- In the **Output** window: `[Bloomly] server ready -- authoritative loop online (6 plots/player)`.

**Do the loop (use radish — it grows in 20s):**
1. Tap **radish** (it highlights green).
2. Tap an empty **Plot**. It becomes `radish  growing  20s left` and counts down every second.
3. When it flips to `radish  READY  tap to harvest`, tap it. The plot empties and your **Inventory**
   shows e.g. `🥕 radish x1 @9c = 9c` — or, if the server rolled a mutation, `radish [golden] x1 @45c`.
4. Tap **Sell all**. Coins jump, inventory clears, `lifetime earned` rises.
5. Earn 100 lifetime → `strawberry` unlocks. Earn 1000 → `blueberry` unlocks. (You'll see the LOCKED
   labels turn into plantable buttons.)

Everything you see is the **server's** truth pushed to your screen once a second. The client only
draws it and sends taps.

---

## 4. The authority boundary at a glance

The client can only affect the game through the remotes below. Every one is validated on the server
before it acts; an unlisted action is impossible. (Details in `src/shared/Remotes.luau` and in the
comment header above each handler in `src/server/init.server.luau`.)

| Remote | Type | Direction | Server validates before acting |
|---|---|---|---|
| `Plant` | RemoteEvent | client → server | arg types (`seedId` string, `plotIndex` number); plot index in range; **plot is empty** (no overwrite); seed id is real; **seed is unlocked for this player** (re-checked server-side, not trusted from the client menu) |
| `Harvest` | RemoteEvent | client → server | arg type (`plotIndex` number); plot index in range; plot **has a crop**; crop is **READY per the server grow clock** (client can't fast-forward growth). **The mutation is rolled on the server** — the outcome is never client-supplied |
| `SellAll` | RemoteEvent | client → server | nothing is trusted — carries **no args**. Server prices the player's **own** inventory at the NPC floor (`baseValue × mutation.mult`) and credits coins. Client cannot set price or amount |
| `GetState` | RemoteFunction | client → server | nothing to validate — it's a **read of the caller's own state only** (keyed off `player`, never a client-supplied id) |
| `StateUpdate` | RemoteEvent | server → client | server→client only. The authoritative view; the client renders it and computes nothing authoritative |

The single most exploit-sensitive line — the mutation roll — lives in `Farm.rollMutation` and runs
**only on the server**. If the client rolled it, every harvest would be the rarest tier.

---

## 5. Where things live

```
default.project.json     Rojo mapping of src/ into the Roblox DataModel
rokit.toml               pins Rojo 7.7.0 (via Rokit)
src/
  shared/                -> ReplicatedStorage.Bloomly  (data + remotes; both sides read these)
    data/
      Config.luau          start coins, plot count, tunables
      Plants.luau          6 meadow crops (values ported from web economy.js) + unlock rules
      Mutations.luau       the 6-tier rarity ladder (spec §2.2)
      Biome.luau           the one starting biome (spec §2.4 schema)
    Remotes.luau           defines every RemoteEvent/RemoteFunction (the whole client↔server surface)
  server/                -> ServerScriptService.BloomlyServer  (authoritative; never trusts the client)
    init.server.luau       lifecycle + validated remote handlers + 1s state-push loop
    PlayerData.luau        in-memory state store + the DataStore seam (load/save TODOs, spec §5.2)
    Farm.luau              the loop rules: mutation roll, plant/harvest/sell, price floor, client view
  client/                -> StarterPlayer.StarterPlayerScripts.BloomlyClient
    init.client.luau       the whole UI: renders server state, sends the 3 intents
```

## 6. Adding content later (the point of the data-driven shape)

- **More crops** → add rows to `Plants.luau`.
- **Different rarity odds / a new tier** → edit/add rows in `Mutations.luau`.
- **A new biome** → add a row to `Biome.luau` (and its crop rows to `Plants.luau`).

None of these touch `Farm.luau` or the server handlers. Logic stays fixed; content is data.

## 7. What is deliberately NOT here (and where it plugs in)

- **Persistence:** state is in-memory only. The exact drop-in points for a session-locked DataStore
  are marked `TODO(DataStore §5.2)` in `PlayerData.luau` (`load`/`save`) and `init.server.luau`
  (`BindToClose`). Build against those two functions.
- **No** marketplace, trade, social, monetization, or second biome — by design. One loop, done
  authoritatively, first.

---

*Not committed to git yet — the repo is initialized but the initial commit is left for you to make
(`git add -A && git commit`). Build verified with `rojo build` (structure) and `luau-analyze`
(the data modules type-check clean; all scripts parse with zero syntax errors).*
