global function SmallMapTitansInit

bool shouldSetInvincible = true;
bool editPilotLoadout = true;
bool giveOnlyOneTitan = false;
float relocateTitanDistance = 280;

void function SmallMapTitansInit() {
	if (GameRules_GetGameMode() == "speedball" && GetCurrentPlaylistName().find("_lf") != null) return; // Do not enable on special lf modes

	if (split(StringReplace(GetConVarString("small_map_titans_modes"), " ", "", true), ",").find(GameRules_GetGameMode()) >= 0
			&& GetConVarString("small_map_titans_maps").find(GetMapName()) != null) {
		Riff_ForceSetSpawnAsTitan( eSpawnAsTitan.Never );	// Force players to spawn as pilots
		AddCallback_OnPlayerKilled( OnPlayerKilled );
		AddCallback_OnPlayerRespawned( OnPlayerRespawned );
		AddCallback_OnClientConnected(OnPlayerConnected);
		//AddCallback_OnClientConnected(OnPlayerDisconnected);
		if (GameRules_GetGameMode() == "speedball") {
			shouldSetInvincible = false;
			editPilotLoadout = false;
			giveOnlyOneTitan = true;
			AddCallback_GameStateEnter( eGameState.Playing, OnEnterPlaying );
			AddCallback_GameStateEnter( eGameState.WinnerDetermined, OnWinnerDetermined );
			AddCallback_OnPilotBecomesTitan( DropFlagForBecomingTitan );
		}
		//if (GetCurrentPlaylistVarInt("classic_mp", 1) == 1) ClassicMP_DefaultNoIntro_Setup();
		ClassicMP_SetCustomIntro( ClassicMP_DefaultNoIntro_Setup, ClassicMP_DefaultNoIntro_GetLength() )
	}
}

void function OnPlayerConnected( entity player ) {
	if (IsAlive(player)) {
		player.Die();
		Chat_ServerBroadcast("DIE");
	}
}

