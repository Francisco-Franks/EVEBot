#include ..\core\defines.iss
/*
	Movement Thread

	This thread handles all movement-related items, including warping,
	system travel, slowboat movement, etc.

	-- CyberTech

 TODO/CT - we used to reload weapons during warping, this needs moved to somewhere appropriate
*/
objectdef obj_Destination
{
	variable int DestinationType = 0
	variable int64 Distance

	variable int64 EntityID
	variable int64 SystemID
	variable int64 FleetMemberID
	variable bookmark Bookmark
	variable bool InProgress
	variable bool InteractWithDest

	method Initialize(_Type = 0, int64 _Distance = 0, int64 _EntityID = 0, int64 _SystemID = 0, int64 _FleetMemberID = 0, bookmark _Bookmark = 0, bool _InteractWithDest = FALSE)
	{
		DestinationType:Set[${_Type}]
		Distance:Set[${_Distance}]
		InteractWithDest:Set[${_InteractWithDest}]

		switch ${DestinationType}
		{
			variablecase ${Navigator.DEST_ENTITY}
				EntityID:Set[${_EntityID}]
				break
			variablecase ${Navigator.DEST_SYSTEM}
				SystemID:Set[${_SystemID}]
				break
			variablecase ${Navigator.DEST_FLEETMEMBER}
				FleetMemberID:Set[${MemberID}]
				break
			variablecase ${Navigator.DEST_BOOKMARK}
				Bookmark:Set[${_Bookmark}]
				break
			variablecase ${Navigator.DEST_ACTION_APPROACH}
				EntityID:Set[${_EntityID}]
				break
			variablecase ${Navigator.DEST_ACTION_ORBIT}
				EntityID:Set[${_EntityID}]
				break
			variablecase ${Navigator.DEST_ACTION_KEEPATRANGE}
				EntityID:Set[${_EntityID}]
				break
			variablecase ${Navigator.DEST_ACTION_DOCK}
				EntityID:Set[${_EntityID}]
				break
			variablecase ${Navigator.DEST_ACTION_JUMP}
				EntityID:Set[${_EntityID}]
				break
			variablecase ${Navigator.DEST_ACTION_ACTIVATE}
				EntityID:Set[${_EntityID}]
				break
			variablecase ${Navigator.DEST_ACTION_ALIGNTO}
				EntityID:Set[${_EntityID}]
				break
		}
		Logger:Log["Navigator: Queued ${This.ToString}", LOG_DEBUG]
	}

	method Shutdown()
	{
		Logger:Log["Navigator: Dequeued ${This.ToString}", LOG_DEBUG]
		Navigator.CurrentState:Set[0]
	}

	member:string ToString()
	{
		switch ${DestinationType}
		{
			variablecase ${Navigator.DEST_ENTITY}
				return "EntityID ${EntityID} (${Entity[${EntityID}].Name})"
			variablecase ${Navigator.DEST_SYSTEM}
				return "SystemID ${SystemID} (${Universe[${SystemID}].Name})"
			variablecase ${Navigator.DEST_FLEETMEMBER}
				return "Fleet Member ID ${FleetMemberID}"
			variablecase ${Navigator.DEST_BOOKMARK}
				return "Bookmark ${Bookmark}"
			variablecase ${Navigator.DEST_ACTION_APPROACH}
				return "EntityID ${EntityID} (${Entity[${EntityID}].Name}) (Approach)"
			variablecase ${Navigator.DEST_ACTION_ORBIT}
				return "EntityID ${EntityID} (${Entity[${EntityID}].Name}) (Orbit)"
			variablecase ${Navigator.DEST_ACTION_KEEPATRANGE}
				return "EntityID ${EntityID} (${Entity[${EntityID}].Name}) (Keep At Range)"
			variablecase ${Navigator.DEST_ACTION_DOCK}
				return "EntityID ${EntityID} (${Entity[${EntityID}].Name}) (Dock)"
			variablecase ${Navigator.DEST_ACTION_JUMP}
				return "EntityID ${EntityID} (${Entity[${EntityID}].Name}) (Jump)"
			variablecase ${Navigator.DEST_ACTION_ACTIVATE}
				return "EntityID ${EntityID} (${Entity[${EntityID}].Name}) (Activate)"
			variablecase ${Navigator.DEST_ACTION_ALIGNTO}
				return "EntityID ${EntityID} (${Entity[${EntityID}].Name}) (AlignTo)"
		}

		return "Unknown Destination Type"
	}
}

