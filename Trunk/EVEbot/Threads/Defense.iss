#include ..\core\defines.iss
/*
	Defense Thread

	This thread handles ship _defense_.

	No offensive actions occur in this thread.

	-- CyberTech

*/

objectdef obj_Defense
{
	variable string SVN_REVISION = "$Rev$"
	variable int Version

	variable bool Running = TRUE

	variable time NextPulse
	variable int PulseIntervalInSeconds = 1

	variable bool Hide = FALSE
	variable string HideReason
	variable bool Hiding = FALSE

	method Initialize()
	{
		Event[OnFrame]:AttachAtom[This:Pulse]
		UI:UpdateConsole["Thread: obj_Defense: Initialized", LOG_MINOR]
	}

	method Pulse()
	{
		if !${Script[EVEBot](exists)}
		{
			return
		}

		; Commented out for now - I want the bot to handle automatic defense when it's
		; loaded, as a background task. - CyberTech
		;if ${EVEBot.Paused}
		;{
		;	return
		;}

		if ${Time.Timestamp} >= ${This.NextPulse.Timestamp}
		{
			if ${This.Running}
			{
				This:TakeDefensiveAction[]
				This:CheckTankMinimums[]
				This:CheckLocal[]
				This:CheckAmmo[]

				if !${This.Hide} && ${This.Hiding} && ${This.TankReady}
				{
					UI:UpdateConsole["Thread: obj_Defense: No longer hiding"]
					This.Hiding:Set[FALSE]
				}
			}

			This.NextPulse:Set[${Time.Timestamp}]
			This.NextPulse.Second:Inc[${This.PulseIntervalInSeconds}]
			This.NextPulse:Update
		}
	}

	method CheckTankMinimums()
	{
		if !${Script[EVEBot](exists)}
		{
			return
		}

		if	${Ship.IsCloaked} || \
			${_Me.InStation}
		{
			return
		}

		if ${Ship.IsPod}
		{
			This:RunAway["We're in a pod! Run Away! Run Away!"]
		}

		if (${_Me.Ship.ArmorPct} < ${Config.Combat.MinimumArmorPct}  || \
			${_Me.Ship.ShieldPct} < ${Config.Combat.MinimumShieldPct} || \
			${_Me.Ship.CapacitorPct} < ${Config.Combat.MinimumCapPct})
		{
			UI:UpdateConsole["Armor is at ${_Me.Ship.ArmorPct.Int}%: ${Me.Ship.Armor.Int}/${Me.Ship.MaxArmor.Int}", LOG_CRITICAL]
			UI:UpdateConsole["Shield is at ${_Me.Ship.ShieldPct.Int}%: ${Me.Ship.Shield.Int}/${Me.Ship.MaxShield.Int}", LOG_CRITICAL]
			UI:UpdateConsole["Cap is at ${_Me.Ship.CapacitorPct.Int}%: ${Me.Ship.Capacitor.Int}/${Me.Ship.MaxCapacitor.Int}", LOG_CRITICAL]

			if !${Config.Combat.RunOnLowTank}
			{
				UI:UpdateConsole["Run On Low Tank Disabled: Fighting", LOG_CRITICAL]
			}
			elseif ${_Me.ToEntity.IsWarpScrambled}
			{
				UI:UpdateConsole["Warp Scrambled: Fighting", LOG_CRITICAL]
			}
			else
			{
				This:RunAway["Defensive Status"]
				return
			}
		}
	}

	; 3rd Parties should call this if they want Defense thread to initiate safespotting
	method RunAway(string Reason="Not Specified")
	{
		if !${Script[EVEBot](exists)}
		{
			return
		}

		This.Hide:Set[TRUE]
		This.HideReason:Set[${Reason}]
		if !${This.Hiding}
		{
			UI:UpdateConsole["Fleeing: ${Reason}", LOG_CRITICAL]
		}
	}

	method ReturnToDuty()
	{
		UI:UpdateConsole["Returning to duty", LOG_CRITICAL]
		This.Hide:Set[FALSE]
	}

	member:bool TankReady()
	{
		if !${Script[EVEBot](exists)}
		{
			return
		}

		if ${_Me.InStation}
		{
			return TRUE
		}

		;TODO:  These should be moved to config variables w/ UI controls
		variable int ArmorPctReady = 50
		variable int ShieldPctReady = 80
		variable int CapacitorPctReady = 80

		if  ${_Me.Ship.ArmorPct} < ${ArmorPctReady} || \
			(${_Me.Ship.ShieldPct} < ${ShieldPctReady} && ${Config.Combat.MinimumShieldPct} > 0) || \
			${_Me.Ship.CapacitorPct} < ${CapacitorPctReady}
		{
			return FALSE
		}

		return TRUE
	}

	method CheckLocal()
	{
		if !${Script[EVEBot](exists)}
		{
			return
		}

		if	${Ship.IsCloaked} || \
			${_Me.InStation}
		{
			return
		}

		if ${Social.IsSafe} == FALSE
		{
			if ${_Me.ToEntity.IsWarpScrambled}
			{
				; TODO - we need to quit if a red warps in while we're scrambled -- CyberTech
				UI:UpdateConsole["Warp Scrambled: Ignoring System Status"]
			}
			else
			{
				This:RunAway["Hostiles in Local"]
			}
		}
	}

	method CheckAmmo()
	{
		if !${Script[EVEBot](exists)}
		{
			return
		}

		; TODO - move this to offensive thread, and call back to Defense.RunAway() if necessary - CyberTech

		if	${Ship.IsCloaked} || \
			${_Me.InStation}
		{
			return
		}

		if ${Ship.IsAmmoAvailable} == FALSE
		{
			if ${Config.Combat.RunOnLowAmmo} == TRUE
			{
				; TODO - what to do about being warp scrambled in this case?
				This:RunAway["No Ammo!"]
			}
		}
	}

	function Flee()
	{
		if !${Script[EVEBot](exists)}
		{
			return
		}

		This.Hiding:Set[TRUE]
		echo ${SafeSpots.Count}
		if ${Config.Combat.RunToStation} || ${SafeSpots.Count} == 0
		{
			call This.FleeToStation
		}
		else
		{
			call This.FleeToSafespot
		}
	}

	function FleeToStation()
	{
		if !${Script[EVEBot](exists)}
		{
			return
		}

		if !${Station.Docked}
		{
			call Station.Dock
		}
	}

	function FleeToSafespot()
	{
		if !${Script[EVEBot](exists)}
		{
			return
		}

		if ${Safespots.IsAtSafespot}
		{
			if !${Ship.IsCloaked}
			{
				${Ship:Activate_Cloak[]
			}
		}
		else
		{
			; Are we at the safespot and not warping?
			if ${_Me.ToEntity.Mode} != 3
			{
				call Safespots.WarpToNext
				wait 30
			}
		}
	}

	method TakeDefensiveAction()
	{
		if !${Script[EVEBot](exists)}
		{
			return
		}

		;TODO: These should be moved to config variables w/ UI controls
		variable int ArmorPctEnable = 100
		variable int ArmorPctDisable = 98
		variable int ShieldPctEnable = 99
		variable int ShieldPctDisable = 95
		variable int CapacitorPctEnable = 20
		variable int CapacitorPctDisable = 80

		if	${Ship.IsCloaked} || \
			${_Me.InStation}
		{
			return
		}

		if ${_Me.Ship.ArmorPct} < ${ArmorPctEnable}
		{
			/* Turn on armor reps, if you have them
				Armor reps do not rep right away -- they rep at the END of the cycle.
				To counter this we start the rep as soon as any damage occurs.
			*/
			Ship:Activate_Armor_Reps[]
		}
		elseif ${_Me.Ship.ArmorPct} > ${ArmorPctDisable}
		{
			Ship:Deactivate_Armor_Reps[]
		}

		if (${_Me.ToEntity.Mode} == 3)
		{
			; We are in warp, we turn on shield regen so we can use up cap while it has time to regen
			if ${_Me.Ship.ShieldPct} < 99
			{
				Ship:Activate_Shield_Booster[]
			}
			else
			{
				Ship:Deactivate_Shield_Booster[]
			}
		}
		else
		{
			; We're not in warp, so use normal percentages to enable/disable
			if ${_Me.Ship.ShieldPct} < ${ShieldPctEnable} || ${Config.Combat.AlwaysShieldBoost}
			{
				Ship:Activate_Shield_Booster[]
			}
			elseif ${_Me.Ship.ShieldPct} > ${ShieldPctDisable} && !${Config.Combat.AlwaysShieldBoost}
			{
				Ship:Deactivate_Shield_Booster[]
			}
		}

		if ${_Me.Ship.CapacitorPct} < ${CapacitorPctEnable}
		{
			Ship:Activate_Cap_Booster[]
		}
		elseif ${_Me.Ship.CapacitorPct} > ${CapacitorPctDisable}
		{
			Ship:Deactivate_Cap_Booster[]
		}

		; Active shield (or armor) hardeners
		; If you don't have hardeners this code does nothing.
		; This uses shield and uncached GetTargetedBy (to reduce chance of a
		; volley making it thru before hardeners are up)
		if ${Me.GetTargetedBy} > 0 || ${_Me.Ship.ShieldPct} < 99
		{
			Ship:Activate_Hardeners[]
		}
		else
		{
			Ship:Deactivate_Hardeners[]
		}
	}
}

variable(global) obj_Defense Defense

function main()
{
	while ${Script[EVEBot](exists)}
	{
		if ${Defense.Hide}
		{
			call Defense.Flee
			wait 10 !${Script[EVEBot](exists)}
		}
		waitframe
	}
	echo "EVEBot exited, unloading ${Script.Filename}"
}