# Resistance Multiplayer — local preview

An unofficial Terminator Resistance experiment: two game instances, a human
and an Infiltrator body, independent movement, mouse aiming and a small
host-controlled combat prototype.

**This release connects two instances on one Windows PC. Steam Internet
matches are not implemented. It is a development preview, not finished
campaign co-op or a competitive multiplayer release.**

Stability is experimental. A host crash occurred during cold-start testing;
input callbacks were simplified afterward, but longer sessions and repeated
reconnects still need validation.

## What works

- Plasma firing requests over the existing owned player connection.
- Host-controlled ammunition, fire rate, two-second reloads and hit tests.
- Player health, kills/deaths and five-second respawns without invoking the
  single-player game-over/save pipeline.
- PvP uses first person; its third-person switch is disabled.
- Co-op blocks damage between players and permits first/third person.
- A combat HUD, weapon meshes, muzzle/audio effects and Terminator vision
  preview. First-person hands and proper weapon animations remain unfinished.

The prototype currently assigns the native host as human and joining base
characters as Terminators. Human/Terminator balancing is preliminary (100
versus 1000 health). General faction selection and additional players have
not been play-tested.

## Install

1. Own and install the compatible Steam game. Download the release ZIP and
   extract it before running anything.
2. Double-click **Install-Mod.cmd**. It finds the Steam game, downloads the
   pinned official UE4SS dependency, and prepares isolated game copies under
   `%LOCALAPPDATA%\TRMP-LocalPreview`.
3. Open **Launch-Mod.cmd in the installed folder**. Start a co-op or PvP host.
4. In the host game, choose **Play → Continue** to load the copied save. Use
   **Host loaded save** in the launcher, then finish the game's loading screen.
5. Start player two, use **Join player two**, and finish its loading screen.
   The joining character appears near the host after initialization.

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
A real peer/session transport and Internet test are still required.

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
