# Roadmap

1. Validate the local weapon/health prototype across fresh launches and
   reconnects. Expand collision, death and respawn coverage before adding
   more weapons.
2. Implement a Steam session and game-traffic transport using the authenticated
   game context. Require relay-only routing for IP privacy where available.
   Test with separate authenticated peers; keep localhost as the test path.
3. Replace/review the temporary combat RPC carrier and review the engine's
   inherited server RPCs. Add movement validation, abuse limits and version
   negotiation. Player-hosted PvP still trusts its host.
4. Add faction assignment, first-person arms/weapon animation and both factions'
   proper vision abilities. Co-op may offer third person; active PvP players
   remain first person. Spectator/death-camera rules need a separate decision.
5. Investigate general campaign co-op and dedicated-server feasibility. Test
   on separate machines and content editions before a public online release.
6. Publish tested preview artifacts through GitHub Releases. Workshop would
   require the game's developer/publisher to enable and integrate it.
