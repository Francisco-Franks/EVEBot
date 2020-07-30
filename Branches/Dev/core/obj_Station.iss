/*
	Station class

	Object to contain members related to in-station activities.

	-- CyberTech

*/

objectdef obj_EVEDB_StationID
{
#ifdef TESTCASE
	variable string CONFIG_FILE = "${Script.CurrentDirectory}/../Data/EVEDB_StationID.xml"
#else
	variable string CONFIG_FILE = "${BaseConfig.DATA_PATH}/EVEDB_StationID.xml"
#endif
	variable string SET_NAME = "EVEDB_StationID"

	method Initialize()
	{
		LavishSettings[${This.SET_NAME}]:Remove
		Logger:Log["${This.ObjectName}: Loading database from ${This.CONFIG_FILE}", LOG_MINOR]
		LavishSettings:Import[${CONFIG_FILE}]

		Logger:Log["obj_EVEDB_StationID: Initialized", LOG_MINOR]
	}

	method Shutdown()
	{
		LavishSettings[${This.SET_NAME}]:Remove
	}

	member:int StationID(string stationName)
	{
		return ${LavishSettings[${This.SET_NAME}].FindSet[${stationName}].FindSetting[stationID, NOTSET]}
	}
}

objectdef obj_Station
{
	variable index:item DronesInStation

	method Initialize()
	{
		Logger:Log["obj_Station: Initialized", LOG_MINOR]
	}

	member:bool Docked()
	{
		if ${EVEBot.SessionValid} && \
			!${Me.InSpace} && \
			${Me.InStation} && \
			${Me.StationID} > 0
		{
			return TRUE
		}
		return FALSE
	}

	member:bool DockedAtStation(int64 StationID)
	{
		if ${EVEBot.SessionValid} && \
			!${Me.InSpace} && \
			${Me.InStation} && \
			${Me.StationID} == ${StationID}

		{
			return TRUE
		}

		return FALSE
	}

	function GetStationItems()
	{
		while !${Me.InStation}
		{
			Logger:Log["obj_Cargo: Waiting for InStation..."]
			wait 10
		}

		call Inventory.StationHangar.Activate ${Me.Station.ID}
		Inventory.StationHangar:GetItems[This.DronesInStation, "CategoryID == 18"]
	}

	function DockAtStation(int64 StationID)
	{
		variable int Counter = 0

		if ${Me.InStation}
		{
			Logger:Log["DockAtStation called, but we're already in station!"]
			return
		}

		Logger:Log["Docking at ${EVE.GetLocationNameByID[${StationID}]}"]

		if ${Entity[${StationID}](exists)}
		{
			if ${Entity[${StationID}].Distance} > WARP_RANGE
			{
				Logger:Log["Warping to Station"]
				call Ship.WarpToID ${StationID}
				do
				{
				   wait 30
				}
				while ${Entity[${StationID}].Distance} > WARP_RANGE
			}

			do
			{
				Entity[${StationID}]:Dock
				Logger:Log["Approaching docking range..."]
				wait 200 ${This.DockedAtStation[${StationID}]}
			}
			while (${Entity[${StationID}].Distance} > DOCKING_RANGE)

			Counter:Set[0]
			Logger:Log["In Docking Range ... Docking"]
			;Logger:Log["DEBUG: StationExists = ${Entity[${StationID}](exists)}"]
			do
			{
				Entity[${StationID}]:Dock
				wait 30
				Counter:Inc[1]
				if (${Counter} > 20)
				{
					Logger:Log["Warning: Docking incomplete after 60 seconds", LOG_CRITICAL]
					Counter:Set[0]
				}
			}
			while !${This.DockedAtStation[${StationID}]}
		}
		else
		{
			Logger:Log["Station Requested does not exist!  Trying Safespots...", LOG_CRITICAL]
			call Safespots.WarpToNext
		}
	}

	function Dock()
	{
		variable int64 StationID
		StationID:Set[${Entity["(CategoryID = CATEGORYID_STATION || CategoryID = CATEGORYID_STRUCTURE) && Name = ${Config.Common.HomeStation}"].ID}]

		if ${Me.InStation}
		{
			Logger:Log["Dock called, but we're already instation!"]
			return
		}

		if ${StationID} <= 0 || !${Entity[${StationID}](exists)}
		{
			Logger:Log["Warning: Home station '${Config.Common.HomeStation}' not found, going to nearest base", LOG_CRITICAL]
			StationID:Set[${Entity["(CategoryID = CATEGORYID_STATION || CategoryID = CATEGORYID_STRUCTURE)"].ID}]
		}

		if ${Entity[${StationID}](exists)}
		{
			Logger:Log["Docking at ${StationID}:${Entity[${StationID}].Name}"]
			call This.DockAtStation ${StationID}
		}
		else
		{
			Logger:Log["No stations in this system!  Trying Safespots...", LOG_CRITICAL]
			call Safespots.WarpToNext
		}
	}

	function Undock()
	{
		variable int Counter
		variable int64 StationID
		StationID:Set[${Me.StationID}]

		if !${Me.InStation}
		{
			Logger:Log["WARNING: Undock called, but we're already undocking!", LOG_ECHOTOO]
			return
		}

		Logger:Log["Undocking from ${Me.Station.Name}"]
		Config.Common:SetHomeStation[${Me.Station.Name}]
		Logger:Log["Undock: Home Station set to ${Config.Common.HomeStation}"]

		EVE:Execute[CmdExitStation]
		wait WAIT_UNDOCK
		Counter:Set[0]
		do
		{
			wait 10
			Counter:Inc[1]
			if ${Counter} > 20
			{
			   Counter:Set[0]
			   EVE:Execute[CmdExitStation]
			   Logger:Log["Undock: Unexpected failure, retrying...", LOG_CRITICAL]
			   Logger:Log["Undock: Debug: EVEWindow[Local]=${EVEWindow[Local](exists)}", LOG_CRITICAL]
			   Logger:Log["Undock: Debug: Me.InStation=${Me.InStation}", LOG_CRITICAL]
			   Logger:Log["Undock: Debug: Me.StationID=${Me.StationID}", LOG_CRITICAL]
			}
		}
		while ${This.Docked}
		Logger:Log["Undock: Complete"]

		Config.Common:SetHomeStation[${Entity["(GroupID = 15 || GroupID = 1657)"].Name}]

		Ship.RetryUpdateModuleList:Set[1]
	}

}
