-- Shared presentation of imported actions. Never change data while describing it.
local M={}
M.names={
  nop="Do nothing",nop1="Do nothing",special="Run a built-in game action",specialvar="Run a game action and remember its answer",
  callnative="Run a built-in game function",gotonative="Continue with a built-in game function",
  callstd="Run a common game action",gotostd="Finish with a common game action",waitstate="Wait for the game action to finish",
  loadword="Prepare a value for the next action",loadbyte="Prepare a small value",copylocal="Copy a temporary value",
  setvar="Remember a number",setorcopyvar="Remember a number or copy a saved value",addvar="Increase a saved number",subvar="Decrease a saved number",copyvar="Copy a saved number",
  compare_var_to_value="Check a saved number",compare_var_to_var="Compare two saved numbers",
  goto_if="Continue elsewhere if the check matches",call_if="Run another event if the check matches",
  setflag="Turn a saved switch ON",clearflag="Turn a saved switch OFF",checkflag="Check a saved switch",
  playse="Play a sound",waitse="Wait for the sound to finish",playfanfare="Play a celebration tune",waitfanfare="Wait for the tune to finish",
  playbgm="Play background music",savebgm="Remember the background music",fadedefaultbgm="Return to the map's music",fadenewbgm="Fade into new music",fadeoutbgm="Fade music out",fadeinbgm="Fade music in",
  additem="Give the player an item",removeitem="Take an item from the player",checkitem="Check the player's Bag",checkitemspace="Check for room in the Bag",checkitemtype="Find an item's Bag pocket",addpcitem="Put an item in the PC",checkpcitem="Check items in the PC",
  removeobject="Hide a character",addobject="Show a character",removeobjectat="Hide a character on another map",addobjectat="Show a character on another map",hideobjectat="Hide a character on another map",showobjectat="Show a character on another map",
  setobjectxy="Move a character to a position",setobjectxyperm="Remember a character's home position",copyobjectxytoperm="Keep a character's current position",turnobject="Turn a character",setobjectmovementtype="Change how a character moves",
  applymovementat="Move a character on another map",waitmovementat="Wait for a character on another map",
  trainerbattle="Battle a trainer",dotrainerbattle="Start the prepared trainer battle",gotopostbattlescript="Continue after the battle",gotobeatenscript="Continue after an already defeated trainer",
  checktrainerflag="Check whether a trainer was defeated",settrainerflag="Remember that a trainer was defeated",cleartrainerflag="Allow a trainer to battle again",
  yesnobox="Ask the player: Yes / No",multichoice="Let the player choose from a list",multichoicedefault="Show choices with one preselected",multichoicegrid="Show choices in a grid",
  showmonpic="Show a Pokémon picture",hidemonpic="Hide the Pokémon picture",givemon="Give the player a Pokémon",giveegg="Give the player a Pokémon Egg",setmonmove="Change a Pokémon's move",checkpartymove="Check whether the team knows a move",
  bufferspeciesname="Prepare a Pokémon name for dialogue",bufferleadmonspeciesname="Prepare the first Pokémon's species name",bufferpartymonnick="Prepare a team Pokémon's nickname",bufferitemname="Prepare an item name for dialogue",buffermovename="Prepare a move name for dialogue",buffernumberstring="Prepare a number for dialogue",bufferstdstring="Prepare a common phrase for dialogue",bufferstring="Prepare text for dialogue",
  pokemart="Open a shop",random="Choose a random number",addmoney="Give the player money",removemoney="Take money from the player",checkmoney="Check whether the player has enough money",showmoneybox="Show the player's money",hidemoneybox="Hide the money display",updatemoneybox="Refresh the money display",
  fadescreen="Fade the screen",fadescreenspeed="Fade the screen at a chosen speed",setflashlevel="Set how dark the area is",animateflash="Change how much of the area is lit",messageautoscroll="Show text that advances automatically",braillemessage="Show a Braille message",
  dofieldeffect="Show an effect on the map",setfieldeffectargument="Prepare a setting for a map effect",waitfieldeffect="Wait for a map effect to finish",setrespawn="Choose where the player returns after losing",checkplayergender="Check the player's gender",playmoncry="Play a Pokémon's cry",waitmoncry="Wait for the Pokémon's cry",
  setmetatile="Change a map tile",resetweather="Restore the map's weather",setweather="Choose the weather",doweather="Apply the chosen weather",setmaplayoutindex="Change the map layout",
  opendoor="Open a door",closedoor="Close a door",waitdooranim="Wait for the door",setdooropen="Leave a door open",setdoorclosed="Leave a door closed",showelevmenu="Choose an elevator floor",addelevmenuitem="Add an elevator destination",
  checkcoins="Check the player's coins",addcoins="Give the player coins",removecoins="Take coins from the player",showcoinsbox="Show the player's coins",hidecoinsbox="Hide the coin display",updatecoinsbox="Refresh the coin display",
  setwildbattle="Prepare a wild Pokémon battle",dowildbattle="Start the prepared wild battle",getpartysize="Count the Pokémon on the team",getplayerxy="Remember the player's position",gettime="Check the time",initclock="Set the clock",dotimebasedevents="Update events that depend on time",
  signmsg="Use a sign-style text box",normalmsg="Use a normal text box",textcolor="Change the text color",setworldmapflag="Mark a place as visited",incrementgamestat="Increase a game statistic",playslotmachine="Play a slot machine",
  compare_ptr_to_value="Compare a number from game memory",compare_local_to_value="Check a temporary number",compare_local_to_ptr="Compare a temporary number with game memory",compare_local_to_local="Compare two temporary numbers",compare_ptr_to_ptr="Compare two values in game memory",compare_ptr_to_local="Compare game memory with a temporary number",
  drawbox="Draw a box on screen",erasebox="Erase a box from the screen",drawboxtext="Draw text inside a box",
  setmysteryeventstatus="Set the Mystery Event result",trywondercardscript="Run the Wonder Card event",setmonmodernfatefulencounter="Mark a Pokémon as a fateful encounter",checkmonmodernfatefulencounter="Check a Pokémon's fateful encounter mark",setmonmetlocation="Set where a Pokémon was met",
  endram="Finish the temporary event",returnram="Return from the temporary event",loadhelp="Show help text",unloadhelp="Close help text",getbraillestringwidth="Measure the Braille message width",comparestat="Check a game statistic",
  bufferitemnameplural="Prepare an item name with a quantity",bufferboxname="Prepare a storage box name",bufferdecorationname="Prepare a decoration name",
  warpspinenter="Move to another map with a spinning entrance",setvaddress="Set the starting address of a relocated event",vgoto="Continue in a relocated event",vcall="Run a relocated event",vgoto_if="Continue in a relocated event if the check matches",vcall_if="Run a relocated event if the check matches",vmessage="Show text from a relocated event",vbuffermessage="Prepare a message from a relocated event",vbufferstring="Prepare text from a relocated event",
  createvobject="Show a temporary character",turnvobject="Turn a temporary character",setobjectsubpriority="Change a character's drawing order",resetobjectsubpriority="Restore a character's drawing order",setstepcallback="Choose what happens after each player step",
  callstd_if="Run a common action if the check matches",gotostd_if="Finish with a common action if the check matches",copybyte="Copy a small value in game memory",setptr="Write a value to game memory",loadbytefromptr="Read a small value from game memory",setptrbyte="Write a small value to game memory",
  choosecontestmon="Choose a Pokémon for a contest",startcontest="Start a Pokémon contest",showcontestresults="Show the contest results",contestlinktransfer="Share contest data with other players",showcontestpainting="Show a contest painting",getpokenewsactive="Check whether Pokémon news is active",
  pokemartdecoration="Open a decoration shop",pokemartdecoration2="Open a second decoration shop",setberrytree="Set up a Berry tree",adddecoration="Give a decoration",removedecoration="Remove a decoration",checkdecor="Check for a decoration",checkdecorspace="Check for room for a decoration",
}
for op,label in pairs({warp="Move to another map",warpsilent="Move to another map without a transition",warpdoor="Go through a door to another map",warphole="Fall into another map",warpteleport="Teleport to another map",setwarp="Choose the next map destination",setdynamicwarp="Remember a return destination",setdivewarp="Choose the underwater destination",setholewarp="Choose where a hole leads",setescapewarp="Choose the escape destination"}) do M.names[op]=label end
-- Keyed by pret special name: each game numbers its specials differently.
local specialText={
  HealPlayerParty="Heal the player's Pokémon",ShowPokemonStorageSystemPC="Open Pokémon storage",ShowTownMap="Show the town map",
  AnimatePcTurnOn="Animate the PC turning on",AnimatePcTurnOff="Animate the PC turning off",BedroomPC="Open the bedroom PC",PlayerPC="Open the player's PC",CreatePCMenu="Open the PC menu",
  ChangePokemonNickname="Change a Pokémon's nickname",ChangeBoxPokemonNickname="Change a stored Pokémon's nickname",ChoosePartyMon="Choose a Pokémon from the team",ChooseMonForMoveTutor="Choose a Pokémon to learn a move",
  EnterHallOfFame="Enter the Hall of Fame",EnableNationalPokedex="Unlock the National Pokédex",IsNationalPokedexEnabled="Check whether the National Pokédex is unlocked",
  Script_HasTrainerBeenFought="Check whether this trainer has been battled",PlayTrainerEncounterMusic="Play the trainer's encounter music",ShouldTryRematchBattle="Check whether a rematch should start",IsTrainerReadyForRematch="Check whether the trainer is ready for a rematch",HasEnoughMonsForDoubleBattle="Check for enough Pokémon for a double battle",
  GetBattleOutcome="Check how the battle ended",GetLeadMonFriendship="Check the first Pokémon's friendship",DaisyMassageServices="Offer Daisy's Pokémon massage",GetDaycareState="Check the Day Care",StartOldManTutorialBattle="Start the old man's catching lesson",
  StartMarowakBattle="Start the Marowak battle",StartLegendaryBattle="Start a legendary Pokémon battle",SetVermilionTrashCans="Set up the Vermilion Gym trash-can puzzle",
  CalculatePlayerPartyCount="Count the Pokémon on the team",CountPartyNonEggMons="Count team Pokémon that are not Eggs",GetPokedexCount="Count Pokédex entries",IsThereRoomInAnyBoxForMorePokemon="Check for room in Pokémon storage",GetStarterSpecies="Check which starter the player chose",DoSeagallopFerryScene="Show the ferry journey",DrawSeagallopDestinationMenu="Choose a ferry destination",
  SetUsedPkmnCenterQuestLogEvent="Record a visit to the Pokémon Center",QuestLog_StartRecordingInputsAfterDeferredEvent="Resume recording the player's actions",GetQuestLogState="Check whether the adventure recap is recording",QuestLog_CutRecording="Stop recording the adventure recap",
  BufferMonNickname="Prepare a Pokémon's nickname for dialogue",IsMonOTIDNotPlayers="Check whether a Pokémon has a different original trainer ID",BrailleCursorToggle="Show or hide the Braille reading cursor",SetUnlockedPokedexFlags="Record which Pokédex features are unlocked",
  Script_SetHelpContext="Choose the current help topic",BackupHelpContext="Remember the current help topic",RestoreHelpContext="Restore the previous help topic",SetHelpContextForMap="Choose the help topic for this map",HelpSystem_Disable="Turn off the help system",HelpSystem_Enable="Turn on the help system",
  SetUpTrainerMovement="Prepare the trainer to walk toward the player",VsSeekerResetObjectMovementAfterChargeComplete="Restore character movement after using the Vs. Seeker",VsSeekerFreezeObjectsAfterChargeComplete="Pause characters after using the Vs. Seeker",SetBattledTrainerFlag="Remember that the trainer was battled",
  ShowEasyChatScreen="Let the player build a phrase",ShowEasyChatMessage="Show the phrase the player built",StartGroudonKyogreBattle="Start the Groudon or Kyogre battle",StartRegiBattle="Start a Regi battle",StartSouthernIslandBattle="Start the Southern Island battle",
  NameRaterWasNicknameChanged="Check whether the Name Rater changed the nickname",CountPartyAliveNonEggMons_IgnoreVar0x8004Slot="Count other team Pokémon that can battle",BufferBigGuyOrBigGirlString="Prepare the player's form of address",SetHiddenItemFlag="Remember that a hidden item was found",GetSelectedMonNicknameAndSpecies="Prepare the chosen Pokémon's nickname and species",
  IsEnoughForCostInVar0x8005="Check whether the player can afford the prepared price",SubtractMoneyFromVar0x8005="Charge the player the prepared price",GetRandomSlotMachineId="Choose a random slot machine",GetPartyMonSpecies="Check a team Pokémon's species",IsSelectedMonEgg="Check whether the chosen Pokémon is an Egg",
  HasAllKantoMons="Check whether the Kanto Pokédex is complete",IsMonOTNameNotPlayers="Check whether a Pokémon has a different original trainer name",DoesPartyHaveEnigmaBerry="Check whether a team Pokémon holds an Enigma Berry",SetSeenMon="Mark a Pokémon as seen in the Pokédex",ShouldShowBoxWasFullMessage="Check whether to show the storage-box-full message",
  DoesPlayerPartyContainSpecies="Check for a species on the player's team",GetPCBoxToSendMon="Find the storage box for a received Pokémon",HasAtLeastOneBerry="Check whether the player has any Berries",GetPlayerFacingDirection="Check which way the player is facing",
  GetSelectedSeagallopDestination="Read the chosen ferry destination",GetSeagallopNumber="Check which ferry is being used",IsPlayerLeftOfVermilionSailor="Check whether the player is left of the Vermilion sailor",IsBadEggInParty="Check for a Bad Egg on the team",HasAllMons="Check whether the Pokédex is complete",IsPlayerNotInTrainerTowerLobby="Check whether the player is outside the Trainer Tower lobby",PlayerPartyContainsSpeciesWithPlayerID="Check for a species caught by this player",IsDodrioInParty="Check for Dodrio on the team",
  BufferUnionRoomPlayerName="Prepare a Union Room player's name",ShowFieldMessageStringVar4="Show the prepared map message",DrawWholeMapView="Redraw the map",RockSmashWildEncounter="Check for a wild battle after Rock Smash",EnterSafariMode="Start a Safari Zone visit",ExitSafariMode="End the Safari Zone visit",InitRoamer="Set up the roaming legendary Pokémon",
  SetIcefallCaveCrackedIceMetatiles="Set up the cracked ice in Icefall Cave",ShakeScreen="Shake the screen",SetPostgameFlags="Unlock events after becoming Champion",ForcePlayerOntoBike="Put the player on a bicycle",SampleResortGorgeousMonAndReward="Choose the requested Pokémon and reward at Resort Gorgeous",ForcePlayerToStartSurfing="Make the player start Surfing",DisableMsgBoxWalkaway="Keep the player from walking away from the message",SetDeoxysTrianglePalette="Change the Deoxys triangle's colors",UpdateLoreleiDollCollection="Update Lorelei's doll collection",CreateEnemyEventMon="Prepare the event's opposing Pokémon",
  GetElevatorFloor="Check the current elevator floor",AnimateElevator="Animate the elevator ride",SpawnCameraObject="Create a separate camera target",RemoveCameraObject="Remove the separate camera target",DrawElevatorCurrentFloorWindow="Show the current elevator floor",ListMenu="Open a scrolling choice list",ReturnToListMenu="Return to the scrolling choice list",CloseElevatorCurrentFloorWindow="Hide the elevator floor display",AnimateTeleporterHousing="Animate the teleporter housing",AnimateTeleporterCable="Animate the teleporter cable",InitElevatorFloorSelectMenuPos="Set the starting elevator-floor choice",
  GetInGameTradeSpeciesInfo="Read the Pokémon species for an in-game trade",CreateInGameTradePokemon="Prepare the Pokémon received in a trade",DoInGameTradeScene="Show the Pokémon trade",GetTradeSpecies="Check the trade's Pokémon species",
  GetDaycareMonNicknames="Prepare the Day Care Pokémon's nicknames",RejectEggFromDayCare="Decline the Day Care Egg",GiveEggFromDaycare="Give the player the Day Care Egg",SetDaycareCompatibilityString="Prepare the Day Care compatibility message",StoreSelectedPokemonInDaycare="Leave the chosen Pokémon at the Day Care",ChooseSendDaycareMon="Choose a Pokémon to leave at the Day Care",ShowDaycareLevelMenu="Show the Day Care Pokémon and their levels",GetNumLevelsGainedFromDaycare="Check levels gained at the Day Care",GetDaycareCost="Calculate the Day Care fee",TakePokemonFromDaycare="Return a Pokémon from the Day Care",GetDaycarePokemonCount="Count Pokémon staying at the Day Care",
  PutMonInRoute5Daycare="Leave a Pokémon at the Route 5 Day Care",GetCostToWithdrawRoute5DaycareMon="Calculate the Route 5 Day Care fee",IsThereMonInRoute5Daycare="Check for a Pokémon at the Route 5 Day Care",GetNumLevelsGainedForRoute5DaycareMon="Check levels gained at the Route 5 Day Care",TakePokemonFromRoute5Daycare="Return a Pokémon from the Route 5 Day Care",
  FadeScreen="Fade the screen",OpenNaming="Open the naming screen",PlayCry="Play a Pokémon's cry",
  -- src/cable_club.c uses 0x8004 for format and 0x8005 for the player's spot.
  EnterColosseumPlayerSpot="Start a multiplayer battle at the Colosseum",
  SavePlayerParty="Set the player's team aside",LoadPlayerParty="Bring back the set-aside team",ChooseHalfPartyForBattle="Choose Pokémon to enter a battle",Field_AskSaveTheGame="Ask the player to save the game",
  GetHeracrossSizeRecordInfo="Prepare the Heracross size record",CompareHeracrossSize="Compare a Heracross with the size record",GetMagikarpSizeRecordInfo="Prepare the Magikarp size record",CompareMagikarpSize="Compare a Magikarp with the size record",
  Script_IsFanClubMemberFanOfPlayer="Check whether a Fan Club member is a fan of the player",Script_GetNumFansOfPlayerInTrainerFanClub="Count the player's fans in the Fan Club",Script_BufferFanClubTrainerName="Prepare a Fan Club member's name",Script_TryLoseFansFromPlayTimeAfterLinkBattle="Update Fan Club fans after a link battle",
  Script_TryLoseFansFromPlayTime="Update Fan Club fans for time played",Script_SetPlayerGotFirstFans="Record the player's first Fan Club fans",Script_UpdateTrainerFanClubGameClear="Update the Fan Club after becoming Champion",Script_TryGainNewFanFromCounter="Check for a new Fan Club fan",
  ScriptHatchMon="Hatch an Egg",EggHatch="Show an Egg hatching",ShowBattleRecords="Show the link battle records",GetProfOaksRatingMessage="Prepare Professor Oak's Pokédex rating",
  ChooseMonForMoveRelearner="Choose a Pokémon to relearn a move",SelectMoveDeleterMove="Choose a move to forget",MoveDeleterForgetMove="Forget the chosen move",BufferMoveDeleterNicknameAndMove="Prepare the Pokémon's nickname and the move to forget",GetNumMovesSelectedMonHas="Count the chosen Pokémon's moves",TeachMoveRelearnerMove="Teach a remembered move",
  BufferEReaderTrainerGreeting="Prepare the e-Reader trainer's greeting",StartSpecialBattle="Start a special battle",ValidateEReaderTrainer="Check the e-Reader trainer data",ReducePlayerPartyToThree="Keep only three Pokémon on the team",
  HallOfFamePCBeginFade="Fade out to view the Hall of Fame",ShowDiploma="Show the diploma",BufferEReaderTrainerName="Prepare the e-Reader trainer's name",
  Script_FacePlayer="Turn the character toward the player",Script_ClearHeldMovement="Release the character's held movement",SetEReaderTrainerGfxId="Set the e-Reader trainer's appearance",LoadPlayerBag="Bring back the set-aside Bag",
  SeafoamIslandsB4F_CurrentDumpsPlayerOnLand="Check whether the Seafoam Islands current carries the player to land",CheckAddCoins="Check for room for more Game Corner coins",UpdateTrainerCardPhotoIcons="Update the Trainer Card photo",StickerManGetBragFlags="Check what the Sticker Man can praise",
  SetWalkingIntoSignVars="Let the player walk away from a sign message",SetFlavorTextFlagFromSpecialVars="Unlock a Fame Checker fact",UpdatePickStateFromSpecialVar8005="Update a person's Fame Checker entry",
  ValidateSavedWonderCard="Check the saved Wonder Card",GetMysteryGiftCardStat="Read a Wonder Card count",WonderNews_GetRewardInfo="Check the Wonder News reward",OpenMuseumFossilPic="Show the museum fossil picture",CloseMuseumFossilPic="Hide the museum fossil picture",
  ChooseMonForWirelessMinigame="Choose a Pokémon for a wireless minigame",DoSSAnneDepartureCutscene="Show the S.S. Anne leaving port",IsPokemonJumpSpeciesInParty="Check for a Pokémon that can play Pokémon Jump",CallTrainerTowerFunc="Run a Trainer Tower action",
  ShowPokemonJumpRecords="Show the Pokémon Jump records",BufferTMHMMoveName="Prepare a TM or HM move name",DisplayBerryPowderVendorMenu="Show the Berry Powder exchange menu",RemoveBerryPowderVendorMenu="Hide the Berry Powder exchange menu",
  Script_HasEnoughBerryPowder="Check for enough Berry Powder",Script_TakeBerryPowder="Take Berry Powder from the player",PrintPlayerBerryPowderAmount="Show the player's Berry Powder",DoPokemonLeagueLightingEffect="Show the Pokémon League lighting effect",
  ShowBerryCrushRankings="Show the Berry Crush rankings",CapeBrinkGetMoveToTeachLeadPokemon="Check which Cape Brink move the first Pokémon can learn",HasLearnedAllMovesFromCapeBrinkTutor="Check whether all Cape Brink moves are learned",DoCredits="Play the credits",
  ShowDodrioBerryPickingRecords="Show the Dodrio Berry Picking records",DoDeoxysTriangleInteraction="Handle touching the Deoxys triangle",LoopWingFlapSound="Repeat the wing flapping sound",
  -- pret/pokeemerald data/specials.inc names not shared with FireRed.
  SetCableClubWarp="Set the return point for the link room",DoCableClubWarp="Enter the link room",ReturnFromLinkRoom="Return from the link room",CleanupLinkRoomState="Reset the link room",ExitLinkRoom="Leave the link room",
  SetPlayerSecretBase="Make this the player's Secret Base",CheckPlayerHasSecretBase="Check whether the player has a Secret Base",EnterSecretBase="Enter the Secret Base",ClearAndLeaveSecretBase="Clear the Secret Base and leave it",MoveOutOfSecretBase="Move out of the Secret Base",
  IsCurSecretBaseOwnedByAnotherPlayer="Check whether this Secret Base belongs to another player",GetCurSecretBaseRegistrationValidity="Check whether this Secret Base can be registered",ToggleCurSecretBaseRegistry="Register or unregister this Secret Base",
  ShowSecretBaseDecorationMenu="Open the Secret Base decoration menu",ShowSecretBaseRegistryMenu="Open the registered Secret Base list",PrepSecretBaseBattleFlags="Prepare the Secret Base battle switches",GetSecretBaseOwnerAndState="Check the Secret Base owner and state",
  InitSecretBaseDecorationSprites="Set up the Secret Base decorations",SetDecoration="Place the Secret Base decorations",GetObjectEventLocalIdByFlag="Find the character controlled by a saved switch",GetSecretBaseTypeInFrontOfPlayer="Check the Secret Base spot in front of the player",
  SetSecretBaseOwnerGfxId="Set the Secret Base owner's appearance",PutAwayDecorationIteration="Put away a decoration",EnterNewlyCreatedSecretBase="Enter the newly made Secret Base",SetBattledOwnerFromResult="Remember the Secret Base battle result",DoSecretBasePCTurnOffEffect="Animate the Secret Base PC turning off",
  CopyCurSecretBaseOwnerName_StrVar1="Prepare the Secret Base owner's name",MoveOutOfSecretBaseFromOutside="Move out of the Secret Base from outside",GetSecretBaseNearbyMapName="Prepare the name of the area near the Secret Base",InitSecretBaseVars="Reset the Secret Base visit values",
  DeclinedSecretBaseBattle="Record a declined Secret Base battle",DrewSecretBaseBattle="Record a Secret Base battle draw",WonSecretBaseBattle="Record a Secret Base battle win",LostSecretBaseBattle="Record a Secret Base battle loss",
  CheckInteractedWithFriendsSandOrnament="Record examining a friend's sand ornament",CheckInteractedWithFriendsDollDecor="Record examining a friend's doll",CheckInteractedWithFriendsCushionDecor="Record examining a friend's cushion",CheckInteractedWithFriendsPosterDecor="Record examining a friend's poster",
  CheckInteractedWithFriendsFurnitureBottom="Record examining the bottom of a friend's furniture",CheckInteractedWithFriendsFurnitureMiddle="Record examining the middle of a friend's furniture",CheckInteractedWithFriendsFurnitureTop="Record examining the top of a friend's furniture",
  InteractWithShieldOrTVDecoration="Examine a shield or TV decoration",
  RecordMixingPlayerSpotTriggered="Start Record Mixing from the player's seat",TryBattleLinkup="Connect with another player for a battle",TryTradeLinkup="Connect with another player for a trade",TryRecordMixLinkup="Connect with other players for Record Mixing",
  ValidateMixingGameLanguage="Check the other player's game language for Record Mixing",CloseLink="Close the link connection",ColosseumPlayerSpotTriggered="Start a Colosseum battle from the player's seat",PlayerEnteredTradeSeat="Sit the player in the trade seat",
  Script_StartWiredTrade="Start a cable link trade",CableClubSaveGame="Save the game before linking",TryBerryBlenderLinkup="Connect with other players for the Berry Blender",GetLinkPartnerNames="Prepare the link partners' names",
  SpawnLinkPartnerObjectEvent="Show the link partners in the room",Script_ShowLinkTrainerCard="Show a link partner's Trainer Card",IsWirelessAdapterConnected="Check for a wireless adapter",TryBecomeLinkLeader="Host a wireless group",TryJoinLinkGroup="Join a wireless group",
  RunUnionRoom="Enter the Union Room",ShowWirelessCommunicationScreen="Show the wireless communication screen",InitUnionRoom="Set up the Union Room",Script_ResetUnionRoomTrade="Reset the Union Room trade",GetWirelessCommType="Check the wireless connection type",
  ObjectEventInteractionGetBerryTreeData="Read the Berry tree's state",ObjectEventInteractionGetBerryName="Prepare the Berry tree's Berry name",ObjectEventInteractionGetBerryCountString="Prepare the Berry tree's harvest count",Bag_ChooseBerry="Choose a Berry from the Bag",
  ObjectEventInteractionPlantBerryTree="Plant the chosen Berry",ObjectEventInteractionPickBerryTree="Pick Berries from the tree",ObjectEventInteractionRemoveBerryTree="Remove the Berry tree",ObjectEventInteractionWaterBerryTree="Water the Berry tree",
  DoWateringBerryTreeAnim="Animate watering the Berry tree",PlayerHasBerries="Check whether the player has any Berries",IsEnigmaBerryValid="Check whether the Enigma Berry is valid",IncrementDailyPlantedBerries="Count a Berry planted today",IncrementDailyPickedBerries="Count Berries picked today",
  GetTrainerBattleMode="Check the trainer battle type",ShowTrainerIntroSpeech="Show the trainer's before-battle dialogue",ShowTrainerCantBattleSpeech="Show the trainer's dialogue when the player cannot battle",GetTrainerFlag="Check whether the trainer was defeated",
  DoTrainerApproach="Make the trainer walk to the player",BattleSetup_StartRematchBattle="Start the trainer rematch battle",SetTrainerFacingDirection="Turn the trainer toward the player",ShouldTryGetTrainerScript="Check whether a second trainer is waiting",
  TryPrepareSecondApproachingTrainer="Prepare a second trainer to approach",PlayerFaceTrainerAfterBattle="Turn the player toward the trainer after battle",DoSpecialTrainerBattle="Start a special trainer battle",
  BattleSetup_StartLegendaryBattle="Start a legendary Pokémon battle",BattleSetup_StartLatiBattle="Start the Latias or Latios battle",StartWallyTutorialBattle="Start Wally's catching lesson",LoadWallyZigzagoon="Prepare Wally's Zigzagoon",
  TurnOffTVScreen="Turn off the TV screen",TurnOnTVScreen="Turn on the TV screen",DoTVShow="Show the current TV program",DoPokeNews="Show the Pokémon News",GetRandomActiveShowIdx="Choose a random TV program on the air",GetSelectedTVShow="Check which TV program is chosen",
  InterviewBefore="Prepare a TV interview",InterviewAfter="Record the TV interview",IsLeadMonNicknamedOrNotEnglish="Check whether the first Pokémon has a nickname or a foreign name",SetContestCategoryStringVarForInterview="Prepare the contest category for the interview",
  GetNextActiveShowIfMassOutbreak="Check for a mass outbreak TV program",IsTVShowAlreadyInQueue="Check whether the TV program is already planned",CheckForPlayersHouseNews="Check for TV news to see at home",GetMomOrDadStringForTVMessage="Prepare \"Mom\" or \"Dad\" for a TV message",
  ResetTVShowState="Reset the TV program state",TryPutNameRaterShowOnTheAir="Try to put the Name Rater show on TV",TryPutTreasureInvestigatorsOnAir="Try to put the treasure investigators show on TV",TryPutLotteryWinnerReportOnAir="Try to put the lottery winner report on TV",
  TryPutTrainerFanClubOnAir="Try to put the Fan Club show on TV",ShouldHideFanClubInterviewer="Check whether to hide the Fan Club interviewer",PutFanClubSpecialOnTheAir="Put the Fan Club special on TV",
  GabbyAndTyGetBattleNum="Check how often Gabby and Ty were battled",GabbyAndTyAfterInterview="Record the Gabby and Ty interview",GabbyAndTyBeforeInterview="Prepare the Gabby and Ty interview",DoTVShowInSearchOfTrainers="Show Gabby and Ty's TV program",
  IsGabbyAndTyShowOnTheAir="Check whether Gabby and Ty's program is on TV",GabbyAndTyGetLastQuote="Prepare the player's last quote for Gabby and Ty",GabbyAndTyGetLastBattleTrivia="Check the last battle's highlight for Gabby and Ty",GetGabbyAndTyLocalIds="Find Gabby and Ty's characters",
  GetContestWinnerId="Check which contestant won",GetContestPlayerId="Check the player's contest entry number",GetNpcContestantLocalId="Find a contestant's character",BufferContestWinnerTrainerName="Prepare the contest winner's name",BufferContestWinnerMonName="Prepare the contest winner's Pokémon name",
  BufferContestTrainerAndMonNames="Prepare a contestant's name and Pokémon name",GetContestMonConditionRanking="Check how the Pokémon's condition ranks",SetContestTrainerGfxIds="Set the contestants' appearances",TryEnterContestMon="Try to enter the Pokémon in the contest",
  GetContestantNamesAtRank="Prepare the names at a contest rank",SetLinkContestPlayerGfx="Set the link contestants' appearances",GetContestMonCondition="Check the Pokémon's contest condition",HasMonWonThisContestBefore="Check whether the Pokémon won this contest before",
  GiveMonContestRibbon="Give the Pokémon a contest ribbon",IsContestDebugActive="Check whether contest debugging is on",GiveMonArtistRibbon="Give the Pokémon the Artist Ribbon",TryContestGModeLinkup="Connect with other players for a contest",TryContestEModeLinkup="Connect with Emerald players for a contest",
  ShouldReadyContestArtist="Check whether the contest artist should appear",SaveMuseumContestPainting="Save the contest painting for the museum",DoesContestCategoryHaveMuseumPainting="Check whether the museum has this category's painting",CountPlayerMuseumPaintings="Count the player's museum paintings",
  ShowContestPainting="Show the contest painting",DoContestHallWarp="Move to the contest hall",ShowContestEntryMonPic="Show the contest entry's picture",HideContestEntryMonPic="Hide the contest entry's picture",GetContestMultiplayerId="Check the player's link contest number",
  GenerateContestRand="Choose a random contest value",LinkContestWaitForConnection="Wait for the link contest connection",LinkContestTryShowWirelessIndicator="Show the wireless signal for a link contest",LinkContestTryHideWirelessIndicator="Hide the wireless signal for a link contest",
  IsWirelessContest="Check whether the contest is wireless",IsContestWithRSPlayer="Check for a Ruby or Sapphire player in the contest",ClearLinkContestFlags="Clear the link contest settings",LoadLinkContestPlayerPalettes="Load the link contestants' colors",
  CheckLeadMonCool="Check the first Pokémon's Cool condition",CheckLeadMonBeauty="Check the first Pokémon's Beauty condition",CheckLeadMonCute="Check the first Pokémon's Cute condition",CheckLeadMonSmart="Check the first Pokémon's Smart condition",CheckLeadMonTough="Check the first Pokémon's Tough condition",
  SaveGame="Save the game",ShowEasyChatProfile="Show the player's profile phrase",Script_GetCurrentMauvilleMan="Check which Mauville visitor is present",HasBardSongBeenChanged="Check whether the Bard's song was changed",SaveBardSongLyrics="Save the Bard's new song lyrics",
  HasHipsterTaughtWord="Check whether the Hipster taught a word",SetHipsterTaughtWord="Remember that the Hipster taught a word",HipsterTryTeachWord="Have the Hipster teach a word",PlayBardSong="Play the Bard's song",SetMauvilleOldManObjEventGfx="Set the Mauville visitor's appearance",
  GenerateGiddyLine="Prepare Giddy's next line",GiddyShouldTellAnotherTale="Check whether Giddy tells another story",StorytellerGetFreeStorySlot="Check for room for another Storyteller story",Script_StorytellerDisplayStory="Tell the chosen Storyteller story",
  StorytellerStoryListMenu="Open the Storyteller's story list",StorytellerUpdateStat="Record a new Storyteller story",Script_StorytellerInitializeRandomStat="Choose a feat for the Storyteller to ask about",HasStorytellerAlreadyRecorded="Check whether the Storyteller already has this story",
  TraderMenuGetDecoration="Choose a decoration to trade with the Trader",GetTraderTradedFlag="Check whether the Trader already traded",DoesPlayerHaveNoDecorations="Check whether the player has no decorations",IsDecorationCategoryFull="Check whether a decoration category is full",
  TraderShowDecorationMenu="Show the Trader's decorations",TraderDoDecorationTrade="Trade decorations with the Trader",
  GetSeedotSizeRecordInfo="Prepare the Seedot size record",CompareSeedotSize="Compare a Seedot with the size record",GetLotadSizeRecordInfo="Prepare the Lotad size record",CompareLotadSize="Compare a Lotad with the size record",
  BufferTrendyPhraseString="Prepare Dewford's trendy phrase",IsTrendyPhraseBoring="Check whether the trendy phrase has become boring",BufferDeepLinkPhrase="Prepare a random hobby or lifestyle word",GetDewfordHallPaintingNameIndex="Check which painting hangs in Dewford Hall",
  SwapRegisteredBike="Swap the registered bicycle",GetPlayerAvatarBike="Check which bicycle the player is riding",GetRecordedCyclingRoadResults="Show the Cycling Road record",Special_BeginCyclingRoadChallenge="Start the Cycling Road challenge",
  FinishCyclingRoadChallenge="Finish the Cycling Road challenge",UpdateCyclingRoadState="Update the Cycling Road challenge",
  MauvilleGymSetDefaultBarriers="Reset the Mauville Gym barriers",MauvilleGymPressSwitch="Press a Mauville Gym switch",MauvilleGymDeactivatePuzzle="Turn off the Mauville Gym puzzle",PetalburgGymSlideOpenRoomDoors="Slide open the Petalburg Gym doors",
  PetalburgGymUnlockRoomDoors="Unlock the Petalburg Gym doors",SetSootopolisGymCrackedIceMetatiles="Set up the cracked ice in Sootopolis Gym",RotatingGate_InitPuzzle="Set up the rotating gate puzzle",RotatingGate_InitPuzzleAndGraphics="Set up and draw the rotating gate puzzle",
  StorePlayerCoordsInVars="Remember the player's position",GetPlayerTrainerIdOnesDigit="Check the last digit of the player's trainer ID",GetPlayerBigGuyGirlString="Prepare the player's form of address",GetRivalSonDaughterString="Prepare \"son\" or \"daughter\" for the rival's parent",
  CableCarWarp="Move to the other cable car station",CableCar="Ride the cable car",Overworld_PlaySpecialMapMusic="Play the map's special music",StopMapMusic="Stop the map music",Script_FadeOutMapMusic="Fade out the map music",
  StartWallClock="Set the wall clock",Special_ViewWallClock="Look at the wall clock",ChooseStarter="Choose a starter Pokémon",InitBirchState="Reset Professor Birch's location",IsStarterInParty="Check whether the starter Pokémon is on the team",
  GetFirstFreePokeblockSlot="Find room in the Pokéblock Case",DoBerryBlending="Use the Berry Blender",ShowBerryBlenderRecordWindow="Show the Berry Blender records",GetPokeblockFeederInFront="Check for a Pokéblock feeder in front of the player",
  OpenPokeblockCaseOnFeeder="Choose a Pokéblock for the feeder",GetPokeblockNameByMonNature="Prepare the Pokéblock flavor a Pokémon likes",PlayRoulette="Play roulette",GetSlotMachineId="Check which slot machine is being used",
  IsFanClubMemberFanOfPlayer="Check whether a Fan Club member is a fan of the player",GetNumFansOfPlayerInTrainerFanClub="Count the player's fans in the Fan Club",BufferFanClubTrainerName="Prepare a Fan Club member's name",
  TryLoseFansFromPlayTimeAfterLinkBattle="Update Fan Club fans after a link battle",TryLoseFansFromPlayTime="Update Fan Club fans for time played",SetPlayerGotFirstFans="Record the player's first Fan Club fans",UpdateTrainerFanClubGameClear="Update the Fan Club after becoming Champion",
  GetDaycareCostAndPrepareString="Calculate the Day Care fee and prepare it for dialogue",CheckDaycareMonReceivedMail="Check whether a Day Care Pokémon received mail",ShowLinkBattleRecords="Show the link battle records",
  TryFieldPoisonWhiteOut="Handle the team fainting from poison",SetCB2WhiteOut="Return to the last Pokémon Center after losing",SetSSTidalFlag="Mark the S.S. Tidal as sailing",ResetSSTidalFlag="Mark the S.S. Tidal as docked",
  ScriptMenu_CreateLilycoveSSTidalMultichoice="Choose a S.S. Tidal destination",GetLilycoveSSTidalSelection="Read the chosen S.S. Tidal destination",IsMirageIslandPresent="Check whether Mirage Island is visible",UpdateShoalTideFlag="Update the Shoal Cave tide",
  ScriptGetPokedexInfo="Count Pokémon seen and caught",ShowPokedexRatingMessage="Show the Professor's Pokédex rating",HasAllHoennMons="Check whether the Hoenn Pokédex is complete",
  DoPCTurnOnEffect="Animate the PC turning on",DoPCTurnOffEffect="Animate the PC turning off",ScriptMenu_CreatePCMultichoice="Open the PC menu",AccessHallOfFamePC="View the Hall of Fame on the PC",Special_ShowDiploma="Show the diploma",
  SetDeptStoreFloor="Remember the department store floor",ShowDeptStoreElevatorFloorSelect="Choose a department store floor",GetDeptStoreDefaultFloorChoice="Check the default department store floor choice",CloseDeptStoreElevatorWindow="Hide the department store floor display",
  MoveElevator="Move the elevator",DoLotteryCornerComputerEffect="Animate the Lottery Corner computer",EndLotteryCornerComputerEffect="Stop the Lottery Corner computer animation",RetrieveLotteryNumber="Read today's lottery number",
  PickLotteryCornerTicket="Draw the Lottery Corner prize",BufferLottoTicketNumber="Prepare the lottery ticket number",MoveDeleterChooseMoveToForget="Choose a move to forget",GetLeadMonFriendshipScore="Check the first Pokémon's friendship",
  CopyEReaderTrainerGreeting="Prepare the e-Reader trainer's greeting",ReducePlayerPartyToSelectedMons="Keep only the chosen Pokémon on the team",FieldShowRegionMap="Show the town map",GetWeekCount="Check how many weeks have passed",
  ResetTrickHouseNuggetFlag="Reset the Trick House prize",SetTrickHouseNuggetFlag="Remember that the Trick House prize was taken",LookThroughPorthole="Look through the porthole",DoSoftReset="Restart the game",GameClear="Record the game as beaten and enter the Hall of Fame",
  ShowGlassWorkshopMenu="Open the glass workshop menu",CheckRelicanthWailord="Check for Relicanth and Wailord on the team",ShouldDoBrailleRegirockEffectOld="Check the old Regirock Braille puzzle (unused)",ShouldDoBrailleRegicePuzzle="Check whether the Regice Braille puzzle is active",
  DoOrbEffect="Show the orb's glow",FadeOutOrbEffect="Fade out the orb's glow",WaitWeather="Wait for the weather to change",StartDroughtWeatherBlend="Start the drought weather",SetRoute119Weather="Set Route 119's weather",SetRoute123Weather="Set Route 123's weather",
  CreateAbnormalWeatherEvent="Start a strange weather event",GetAbnormalWeatherMapNameAndType="Prepare where the strange weather is",Unused_SetWeatherSunny="Make the weather sunny (unused)",
  FoundAbandonedShipRoom1Key="Check whether the Abandoned Ship Room 1 key was found",FoundAbandonedShipRoom2Key="Check whether the Abandoned Ship Room 2 key was found",FoundAbandonedShipRoom4Key="Check whether the Abandoned Ship Room 4 key was found",
  FoundAbandonedShipRoom6Key="Check whether the Abandoned Ship Room 6 key was found",FoundBlackGlasses="Remember that the BlackGlasses were found",
  LeadMonHasEffortRibbon="Check whether the first Pokémon has the Effort Ribbon",GiveLeadMonEffortRibbon="Give the first Pokémon the Effort Ribbon",Special_AreLeadMonEVsMaxedOut="Check whether the first Pokémon's training is maxed out",
  TryUpdateRusturfTunnelState="Update Rusturf Tunnel after a rock is smashed",IsGrassTypeInParty="Check for a Grass-type Pokémon on the team",IsPokerusInParty="Check for Pokérus on the team",ScriptCheckFreePokemonStorageSpace="Check for room in Pokémon storage",
  ScriptGetPartyMonSpecies="Check a team Pokémon's species",MonOTNameNotPlayer="Check whether a Pokémon has a different original trainer name",IsLastMonThatKnowsSurf="Check whether this is the last team Pokémon that knows Surf",CountPartyAliveNonEggMons="Count team Pokémon that can battle",
  DoSealedChamberShakingEffect_Long="Shake the Sealed Chamber for a long time",DoSealedChamberShakingEffect_Short="Shake the Sealed Chamber briefly",ShakeCamera="Shake the camera",OffsetCameraForBattle="Shift the camera for a battle",
  DoDiveWarp="Dive or surface to the connected map",DoFallWarp="Fall to the map below",SetChampionSaveWarp="Set the save point after becoming Champion",ResetHealLocationFromDewford="Move the return point from Dewford to Petalburg",ShowMapNamePopup="Show the map name",
  SetPacifidlogTMReceivedDay="Remember the day the Pacifidlog TM was given",GetDaysUntilPacifidlogTMAvailable="Check the days until the Pacifidlog TM can be given again",
  SetLilycoveLadyGfx="Set the Lilycove lady's appearance",Script_GetLilycoveLadyId="Check which Lilycove lady is present",GetFavorLadyState="Check the Favor Lady's state",BufferFavorLadyRequest="Prepare the Favor Lady's request",
  HasAnotherPlayerGivenFavorLadyItem="Check whether another player gave the Favor Lady an item",BufferFavorLadyItemName="Prepare the item given to the Favor Lady",BufferFavorLadyPlayerName="Prepare the name of the player who helped the Favor Lady",
  DidFavorLadyLikeItem="Check whether the Favor Lady liked the item",Script_FavorLadyOpenBagMenu="Choose an item for the Favor Lady",Script_DoesFavorLadyLikeItem="Check whether the Favor Lady likes the chosen item",
  IsFavorLadyThresholdMet="Check whether the Favor Lady is ready to give a prize",FavorLadyGetPrize="Prepare the Favor Lady's prize",SetFavorLadyState_Complete="Finish the Favor Lady's request",
  GetQuizLadyState="Check the Quiz Lady's state",GetQuizAuthor="Check who wrote the quiz",IsQuizLadyWaitingForChallenger="Check whether the Quiz Lady is waiting for a challenger",QuizLadyShowQuizQuestion="Show the quiz question",QuizLadyGetPlayerAnswer="Let the player answer the quiz",
  IsQuizAnswerCorrect="Check whether the quiz answer is correct",BufferQuizPrizeItem="Prepare the quiz prize",SetQuizLadyState_Complete="Finish the quiz",BufferQuizAuthorNameAndCheckIfLady="Prepare the quiz author's name",SetQuizLadyState_GivePrize="Mark the quiz prize as ready",
  ClearQuizLadyPlayerAnswer="Clear the player's quiz answer",Script_QuizLadyOpenBagMenu="Choose a prize for the player's quiz",ClearQuizLadyQuestionAndAnswer="Clear the quiz question and answer",QuizLadySetCustomQuestion="Let the player write a quiz question",
  QuizLadyTakePrizeForCustomQuiz="Take the prize for the player's quiz",QuizLadyRecordCustomQuizData="Save the player's quiz",QuizLadySetWaitingForChallenger="Wait for someone to take the player's quiz",BufferQuizCorrectAnswer="Prepare the quiz's correct answer",
  BufferQuizPrizeName="Prepare the quiz prize name",QuizLadyPickNewQuestion="Choose a new quiz question",
  ShouldContestLadyShowGoOnAir="Check whether the Contest Lady's show goes on TV",HasPlayerGivenContestLadyPokeblock="Check whether the player gave the Contest Lady a Pokéblock",Script_BufferContestLadyCategoryAndMonName="Prepare the Contest Lady's category and Pokémon name",
  OpenPokeblockCaseForContestLady="Choose a Pokéblock for the Contest Lady",SetContestLadyGivenPokeblock="Remember the Pokéblock given to the Contest Lady",GetContestLadyMonSpecies="Check the Contest Lady's Pokémon",GetContestLadyCategory="Check the Contest Lady's favorite category",
  PutLilycoveContestLadyShowOnTheAir="Put the Contest Lady's show on TV",
  CallFrontierUtilFunc="Run a Battle Frontier action",CallBattleTowerFunc="Run a Battle Tower action",CallBattleDomeFunction="Run a Battle Dome action",CallBattlePalaceFunction="Run a Battle Palace action",CallBattleArenaFunction="Run a Battle Arena action",
  CallBattleFactoryFunction="Run a Battle Factory action",CallBattlePikeFunction="Run a Battle Pike action",CallBattlePyramidFunction="Run a Battle Pyramid action",CallVerdanturfTentFunction="Run a Verdanturf Battle Tent action",
  CallFallarborTentFunction="Run a Fallarbor Battle Tent action",CallSlateportTentFunction="Run a Slateport Battle Tent action",CallApprenticeFunction="Run an Apprentice action",CallTrainerHillFunction="Run a Trainer Hill action",
  ChoosePartyForBattleFrontier="Choose Pokémon for a Battle Frontier challenge",GetBattleTowerSinglesStreak="Check the Battle Tower single battle streak",TryInitBattleTowerAwardManObjectEvent="Set up the Battle Tower award man",TryHideBattleTowerReporter="Hide the Battle Tower reporter if needed",
  CloseBattlePikeCurtain="Close the Battle Pike curtain",BufferBattleTowerElevatorFloors="Prepare the Battle Tower elevator floors",SetBattleTowerLinkPlayerGfx="Set the Battle Tower partner's appearance",SaveForBattleTowerLink="Save before a Battle Tower link",
  LinkRetireStatusWithBattleTowerPartner="Share retirement with the Battle Tower partner",BattleTowerReconnectLink="Reconnect with the Battle Tower partner",TrySetBattleTowerLinkType="Set the Battle Tower link type",
  TryStoreHeldItemsInPyramidBag="Put held items in the Battle Pyramid Bag",ChooseItemsToTossFromPyramidBag="Choose items to throw away from the Battle Pyramid Bag",DoBattlePyramidMonsHaveHeldItem="Check whether Battle Pyramid Pokémon hold items",
  BattlePyramidChooseMonHeldItems="Choose held items for the Battle Pyramid",GetBattlePyramidHint="Prepare the Battle Pyramid hint",DoDomeConfetti="Show the Battle Dome confetti",
  ShowBattlePointsWindow="Show the player's Battle Points",UpdateBattlePointsWindow="Refresh the Battle Points display",CloseBattlePointsWindow="Hide the Battle Points display",GiveFrontierBattlePoints="Give the player Battle Points",
  TakeFrontierBattlePoints="Take Battle Points from the player",GetFrontierBattlePoints="Check the player's Battle Points",ShowFrontierExchangeCornerItemIconWindow="Show the exchange corner item picture",CloseFrontierExchangeCornerItemIconWindow="Hide the exchange corner item picture",
  ShowRankingHallRecordsWindow="Show the Ranking Hall records",ScrollRankingHallRecordsWindow="Scroll the Ranking Hall records",ShowFrontierManiacMessage="Show the Frontier Maniac's tip",ShowNatureGirlMessage="Show the Nature Girl's message",
  ShowFrontierGamblerLookingMessage="Show the Frontier Gambler's challenge",ShowFrontierGamblerGoMessage="Show the Frontier Gambler's reminder",BufferVarsForIVRater="Prepare the Pokémon's potential for the judge",
  BufferBattleFrontierTutorMoveName="Prepare the Battle Frontier tutor's move name",CloseBattleFrontierTutorWindow="Hide the Battle Frontier tutor's move list",GetBattleFrontierTutorMoveIndex="Check which move the Battle Frontier tutor teaches",
  PlayerNotAtTrainerHillEntrance="Check whether the player is away from the Trainer Hill entrance",ShowTrainerHillRecords="Show the Trainer Hill records",RemoveRecordsWindow="Hide the records",
  ShowScrollableMultichoice="Open a scrolling choice list",ScrollableMultichoice_TryReturnToList="Return to the scrolling choice list",ScrollableMultichoice_RedrawPersistentMenu="Redraw the scrolling choice list",ScrollableMultichoice_ClosePersistentMenu="Close the scrolling choice list",
  HasEnoughBerryPowder="Check for enough Berry Powder",TakeBerryPowder="Take Berry Powder from the player",
  DoMirageTowerCeilingCrumble="Crumble the Mirage Tower ceiling",SetMirageTowerVisibility="Show or hide the Mirage Tower",StartPlayerDescendMirageTower="Lower the player down the Mirage Tower",StartMirageTowerDisintegration="Make the Mirage Tower crumble",
  StartMirageTowerShake="Shake the Mirage Tower",StartMirageTowerFossilFallAndSink="Drop the fossil into the sand",
  Script_DoRayquazaScene="Show the Rayquaza scene",OpenPokenavForTutorial="Open the PokéNav tutorial",ScriptMenu_CreateStartMenuForPokenavTutorial="Show the menu for the PokéNav tutorial",CountPlayerTrainerStars="Count the player's Trainer Card stars",
  SetMatchCallRegisteredFlag="Register the trainer for Match Call",IsTrainerRegistered="Check whether the trainer is registered for Match Call",GetMartEmployeeObjectEventId="Find the shop clerk's character",
  DoDeoxysRockInteraction="Handle touching the Deoxys rock",SetDeoxysRockPalette="Change the Deoxys rock's colors",SetMewAboveGrass="Show Mew above the grass",DestroyMewEmergingGrassSprite="Remove the grass Mew appeared from",
  ShouldDistributeEonTicket="Check whether to give out the Eon Ticket",LoopWingFlapSE="Repeat the wing flapping sound",
  TryBufferWaldaPhrase="Prepare Walda's phrase",DoWaldaNamingScreen="Let the player choose Walda's phrase",TryGetWallpaperWithWaldaPhrase="Check whether Walda's phrase unlocks a wallpaper",
}
local specialHelpText={
  EnterColosseumPlayerSpot="Wait for the other players, then start a Colosseum battle. The current game skips this action; settings are saved but multiplayer battles are not supported yet.",
}
-- Gen3Clock: added to the game by the mod, not the ROM.
local modSpecials={[0xE100]="Read the clock (day, date and time)"}
local modSpecialHelp={
  [0xE100]="Reads the real time clock. Dialogue after it can say {STR_VAR_1} (the day, e.g. Tuesday), {STR_VAR_2} (the date, e.g. 29 September) and {STR_VAR_3} (the time, e.g. 10:42 PM). It also saves numbers to check: 0x8004 the day (0 Sunday to 6 Saturday), 0x8005 the hour (0-23), 0x8006 the minute, 0x8007 the part of the day (0 morning, 1 day, 2 night).",
}
local function activeGame() return require("src.core.game3.profile").resolveId() end
-- The pret name of a special number in the game being edited.
function M.specialName(id) return require("src.core.game3.scripting.stdscripts").specialName(activeGame(),id) end
M.specials=setmetatable({},{__index=function(_,id) return modSpecials[id] or specialText[M.specialName(id)] end})
M.specialHelp=setmetatable({},{__index=function(_,id) return modSpecialHelp[id] or specialHelpText[M.specialName(id)] end})
local function specialChoices()
  local out={}
  for id,name in pairs(require("src.core.game3.scripting.stdscripts").specialIds(activeGame())) do out[id]=specialText[name] end
  for id,label in pairs(modSpecials) do out[id]=label end
  return out
