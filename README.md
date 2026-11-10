# Resistance Multiplayer — alpha 0.6.0-alpha.1

An unofficial Terminator Resistance multiplayer experiment. The Infiltrator experiment keeps the original
mission: the host plays the native Infiltrator, while player two takes
control of an existing Resistance soldier in the selected bunker.

**This alpha includes Steam invitation acceptance, experimental relay transport
and local crash reporting. Internet play between separate accounts/machines
has NOT yet been validated.** The tested gameplay path uses two isolated
instances on one PC, including a local Steam socket-pair tunnel test.
See [the Steam test guide](docs/STEAM-TEST.txt). Default launches
still use localhost. Campaign co-op and competitive multiplayer are unfinished.

This alpha prepares local crash reports for review; nothing is
uploaded automatically. Use **Diagnostic reports** in the launcher. Public
GitHub sharing is optional and requires deliberate submission in your browser.
See [diagnostic data, limits and privacy controls](docs/DIAGNOSTICS-PRIVACY.txt).

**[Download the alpha installer ZIP](https://github.com/Pox101/Terminator-Resistance-Multiplayer/releases/download/v0.6.0-alpha.1/TRMP-0.6.0-alpha.1.zip)**
([release notes](https://github.com/Pox101/Terminator-Resistance-Multiplayer/releases/tag/v0.6.0-alpha.1)).
No Git, GitHub account, compiler or developer tools are needed to download or
install. Extract all files, run Install-Mod.cmd, then Launch-Mod.cmd in the
installed folder. Start with [START-HERE.txt](START-HERE.txt) and [QUICK-START.txt](QUICK-START.txt).
For reporting without GitHub, see [REPORT-A-BUG.txt](REPORT-A-BUG.txt).
Contact: **luckyluka160@gmail.com** or [TRMP Discord](https://discord.gg/Dg2qD6U3b)
for testing partners and reviewed report attachments. Discord was announced
after the alpha.1 ZIP was packaged; the existing email/report-folder buttons
work with that ZIP. No automatic Discord upload or bot is installed.
One tester switches window focus to control each instance. Simultaneous
two-controller couch PvP and split-screen are not implemented. A test checklist
and feedback template are in `docs/`.

Stability is experimental. Native client initialization required safe visual
mirrors. A crash dump identified a fault inside UE4SS Lua callback handling;
recurring asynchronous scheduling was replaced by a fixed game-thread callback
and a local deadline queue. Longer sessions and complete mission playthroughs
remain unverified. See [the related UE4SS issue](https://github.com/UE4SS-RE/RE-UE4SS/issues/1180).

## Infiltrator mission experiment

- The original mission creates its randomized world before listen hosting
  starts. Hosting does not reopen or replace the mission.
- The joining player drives one existing bunker soldier. Its original
  actor, health, team and mission references stay on the host.
- The host keeps the native Infiltrator weapon, health, HUD and vision.
- Native Infiltrator shots damage the original player-controlled soldier.
  Its native death contributes to the game's own kill statistics. A dead
  defender loses movement and firing and stays eliminated without respawning.
- Player shooting uses the soldier's original rifle range, rate, ammo and
  damage type, with server hit tests feeding the native damage system.
  Reload requests use the native weapon component.
- Randomized bunker interior transforms are sent to the client.
- Original mission objectives remain. There is no added round timer,
  defender-kill victory condition or automatic player respawn.
- The client receives the native mission outcome. Native mission completion
  and Infiltrator defeat stop further defender actions and show an end message.
  The defender sees MISSION FAILED when the Infiltrator completes its mission,
  and MISSION SUCCESS when the Infiltrator is stopped. The native host summary
  and the original mission state remain unchanged.
  **Restart Mission** reloads the native mission. The previously connected
  defender waits through the disconnect and rejoins when hosting is ready.
  Finish the original loading screens with a key press on both games.
- The Resistance player's first-person view uses the installed Avatar arms,
  plasma idle/aim/fire/reload animations and the native weapon socket.

This is a one-defender experiment. Other soldiers remain NPCs. Additional
human slots, full NPC animation/ragdoll synchronization and visual polish
still need work. End-to-end native weapon hits, defender death and the
native ending flow were exercised in an accelerated local integration test;
a normal full-length playthrough and longer sessions remain unverified. The joining player's
world-body presentation still uses simplified visuals.

## Earlier arena prototype

- Plasma firing requests over the existing owned player connection.
- Host-controlled ammunition, fire rate, two-second reloads and hit tests.
- Player health, kills/deaths and five-second respawns without invoking the
  single-player game-over/save pipeline.
- PvP uses first person; its third-person switch is disabled.
- Co-op blocks damage between players and permits first/third person.
- A combat HUD, weapon meshes, muzzle/audio effects and Terminator vision
  preview. The plasma view model uses native Avatar hands and animations;
  faction-specific hands and complete weapon animation support need work.

The arena prototype assigns the native host as human and joining base
characters as Terminators. Human/Terminator balancing is preliminary (100
versus 1000 health). General faction selection and additional players have
not been play-tested.

## Install

1. Own and install the compatible Steam game. Download the release ZIP and
   extract it before running anything.
2. Double-click **Install-Mod.cmd**. It finds the Steam game, downloads the
   pinned official UE4SS dependency, and prepares isolated game copies under
   `%LOCALAPPDATA%\TRMP-LocalPreview`.
3. Open **Launch-Mod.cmd in the installed folder**. For the mission test,
   select **Start Infiltrator mission host**.
4. In the host game choose **Play → New Infiltrator Mode**, finish the intro
   and wait for automatic hosting. Existing copied campaign saves remain available.
5. Select **Play a Resistance NPC**, then **Join player two** and finish the
   joining game's loading screen. The soldier appears inside the chosen bunker.

For the earlier arena test, start a co-op/PvP host, choose **Play → Continue**
to use the copied save, then **Host loaded save** before joining player two.

### Experimental Steam invitations

In an isolated mod game, choose **Play → Play Versus**, below Infiltrator
Mode. This creates a private two-person Steam lobby and opens Steam's friend
invitation dialog. **Invite Friends** reopens that dialog; **Back** leaves
the lobby. Steam must be running with the overlay enabled.

The older 0.5.1 previews the menu/invitation flow only. This alpha
0.6 adds an opt-in Steam Versus path with invite acceptance, lobby checks and
relay transport. Separate-peer Internet validation is pending; see
[STEAM-TEST.txt](docs/STEAM-TEST.txt). Use the default launcher steps above for
the existing two-instance local test.

If automatic discovery fails, run:

```powershell
.\Install-Mod.ps1 -GameRoot 'D:\SteamLibrary\steamapps\common\Terminator Resistance'
```

The installer verifies this executable SHA256 before installing:
`5A01BBEE102990B1B1108C8656994ED19D46A9B2735C3B3A11EB9C7921CAFDB4`.
Other builds and content combinations have not been validated. The shipped
Infiltrator and Resistance soldier assets used by the prototype must be
installed; DLC/content compatibility still needs broader testing.

## Save isolation

The installer reads and copies original saves once into each isolated
profile. Game launches use their own `-UserDir`. Updating the preview keeps
those copied profiles. Installation never writes to the original game or
original save directory. The large Engine/Content folders are linked to the
existing installation and are not bundled or duplicated.

Close the preview game windows before updating. Do not publish your runtime,
profile, backup, crash or log directories when sharing the source project.

## Experimental Infiltrator mission takeover

The launcher also offers **Start Infiltrator mission host** and **Play a
Resistance NPC**. This scenario is under live validation; it is separate from the
campaign-save arena above.

1. Start the Infiltrator host. Choose **Play > New Infiltrator Mode**, select
   Normal difficulty and finish the loading screen and intro.
2. Hosting starts in the existing mission after the intro. Do not use
   **Host loaded save** for this scenario: it would reopen the level.
3. Start the Resistance defender and use **Join player two**. Finish its
   loading screen promptly; this map is larger than the arena map.
4. Player two takes control of an existing soldier in the selected Tech-Com
   bunker. Both players use first person. The Infiltrator still follows the
   original intel/bunker objectives. The defender tries to stop it.

The native host runs the Infiltrator and Resistance NPC simulation. The
client uses base-engine character mirrors to avoid executing unsupported
single-player callbacks. NPC mirrors currently use the common Resistance
soldier model, walking/idle animation and disappear on death; full ragdolls
and precise weapon-animation replication are unfinished. The defender's
movement drives the original NPC, and firing/reloading commands use that
NPC's original weapon component. Its original health and quest/death
callbacks remain authoritative. The client plasma view model attaches to the
native Avatar's hand socket. The installed Infiltrator/Franco model is used;
an exact film-model T-850 designation has not been established.

There is no added survival timer or replacement victory condition. Killing
the controlled soldier removes that original NPC; the Infiltrator mission
continues. Restart through the game's original mission flow. The prototype
currently supports one remote NPC player; larger player counts are untested.

After **Restart Mission**, the defender may briefly show the main menu while
the host reloads and repeats its intro. It rejoins automatically; press a key
to finish each game's loading screen. This recovery follows only a previously
joined local host in the same running process. Relaunching the host requires
an explicit join again. Both instances must use this version.

## Controls

| Input | Action |
| --- | --- |
| WASD / mouse | Move / look |
| Left mouse | Fire plasma rifle |
| Right mouse | Aim zoom |
| R | Reload |
| F5 | First/third person in co-op; rejected in PvP |
| V | Joining Terminator's vision preview |
| F6 / F7 | Host current gameplay level / join localhost |

Focus the window for the player you want to control. Short automated key taps
may be missed by the loader; normal held input is sampled independently for
the foreground process. Spawning near scenery can obstruct movement; strafe
into clear space. The shoulder camera pulls forward around obstructions.

Resistance ultravision for all networked humans and full Terminator
scanning/highlighting are intended features, not completed ones. Campaign
AI, objectives, progression, enemy damage and general map travel are not
certified for co-op by this preview.

## Networking and security status

The launcher binds IP networking to **127.0.0.1**. Do not change it to expose
the prototype on the Internet. The host computes player hits and owns combat
state; clients send only fire/reload actions. Existing owned engine RPCs
carry these actions. That temporary carrier needs replacement/review before
production online use. Packet/state validation and weapon rate limits are
covered by tests, but the original engine's networking surface is not audited.

The optional Steam diagnostic found the game authenticated as app 954740,
obtained SteamNetworkingSockets012, delivered a local network socket-pair
payload and reported the relay network available. This does **not** prove
Steam peer-to-peer game connectivity, relay-only IP privacy or cheat resistance.
The alpha implements real-peer lobby/transport code, but an actual two-account
Internet test is still required. Authenticated relay flags and a working local
socket pair do not establish that the whole remote flow works on other PCs.

## Build and test

Use Visual Studio C++ x64 build tools on Windows:

```powershell
.\Build-Native.cmd
python -m pip install -r tests/requirements.txt
python tests/run_rules.py
.\Package-Release.ps1
```

The package builder uses an explicit file allowlist and generates a payload
manifest plus archive SHA256. It excludes game files, saves, logs and local
attachments. The GitHub workflow builds/tests and uploads a preview artifact;
an explicit release workflow can publish a prerelease once the repository is
connected. See `docs/RELEASE-NOTES.md` and `docs/ROADMAP.md`.

MIT applies to the project's original code. Game content and dependencies
retain their own rights; see `THIRD-PARTY-NOTICES.txt`.
