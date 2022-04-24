global function SmallMapTitansInit

bool shouldSetInvincible = true;
bool editPilotLoadout = true;
bool giveOnlyOneTitan = false;

void function SmallMapTitansInit() {
	if (GameRules_GetGameMode() == "speedball" && GetCurrentPlaylistName().find("_lf") != null) return; // Do not enable on special lf modes

	if (split(StringReplace(GetConVarString("small_map_titans_modes"), " ", "", true), ",").find(GameRules_GetGameMode()) >= 0
			&& GetConVarString("small_map_titans_maps").find(GetMapName()) != null) {
		Riff_ForceSetSpawnAsTitan( eSpawnAsTitan.Never );	// Force players to spawn as pilots
		AddCallback_OnPlayerKilled( OnPlayerKilled );
		AddCallback_OnPlayerRespawned( OnPlayerRespawned );
		if (GameRules_GetGameMode() == "speedball") {
			shouldSetInvincible = false;
			editPilotLoadout = false;
			giveOnlyOneTitan = true;
			AddCallback_GameStateEnter( eGameState.Playing, OnEnterPlaying );
			AddCallback_GameStateEnter( eGameState.WinnerDetermined, OnWinnerDetermined );
			AddCallback_OnPilotBecomesTitan( DropFlagForBecomingTitan );
		}
		if (GetCurrentPlaylistVarInt("classic_mp", 1) == 1) ClassicMP_DefaultNoIntro_Setup();
	}
}


void function OnEnterPlaying() {
	//Chat_ServerBroadcast("PLAYING");
	//Chat_ServerBroadcast(GetCurrentPlaylistName());
	thread AddRoundTime_Threaded(GetConVarFloat("small_map_titans_additional_lf_time"));	// Add a couple mins to live fire modes
}

void function AddRoundTime_Threaded(float time) {
	WaitFrame();
	SetServerVar( "roundEndTime", expect float(GetServerVar("roundEndTime")) + time)
}

bool function PlayerHasFlag( entity player ) {
	entity flagCarrier = GetGlobalNetEnt( "flagCarrier" );
	if (flagCarrier == player) return true;
	return false;
}

void function DropFlagForBecomingTitan( entity pilot, entity titan ) {
	//Chat_ServerBroadcast("EMBARKING");
	if (PlayerHasFlag(pilot)) thread PhaseToDropFlag_Threaded( pilot );
}

void function PhaseToDropFlag_Threaded(entity ent) {
	//Chat_ServerBroadcast("PHASING");
	while (PlayerHasFlag(ent)) {
		PhaseShift( ent, 0, 0.001 );
		WaitFrame();
	}
}

void function OnWinnerDetermined() {
	//Chat_ServerBroadcast("WINNER DETERMINED");
	foreach (entity player in GetPlayerArray()) {
		//KillPlayersTitan(player);
		if (player.IsTitan()) thread PlayerDisembarksTitan( player );	// Have each player disembark to prevent crash
	}
}

void function OnPlayerKilled( entity victim, entity attacker, var damageInfo ) {
	if (victim.IsTitan() || giveOnlyOneTitan) return;
	// Kill the titan if the player died and wasn't even in it
	KillPlayersTitan(victim);
}

void function OnPlayerRespawned( entity player ) {
	if (!IsValid(player)) return;

	if (editPilotLoadout) {
		foreach ( entity weapon in player.GetMainWeapons() ) player.TakeWeaponNow( weapon.GetWeaponClassName() );
		foreach ( entity weapon in player.GetOffhandWeapons() ) player.TakeWeaponNow( weapon.GetWeaponClassName() );

		// Give the player something to hold to know they are cloaked
		player.GiveWeapon("mp_weapon_semipistol");
		foreach ( entity weapon in player.GetMainWeapons() ) {
	    weapon.SetWeaponPrimaryAmmoCount(0);
	    weapon.SetWeaponPrimaryClipCount(0);
		}
		GivePassive(player, ePassives.PAS_STEALTH_MOVEMENT);
		Rodeo_Disallow(player); // Disable rodeo so players will get in the fucking robot shinji
	}
	GivePassive(player, ePassives.PAS_FAST_EMBARK); // Give phase embark as QOL

	//Disembark_Disallow(player); // Do not let player disembark because they could call a fresh titan
	if (shouldSetInvincible) {
		player.SetInvulnerable();
		EnableCloak( player, GetConVarFloat("small_map_titans_invincible_time") );
	}

	if (!giveOnlyOneTitan) SendHudMessage( player, "Stand still to call your titan\n  Move again to reposition", 0.41, 0.4, 240, 182, 27, 255, 0, 6, 2);
	thread SpawnTitan_Threaded(player);
}

void function SpawnTitan_Threaded(entity player) {
	while (GetGameState() != eGameState.WinnerDetermined && IsValid(player) && IsAlive(player) && !player.IsTitan() && !IsPlayerEmbarking(player)) {

		// Players have a limited time of invincibility and invisibility to enter titan
		if (GetPlayerLastRespawnTime(player) < Time() - GetConVarFloat("small_map_titans_invincible_time")) {
			player.ClearInvulnerable();
		}

		while (GameRules_GetGameMode() != "speedball" // We do not wait in lf because we want the titan to drop as soon as players spawn
					 && !IsValid(GetPlayerTitanInMap( player ))
					 && IsValid(player)
					 && Length(player.GetVelocity()) == 0) WaitFrame();	// Wait until player starts to move
		while (IsValid(player) && Length(player.GetVelocity()) > 0) WaitFrame();	// Now wait until player stops

		Point dropPoint;
		if (IsValid(player) && IsAlive(player) && !player.IsTitan() && !IsPlayerEmbarking(player)) {
			dropPoint.origin = player.GetOrigin();
			thread CreateTitanForPlayerAndHotdrop( player, dropPoint );
		}
		if (giveOnlyOneTitan) return;

		// Wait for titan to drop
		while (IsValid(player) && IsReplacementDropInProgress(player)) {
			// Kill the titan if the player has moved away from the drop point
			if (Distance( player.GetOrigin(), dropPoint.origin ) > 250) KillPlayersTitan(player);
			WaitFrame();
		}

		// Wait until player has either embarked or moved away from titan
		while (IsValid(player)
					 && IsValid(GetPlayerTitanInMap( player ))
					 && !player.IsTitan() && !IsPlayerEmbarking(player)
					 && Distance( player.GetOrigin(), GetPlayerTitanInMap( player ).GetOrigin() ) < 250) {
			//Chat_ServerBroadcast(Distance( player.GetOrigin(), GetPlayerTitanInMap( player ).GetOrigin() ).tostring())
			WaitFrame();
		}
	}

	if (IsValid(player)) player.ClearInvulnerable();
}

void function KillPlayersTitan( entity player ) {
	entity titan = GetPlayerTitanInMap( player );
	if (IsValid(titan)) titan.Die();
}