end
local common={[0]="Give an item with a message",[1]="Pick up an item",[2]="Show character dialogue",[3]="Show a sign message",[4]="Show a normal message",[5]="Ask a Yes / No question",[6]="Show a message that closes automatically",[7]="Give a decoration",[8]="Show the item being put away",[9]="Show the item received"}
M.options={common=common,
  linkBattleFormat={[1]="Single battle",[2]="Double battle",[5]="Multi battle (four players)"},
  linkBattleSpot={[0]="Player spot 1",[1]="Player spot 2",[2]="Player spot 3",[3]="Player spot 4"},
  direction={[1]="Down",[2]="Up",[3]="Left",[4]="Right"},
  fade={[0]="Reveal from black",[1]="Fade to black",[2]="Reveal from white",[3]="Fade to white"},
  condition={[0]="Is less than",[1]="Equals",[2]="Is greater than",[3]="Is at most",[4]="Is at least",[5]="Does not equal"},
  yesno={[0]="No",[1]="Yes"},
  idleMovement={[0]="Stay still",[1]="Look around",[2]="Walk around",[7]="Face up",[8]="Face down",[9]="Face left",[10]="Face right"},
  pokedex={[0]="Kanto Pokédex",[1]="National Pokédex"},
  daycareSlot={[0]="First Day Care Pokémon",[1]="Second Day Care Pokémon"},
  elevatorFloor={[0]="Basement 4",[1]="Basement 3",[2]="Basement 2",[3]="Basement 1",[4]="Floor 1",[5]="Floor 2",[6]="Floor 3",[7]="Floor 4",[8]="Floor 5",[9]="Floor 6",[10]="Floor 7",[11]="Floor 8",[12]="Floor 9",[13]="Floor 10",[14]="Floor 11",[15]="Rooftop"},
  weather={[0]="Clear",[1]="Rain",[2]="Falling ash",[3]="Fog",[4]="Sandstorm",[5]="Bright sun"},
  teamSlot={[0]="First Pokémon",[1]="Second Pokémon",[2]="Third Pokémon",[3]="Fourth Pokémon",[4]="Fifth Pokémon",[5]="Sixth Pokémon"},
  moveSlot={[0]="First move",[1]="Second move",[2]="Third move",[3]="Fourth move"},
}
function M.label(step)
  if type(step)=="string" then return M.names[step] end
  if step.op=="special" or step.op=="specialvar" then
    local id=step.op=="special" and (step.id or step[1]) or step[2]
    local name=M.specials[id] or "Built-in game action "..tostring(id).." (purpose not yet described)"
    return name..(step.op=="specialvar" and " and remember the answer" or "")
  end
  if step.op=="callstd" or step.op=="gotostd" then return common[step.std or step[1]] or "Common game action "..tostring(step.std or step[1]).." (purpose not yet described)" end
  return M.names[step.op]