void function OnPlayerDisconnected( entity player ) {
	//KillPlayersTitan(player);
	//player.Die();
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

/*
mixtape_1  | [15:42:49] [info] [SERVER SCRIPT] TitanDisembarkDebug: Player  <-747.961, 1719.03, 4.03125> <0, 42.4555, 0> mp_lf_traffic
mixtape_1  | [15:42:49] [info] [SERVER SCRIPT] SCRIPT ERROR: [SERVER] ContextAction_SetBusy: Already in the middle of a context action: execution_target
mixtape_1  | [15:42:49] [info] [SERVER SCRIPT]  -> player.ContextAction_SetBusy()
mixtape_1  | [15:42:49] [info] [SERVER SCRIPT]
mixtape_1  | CALLSTACK
mixtape_1  | *FUNCTION [PlayerDisembarksTitanWithSequenceFuncs()] titan/sh_titan_embark.gnut line [1400]
mixtape_1  | *FUNCTION [PlayerDisembarksTitan()] titan/sh_titan_embark.gnut line [1371]
mixtape_1  |
mixtape_1  | [15:42:49] [info] [SERVER SCRIPT] LOCALS
mixtape_1  | [wasCustomDisembark] false
mixtape_1  | [e] TABLE
mixtape_1  | [titanSequenceFunc] CLOSURE
mixtape_1  | [playerSequenceFunc] CLOSURE
mixtape_1  | [player] ENTITY (player XymaScope [3] (player "XymaScope" at <-747.961 1719.03 4.03125>))
mixtape_1  | [this] TABLE
mixtape_1  | [player] ENTITY (player XymaScope [3] (player "XymaScope" at <-747.961 1719.03 4.03125>))
mixtape_1  | [this] TABLE
mixtape_1  |
mixtape_1  | DIAGPRINTS
mixtape_1  |
mixtape_1  | [15:42:49] [info] [SERVER SCRIPT] ShouldDoReplay(): Not doing a replay because the player died from an execution.
*/

void function OnWinnerDetermined() {
	//Chat_ServerBroadcast("WINNER DETERMINED");
	foreach (entity player in GetPlayerArray()) {
		//KillPlayersTitan(player);
		if (player.IsTitan()) {
			// Have each player disembark to prevent crash
			entity titan = CreateAutoTitanForPlayer_ForTitanBecomesPilot(player);
			DispatchSpawn( titan );
			thread TitanBecomesPilot(player, titan);

			//if ( player.ContextAction_IsBusy() ) {

			//}
			// thread PlayerDisembarksTitan( player );
			//thread ForcedTitanDisembark(player);

		}
	}
}

void function OnPlayerKilled( entity victim, entity attacker, var damageInfo ) {
	if (victim.IsTitan() || giveOnlyOneTitan) return;
	// Kill the titan if the player died and wasn't even in it
	KillPlayersTitan(victim);
}

void function OnPlayerRespawned( entity player ) {
	if (!IsValidPlayer(player)) return;

	if (editPilotLoadout) {
		//foreach ( entity weapon in player.GetMainWeapons() ) player.TakeWeaponNow( weapon.GetWeaponClassName() );
		//foreach ( entity weapon in player.GetOffhandWeapons() ) player.TakeWeaponNow( weapon.GetWeaponClassName() );
		TakeAllWeapons(player);

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

	if (!giveOnlyOneTitan) SendHudMessage( player, "Stand still in an open space to call your titan\n                  Move again to reposition", 0.35, 0.4, 240, 182, 27, 255, 0, 8, 2);
	thread SpawnTitan_Threaded(player);
}

void function SpawnTitan_Threaded(entity player) {
	while (GetGameState() != eGameState.WinnerDetermined && IsValidPlayer(player) && IsAlive(player) && !player.IsTitan() && !IsPlayerEmbarking(player)) {

		// Players have a limited time of invincibility and invisibility to enter titan
		if (GetPlayerLastRespawnTime(player) < Time() - GetConVarFloat("small_map_titans_invincible_time")) player.ClearInvulnerable();

		while (GameRules_GetGameMode() != "speedball" // We do not wait in lf because we want the titan to drop as soon as players spawn
					 && IsValidPlayer(player)
					 && Length(player.GetVelocity()) == 0
					 && !IsValid(GetPlayerTitanInMap( player ))) WaitFrame();	// Wait until player starts to move
		while (IsValidPlayer(player)
					 && (Length(player.GetVelocity()) > 0
					 		 || GetVerticalClearance(player.GetOrigin()) <= 250 )
				  ){
						 //Chat_ServerBroadcast(GetVerticalClearance(player.GetOrigin()).tostring());
						 WaitFrame();	// Now wait until player stops
					 }

					 //Chat_ServerBroadcast("DROPPING " + GetVerticalClearance(player.GetOrigin()).tostring());

		Point dropPoint;
		if (IsValidPlayer(player) && IsAlive(player) && !player.IsTitan() && !IsPlayerEmbarking(player)) {
			dropPoint.origin = player.GetOrigin();
			dropPoint.angles = player.GetAngles();
			thread CreateTitanForPlayerAndHotdrop( player, dropPoint );
		}

		// Wait for titan to drop
		while (IsValidPlayer(player) && IsAlive(player) && IsReplacementDropInProgress(player)) {
			if (PlayerHasTitan(player) && Distance( player.GetOrigin(), player.GetPetTitan().GetOrigin() ) < 200) PlayerLungesToEmbark(player, player.GetPetTitan());
			else if (Distance( player.GetOrigin(), dropPoint.origin ) > relocateTitanDistance) KillPlayersTitan(player); // Kill the titan if the player has moved away from the drop point
			WaitFrame();
		}

		if (giveOnlyOneTitan) return;

		// Wait until player has either embarked or moved away from titan
		while (IsValidPlayer(player)
					 && IsValid(GetPlayerTitanInMap( player ))
					 && !player.IsTitan()
					 && !IsPlayerEmbarking(player)
					 && Distance( player.GetOrigin(), GetPlayerTitanInMap( player ).GetOrigin() ) < relocateTitanDistance) {
			//Chat_ServerBroadcast(Distance( player.GetOrigin(), GetPlayerTitanInMap( player ).GetOrigin() ).tostring())
			WaitFrame();
		}
	}

	if (IsValidPlayer(player)) player.ClearInvulnerable();
}

void function KillPlayersTitan( entity player ) {
	if (!PlayerHasTitan(player)) return;
	entity titan = GetPlayerTitanInMap( player );
	if (IsValid(titan) && IsAlive(titan)) titan.Die();
}
