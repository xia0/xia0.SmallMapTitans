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
		AddCallback_OnClientConnected( OnPlayerConnected );
		//AddCallback_OnClientConnected(OnPlayerDisconnected);
		if (GameRules_GetGameMode() == "speedball") {
			shouldSetInvincible = false;
			editPilotLoadout = false;
			giveOnlyOneTitan = true;
			AddCallback_GameStateEnter( eGameState.Playing, OnEnterPlaying );
			AddCallback_GameStateEnter( eGameState.WinnerDetermined, OnWinnerDetermined );
			//AddCallback_OnPilotBecomesTitan( DropFlagForBecomingTitan );
			AddCallback_OnTouchHealthKit( "item_flag", OnFlagCollected );
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

bool function OnFlagCollected( entity player, entity flag ) {
	thread MonitorForEmbark_Threaded( player, flag );
	return false;
}

void function MonitorForEmbark_Threaded( entity player, entity flag ) {
	while (IsValidPlayer(player) && IsAlive(player) && PlayerHasFlag(player)) {
		if (IsPlayerEmbarking(player) || player.IsTitan()) {
			player.Signal( "OnDestroy" );
			WaitFrame();
			flag.SetAngles(< 0, 0, 0 >);
			return;
		}
		WaitFrame();
	}
}


void function OnWinnerDetermined() {
	//Chat_ServerBroadcast("WINNER DETERMINED");
	foreach (entity player in GetPlayerArray()) {
		if (player.IsTitan()) {
			// Have each player disembark to prevent crash
			entity titan = CreateAutoTitanForPlayer_ForTitanBecomesPilot(player);
			DispatchSpawn( titan );
			thread TitanBecomesPilot(player, titan);
		}
	}
}

void function OnPlayerKilled( entity victim, entity attacker, var damageInfo ) {
	if (giveOnlyOneTitan) return;	// Don't kill the titan in LF mode
	// Kill the titan if the player died and wasn't even in it
	if (PlayerHasTitan(victim)) KillPlayersTitan(victim);
	UpdateNextRespawnTime(victim, Time());	// ALlow instant respawn since we have to wait for titan to drop
}

void function OnPlayerRespawned( entity player ) {
	if (!IsValidPlayer(player)) return;

	if (editPilotLoadout) {
		TakeAllWeapons(player);

		// Give the player something to hold to know they are cloaked
		player.GiveWeapon("mp_weapon_semipistol");
		foreach ( entity weapon in player.GetMainWeapons() ) {
	    weapon.SetWeaponPrimaryAmmoCount(0);
	    weapon.SetWeaponPrimaryClipCount(0);
		}
		GivePassive(player, ePassives.PAS_STEALTH_MOVEMENT);
		GivePassive(player, ePassives.PAS_FAST_EMBARK);
		Rodeo_Disallow(player); // Disable rodeo so players will get in the fucking robot shinji
	}

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

		// Wait while player is moving or not enough vertical clearance
		while (IsValidPlayer(player)
					 && (Length(player.GetVelocity()) > 0 ||
					 		 GetVerticalClearance( (OriginToGround(player.GetOrigin())) + < 0, 0, 10 > ) < 285 )
				  ) WaitFrame();	// Now wait until player stops

					 //Chat_ServerBroadcast("DROPPING " + GetVerticalClearance(player.GetOrigin()).tostring());


		/*
		while (player.GetActiveWeapon().IsWeaponInAds()) WaitFrame();

		// Wait for player to ADS
		while ( GameRules_GetGameMode() != "speedball" && IsValidPlayer(player) && IsAlive(player) ) {
			Chat_ServerBroadcast(GetVerticalClearance( (OriginToGround(player.GetOrigin())) + < 0, 0, 10 > ).tostring());
			// Check if player is ADS
			if (player.GetActiveWeapon().IsWeaponInAds()) {
				Chat_ServerBroadcast("ADS");

				// Check for vertical clearance
				if ( GetVerticalClearance( (OriginToGround(player.GetOrigin())) + < 0, 0, 10 > ) < 280 ) {
					EmitSoundOnEntityOnlyToPlayer( player, player, "DataKnife_Hack_Spectre_Pt2" )
					while (IsValidPlayer(player) && player.GetActiveWeapon().IsWeaponInAds()) WaitFrame(); // Wait for player to leave ADS
				}
				else {
					break;
				}
			}
			WaitFrame();
		}
		*/

		//if (GameRules_GetGameMode() == "speedball") player.FreezeControlsOnServer(); // Freeze controls - sometimes NS lets players wander away

		// Call actual titan here
		Point dropPoint;
		if (IsValidPlayer(player) && IsAlive(player) && !player.IsTitan() && !IsPlayerEmbarking(player)) {
			dropPoint.origin = OriginToGround(player.GetOrigin());
			dropPoint.angles = VectorToAngles( FlattenVector(player.GetViewVector()) );
			thread CreateTitanForPlayerAndHotdrop( player, dropPoint );
		}

		// Wait for titan to drop
		while (IsValidPlayer(player) && IsAlive(player) && IsReplacementDropInProgress(player)) {
			if (PlayerHasTitan(player) && Distance( player.GetOrigin(), player.GetPetTitan().GetOrigin() ) < 200) PlayerLungesToEmbark(player, player.GetPetTitan());
			else if (!giveOnlyOneTitan && Distance( player.GetOrigin(), dropPoint.origin ) > relocateTitanDistance) KillPlayersTitan(player); // Kill the titan if the player has moved away from the drop point
			WaitFrame();
		}

		if (giveOnlyOneTitan) return;

		// Wait until player has either embarked or moved away from titan
		while (IsValidPlayer(player)
					 && IsValid(GetPlayerTitanInMap( player ))
					 && !player.IsTitan()
					 && !IsPlayerEmbarking(player)
					 && Distance( player.GetOrigin(), GetPlayerTitanInMap( player ).GetOrigin() ) < relocateTitanDistance
					 ) {
			WaitFrame();
		}
	}

	if (IsValidPlayer(player)) player.ClearInvulnerable();
}

