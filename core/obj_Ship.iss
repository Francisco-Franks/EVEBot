/*
	Ship class
	
	Main object for interacting with the ship and its functions
	
	-- CyberTech
	
*/

objectdef obj_Ship
{
	variable int MODE_WARPING = 3
	
	variable int FrameCounter
	variable int Calculated_MaxLockedTargets
	variable float BaselineUsedCargo
	variable bool CargoIsOpen
	variable index:module ModuleList
	variable index:module ModuleList_MiningLaser
	variable index:module ModuleList_Weapon
	variable index:module ModuleList_ActiveResists
	variable index:module ModuleList_Regen_Shield
	variable index:module ModuleList_Repair_Armor
	variable index:module ModuleList_Repair_Hull
	variable index:module ModuleList_AB_MWD
	variable index:module ModuleList_Passive
	variable index:module ModuleList_Salvagers
	variable index:module ModuleList_TractorBeams
	variable bool Repairing_Armor = FALSE
	variable bool Repairing_Hull = FALSE

	variable iterator ModulesIterator

	variable obj_Drones Drones

	method Initialize()
	{
		This:StopShip[]
		This:UpdateModuleList[]

		Event[OnFrame]:AttachAtom[This:Pulse]
		This:CalculateMaxLockedTargets
		UI:UpdateConsole["obj_Ship: Initialized"]
	}
	
	method Shutdown()
	{
		Event[OnFrame]:DetachAtom[This:Pulse]
	}

	method Pulse()
	{
		if ${EVEBot.Paused}
		{
			return
		}
		
		FrameCounter:Inc
	    variable int IntervalInSeconds = 8
	    
		if ${FrameCounter} >= ${Math.Calc[${Display.FPS} * ${IntervalInSeconds}]}
		{
    		if (${Me.InStation(exists)} && !${Me.InStation})
    		{		    
    			This:ValidateModuleTargets
    				
    			;Ship Armor Repair
    			if ${This.Total_Armor_Reps} > 0
    			{
    				if ${Me.Ship.ArmorPct} < 100
    				{
    					This:ActivateRepairing_Armor
    				}
    					
    				if ${This.Repairing_Armor}
    				{
    					if ${Me.Ship.ArmorPct} == 100
    					{
    						This:DeactivateRepairing_Armor
    						This.Repairing_Armor:Set[FALSE]
    					}
    				}
    			}
    			
    			;Shield Boosters
    			;UI:UpdateConsole["Debug: Obj_Ship: Possible Hostiles: ${Social.PossibleHostiles}"]
    			;UI:UpdateConsole["Debug: Obj_Ship: Shield Booster Activation: ${Config.Combat.ShieldBAct}"]
    			/* TODO: CyberTech - This should be an option, not forced. */
    			if ${Social.PossibleHostiles} || \
    				${Me.Ship.ShieldPct} < 100 || \
    				${Config.Combat.AlwaysShieldBoost}
    			{
    				This:Activate_Shield_Booster[]
    			}
    			else
    			{
    				This:Deactivate_Shield_Booster[]
    			}
    			
    			FrameCounter:Set[0]
    		}
    		else
    		{
    		    FrameCounter:Set[0]
    		}
		}		
	}
	
	member:float CargoMinimumFreeSpace()
	{
		if !${Me.Ship(exists)}
		{
			return
		}

		return ${Math.Calc[${Me.Ship.CargoCapacity}*0.02]}
	}
	
	member:float CargoFreeSpace()
	{
		if !${Me.Ship(exists)}
		{
			return 0
		}

		if ${Me.Ship.UsedCargoCapacity} < 0
		{
			return ${Me.Ship.CargoCapacity}
		}
		return ${Math.Calc[${Me.Ship.CargoCapacity}-${Me.Ship.UsedCargoCapacity}]}
	}

	member:bool CargoFull()
	{
		if !${Me.Ship(exists)}
		{
			return FALSE
		}

		if ${This.CargoFreeSpace} <= ${This.CargoMinimumFreeSpace}
		{
			return TRUE
		}
		return FALSE
	}
	
	member:bool CargoHalfFull()
	{
		if !${Me.Ship(exists)}
		{
			return FALSE
		}

		if ${This.CargoFreeSpace} <= ${Math.Calc[${Me.Ship.CargoCapacity}*0.50]}
		{
			return TRUE
		}
		return FALSE
	}

	method UpdateModuleList()
	{
		if ${Me.InStation}
		{
			; GetModules cannot be used in station as of 07/15/2007
			UI:UpdateConsole["DEBUG: obj_Ship:UpdateModuleList called while in station"]
			return
		}
			
		This.ModuleList:Clear
		This.ModuleList_MiningLaser:Clear
		This.ModuleList_Weapon:Clear
		This.ModuleList_ActiveResists:Clear
		This.ModuleList_Regen_Shield:Clear
		This.ModuleList_Repair_Armor:Clear
		This.ModuleList_AB_MWD:Clear
		This.ModuleList_Passive:Clear
		This.ModuleList_Repair_Armor:Clear
		This.ModuleList_Repair_Hull:Clear
		This.ModuleList_Salvagers:Clear
		This.ModuleList_TractorBeams:Clear

		Me.Ship:DoGetModules[This.ModuleList]
		
		if !${This.ModuleList.Used} && ${Me.Ship.HighSlots} > 0
		{
			UI:UpdateConsole["ERROR: obj_Ship:UpdateModuleList - No modules found. Pausing - If this ship has slots, you must have at least one module equipped, of any type."]
			EVEBot:Pause
			return
		}
	
		variable iterator Module

		UI:UpdateConsole["Module Inventory:"]
		This.ModuleList:GetIterator[Module]
		if ${Module:First(exists)}
		do
		{
			variable int GroupID
			GroupID:Set[${Module.Value.ToItem.GroupID}]
			variable int TypeID
			TypeID:Set[${Module.Value.ToItem.TypeID}]

			if !${Module.Value.IsActivatable}
			{
				This.ModuleList_Passive:Insert[${Module.Value}]
				continue
			}

			;echo "DEBUG: Slot: ${Module.Value.ToItem.Slot}  ${Module.Value.ToItem.Name}"
			;echo " DEBUG: Group: ${Module.Value.ToItem.Group}  ${GroupID}"
			;echo " DEBUG: Type: ${Module.Value.ToItem.Type}  ${TypeID}"
			
			if ${Module.Value.MiningAmount(exists)}
			{
				This.ModuleList_MiningLaser:Insert[${Module.Value}]
				continue
			}
		   	
			; TODO - Populate these arrays
			;This.ModuleList_Weapon
			;This.ModuleList_ActiveResists
			;This.ModuleList_AB_MWD
			switch ${GroupID}
			{
				case GROUPID_FREQUENCY_MINING_LASER
					break
				case GROUPID_SHIELD_BOOSTER
					This.ModuleList_Regen_Shield:Insert[${Module.Value}]
					continue
				case GROUPID_AFTERBURNER
					This.ModuleList_AB_MWD:Insert[${Module.Value}]
					continue
				case 62
					This.ModuleList_Repair_Armor:Insert[${Module.Value}]
					continue
				case 538
					/* data miners */
					; DEBUG: Group: Data Miners  538
					; DEBUG: Type: Salvager I  25861
					if ${TypeID} == 25861
				   	{	/* Salvager I */
						This.ModuleList_Salvagers:Insert[${Module.Value}]
				   	}
					continue
				case 650
					/* tractor beams */
					; DEBUG: Group: Tractor Beam  650
					; DEBUG: Type: Small Tractor Beam I  24348
					This.ModuleList_TractorBeams:Insert[${Module.Value}]
					continue
				case NONE
					This.ModuleList_Repair_Hull:Insert[${Module.Value}]
				  continue
				default
					continue
			}

		} 
		while ${Module:Next(exists)}

		UI:UpdateConsole["Passive Modules:"]
		This.ModuleList_Passive:GetIterator[Module]
		if ${Module:First(exists)}
		do
		{
			UI:UpdateConsole["    Slot: ${Module.Value.ToItem.Slot}  ${Module.Value.ToItem.Name}"]
		}
		while ${Module:Next(exists)}

		UI:UpdateConsole["Mining Modules:"]
		This.ModuleList_MiningLaser:GetIterator[Module]
		if ${Module:First(exists)}
		do
		{
			UI:UpdateConsole["    Slot: ${Module.Value.ToItem.Slot}  ${Module.Value.ToItem.Name}"]
		}
		while ${Module:Next(exists)}
		
		UI:UpdateConsole["Armor Repair Modules:"]
		This.ModuleList_Repair_Armor:GetIterator[Module]
		if ${Module:First(exists)}
		do
		{
			UI:UpdateConsole["    Slot: ${Module.Value.ToItem.Slot}  ${Module.Value.ToItem.Name}"]
		}
		while ${Module:Next(exists)}
		
		UI:UpdateConsole["Shield Regen Modules:"]
		This.ModuleList_Regen_Shield:GetIterator[Module]
		if ${Module:First(exists)}
		do
		{
			UI:UpdateConsole["    Slot: ${Module.Value.ToItem.Slot}  ${Module.Value.ToItem.Name}"]
		}
		while ${Module:Next(exists)}

		UI:UpdateConsole["AfterBurner Modules:"]
		This.ModuleList_AB_MWD:GetIterator[Module]
		if ${Module:First(exists)}
		do
		{
			UI:UpdateConsole["    Slot: ${Module.Value.ToItem.Slot}  ${Module.Value.ToItem.Name}"]
		}
		while ${Module:Next(exists)}

		if ${This.ModuleList_AB_MWD.Used} > 1
		{
			UI:UpdateConsole["Warning: More than 1 Afterburner or MWD was detected, I will only use the first one."]
		}

		UI:UpdateConsole["Salvaging Modules:"]
		This.ModuleList_Salvagers:GetIterator[Module]
		if ${Module:First(exists)}
		do
		{
			UI:UpdateConsole["    Slot: ${Module.Value.ToItem.Slot}  ${Module.Value.ToItem.Name}"]
		}
		while ${Module:Next(exists)}

		UI:UpdateConsole["Tractor Beam Modules:"]
		This.ModuleList_TractorBeams:GetIterator[Module]
		if ${Module:First(exists)}
		do
		{
			UI:UpdateConsole["    Slot: ${Module.Value.ToItem.Slot}  ${Module.Value.ToItem.Name}"]
		}
		while ${Module:Next(exists)}
	}
	
	method UpdateBaselineUsedCargo()
	{
		; Store the used cargo space as the cargo hold exists NOW, with whatever is leftover in it.
		This.BaselineUsedCargo:Set[${Me.Ship.UsedCargoCapacity.Ceil}]
	}
		
	member:int MaxLockedTargets()
	{
		This:CalculateMaxLockedTargets[]
		return ${This.Calculated_MaxLockedTargets}
	}
	
	; "Safe" max locked targets is defined as max locked targets - 1
	; for a buffer of targets so that hostiles may be targeted.
	; Always return at least 1
	
	member:int SafeMaxLockedTargets()
	{
		variable int result
		result:Set[${This.Calculated_MaxLockedTargets}]
		if ${result} > 3
		{
			result:Dec
		}
		return ${result}
	}

	member:int TotalMiningLasers()
	{	
		return ${This.ModuleList_MiningLaser.Used}
	}
	
	member:int TotalActivatedMiningLasers()
	{
		if !${Me.Ship(exists)}
		{
			return 0
		}

		variable int count
		variable iterator Module
		
		This.ModuleList_MiningLaser:GetIterator[Module]
		if ${Module:First(exists)}
		do
		{
			if ${Module.Value.IsActive} || \
				${Module.Value.IsGoingOnline} || \
				${Module.Value.IsDeactivating} || \
				${Module.Value.IsChangingAmmo} || \
				${Module.Value.IsReloadingAmmo}
			{
				count:Inc
			}
		}
		while ${Module:Next(exists)}

		return ${count}		
	}

	; Note: This doesn't return ALL the mining amounts, just one.
	; It should perhaps be changed to return the largest, or the smallest, or an average.
	member:float MiningAmountPerLaser()
	{
		if !${Me.Ship(exists)}
		{
			return 0
		}

		variable iterator Module

		This.ModuleList_MiningLaser:GetIterator[Module]
		if ${Module:First(exists)}
		{
			if ${Module.Value.SpecialtyCrystalMiningAmount(exists)}
			{
				return ${Module.Value.SpecialtyCrystalMiningAmount}
			}
			else
			{
				return ${Module.Value.MiningAmount}
			}
		}
		return 0
	}

	; Note: This doesn't return ALL the mining amounts, just one.
	; Returns the laser mining range minus 10%
	member:int OptimalMiningRange()
	{
		if !${Me.Ship(exists)}
		{
			return 0
		}

		variable iterator Module

		This.ModuleList_MiningLaser:GetIterator[Module]
		if ${Module:First(exists)}
		{
			return ${Math.Calc[${Module.Value.OptimalRange}*0.90]}
		}

		return 0
	}

	; Returns the loaded crystal in a mining laser, given the slot name ("HiSlot0"...)
	member:string LoadedMiningLaserCrystal(string SlotName)
	{
		if !${Me.Ship(exists)}
		{
			return "NOCHARGE"
		}

		
		if ${Me.Ship.Module[${SlotName}].Charge(exists)}
		{
			return ${Me.Ship.Module[${SlotName}].Charge.Name.Token[1, " "]}
		}
		return "NOCHARGE"
		
		variable iterator Module

		This.ModuleList_MiningLaser:GetIteratorModule]
		if ${Module:First(exists)}
		do
		{
			if !${Module.Value.SpecialtyCrystalMiningAmount(exists)}
			{
				continue
			}
			if ${Module.Value.ToItem.Slot.Equal[${SlotName}]} && \
				${Module.Value.Charge(exists)}
			{
				;UI:UpdateConsole["DEBUG: obj_Ship:LoadedMiningLaserCrystal Returning ${Module.Value.Charge.Name.Token[1, " "]}]
				return ${Module.Value.Charge.Name.Token[1, " "]}
			}
		}
		while ${Module:Next(exists)}

		return "NOCHARGE"
	}
	
	; Returns TRUE if we've got a laser mining this entity already
	member:bool IsMiningAsteroidID(int EntityID)
	{
		if !${Me.Ship(exists)}
		{
			return
		}

		variable iterator Module

		This.ModuleList_MiningLaser:GetIterator[Module]
		if ${Module:First(exists)}
		do
		{
			if ${Module.Value.LastTarget(exists)} && \ 
				${Module.Value.LastTarget.ID} == ${EntityID} && \
				( ${Module.Value.IsActive} || ${Module.Value.IsGoingOnline} )
			{
				return TRUE
			}
		}
		while ${Module:Next(exists)}
		
		return FALSE
	}
	
	method UnlockAllTargets()
	{
		variable index:entity LockedTargets
		variable iterator Target

		Me:DoGetTargets[LockedTargets]
		LockedTargets:GetIterator[Target]

		if ${Target:First(exists)}
		{
			UI:ConsoleUpdate["Unlocking all targets"]
		}
		
		do
		{
			Target.Value:UnlockTarget
		}
		while ${Target:Next(exists)}
	}

	method CalculateMaxLockedTargets()
	{
		if !${Me.Ship(exists)}
		{
			return
		}

		if ${Me.MaxLockedTargets(exists)} && ${Me.MaxLockedTargets} < ${Me.Ship.MaxLockedTargets}
		{
			Calculated_MaxLockedTargets:Set[${Me.MaxLockedTargets}]
		}
		else
		{
			Calculated_MaxLockedTargets:Set[${Me.Ship.MaxLockedTargets}]
		}		
	}

	function ChangeMiningLaserCrystal(string OreType, string SlotName)
	{
		; We might need to change loaded crystal
		variable string LoadedAmmo
	
		LoadedAmmo:Set[${This.LoadedMiningLaserCrystal[${SlotName}]}]
		if !${OreType.Find[${LoadedAmmo}](exists)}
		{
			UI:UpdateConsole["Current crystal in ${SlotName} is ${LoadedAmmo}, looking for ${OreType}"]
			variable index:item CrystalList
			variable iterator CrystalIterator
			
			Me.Ship.Module[${SlotName}]:DoGetAvailableAmmo[CrystalList]
			
			CrystalList:GetIterator[CrystalIterator]
			if ${CrystalIterator:First(exists)}
			do
			{
				variable string CrystalType
				CrystalType:Set[${CrystalIterator.Value.Name.Token[1, " "]}]
				
				;echo "DEBUG: ChangeMiningLaserCrystal Testing ${OreType} contains ${CrystalType}"
				if ${OreType.Find[${CrystalType}](exists)}
				{
					UI:UpdateConsole["Switching Crystal in ${SlotName} from ${LoadedAmmo} to ${CrystalIterator.Value.Name}"]
					Me.Ship.Module[${SlotName}]:ChangeAmmo[${CrystalIterator.Value.ID},1]
					; This takes 2 seconds ingame, let's give it 50% more
					wait 30
					return
				}
			}
			while ${CrystalIterator:Next(exists)}
			UI:UpdateConsole["Warning: No crystal found for ore type ${OreType}, efficiency reduced"]
		}
	}
	
	; Validates that all targets of activated modules still exist
	; TODO - Add mid and low targetable modules, and high hostile modules, as well as just mining.
	method ValidateModuleTargets()
	{
		if !${Me.Ship(exists)}
		{
			return
		}
		
		variable iterator Module

		This.ModuleList_MiningLaser:GetIterator[Module]
		if ${Module:First(exists)}
		do
		{
			if ${Module.Value.IsActive} && \
				!${Module.Value.IsDeactivating} && \
				( !${Module.Value.LastTarget(exists)} || !${Entity[id,${Module.Value.LastTarget.ID}](exists)} )
			{
				UI:UpdateConsole["${Module.Value.ToItem.Slot}:${Module.Value.ToItem.Name} has no target: Deactivating"]
				Module.Value:Click
			}
		}
		while ${Module:Next(exists)}
	}


/*
CycleMiningLaser: HiSlot1 Activate: FALSE
Error: Math sequence not available
Dumping script stack
--------------------
-->C:/Program Files/InnerSpace/Scripts/evebot/core/obj_Ship.iss:516 Atom000000B1() if !${Activate} &&(!${Me.Ship.Module[${Slot}].IsActive} ||${Me.Ship.Module[${Slot}].IsGoingOnline}
||${Me.Ship.Module[${Slot}].IsDeactivating} ||${Me.Ship.Module[${Slot}].IsChangingAmmo} ||${Me.Ship.Module[${Slot}].IsReloadingAmmo}
C:/Program Files/InnerSpace/Scripts/evebot/core/obj_Ship.iss:584 ActivateFreeMiningLaser() wait 10
C:/Program Files/InnerSpace/Scripts/evebot/core/obj_Miner.iss:190 Mine() call Ship.ActivateFreeMiningLaser
C:/Program Files/InnerSpace/Scripts/evebot/core/obj_Miner.iss:59 ProcessState() call Miner.Mine
C:/Program Files/InnerSpace/Scripts/evebot/evebot.iss:90 main() call ${BotType}.ProcessState
	*/
	
	method CycleMiningLaser(string Activate, string Slot)
	{
		echo CycleMiningLaser: ${Slot} Activate: ${Activate}
		if ${Activate.Equal[ON]} && \
			( ${Me.Ship.Module[${Slot}].IsActive} || \
			  ${Me.Ship.Module[${Slot}].IsGoingOnline} || \
			  ${Me.Ship.Module[${Slot}].IsDeactivating} || \
			  ${Me.Ship.Module[${Slot}].IsChangingAmmo} || \
			  ${Me.Ship.Module[${Slot}].IsReloadingAmmo} \
			)
		{
			echo "obj_Ship:CycleMiningLaser: Tried to Activate the module, but it's already active or changing state."
			return
		}
				
		if ${Activate.Equal[OFF]} && \
			(!${Me.Ship.Module[${Slot}].IsActive} || \
			  ${Me.Ship.Module[${Slot}].IsGoingOnline} || \
			  ${Me.Ship.Module[${Slot}].IsDeactivating} || \
			  ${Me.Ship.Module[${Slot}].IsChangingAmmo} || \
			  ${Me.Ship.Module[${Slot}].IsReloadingAmmo} \
			)
		{
			echo "obj_Ship:CycleMiningLaser: Tried to Deactivate the module, but it's already active or changing state."
			return
		}

		if ${Activate.Equal[ON]} && \
			(	!${Me.Ship.Module[${Slot}].LastTarget(exists)} || \
				!${Entity[id,${Me.Ship.Module[${Slot}].LastTarget.ID}](exists)} \
			)
		{
			echo "obj_Ship:CycleMiningLaser: Target doesn't exist"
			return
		}

		Me.Ship.Module[${Slot}]:Click
		if ${Activate.Equal[ON]}
		{
			; Delay from 18 to 45 seconds before deactivating
			TimedCommand ${Math.Rand[65]:Inc[30]} Script[EVEBot].ExecuteAtom[Ship:CycleMiningLaser, OFF, ${Slot}]
			echo "next: off"
			return
		}
		else
		{
			; Delay for the time it takes the laser to deactivate and be ready for reactivation
			TimedCommand 20 Script[EVEBot].ExecuteAtom[Ship:CycleMiningLaser, ON, "${Slot}"]
			echo "next: on"
			return
		}
	}

	method DeactivateAllMiningLasers()
	{
		if !${Me.Ship(exists)}
		{
			return
		}
		
		variable iterator Module

		This.ModuleList_MiningLaser:GetIterator[Module]
		if ${Module:First(exists)}
		{
			if ${Module.Value.IsActive} && \
				!${Module.Value.IsDeactivating}
			{
				UI:UpdateConsole["Deactivating all mining lasers..."]
			}
		}
		do
		{
			if ${Module.Value.IsActive} && \
				!${Module.Value.IsDeactivating}
			{
				Module.Value:Click
			}
		}
		while ${Module:Next(exists)}
	}
	function ActivateFreeMiningLaser()
	{
		if !${Me.Ship(exists)}
		{
			return
		}

		if ${Me.ActiveTarget.CategoryID} != ${Asteroids.AsteroidCategoryID}
		{
			UI:UpdateConsole["Error: Mining Lasers may only be used on Asteroids"]
			return
		}

		variable iterator Module
		
		This.ModuleList_MiningLaser:GetIterator[Module]
		if ${Module:First(exists)}
		do
		{
			if !${Module.Value.IsActive} && \
				!${Module.Value.IsGoingOnline} && \
				!${Module.Value.IsDeactivating} && \
				!${Module.Value.IsChangingAmmo} &&\
				!${Module.Value.IsReloadingAmmo}
			{
				variable string Slot
				Slot:Set[${Module.Value.ToItem.Slot}]
				if ${Module.Value.SpecialtyCrystalMiningAmount(exists)}
				{
					variable string OreType
					OreType:Set[${Me.ActiveTarget.Name.Token[2,"("]}]
					OreType:Set[${OreType.Token[1,")"]}]
					;OreType:Set[${OreType.Replace["(",]}]
					;OreType:Set[${OreType.Replace[")",]}]
					call This.ChangeMiningLaserCrystal "${OreType}" ${Slot}
				}

				UI:UpdateConsole["Activating: ${Module.Value.ToItem.Slot}: ${Module.Value.ToItem.Name}"]
				Module.Value:Click
				wait 25
				;TimedCommand ${Math.Rand[35]:Inc[18]} Script[EVEBot].ExecuteAtom[Ship:CycleMiningLaser, OFF, ${Slot}]
				return
			}
			wait 10
		}
		while ${Module:Next(exists)}
	}

	method StopShip()
	{
		EVE:Execute[CmdStopShip]
	}
	
	; Approaches EntityID to within 5% of Distance, then stops ship.  Momentum will handle the rest.
	function Approach(int EntityID, int64 Distance)
	{
		if ${Entity[${EntityID}](exists)}
		{
			variable float64 OriginalDistance = ${Entity[${EntityID}].Distance}
			If ${OriginalDistance} < ${Distance}
			{
				return
			}
			
			UI:UpdateConsole["Approaching: ${Entity[${EntityID}].Name} - ${Math.Calc[(${Entity[${EntityID}].Distance} - ${Distance}) / ${Me.Ship.MaxVelocity}].Ceil} Seconds away"]
			This:Activate_AfterBurner[]
			do
			{
				Entity[${EntityID}]:Approach
				wait 50

				if ${Entity[${EntityID}](exists)} && \
					${OriginalDistance} < ${Entity[${EntityID}].Distance}
				{
					UI:UpdateConsole["DEBUG: obj_Ship:Approach: ${Entity[${EntityID}].Name} is getting further away!  Is it moving? Are we stuck, or colliding?"]
				}
			
				if ${Entity[${EntityID}](exists)} && \
					${OriginalDistance} == ${Entity[${EntityID}].Distance}
				{
					UI:UpdateConsole["DEBUG: obj_Ship:Approach: We may be stuck or colliding"]
					EVE:Execute[CmdStopShip]
					return
				}
			}
			while ${Entity[${EntityID}].Distance} > ${Math.Calc[${Distance} * 1.05]}
			EVE:Execute[CmdStopShip]
			This:Deactivate_AfterBurner[]
		}
	}			

	member IsCargoOpen()
	{
		if ${EVEWindow[MyShipCargo](exists)}
		{
			if ${EVEWindow[MyShipCargo].Caption(exists)}
			{
				return TRUE
			}
			else
			{
				UI:UpdateConsole["\${EVEWindow[MyShipCargo](exists)} == ${EVEWindow[MyShipCargo](exists)}"]
				UI:UpdateConsole["\${EVEWindow[MyShipCargo].Caption(exists)} == ${EVEWindow[MyShipCargo].Caption(exists)}"]
			}
		}
		
		;; ELSE
		return FALSE
	}
	
	function OpenCargo()
	{
		if !${This.IsCargoOpen}
		{
			UI:UpdateConsole["Opening Ship Cargohold"]
			EVE:Execute[OpenCargoHoldOfActiveShip]
			wait WAIT_CARGO_WINDOW
			while !${This.IsCargoOpen}
			{
				wait 0.5
			}
			wait 10
		}
	}

	function CloseCargo()
	{
		if ${This.IsCargoOpen}
		{
			UI:UpdateConsole["Closing Ship Cargohold"]
			EVEWindow[MyShipCargo]:Close
			wait WAIT_CARGO_WINDOW
			while ${This.IsCargoOpen}
			{
				wait 0.5
			}
			wait 10
		}
	}

	
	function WarpToID(int Id)
	{ 
		if (${Id} <= 0)
		{
			UI:UpdateConsole["Error: obj_Ship:WarpToID: Id is <= 0 (${Id})"]
			return
		}
		
		if !${Entity[${Id}](exists)}
		{
			UI:UpdateConsole["Error: obj_Ship:WarpToID: No entity matched the ID given."]
			return
		}

		call This.WarpPrepare
		while ${Entity[${Id}].Distance} >= 10000
		{
			UI:UpdateConsole["Warping to ${Entity[${Id}].Name}"]
			Entity[${Id}]:WarpTo
			call This.WarpWait
		}
	}	

	function WarpToBookMarkName(string DestinationBookmarkLabel)
	{
		if (!${EVE.Bookmark[${DestinationBookmarkLabel}](exists)})
		{  
			UI:UpdateConsole["ERROR: Bookmark: '${DestinationBookmarkLabel}' does not exist!"]
			return
		}
		
		call This.WarpToBookMark ${EVE.Bookmark[${DestinationBookmarkLabel}].ID}
	}
	
	function WarpToBookMark(bookmark DestinationBookmark)
	{
		variable int Counter

		if (${Me.InStation})
		{
			call Station.Undock
		}
		
		call This.WarpPrepare
		if (${DestinationBookmark.SolarSystemID} != ${Me.SolarSystemID})
		{
			UI:UpdateConsole["Setting autopilot destination: ${DestinationBookmark.Label}]}"]
			DestinationBookmark:SetDestination
			wait 5
			UI:UpdateConsole["Activating autopilot and waiting until arrival..."]
			EVE:Execute[CmdToggleAutopilot]
			do
			{
				wait 50
				if !${Me.AutoPilotOn(exists)}
				{
					do
					{
						wait 5
					}
					while !${Me.AutoPilotOn(exists)}
				}
			}
			while ${Me.AutoPilotOn}
			wait 20
			do
			{
			   wait 10
			}
			while !${Me.ToEntity.IsCloaked}
			wait 5
		}

		if ${DestinationBookmark.ToEntity(exists)} && \
			${DestinationBookmark.ToEntity.CategoryID} == CATEGORYID_STATION
		{
			/* This is a station bookmark, we can use .Distance properly */

			while ${DestinationBookmark.ToEntity.Distance} > WARP_RANGE
			{
				UI:UpdateConsole["Warping to bookmark ${DestinationBookmark.Label}"]
				DestinationBookmark:WarpTo
				call This.WarpWait
				;; TODO - verify we entered warp
			}
		}
		elseif ${DestinationBookmark.TypeID} != 5
		{
			/* This is an entity bookmark, but that entity is not on the overhead yet. */
			/* TODO - ToEntity.Distance doesnt work for anything but stations at the moment, merge with above when it does - CyberTech */

			while !${DestinationBookmark.ToEntity(exists)}
			{
				UI:UpdateConsole["Warping to bookmark ${DestinationBookmark.Label}"]
				DestinationBookmark:WarpTo
				call This.WarpWait
				;; TODO - verify we entered warp
			}
		}
		else
		{
			/* This is an in-space bookmark, just warp to it. */
			/* TODO - write distance(xyz,xyz) function to check distance to  */
			/* the bookmark.  We'll have to figure out eve units to convert it to meters. */
			/* we won't support multi-warp bookmarks of this type till we do so */

			UI:UpdateConsole["Warping to bookmark ${DestinationBookmark.Label}"]
			DestinationBookmark:WarpTo
			call This.WarpWait
		}
		
		if ${DestinationBookmark.ToEntity(exists)}
		{
			switch ${DestinationBookmark.ToEntity.CategoryID}
			{
				case 2
					; stargate
					break
				case CATEGORYID_STATION
					call This.Approach ${DestinationBookmark.ToEntity.ID} DOCKING_RANGE
					UI:UpdateConsole["Docking with destination station"]
					DestinationBookmark.ToEntity:Dock
					UI:UpdateConsole["Waiting until ship enters the station"]
					Counter:Set[0]
					do
					{
					   wait 20
					   Counter:Inc[20]
					   UI:UpdateConsole["Tick ${Counter}"]
					   if ${Counter} > 220
					   {
					      UI:UpdateConsole["Retrying to dock with destination station"]
					      ;DestinationBookmark.ToEntity:Dock	
					      Entity[CategoryID,3]:Dock
					      Counter:Set[0]
					   }
					}
					while !${Me.InStation}
					break
			}

			switch ${DestinationBookmark.ToEntity.TypeID}
			{
				case TYPEID_CORPORATE_HANGAR_ARRAY
					call This.Approach ${DestinationBookmark.ToEntity.ID} CORP_HANGAR_LOOT_RANGE
					break
			}
		}
		wait 20  
	}

	function WarpPrepare()
	{ 
		UI:UpdateConsole["Preparing for warp"]
		if ${This.Drones.WaitingForDrones}
		{
			UI:UpdateConsole["Drone deployment already in process, delaying warp"]
			do
			{
				waitframe
			}
			while ${This.Drones.WaitingForDrones}
		}
		This:DeactivateAllMiningLasers[]
		This:UnlockAllTargets[]
		call This.Drones.ReturnAllToDroneBay
	}
	
	member:bool InWarp()
	{
		if ${Me.ToEntity.Mode} == 3
		{
			return TRUE
		}
		return FALSE
	}
	
	function WarpWait()
	{
		variable bool Warped = FALSE
		; TODO - add check for InWarp== true at least once, to validate we did actually warp.
		wait 150
		if ${Me.ToEntity.Mode} == 3
		{
			UI:UpdateConsole["Warping..."]
		}
		while ${Me.ToEntity.Mode} == 3
		{
			Warped:Set[TRUE]
			wait 20
		}
		UI:UpdateConsole["Dropped out of warp"]
		wait 20
		return ${Warped}
	}	

	method Activate_AfterBurner()
	{
		if !${Me.Ship(exists)}
		{
			return
		}
		
		variable iterator Module
		
		This.ModuleList_AB_MWD:GetIterator[Module]
		if ${Module:First(exists)}
		{
			if !${Module.Value.IsActive}
			{
				UI:UpdateConsole["Activating ${Module.Value.ToItem.Name}"]
				Module.Value:Click
			}
		}
	}
	
	member:int Total_Armor_Reps()
	{
		return ${This.ModuleList_Repair_Armor.Used}
	}
	
	method Activate_Armor_Reps()
	{
		if !${Me.Ship(exists) || }
		{
			return
		}
		
		variable iterator Module
		
		This.ModuleList_Repair_Armor:GetIterator[Module]
		if ${Module:First(exists)}
		do
		{
			if !${Module.Value.IsActive}
			{
				UI:UpdateConsole["Activating ${Module.Value.ToItem.Name}"]
				Module.Value:Click
				This.Repairing_Armor:Set[TRUE]
			}
		}
		while ${Module:Next(exists)}
	}
	
	method Deactivate_Armor_Reps()
	{
		if !${Me.Ship(exists)}
		{
			return
		}
		
		variable iterator Module
		
		This.ModuleList_Repair_Armor:GetIterator[Module]
		if ${Module:First(exists)}
		{
			if ${Module.Value.IsActive}
			{
				UI:UpdateConsole["Deactivating ${Module.Value.ToItem.Name}"]
				Module.Value:Click
			}
		}
	}

	method Deactivate_AfterBurner()
	{
		if !${Me.Ship(exists)}
		{
			return
		}
		
		variable iterator Module
		
		This.ModuleList_AB_MWD:GetIterator[Module]
		if ${Module:First(exists)}
		{
			if ${Module.Value.IsActive}
			{
				UI:UpdateConsole["Deactivating ${Module.Value.ToItem.Name}"]
				Module.Value:Click
			}
		}
	}

	method Activate_Shield_Booster()
	{
		if !${Me.Ship(exists)}
		{
			return
		}
		
		variable iterator Module
		
		This.ModuleList_Regen_Shield:GetIterator[Module]
		if ${Module:First(exists)}
		do
		{
			if !${Module.Value.IsActive}
			{
				UI:UpdateConsole["Activating ${Module.Value.ToItem.Name}"]
				Module.Value:Click
			}
		}	
		while ${Module:Next(exists)}
	}
	
	method Deactivate_Shield_Booster()
	{
		if !${Me.Ship(exists)}
		{
			return
		}
		
		variable iterator Module
		
		This.ModuleList_Regen_Shield:GetIterator[Module]
		if ${Module:First(exists)}
		do
		{
			if ${Module.Value.IsActive}
			{
				UI:UpdateConsole["Deactivating ${Module.Value.ToItem.Name}"]
				Module.Value:Click
			}
		}
		while ${Module:Next(exists)}
	}

	function LockTarget(int64 TargetID)
	{
		if ${Entity[${TargetID}](exists)}
		{
			UI:UpdateConsole["Locking ${Entity[${TargetID}].Name}: " ${EVEBot.MetersToKM_Str[${Entity[${TargetID}].Distance}]}"]
			Entity[${TargetID}]:LockTarget
			wait 30
		}
	}

	function StackAll()
	{
		if ${This.IsCargoOpen}
		{
			Me.Ship:StackAllCargo
		}
	}

	; Returns the salvager range minus 10%
	member:int OptimalSalvageRange()
	{
		if !${Me.Ship(exists)}
		{
			return 0
		}

		variable iterator Module

		This.ModuleList_Salvagers:GetIterator[Module]
		if ${Module:First(exists)}
		{
			return ${Math.Calc[${Module.Value.OptimalRange}*0.90]}
		}

		return 0
	}

	; Returns the tractor range minus 10%
	member:int OptimalTractorRange()
	{
		if !${Me.Ship(exists)}
		{
			return 0
		}

		variable iterator Module

		This.ModuleList_TractorBeams:GetIterator[Module]
		if ${Module:First(exists)}
		{
			return ${Math.Calc[${Module.Value.OptimalRange}*0.90]}
		}

		return 0
	}
}