end
-- Named aliases mirror the importer. Editing updates both representations only
-- when present, so imported commands and editor-created commands both round trip.
local schemas={}
local function schema(ops,fields) for op in ops:gmatch("%S+") do schemas[op]=fields end end
schema("setvar addvar subvar compare_var_to_value",{{"var","Saved number to check or change"},{"value","Number"}})
schema("setorcopyvar copyvar compare_var_to_var",{{false,"Saved number to check or change"},{false,"Number or saved-number ID"}})
schema("setflag clearflag checkflag",{{"flag","Saved switch number"}})
schema("delay",{{"frames","Wait time (60 = one second)"}})
schema("special",{{"id","Built-in game action","special"}})
schema("specialvar",{{false,"Save the answer in this saved number"},{false,"Built-in game action","special"}})
schema("callstd gotostd",{{"std","Common game action","common"}})
schema("loadword loadbyte",{{"dest","Temporary slot for the next action"},{"value","Value to prepare"}})
schema("additem removeitem checkitem checkitemspace addpcitem checkpcitem",{{"item","Item","item"},{"quantity","How many"}})
schema("warp warpsilent warpdoor warpteleport warpspinenter setwarp setdynamicwarp setdivewarp setholewarp setescapewarp",{{false,"Destination map group"},{false,"Destination map number"},{false,"Destination exit (255 = use position below)"},{false,"Destination column"},{false,"Destination row"}})
schema("setweather",{{false,"Weather","weather"}})
schema("setmetatile",{{false,"Map column"},{false,"Map row"},{false,"Replacement tile number"},{false,"Block walking","yesno"}})
schema("yesnobox",{{false,"Menu column"},{false,"Menu row"}})
schema("multichoice",{{false,"Menu column"},{false,"Menu row"},{false,"List of choices"},{false,"Prevent cancel","yesno"}})
schema("multichoicedefault",{{false,"Menu column"},{false,"Menu row"},{false,"List of choices"},{false,"Starting choice (0 = first)"},{false,"Prevent cancel","yesno"}})
schema("multichoicegrid",{{false,"Menu column"},{false,"Menu row"},{false,"List of choices"},{false,"Number of columns"},{false,"Prevent cancel","yesno"}})
schema("addmoney removemoney checkmoney",{{"amount","Amount of money"},{false,"Use multiplayer money","yesno"}})
schema("addcoins removecoins",{{"amount","Number of coins"}})
schema("removeobject addobject copyobjectxytoperm",{{"localId","Character","character"}})
schema("waitmovement",{{"localId","Wait for","movingCharacter"}})
schema("playse playfanfare playbgm savebgm fadenewbgm",{{"song","Sound or music","audio"},{false,"Music playback setting"}})
schema("fadescreen fadescreenspeed",{{false,"Screen transition","fade"},{false,"Fade speed"}})
schema("setobjectxy setobjectxyperm",{{"localId","Character","character"},{false,"Map column"},{false,"Map row"}})
schema("turnobject",{{"localId","Character","character"},{"direction","Face toward","direction"}})
schema("goto call",{{"target","Event to run","event"}})
schema("goto_if call_if",{{"cond","Continue when the previous check","condition"},{"target","Event to run","event"}})
schema("opendoor closedoor setdooropen setdoorclosed",{{false,"Map column"},{false,"Map row"}})
schema("giveegg",{{false,"Pokémon inside the Egg","species"}})
schema("setwildbattle",{{"species","Wild Pokémon","species"},{"level","Level"},{"item","Held item","item"}})
schema("givemon",{{"species","Pokémon to give","species"},{"level","Level"},{false,"Held item","item"},{false,"Reserved game value"},{false,"Reserved game value"},{false,"Reserved game value"}})
schema("showmonpic",{{false,"Pokémon picture","species"},{false,"Screen column"},{false,"Screen row"}})
schema("setmonmove",{{false,"Pokémon on the team","teamSlot"},{false,"Move to replace","moveSlot"},{false,"New move","move"}})
schema("checkpartymove",{{false,"Move to look for","move"}})
schema("bufferspeciesname",{{"dest","Text slot"},{"src","Pokémon name","species"}})
schema("buffermovename",{{"dest","Text slot"},{"src","Move name","move"}})
schema("bufferitemname",{{"dest","Text slot"},{"src","Item name","item"}})
schema("bufferpartymonnick",{{"dest","Text slot"},{"src","Pokémon on the team","teamSlot"}})
schema("buffernumberstring",{{"dest","Text slot"},{"src","Number to show"}})
schema("checkitemtype",{{"item","Item","item"}})
schema("checktrainerflag settrainerflag cleartrainerflag",{{false,"Trainer","trainer"}})
schema("getplayerxy",{{false,"Save the player's column in"},{false,"Save the player's row in"}})
schema("random",{{false,"Choose from 0 up to this number minus 1"}})
schema("fadeoutbgm fadeinbgm",{{false,"Fade speed"}})
schema("warphole",{{false,"Destination map group"},{false,"Destination map number"}})
schema("setflashlevel animateflash",{{false,"Darkness level"}})
schema("playmoncry",{{false,"Pokémon","species"},{false,"Cry effect"}})
schema("showmoneybox",{{false,"Screen column"},{false,"Screen row"},{false,"Use multiplayer money","yesno"}})
schema("showcoinsbox hidecoinsbox updatecoinsbox hidemoneybox",{{false,"Screen column"},{false,"Screen row"}})
schema("updatemoneybox",{{false,"Screen column"},{false,"Screen row"},{false,"Reserved game value"}})
require("Gen3ActionFields")(schema)
local extraFields={introText={"Before-battle dialogue","dialogue"},defeatText={"Trainer's defeat dialogue","dialogue"},victoryText={"Trainer's victory dialogue","dialogue"},notEnoughText={"Dialogue when the player cannot battle","dialogue"},eventScript={"Event after the battle","event"},localId={"Character","character"},flags={"Battle flags"}}
M.schemas=schemas
function M.fields(step)
  local out,used={}, {op=true,opcode=true,opaque=true}
  for i,d in ipairs(schemas[step.op] or {}) do
    local alias=d[1];local key=alias and step[alias]~=nil and alias or i
    if step[key]~=nil and not used[i] then
      local destination=d[2]=="Destination map group" and step[i+1]~=nil
      out[#out+1]={key=key,index=i,alias=alias,label=destination and "Destination map" or d[2],choices=destination and "destination" or d[3],second=destination and i+1 or nil}
      used[i]=true;if alias then used[alias]=true end;if destination then used[i+1]=true end
    end
  end
  local keys={};for key in pairs(step) do if not used[key] then keys[#keys+1]=key end end
  table.sort(keys,function(a,b) if type(a)==type(b) then return a<b end;return type(a)=="number" end)
  for _,key in ipairs(keys) do
    local d=extraFields[key]
    out[#out+1]={key=key,label=d and d[1] or (type(key)=="number" and "Game setting "..key.." (meaning not yet described)" or tostring(key):gsub("(%l)(%u)","%1 %2"):gsub("_"," ")),choices=d and d[2]}
  end
  return out
end
local limits={}
function M.validNumber(step,field,n)
  local ok,ops=pcall(require,"src.core.game3.scripting.opcodes")
  local set=ok and ops.active()
  local game=set and set.game or ""
  if not limits[game] then
    limits[game]={}
    if set then for _,op in pairs(set.TABLE) do limits[game][op.name]=op.args end end
  end
  local args=limits[game][step.op];local arg=args and args[field.index or field.key]
  local max=arg and ({byte=255,half=65535,word=4294967295,ptr=4294967295})[arg.kind] or 65535
  return n and n==math.floor(n) and n>=0 and n<=max
end
function M.set(step,field,value)
  step[field.key]=value
  if field.index and step[field.index]~=nil then step[field.index]=value end
  if field.alias and step[field.alias]~=nil then step[field.alias]=value end
end
function M.choiceData(S,kind,current)
  local labels={}
  for id,label in pairs(kind=="special" and specialChoices() or M.options[kind] or {}) do labels[tostring(id)]=label end
  local bucket=({species="pokemon",move="moves",trainer="trainers"})[kind]
  if bucket then
    for _,records in ipairs({(S.data or {})[bucket] or {},(S.project or {})[bucket] or {}}) do
      for id,record in pairs(records) do
        if type(record)=="table" and type(record.index)=="number" then
          local name=record.name or record.trainerName or tostring(id):gsub("^MOVE_",""):gsub("^SPECIES_",""):gsub("_"," ")
          labels[tostring(record.index)]=tostring(name).." ("..record.index..")"
        end
      end
    end
  end
  if kind=="event" then
    local catalog=require("Gen3").catalog(S.data,"map_scripts")
    for _,records in ipairs({catalog,((S.project or {}).gen3 or {}).map_scripts or {}}) do
      for id in pairs(records) do labels[tostring(id)]=tostring(id) end
    end
  end
  if kind=="audio" then
    for id,record in pairs(require("Gen3Resources").audio(S.data).songs or {}) do
      labels[tostring(id)]=type(record)=="table" and tostring(record.name or record.label or record.symbol or "Sound "..id):gsub("_"," ") or "Sound "..id
    end
    labels["0"]="Silence"
  end
  if kind=="character" or kind=="movingCharacter" then
    labels["255"]="The player";labels["32783"]="The character being spoken to"
    if kind=="movingCharacter" then labels["0"]="All moving characters" end
    local mapId=(S._eventWindowTarget or {}).mapId or S.g3EventMap or S.mapId
    local map=((S.project or {}).maps or {})[mapId] or ((S.data or {}).maps or {})[mapId]
    for i,object in ipairs(map and map.objects or {}) do
      local id=object.localId or i
      labels[tostring(id)]=(object.editorName or "Character "..id).." at "..tostring(object.x)..", "..tostring(object.y)
    end
  end
  if not labels[tostring(current)] then labels[tostring(current)]="Keep current value ("..tostring(current)..")" end
  local ids={};for id in pairs(labels) do ids[#ids+1]=id end
  table.sort(ids,function(a,b)
    if tonumber(a) and tonumber(b) then return tonumber(a)<tonumber(b) end
    return a<b
  end)
  return ids,labels
end
function M.help(step)
  local op=step.op
  if op=="pokemartdecoration" or op=="pokemartdecoration2" then return "Decoration shops are not supported by the current game. These settings are saved, but the shop will not open." end
  if op=="setfieldeffectargument" then return "The current game does not use this effect setting. You can save it, but changing it will not change the effect yet." end
  if op=="special" or op=="specialvar" then
    local id=op=="special" and (step.id or step[1]) or step[2]
    return M.specialHelp[id] or "This is a built-in game action. Some actions use values prepared by earlier steps."
  end
  if op=="setflag" or op=="clearflag" or op=="checkflag" then return "A saved switch remembers yes or no. Use the same switch number wherever you check that event." end
  if op=="setvar" or op=="addvar" or op=="subvar" or op=="compare_var_to_value" then return "A saved number can track a quest stage or a count. Its number identifies which value to use." end
  if op=="setorcopyvar" then return "Numbers below 16384 are used directly. Higher numbers refer to a stored game value to copy." end
  if op=="goto_if" or op=="call_if" then return "This uses the result of the previous check. Choose when it should run the other event." end
  if op=="setwildbattle" then return "Choose the opponent. The Start the prepared wild battle action begins the fight." end
  if op=="givemon" or op=="giveegg" then return "Choose what the player receives. Leave reserved game values unchanged." end
  if op=="setweather" then return "Choose the weather. Apply the chosen weather makes the change visible." end
  if op=="setmetatile" then return "Replace the tile at this map position and choose whether characters can walk on it." end
  if op=="random" then return "For example, 4 chooses 0, 1, 2, or 3. A later check can use the answer." end
  return "Choose the settings for this action. Hover over a shortened label to read it in full."
end
function M.draw(S,key,step,x,y,w,changed)
  local K=require("Kit");local s=K.scale;local color=require("Theme").PAL.text
  local help=M.help(step)
  K.text("small",K.ellipsize("small",help,w),x,y,color);K.offerTooltip(x,y,w,24*s,help);y=y+30*s
  local fields=M.fields(step)
  if #fields==0 then K.text("small","This action always does the same thing. You can remove it or replace it with another action.",x,y,color);return true,y+30*s end
  for _,field in ipairs(fields) do
    local old=step[field.key]
    K.text("small",K.ellipsize("small",field.label,w),x,y,color);K.offerTooltip(x,y,w,24*s,field.label);y=y+25*s
    local function pick(value) if value~=old then M.set(step,field,value);changed() end end
    if field.choices=="destination" then
      require("Gen3ActionContent").drawDestination(S,old,step[field.second],x,y,w,function(group,number)
        if group~=old or number~=step[field.second] then M.set(step,field,group);step[field.second]=number;changed() end
      end)
    elseif field.choices=="dialogue" then
      y=require("Gen3ActionContent").drawDialogue(S,key.."/"..tostring(field.key),old,x,y,w,pick)
    elseif field.choices=="shop" then
      y=require("Gen3ActionContent").drawShop(S,key,old,x,y,w,pick)
    elseif field.choices=="item" then
      local _,id=require("Gen3EventStory").itemName(S,old)
      require("ItemPicker").field(S,{x=x,y=y,w=w,h=29*s,current=id or "",emptyLabel="Item or saved value "..tostring(old),title="CHOOSE ITEM",onPick=function(itemId)
        local index=require("ItemPicker").indexForId(S,itemId);if index then pick(index) end
      end})
    elseif field.choices then
      local ids,labels=M.choiceData(S,field.choices,old)
      require("ChoicePicker").field(S,{x=x,y=y,w=w,h=29*s,current=tostring(old),ids=ids,labels=labels,title=field.label,onPick=function(value) pick(tonumber(value) or value) end})
    elseif type(old)=="number" or type(old)=="string" then
      local value=K.textfield(key.."/setting/"..tostring(field.key),x,y,w,29*s,tostring(old),"")
      if type(old)=="number" then
        local n=tonumber(value);if M.validNumber(step,field,n) then pick(n) end
      else pick(value) end
    elseif type(old)=="boolean" then
      local value,edited=K.checkbox(x,y,w,29*s,old,"Enabled");if edited then pick(value) end
    elseif type(old)=="table" then
      local _,bottom=M.draw(S,key.."/list/"..tostring(field.key),old,x+12*s,y,math.max(80*s,w-12*s),changed)
      y=bottom
    else
      K.text("small","This setting has no editable value.",x,y,color)
    end
    y=y+42*s
  end
  return true,y
end
return M