void function KillPlayersTitan( entity player ) {
	if (!PlayerHasTitan(player)) return;
	entity titan = GetPlayerTitanInMap( player );
	if (IsValid(titan) && IsAlive(titan)) {
		titan.MakeInvisible()
		titan.Die();
	}
}



/*
// Trying to stop titanfall noise
entity titan = player.GetPetTitan();
float impactTime = GetHotDropImpactTime( titan, "at_hotdrop_drop_2knee_turbo" )
Attachment result = titan.Anim_GetAttachmentAtTime( "at_hotdrop_drop_2knee_turbo", "OFFSET", impactTime )
vector maxs = titan.GetBoundingMaxs()
vector mins = titan.GetBoundingMins()
int mask = titan.GetPhysicsSolidMask()
vector origin = ModifyOriginForDrop( dropPoint.origin, mins, maxs, result.position, mask )
StopSoundAtPosition(dropPoint.origin, "Titan_1P_Warpfall_Start")
StopSoundAtPosition(dropPoint.origin, "Titan_1P_Warpfall_CallIn")
StopSoundAtPosition(dropPoint.origin, "Titan_3P_Warpfall_Start")
StopSoundAtPosition(dropPoint.origin, "Titan_3P_Warpfall_CallIn")
StopSoundAtPosition(origin, "Titan_1P_Warpfall_WarpToLanding_fast")
StopSoundAtPosition(origin, "Titan_3P_Warpfall_WarpToLanding_fast")
StopSoundAtPosition(origin, "titan_hot_drop_turbo_begin")
StopSoundAtPosition(origin, "titan_hot_drop_turbo_begin_3P")
StopSoundOnEntity(player, "titan_hot_drop_turbo_begin")
*/