objectdef obj_Navigator inherits obj_BaseClass
{
	variable bool Enabled = TRUE
	variable int CurrentState = 0

	variable queue:obj_Destination Destinations
	variable iterator Destination

	variable time StateChanged

	; Any new actions need to be copied to obj_Destination:Initialize and obj_Destination:ToString
	variable int DEST_ENTITY = 1
	variable int DEST_SYSTEM = 2
	variable int DEST_BOOKMARK = 3
	variable int DEST_FLEETMEMBER = 4
	variable int DEST_ACTION_APPROACH = 5
	variable int DEST_ACTION_ORBIT = 6
	variable int DEST_ACTION_KEEPATRANGE = 7
	variable int DEST_ACTION_DOCK = 8
	variable int DEST_ACTION_JUMP = 9
	variable int DEST_ACTION_ACIVATE = 10
	variable int DEST_ACTION_ALIGNTO = 10


	variable int STATE_IDLE = 0
	variable int STATE_WARP_INITIATED = 1
	variable int STATE_WARPING = 2
	variable int STATE_APPROACHING = 3
	variable int STATE_JUMPGATE_ACTIVATED = 4
	variable int STATE_JUMPDRIVE_ACTIVATED = 5
	variable int STATE_AUTOPILOT_INITIATED = 6
	variable int STATE_KEEPATRANGE = 7
	variable int STATE_ORBIT = 8
	variable int STATE_DOCKING = 9
	variable int STATE_ALIGNING = 10
	variable int STATE_UNDOCKING = 11

	method Initialize()
	{
		LogPrefix:Set["${This.ObjectName}"]

		This.PulseTimer:SetIntervals[0.1,0.5]
		Event[ISXEVE_onFrame]:AttachAtom[This:Pulse]
		Logger:Log["Thread: ${LogPrefix}: Initialized", LOG_MINOR]
	}

	method Shutdown()
	{
		Event[ISXEVE_onFrame]:DetachAtom[This:Pulse]
	}

	method Pulse()
	{
		if !${Script[EVEBot](exists)}
		{
			Script:End
		}

		if !${EVEBot.Loaded} || ${EVEBot.Disabled}
		{
			return
		}

		if ${This.Enabled} && ${This.PulseTimer.Ready}
		{
			if !${This.Destinations.Peek(exists)}
			{
				This.CurrentState:Set[${STATE_IDLE}]
			}
			else
			{
				if ${This.AtDestination}
				{
					Destination:Dequeue
					; return now, without resetting timer. We'll handle the new dest on the next pulse.
					return
				}

				This:Navigate
			}

			This.PulseTimer:Update
		}
	}

	member:bool Busy()
	{
		variable bool MoreDestinations

		MoreDestinations:Set[${This.Destinations.Peek(exists)}]
		return ${MoreDestinations}
	}

	function WaitWhileBusy()
	{
		while ${This.Busy[]}
		{
			wait 1
		}
	}

	member AtCurrentDestination()
	{
	}

	member AtFinalDestination()
	{
	}

	member:bool ShouldInteractWithDest()
	{
		declarevariable TempEntity entity ${This.Destinations.Peek.EntityID}

		if ${This.Destinations.Peek.InteractWithDest} && ${TempEntity(exists)}
		{
			switch ${TempEntity.GroupID}
			{
				case GROUP_STATION
					This.Destinations.Peek.DestinationType:Set[${This.DEST_ACTION_DOCK}]
					return TRUE
					break
				default
					break
			}
		}
	}

	method Enable()
	{
		Logger:Log["${LogPrefix}: Enabled", LOG_DEBUG]
		This.Enabled:Set[TRUE]
	}

	method Disable()
	{
		Logger:Log["${LogPrefix}: Disabled", LOG_DEBUG]
		This.Enabled:Set[FALSE]
	}

	method SetState(int State)
	{
		;Logger:Log["${LogPrefix} - SetState[${State}]", LOG_DEBUG]
		This.CurrentState:Set[${State}]
		This.StateChanged:Set[${Time.Timestamp}]
	}

	; This will stop the ship as soon as we're on the right vector. If you want
	; to keep moving, use approach
	method AlignTo(int64 EntityID)
	{
		if (${EntityID} <= 0)
		{
			Logger:Log["${LogPrefix} - AlignTo: ERROR: ID is <= 0 (${EntityID})"]
			return
		}

		if !${Entity[${EntityID}](exists)}
		{
			Logger:Log["${LogPrefix} - AlignTo: ERROR: No entity matched the ID given", LOG_DEBUG]
			return
		}

		Destinations:Queue[${DEST_ACTION_ALIGNTO}, ${Range}, ${EntityID}]
	}

	method Approach(int64 EntityID, int64 Range = 0, bool InteractWithDest = FALSE)
	{
		if (${EntityID} <= 0)
		{
			Logger:Log["${LogPrefix} - Approach: ERROR: ID is <= 0 (${EntityID})"]
			return
		}

		if !${Entity[${EntityID}](exists)}
		{
			Logger:Log["${LogPrefix} - Approach: ERROR: No entity matched the ID given", LOG_DEBUG]
			return
		}

		Destinations:Queue[${DEST_ACTION_APPROACH}, ${Range}, ${EntityID}, 0, 0, 0, ${InteractWithDest}]
	}

	method Orbit(int64 EntityID, int64 Range = 0)
	{
		if (${EntityID} <= 0)
		{
			Logger:Log["${LogPrefix} - Orbit: ERROR: ID is <= 0 (${EntityID})"]
			return
		}

		if !${Entity[${EntityID}](exists)}
		{
			Logger:Log["${LogPrefix} - Orbit: ERROR: No entity matched the ID given", LOG_DEBUG]
			return
		}

		Destinations:Queue[${DEST_ACTION_ORBIT}, ${Range}, ${EntityID}]
	}

	method KeepAtRange(int64 EntityID, int64 Range = 0)
	{
		if (${EntityID} <= 0)
		{
			Logger:Log["${LogPrefix} - KeepAtRange: ERROR: ID is <= 0 (${EntityID})"]
			return
		}

		if !${Entity[${EntityID}](exists)}
		{
			Logger:Log["${LogPrefix} - KeepAtRange: ERROR: No entity matched the ID given", LOG_DEBUG]
			return
		}

		Destinations:Queue[${DEST_ACTION_KEEPATRANGE}, ${Range}, ${EntityID}]
	}

	; This can't be called until the entity is on-grid
	method Dock(int64 EntityID)
	{
		if (${EntityID} <= 0)
		{
			Logger:Log["${LogPrefix} - Dock: ERROR: ID is <= 0 (${EntityID})"]
			return
		}

		if !${Entity[${EntityID}](exists)}
		{
			Logger:Log["${LogPrefix} - Dock: ERROR: No entity matched the ID given", LOG_DEBUG]
			return
		}

		; We need to make sure we're approaching to within 200 to dock.
		Destinations:Queue[${DEST_ACTION_APPROACH}, 200, ${EntityID}, 0, 0, 0, TRUE]
		;Destinations:Queue[${DEST_ACTION_DOCK}, 200, ${EntityID}] ; Approach will handle the docking since interact is true
	}

	method JumpThruEntity(int64 EntityID)
	{
		if (${EntityID} <= 0)
		{
			Logger:Log["${LogPrefix} - JumpThruEntity: ERROR: ID is <= 0 (${EntityID})"]
			return
		}

		if !${Entity[${EntityID}](exists)}
		{
			Logger:Log["${LogPrefix} - JumpThruEntity: ERROR: No entity matched the ID given", LOG_DEBUG]
			return
		}

		Destinations:Queue[${DEST_ACTION_JUMP}, 0, ${EntityID}]
	}

	method ActivateEntity(int64 EntityID)
	{
		if (${EntityID} <= 0)
		{
			Logger:Log["${LogPrefix} - ActivateEntity: ERROR: ID is <= 0 (${EntityID})"]
			return
		}

		if !${Entity[${EntityID}](exists)}
		{
			Logger:Log["${LogPrefix} - ActivateEntity: ERROR: No entity matched the ID given", LOG_DEBUG]
			return
		}

		Destinations:Queue[${DEST_ACTION_ACTIVATE}, 0, ${EntityID}]
	}

/*
TODO - integrate in most of the flyto*

		if ${Entity[OwnerID,${charID},CategoryID,6].Distance} > CONFIG_MAX_SLOWBOAT_RANGE
		{
			if ${Entity[OwnerID,${charID},CategoryID,6].Distance} < WARP_RANGE
			{
				Logger:Log["Fleet member is to far for approach; warping to bounce point"]
				call This.WarpToNextSafeSpot
			}
			call Ship.WarpToFleetMember ${charID}
		}
*/
	method FlyToSystem(int64 SystemID)
	{
		if ${SystemID} == ${Me.SystemID}
		{
			Logger:Log["${LogPrefix} - FlyToSystem: ERROR: Already in system ${SystemID}", LOG_DEBUG]
			return
		}
		Destinations:Queue[${DEST_SYSTEM}, 0, 0, ${SystemID}]
	}

	method FlyToEntityID(int64 EntityID, int64 Range = 0, bool InteractWithDest = FALSE)
	{
		if (${EntityID} <= 0)
		{
			Logger:Log["${LogPrefix} - FlyToEntityID: ERROR: ID is <= 0 (${EntityID})"]
			return
		}

		if !${Entity[${EntityID}](exists)}
		{
			Logger:Log["${LogPrefix} - FlyToEntityID: ERROR: No entity matched the ID given", LOG_DEBUG]
			return
		}

		Destinations:Queue[${DEST_ENTITY}, ${Range}, ${EntityID}, 0, 0, 0, ${InteractWithDest}]
	}

	method FlyToFleetMember(int64 FleetMemberCharID, int64 Range = 0, bool InteractWithDest = FALSE)
	{
		Destinations:Queue[${DEST_FLEETMEMBER}, ${Range}, 0, 0, ${FleetMemberCharID}, 0, ${InteractWithDest}]
	}

	method FlyToBookmark(string DestinationBookmark, int64 Range = 0, bool InteractWithDest = FALSE)
	{
		variable int64 BookmarkID
		BookmarkID:Set[${EVE.Bookmark["${DestinationBookmark}"].ID}]

		if ${BookmarkID} > 0
		{
			This:FlyToBookmarkID[${BookmarkID}, ${Range}, ${InteractWithDest}]
		}
		else
		{
			Logger:Log["${LogPrefix} - FlyToBookmark: ${DestinationBookmark} doesn't exist", LOG_DEBUG]
			return
		}
	}

	method FlyToBookmarkID(bookmark DestinationBookmark, int64 Range = 0, bool InteractWithDest = FALSE)
	{
		if !${DestinationBookmark(exists)}
		{
			Logger:Log["${LogPrefix} - FlyToBookmarkID: ${DestinationBookmark} doesn't exist", LOG_DEBUG]
			return
		}

		Logger:Log["${LogPrefix} - FlyToBookmarkID: Flying to ${DestinationBookmark.Label}", LOG_DEBUG]

		if ${DestinationBookmark.ToEntity(exists)}
		{
			Logger:Log["${LogPrefix} - FlyToBookmarkID: Treating Bookmark as an Entity", LOG_DEBUG]
			This:FlyToEntityID[${DestinationBookmark.ToEntity.ID}, ${Range}, ${InteractWithDest}]
			return
		}

		if ${DestinationBookmark.SolarSystemID} != ${Me.SolarSystemID}
		{
			This:FlyToSystem[${DestinationBookmark.SolarSystemID}]
		}

		Destinations:Queue[${DEST_BOOKMARK}, ${Range}, 0, 0, 0, ${DestinationBookmark.ID}, ${InteractWithDest}]
	}

	method Navigate()
	{
		variable int LastStateChange = ${Math.Calc[${Time.Timestamp} - ${This.StateChanged.Timestamp}]}

		; If the time since state change for an evolving state
		; is over the thresold for that state,
		; reset the state so we retry it.
		switch ${This.CurrentState}
		{
			variablecase ${STATE_WARPING}
				{
					if ${Ship.InWarp}
					{
						This:SetState[${STATE_WARPING}]
					}
					elseif ${LastStateChange} > 5
					{
						Logger:Log["${LogPrefix} - Navigate: Warning: thought we were warping, but we aren't", LOG_DEBUG]
						This:SetState[0]
					}
				}
			variablecase ${STATE_AUTOPILOT_INITIATED}
			variablecase ${STATE_WARP_INITIATED}
				if ${Ship.InWarp}
				{
					This:SetState[${STATE_WARPING}]
				}
				elseif ${LastStateChange} > 5
				{
					Logger:Log["${LogPrefix} - Navigate: Warning: Resetting Autopilot/Warp Timer", LOG_DEBUG]
					This:SetState[0]
				}
				break
			variablecase ${STATE_APPROACHING}
				if ${LastStateChange} > 10
				{
					This:SetState[0]
				}
				break
			variablecase ${STATE_JUMPGATE_ACTIVATED}
			variablecase ${STATE_JUMPDRIVE_ACTIVATED}
				if ${LastStateChange} > 10
				{
					This:SetState[0]
				}
				break
		}

		switch ${This.Destinations.Peek.DestinationType}
		{
			variablecase ${Navigator.DEST_ENTITY}
				This:NavigateTo_Entity[]
				break
			variablecase ${Navigator.DEST_SYSTEM}
				This:NavigateTo_System[]
				break
			variablecase ${Navigator.DEST_FLEETMEMBER}
				This:NavigateTo_FleetMember[]
				break
			variablecase ${Navigator.DEST_BOOKMARK}
				This:NavigateTo_Bookmark[]
				break
			variablecase ${Navigator.DEST_ACTION_APPROACH}
				This:Navigate_Approach[]
				break
			variablecase ${Navigator.DEST_ACTION_ORBIT}
				This:Navigate_Orbit[]
				break
			variablecase ${Navigator.DEST_ACTION_KEEPATRANGE}
				This:Navigate_KeepAtRange[]
				break
			variablecase ${Navigator.DEST_ACTION_DOCK}
				This:Navigate_Dock[]
				break
			variablecase ${Navigator.DEST_ACTION_JUMP}
				This:Navigate_Jump[]
				break
			variablecase ${Navigator.DEST_ACTION_ACIVATE}
				This:Navigate_Activate[]
				break
			variablecase ${Navigator.DEST_ACTION_ALIGNTO}
				This:Navigate_AlignTo[]
				break
			default
				Logger:Log["${LogPrefix} - Navigate: ERROR: Unknown Destination Type"]
				break
		}
	}

	method NavigateTo_Entity()
	{
		if !${Me.InSpace}
		{
			This:Navigate_Undock
			return
		}

		if !${Entity[${This.Destinations.Peek.EntityID}](exists)}
		{
			Logger:Log["${LogPrefix} - NavigateTo_Entity: Warning: ${This.Destinations.Peek.EntityID} was not found, skipping", LOG_DEBUG]
			This.Destinations:Dequeue
			return
		}

		if !${Ship.InWarp}
		{
			variable int distance

			switch ${Entity[${This.Destinations.Peek.EntityID}].GroupID}
			{
				case GROUPID_MOON
					distance:Set[WARP_RANGE_MOON]
					BREAK
				case GROUPID_PLANET
					distance:Set[WARP_RANGE_PLANET]
				default
					distance:Set[WARP_RANGE]
					break
			}

			if ${Me.ToEntity.Velocity} > ${MyShip.MaxVelocity}
			{
				; We're still slowing down from warp
				return
			}

			if ${Entity[${This.Destinations.Peek.EntityID}].Distance} <= ${distance}
			{
				Logger:Log["${LogPrefix} - NavigateTo_Entity: Arrived at ${Entity[${This.Destinations.Peek.EntityID}].Name} @${EVEBot.MetersToKM_Str[${Entity[${This.Destinations.Peek.EntityID}].Distance}]}", LOG_DEBUG]

				if ${This.ShouldInteractWithDest}
				{
					; Member changed the action for this dest, so just return
					return
				}

				This.Destinations:Dequeue
				return
			}
		}

		if !${Ship.InWarp} && ${This.CurrentState} != ${STATE_WARP_INITIATED}
		{
			Logger:Log["${LogPrefix} - NavigateTo_Entity: Warping to ${Entity[${This.Destinations.Peek.EntityID}].Name} @${EVEBot.MetersToKM_Str[${This.Destinations.Peek.Distance}]}", LOG_DEBUG]
			Entity[${This.Destinations.Peek.EntityID}]:AlignTo
			if ${This.ReadyToWarp}
			{
				Entity[${This.Destinations.Peek.EntityID}]:WarpTo[${This.Destinations.Peek.Distance}]
				This:SetState[${STATE_WARP_INITIATED}]
			}
		}
	}

	method NavigateTo_System()
	{
		if ${This.Destinations.Peek.SystemID} == ${Me.SystemID}
		{
			Logger:Log["${LogPrefix} - NavigateTo_System: Arrived at ${This.Destinations.Peek.SystemID}"]
			This.Destinations:Dequeue
			return
		}

		if !${Me.InSpace}
		{
			This:Navigate_Undock
			return
		}

		variable index:int apRoute

		; TODO - change this back to using pre-expanded queue after I work out what was sucking FPS - CyberTech
		EVE:GetToDestinationPath[apRoute]
		if ${apRoute.Used} == 0 || ${apRoute:Get[${apRoute.Used}]} != ${This.Destinations.Peek.SystemID}
		{
			EVE:ClearAllWaypoints
			Logger:Log["${LogPrefix} - NavigateTo_System: Setting autopilot from ${Me.SolarSystemID} to ${DestinationSystemID}", LOG_DEBUG]
			Logger:Log["${LogPrefix} - NavigateTo_System: Setting autopilot from ${Universe[${Me.SolarSystemID}].Name} to ${Universe[${DestinationSystemID}].Name}"]
			Universe[${DestinationSystemID}]:SetDestination
		}

		if ${This.CurrentState} == ${STATE_AUTOPILOT_INITIATED} || \
			${This.CurrentState} == ${STATE_WARPING} || \
			${Me.AutoPilotOn}
		{
			return
		}
		EVE:Execute[CmdToggleAutopilot]
		This.SetState[${STATE_AUTOPILOT_INITIATED}]
	}

	method NavigateTo_FleetMember()
	{
		if !${Me.InSpace}
		{
			This:Navigate_Undock
			return
		}
	}

	method NavigateTo_Bookmark()
	{
		variable int Counter

		if !${Me.InSpace}
		{
			This:Navigate_Undock
			return
		}

		/*
			Sun:		ToEntity = false		ItemID = valid		TypeID = Valid		Type = Valid	LocationID = valid		X = invalid
			Station:	ToEntity = true								TypeID = valid		Type = valid	LocationID = valid		X = invalid
			Planet:		ToEntity = true			ItemID = valid		TypeID = valid		Type = valid	LocationID = valid		X = invalid
			Safe Spot:	ToEntity = null			ItemID = invalid	TypeID = valid		Type = valid	LocationID = valid		X = valid
			POS:		ToEntity = false		itemid = invalid	typeid = valid		type = valid	Locationid = valid		X = valid

21:29:41: DestinationBookmark.ID = ##########
21:29:41: DestinationBookmark.Label = xxxxxxxxxxxxx
21:29:41: DestinationBookmark.Type = Station (Caldari 1)
21:29:41: DestinationBookmark.TypeID = 1529
21:29:41: DestinationBookmark.ToEntity(exists) = NULL
21:29:41: DestinationBookmark.ToEntity.Category = NULL
21:29:41: DestinationBookmark.ToEntity.CategoryID = NULL
21:29:41: DestinationBookmark.ToEntity.Distance = NULL
21:29:41: DestinationBookmark.AgentID = -1
21:29:41: DestinationBookmark.ItemID = #######
21:29:41: DestinationBookmark.LocationType = NULL
21:29:41: DestinationBookmark.LocationID = ##########
21:29:41: DestinationBookmark Location: NULL, NULL, NULL
21:29:41: Entity[CategoryID,6].X = NULL
21:29:41: Entity[CategoryID,6].Y = NULL
21:29:41: Entity[CategoryID,6].Z = NULL
21:29:41: Me.ToEntity.X = NULL
21:29:41: Me.ToEntity.Y = NULL
21:29:41: Me.ToEntity.Z = NULL

		*/

		declarevariable DestinationBookmark bookmark ${This.Destinations.Peek.Bookmark.ID}

#if EVEBOT_DEBUG
		if ${This.CurrentState} != ${STATE_WARP_INITIATED} && ${This.CurrentState} != ${STATE_WARPING}
		{
			Logger:Log["DestinationBookmark.ID = ${DestinationBookmark.ID}", LOG_DEBUG]
			Logger:Log["DestinationBookmark.Label = ${DestinationBookmark.Label}", LOG_DEBUG]
			Logger:Log["DestinationBookmark.Type = ${DestinationBookmark.Type}", LOG_DEBUG]
			Logger:Log["DestinationBookmark.TypeID = ${DestinationBookmark.TypeID}", LOG_DEBUG]
			Logger:Log["DestinationBookmark.ToEntity(exists) = ${DestinationBookmark.ToEntity(exists)}", LOG_DEBUG]
			if ${DestinationBookmark.ToEntity(exists)}
			{
				Logger:Log["DestinationBookmark.ToEntity.Category = ${DestinationBookmark.ToEntity.Category}", LOG_DEBUG]
				Logger:Log["DestinationBookmark.ToEntity.CategoryID = ${DestinationBookmark.ToEntity.CategoryID}", LOG_DEBUG]
				Logger:Log["DestinationBookmark.ToEntity.Distance = ${DestinationBookmark.ToEntity.Distance}", LOG_DEBUG]
			}
			Logger:Log["DestinationBookmark.AgentID = ${DestinationBookmark.AgentID}", LOG_DEBUG]
			Logger:Log["DestinationBookmark.ItemID = ${DestinationBookmark.ItemID}", LOG_DEBUG]
			Logger:Log["DestinationBookmark.LocationType = ${DestinationBookmark.LocationType}", LOG_DEBUG]
			Logger:Log["DestinationBookmark.LocationID = ${DestinationBookmark.LocationID}", LOG_DEBUG]
			Logger:Log["DestinationBookmark Location: ${DestinationBookmark.X}, ${DestinationBookmark.Y}, ${DestinationBookmark.Z}", LOG_DEBUG]
			Logger:Log["Entity[CategoryID,6].X = ${Entity[CategoryID,6].X}", LOG_DEBUG]
			Logger:Log["Entity[CategoryID,6].Y = ${Entity[CategoryID,6].Y}", LOG_DEBUG]
			Logger:Log["Entity[CategoryID,6].Z = ${Entity[CategoryID,6].Z}", LOG_DEBUG]
			Logger:Log["Me.ToEntity = ${Me.ToEntity}", LOG_DEBUG]
			Logger:Log["Me.ToEntity.X = ${Me.ToEntity.X}", LOG_DEBUG]
			Logger:Log["Me.ToEntity.Y = ${Me.ToEntity.Y}", LOG_DEBUG]
			Logger:Log["Me.ToEntity.Z = ${Me.ToEntity.Z}", LOG_DEBUG]
		}
#endif

		variable int MinWarpRange
		declarevariable WarpCounter int 0
		declarevariable Label string ${DestinationBookmark.Label}
		declarevariable TypeID int ${DestinationBookmark.ToEntity.TypeID}
		declarevariable GroupID int ${DestinationBookmark.ToEntity.GroupID}
		declarevariable CategoryID int ${DestinationBookmark.ToEntity.CategoryID}
		declarevariable EntityID int64 ${DestinationBookmark.ToEntity.ID}

		if ${DestinationBookmark.ToEntity(exists)}
		{
			This.Destinations.Peek.EntityID:Set[${DestinationBookmark.ToEntity.ID}]

			if !${Ship.InWarp} && ${This.CurrentState} != ${STATE_WARP_INITIATED}
			{
				if ${DestinationBookmark.ToEntity.Distance} > WARP_RANGE
				{
					Logger:Log["${LogPrefix} - NavigateTo_Bookmark: Warping to ${Entity[${This.Destinations.Peek.EntityID}].Name} @${EVEBot.MetersToKM_Str[${This.Destinations.Peek.Distance}]}"]
					Entity[${This.Destinations.Peek.EntityID}]:AlignTo
					if ${This.ReadyToWarp}
					{
						Entity[${This.Destinations.Peek.EntityID}]:WarpTo[${This.Destinations.Peek.Distance}]
						This:SetState[${STATE_WARP_INITIATED}]
						return
					}
				}
				else
				{
					if ${Me.ToEntity.Velocity} > ${MyShip.MaxVelocity}
					{
						; We're still slowing down from warp
						return
					}

					Logger:Log["${LogPrefix} - NavigateTo_Bookmark: Arrived at ${Entity[${This.Destinations.Peek.EntityID}].Name} @${EVEBot.MetersToKM_Str[${This.Destinations.Peek.Distance}]}"]

					if ${This.ShouldInteractWithDest}
					{
						; Member changed the action for this dest, so just return
						return
					}

					This.Destinations:Dequeue
					return
				}
			}
		}
		elseif ${DestinationBookmark.ItemID} == -1 || \
				(${DestinationBookmark.AgentID(exists)} && ${DestinationBookmark.LocationID(exists)})
		{
			/* This is an in-space bookmark, or a dungeon bookmark, just warp to it. */

			variable float64 CurDistance
			CurDistance:Set[${Math.Distance[${Me.ToEntity.X}, ${Me.ToEntity.Y}, ${Me.ToEntity.Z}, ${DestinationBookmark.X}, ${DestinationBookmark.Y}, ${DestinationBookmark.Z}]}]
			if ${CurDistance} > WARP_RANGE
			{
				if !${Ship.InWarp} && ${This.CurrentState} != ${STATE_WARP_INITIATED}
				{
					Logger:Log["${LogPrefix} - NavigateTo_Bookmark: Warping to ${Label} @${EVEBot.MetersToKM_Str[${This.Destinations.Peek.Distance}]}"]
					DestinationBookmark:Approach
					if ${This.ReadyToWarp}
					{
						Logger:Log["${LogPrefix} - NavigateTo_Bookmark: Warping to ${Label} (Attempt #${WarpCounter})", LOG_DEBUG]
						DestinationBookmark:WarpTo[${This.Destinations.Peek.Distance}]
						This:SetState[${STATE_WARP_INITIATED}]
					}
				}
				else
				{
					; TODO - find an entity ID to work with for approaching
					; We don't need to account for the case where the bookmark only shows as entity when we're near it
					; since this function will be recalled and will recheck entity above.
					; find entities like:
					;	CHA
					;	POS
					;	ship assembly array
					;This.Destinations.Peek.EntityID:Set[]
				}
				return
			}
			else
			{
				if ${Me.ToEntity.Velocity} > ${MyShip.MaxVelocity}
				{
					; We're still slowing down from warp
					return
				}
				Logger:Log["${LogPrefix} - NavigateTo_Bookmark: Arrived at ${Label} @ ${EVEBot.MetersToKM_Str[${CurDistance}]}"]
				This.Destinations:Dequeue
				return
			}
		}
		else
		{
			Logger:Log["${LogPrefix} - NavigateTo_Bookmark: FAILED - Unknown bookmark type, cannot decide action, dequeueing ${Label}", LOG_CRITICAL]
			This.Destinations:Dequeue
			return
		}
	}

	method Navigate_Approach()
	{
		variable float64 OriginalDistance
		variable float64 CurrentDistance

		OriginalDistance:Set[${Entity[${EntityID}].Distance}]
		CurrentDistance:Set[${Entity[${EntityID}].Distance}]

		if !${Entity[${This.Destinations.Peek.EntityID}](exists)}
		{
			Logger:Log["${LogPrefix} - Navigate_Approach: Warning: Entity ${This.Destinations.Peek.EntityID} not found", LOG_DEBUG]
			This.Destinations:Dequeue
			return
		}

		if ${Ship.InWarp}
		{
			return
		}

		if ${Me.ToEntity.Velocity} > ${MyShip.MaxVelocity}
		{
			; We're still slowing down from warp
			return
		}

		if ${Entity[${This.Destinations.Peek.EntityID}].Distance} >= WARP_RANGE
		{
			Logger:Log["${LogPrefix} - Navigate_Approach: Entity is warpable, calling warp instead of approach"]
			This:NavigateTo_Entity
			return
		}

		;TODO/CT - Check for distance from warprange -- decide if it's quicker to use a warp bounce.
		if ${Entity[${This.Destinations.Peek.EntityID}].Distance} <= ${This.Destinations.Peek.Distance}
		{
			Logger:Log["${LogPrefix} - Navigate_Approach: Arrived at ${Entity[${This.Destinations.Peek.EntityID}].Name} @${EVEBot.MetersToKM_Str[${Entity[${This.Destinations.Peek.EntityID}].Distance}]}"]

			if ${This.ShouldInteractWithDest}
			{
				; Member changed the action for this dest, so just return
				return
			}

			This.Destinations:Dequeue
			Ship:Deactivate_AfterBurner[]
			EVE:Execute[CmdStopShip]
			return
		}

		if ${This.CurrentState} != ${STATE_APPROACHING}
		{
			Logger:Log["${LogPrefix} - Navigate_Approach: Approaching ${Entity[${This.Destinations.Peek.EntityID}].Name} @${EVEBot.MetersToKM_Str[${This.Destinations.Peek.Distance}]} - ${Math.Calc[${Entity[${This.Destinations.Peek.EntityID}].Distance} / ${MyShip.MaxVelocity}].Ceil} Seconds away"]
			This:SetState[${STATE_ALIGNING}]
			Ship:Activate_AfterBurner[]
		}

		Entity[${This.Destinations.Peek.EntityID}]:Approach
	}

	method Navigate_AlignTo()
	{
		if !${Entity[${This.Destinations.Peek.EntityID}](exists)}
		{
			Logger:Log["${LogPrefix} - Navigate_AlignTo: Warning: Entity ${This.Destinations.Peek.EntityID} not found", LOG_DEBUG]
			This.Destinations:Dequeue
			return
		}

		if ${Ship.InWarp}
		{
			return
		}

		if ${Me.ToEntity.Velocity} > ${MyShip.MaxVelocity}
		{
			; We're still slowing down from warp
			return
		}

		if ${Entity[${This.Destinations.Peek.EntityID}].Distance} <= ${This.Destinations.Peek.Distance}
		{
			Logger:Log["${LogPrefix} - Navigate_AlignTo: Arrived at Entity ${Entity[${This.Destinations.Peek.EntityID}].Name} @ ${EVEBot.MetersToKM_Str[${Entity[${This.Destinations.Peek.EntityID}].Distance}]}", LOG_DEBUG]
			This.Destinations:Dequeue
			return
		}

		if ${This.CurrentState} != ${STATE_ALIGNING}
		{
			Logger:Log["${LogPrefix} - Navigate_AlignTo: Aligning to ${Entity[${This.Destinations.Peek.EntityID}].Name}"]
			This:SetState[${STATE_ALIGNING}]
		}

		Entity[${This.Destinations.Peek.EntityID}]:AlignTo
	}

	method Navigate_Orbit()
	{
		if !${Entity[${This.Destinations.Peek.EntityID}](exists)}
		{
			Logger:Log["${LogPrefix} - Navigate_Orbit: Warning: Entity ${This.Destinations.Peek.EntityID} not found", LOG_DEBUG]
			This.Destinations:Dequeue
			return
		}

		if ${This.CurrentState} != ${STATE_ORBIT}
		{
			Entity[${This.Destinations.Peek.EntityID}]:Orbit[${This.Destinations.Peek.Distance}]
			This:SetState[${STATE_ORBIT}]
		}
		else
		{
			; We're checking if we're within 10% of the requested distance.
			; The reason for this is the requested distance might not actually be attainable without slowing down,
			; and we're not slowing down right now.
			;	See: http://www.eveonline.com/ingameboard.asp?a=topic&threadID=498317&page=1#27 Post 27 for
			;	algorithm for min radius at a given velocity, and max velocity for a given radius, if we want to go that far
			; -- CyberTech
			if ${Entity[${This.Destinations.Peek.EntityID}].Distance} <= ${Math.Calc[${This.Destinations.Peek.Distance} * 1.10]} && \
			 	${Entity[${This.Destinations.Peek.EntityID}].Distance} >= ${Math.Calc[${This.Destinations.Peek.Distance} * 0.90]}
			{
				Logger:Log["${LogPrefix} - Navigate_Orbit: Orbiting Entity ${Entity[${This.Destinations.Peek.EntityID}].Name} @ ${EVEBot.MetersToKM_Str[${This.Destinations.Peek.Distance}]}", LOG_DEBUG]
				This.Destinations:Dequeue
				return
			}
		}
	}

	method Navigate_KeepAtRange()
	{
		if !${Entity[${This.Destinations.Peek.EntityID}](exists)}
		{
			Logger:Log["${LogPrefix} - Navigate_KeepAtRange: Warning: Entity ${This.Destinations.Peek.EntityID} not found", LOG_DEBUG]
			This.Destinations:Dequeue
			return
		}

		; TODO - Possible bug -- what if we called keep at range, but the target is faster than us during the initial approach, and we
		; never remove it from the queue? Navigator queue will be stuck at this point.

		if ${This.CurrentState} != ${STATE_KEEPATRANGE}
		{
			Entity[${This.Destinations.Peek.EntityID}]:KeepAtRange[${This.Destinations.Peek.Distance}]
			This:SetState[${STATE_KEEPATRANGE}]
		}
		else
		{
			if ${Entity[${This.Destinations.Peek.EntityID}].Distance} <= ${This.Destinations.Peek.Distance}
			{
				Logger:Log["${LogPrefix} - Navigate_KeepAtRange: Entity ${Entity[${This.Destinations.Peek.EntityID}].Name} @ ${EVEBot.MetersToKM_Str[${Entity[${This.Destinations.Peek.EntityID}].Distance}]}", LOG_DEBUG]
				This.Destinations:Dequeue
				return
			}
		}
	}

	method Navigate_Dock()
	{
		if ${This.CurrentState} != ${STATE_DOCKING}
		{
			if !${Entity[${This.Destinations.Peek.EntityID}](exists)}
			{
				Logger:Log["${LogPrefix} - Navigate_Dock: Warning: Entity ${This.Destinations.Peek.EntityID} not found", LOG_DEBUG]
				This.Destinations:Dequeue
				return
			}

			if ${Entity[${This.Destinations.Peek.EntityID}].Distance} >= DOCKING_RANGE
			{
				; This is fallback code that shouldn't get called.
				if ${This.CurrentState} != ${STATE_DOCKING}
				{
					Ship:Activate_AfterBurner[]
					Entity[${This.Destinations.Peek.EntityID}]:Approach
					Entity[${This.Destinations.Peek.EntityID}]:Dock
					This:SetState[${STATE_DOCKING}]
				}
				;Logger:Log["${LogPrefix} - Navigate_Dock: Warning: Removing Entity ${Entity[${This.Destinations.Peek.EntityID}].Name} @ ${EVEBot.MetersToKM_Str[${Entity[${This.Destinations.Peek.EntityID}].Distance}]}, outside docking range", LOG_DEBUG]
				;This.Destinations:Dequeue
				return
			}

			if ${Me.InStation}
			{
				Logger:Log["${LogPrefix} - Navigate_Dock: We're already in a station"]
				This.Destinations:Dequeue
				return
			}
		}

		if ${Station.DockedAtStation[${This.Destinations.Peek.EntityID}]}
		{
			Logger:Log["${LogPrefix} - Navigate_Dock: Completed docking @${EVE.GetLocationNameByID[${This.Destinations.Peek.EntityID}]}", LOG_DEBUG]
			This.Destinations:Dequeue
			return
		}

		if ${This.CurrentState} != ${STATE_DOCKING}
		{
			Logger:Log["${LogPrefix} - Navigate_Dock: Docking @${EVE.GetLocationNameByID[${This.Destinations.Peek.EntityID}]}"]
			This:SetState[${STATE_DOCKING}]
		}

		Entity[${This.Destinations.Peek.EntityID}]:Dock
	}

	method Navigate_Undock()
	{
		variable int Counter
		variable int64 StationID

		if ${Me.InSpace} && !${Station.Docked} && ${Me.ToEntity(exists)}
		{
			if ${This.CurrentState} == ${STATE_UNDOCKING}
			{
				Me:SetVelocity[100]

				;TODO/CT - get rid of these here, they shouldn't rely on undocking
				Ship:UpdateModuleList[]
				Ship:SetType[${Entity[CategoryID,CATEGORYID_SHIP].Type}]
				Ship:SetTypeID[${Entity[CategoryID,CATEGORYID_SHIP].TypeID}]
			}
			return
		}

		if ${This.CurrentState} != ${STATE_UNDOCKING}
		{
			Config.Common:LastStationID[${Me.StationID}]
			if ${Config.Common.HomeStation.Equal["NOTSET"]}
			{
				Config.Common:HomeStation["${Me.Station}"]
				Logger:Log["${LogPrefix} - Navigate_Undock: Home Station set to ${Config.Common.HomeStation}"]
			}

			Logger:Log["${LogPrefix} - Navigate_Undock: Undocking from ${Me.Station}"]
			This:SetState[${STATE_UNDOCKING}]
		}

		EVE:Execute[CmdExitStation]

		/*
			Logger:Log["Undock: Unexpected failure, retrying...", LOG_CRITICAL]
			Logger:Log["Undock: Debug: EVEWindow[Local]=${EVEWindow[Local](exists)}", LOG_CRITICAL]
			Logger:Log["Undock: Debug: Me.InStation=${Me.InStation}", LOG_CRITICAL]
			Logger:Log["Undock: Debug: Me.StationID=${Me.StationID}", LOG_CRITICAL]
	   */
	}

	method Navigate_Jump()
	{
		if !${Entity[${This.Destinations.Peek.EntityID}](exists)}
		{
			Logger:Log["${LogPrefix} - Navigate_Jump: Warning: Entity ${This.Destinations.Peek.EntityID} not found", LOG_DEBUG]
			This.Destinations:Dequeue
			return
		}

		if ${Entity[${This.Destinations.Peek.EntityID}].Distance} >= JUMP_RANGE
		{
			Logger:Log["${LogPrefix} - Navigate_Jump: Warning: Removing Entity ${Entity[${This.Destinations.Peek.EntityID}].Name} @ ${EVEBot.MetersToKM_Str[${Entity[${This.Destinations.Peek.EntityID}].Distance}]}, outside gate activation range", LOG_DEBUG]
			This.Destinations:Dequeue
			return
		}

		if ${Me.ToEntity.IsCloaked}
		{
			Logger:Log["${LogPrefix} - Navigate_Jump: Removing Entity ${Entity[${This.Destinations.Peek.EntityID}].Name}, jump complete", LOG_DEBUG]
			This.Destinations:Dequeue
		}

		if ${This.CurrentState} != ${STATE_JUMPING}
		{
			Logger:Log["Jumping thru ${Entity[${This.Destinations.Peek.EntityID}].Name}"]
			This:SetState[${STATE_JUMPING}]
		}

		Entity[${This.Destinations.Peek.EntityID}]:Jump
	}

	method Navigate_Activate()
	{
		if !${Entity[${This.Destinations.Peek.EntityID}](exists)}
		{
			Logger:Log["${LogPrefix} - Navigate_Activate: Warning: Entity ${This.Destinations.Peek.EntityID} not found", LOG_DEBUG]
			This.Destinations:Dequeue
			return
		}

		if ${Entity[${This.Destinations.Peek.EntityID}].Distance} >= JUMP_RANGE
		{
			Logger:Log["${LogPrefix} - Navigate_Activate: Warning: Removing Entity ${Entity[${This.Destinations.Peek.EntityID}].Name} @ ${EVEBot.MetersToKM_Str[${Entity[${This.Destinations.Peek.EntityID}].Distance}]}, outside gate activation range", LOG_DEBUG]
			This.Destinations:Dequeue
			return
		}

		if ${Me.ToEntity.IsCloaked}
		{
			Logger:Log["${LogPrefix} - Navigate_Activate: Removing Entity ${Entity[${This.Destinations.Peek.EntityID}].Name}, jump complete", LOG_DEBUG]
			This.Destinations:Dequeue
		}

		if ${This.CurrentState} != ${STATE_JUMPING}
		{
			Logger:Log["Jumping thru ${Entity[${This.Destinations.Peek.EntityID}].Name}"]
			This:SetState[${STATE_JUMPING}]
		}

		Entity[${This.Destinations.Peek.EntityID}]:Activate
	}

	member:bool ReadyToWarp()
	{
		if !${Ship.HasCovOpsCloak}
		{
			Ship:Deactivate_Cloak[]
		}
		;TODO call Ship.Drones.ReturnAllToDroneBay

		if ${Ship.Drones.DeployedDroneCount} > 0
		{
			; it's up to the caller to determine if they want to ignore this or not.
			return FALSE
		}

		Ship:Deactivate_SensorBoost[]
		Ship:Deactivate_Gang_Links[]
		Ship:DeactivateAllMiningLasers[]
		Ship:UnlockAllTargets[]
		return TRUE
	}

;----------------------------------------------
/*

	; This takes CHARID, not Entity id
	function WarpToFleetMember( int CharID, int distance=0 )
	{
		Validate_Ship()

		if !${Me.Fleet.ID(exists)}
		{
			return
		}

		if !${Me.Fleet.IsMember[${CharID}]}
		{
			Logger:Log["${LogPrefix}: (WarpToFleetMember) Error: No fleet member with CharID: ${CharID}"]
			return
		}

		if ${Me.Fleet.Member[${CharID}].ToPilot.Name(exists)}
		{
			Logger:Log["Debug: WarpToFleetMember ${charID} ${distance}", LOG_DEBUG]
			call This.WarpPrepare
			while !${Me.Fleet.Member[${CharID}].ToEntity(exists)}
			{
				Logger:Log["Warping to Fleet Member: ${FleetMember.Value.ToPilot.Name}"]
				while !${This.WarpEntered}
				{
					FleetMember.Value:WarpTo[${distance}]
					wait 10
				}
				call This.WarpWait
				if ${Return} == 2
				{
					return
				}
			}
			Logger:Log["ERROR: Ship.WarpToFleetMember never reached fleet member!"]
			return
		}
	}

	function ActivateAutoPilot()
	{
		Validate_Ship()

		variable int Counter
		Logger:Log["Activating autopilot and waiting until arrival..."]
		if !${Me.AutoPilotOn}
		{
			EVE:Execute[CmdToggleAutopilot]
		}
		do
		{
			do
			{
				Counter:Inc
				wait 10
			}
			while ${Me.AutoPilotOn(exists)} && !${Me.AutoPilotOn} && (${Counter} < 10)
			wait 10
		}
		while ${Me.AutoPilotOn(exists)} && ${Me.AutoPilotOn}
		Logger:Log["Arrived - Waiting for system load"]
		wait 150
	}
*/
}

variable(global) obj_Navigator Navigator

function main()
{
	EVEBot.Threads:Insert[${Script.Filename}]
	while ${Script[EVEBot](exists)} && !${EVEBot.Loaded}
	{
		waitframe
	}
	while ${Script[EVEBot](exists)}
	{
		waitframe
	}
	echo "${APP_NAME} exited, unloading ${Script.Filename}"
}