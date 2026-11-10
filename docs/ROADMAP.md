# Roadmap

1. Native incoming weapon damage, defender death and the original ending flow
   have local integration coverage. Verify a normal full-length Infiltrator
   playthrough, disconnect recovery and repeated travel across fresh launches.
   Replace the unsafe native network Restart Mission path with a validated
   return-to-lobby/restart flow before enabling Internet sessions.
   Add more occupied NPC slots only after the one-defender test is reliable.
2. The Play Versus menu, private Steam lobby creation and native invitation
   dialog are available as a UI preview. Implement invitation acceptance,
   lobby joining, version/content negotiation and game-traffic transport using
   the authenticated game context. Require relay-only routing for IP privacy where available.
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
