-- License https://www.gnu.org/licenses/gpl-3.0.en.html
-- OpenTX Lua script
-- TELEMETRY

-- File Locations On The Transmitter's SD Card
--  This script file  /SCRIPTS/WIDGETS/
--  Sound files       /SCRIPTS/WIDGETS/mahRe2/sounds/

-- Works On OpenTX Companion Version: 2.2
-- Works With Sensor: FrSky FAS40S, FCS-150A, FAS100, FLVS Voltage Sensors
--
-- Author: RCdiy
-- Web: http://RCdiy.ca
-- Date: 2016 June 28
-- Update: 2017 March 27
-- Update: 2019 November 21 by Dave Eccleston (Handles sensors returning a table of cell voltages)
-- Update: 2022 July 15 by David Morrison (Converted to OpenTX Widget for Horus and TX16S radios)
--
-- Re-authored: Dean Church
-- Date: 2017 March 25
-- Thanks: TrueBuild (ideas)
--
-- Re-Re-authored: David Morrison
-- Date: 2022 December 1
--
-- Changes/Additions:
-- 	Choose between using consumption sensor or voltage sensor to calculate
--		battery capacity remaining.
--	Choose between simple and detailed display.
--  Voice announcements of percentage remaining during active use.
--  After reset, warn if battery is not fully charged
--  After reset, check cells to verify that they are within VoltageDelta of each other


-- Description
-- 	Reads an OpenTX global variable to determine battery capacity in mAh
--		The sensors used are configurable
-- 	Reads an battery consumption sensor and/or a voltage sensor to
--		estimate mAh and % battery capacity remaining
--		A consumption sensor is a calculated sensor based on a current
--			sensor and the time elapsed.
--			http://rcdiy.ca/calculated-sensor-consumption/
-- 	Displays remaining battery mAh and percent based on mAh used
-- 	Displays battery voltage and remaining percent based on volts
--  Displays details such as minimum voltage, maximum current, mAh used, # of cells
-- 	Write remaining battery mAh to a Tx global variable
-- 	Write remaining battery percent to a Tx global variable
-- 		Writes are optional, off by default
--	Announces percentage remaining every 10% change
--		Announcements are optional, on by default
-- Reserve Percentage
-- 	All values are calculated with reference to this reserve.
--	% Remaining = Estimated % Remaining - Reserve %
--	mAh Remaining = Calculated mAh Remaining - (Size mAh x Reserve %)
--	The reserve is configurable, 20% is the set default
-- 	The following is an example of what is displayed at start up
-- 		800mAh remaining for a 1000mAh battery
--		80% remaining
--
--
-- 	Notes & Suggestions
-- 		The OpenTX global variables (GV) have a 1024 limit.
-- 		mAh values are stored in them as mAh/100
-- 		2800 mAh will be 28
-- 		800 mAh will be 8
--
-- 	 The GVs are global to that model, not between models.
-- 	 Standardize across your models which GV will be used for battery
-- 		capacity. For each model you can set different battery capacities.
-- 	  E.g. If you use GV7 for battery capacity/size then
--					Cargo Plane GV7 = 27
--					Quad 250 has GV7 = 13
--
--	Use Special Functions and Switches to choose between different battery
--		capacities for the same model.
--	E.g.
--		SF1 SA-Up Adjust GV7 Value 10 ON
--		SF2 SA-Mid Adjust GV7 Value 20 ON
--	To play your own announcements replace the sound files provided or
--		turn off sounds
-- 	Use Logical Switches (L) and Special Functions (SF) to play your own sound tracks
-- 		E.g.
-- 			L11 - GV9 < 50
-- 			SF4 - L11 Play Value GV9 30s
-- 			SF5 - L11 Play Track #PrcntRm 30s
-- 				After the remaining battery capacity drops below 50% the percentage
-- 				remaining will be announced every 30 seconds.
-- 	L12 - GV9 < 10
-- 	SF3 - L12 Play Track batcrit
-- 				After the remaining battery capacity drops below 50% a battery
-- 				critical announcement will be made every 10 seconds.

-- Configurations
--  For help using telemetry scripts
--    http://rcdiy.ca/telemetry-scripts-getting-started/
local Title = "Flight Battery Monitor"
local name = "mahRe2"

-- Sensors
-- 	Use Voltage and or mAh consumed calculated sensor based on VFAS, FrSky FAS-40
-- 	Use sensor names from OpenTX TELEMETRY screen
--  If you need help setting up a consumption sensor visit
--		http://rcdiy.ca/calculated-sensor-consumption/
-- Change as desired
local VoltageSensor = "Cels" -- optional set to "" to ignore
local mAhSensor = "mAh" -- optional set to "" to ignore
local CurrentSensor = "Curr"
local ThrottleId = 1

-- Reserve Capacity
-- 	Remaining % Displayed = Calculated Remaining % - Reserve %
-- Change as desired
local CapacityReservePercent = 20 -- set to zero to disable

-- Switch used to reset the voltage checking features.
--  typically set to the same switch used to reset timers
local SwReset = "sh"

--   Value used when checking to see if the cell is full for the check_for_full_battery check
local CellFullVoltage = 4.0

--   Value used to when comparing cell voltages to each other.
--    if any cell gets >= VoltageDelta volts of the other cells
--    then play the Inconsistent Cell Warning message
local VoltageDelta = .3

-- Announcements
local soundDirPath = "/WIDGETS/mahRe2/sounds/" -- where you put the sound files
local AnnouncePercentRemaining = true -- true to turn on, false for off

-- Do not change the next line
local GV = {[1] = 0, [2] = 1, [3] = 2,[4] = 3,[5] = 4,[6] = 5, [7] = 6, [8] = 7, [9] = 8}

-- OpenTX Global Variables (GV)
--	These are global to the model and not between models.
--
--	Each flight mode (FM) has its own set of GVs. Using this script you could
--		be flying in FM 0 but access variables from FM 8. This is useful when
--		when running out of GVs available to use.
--		Most users can leave the flight mode setting at the default value.
--
--	If you have configured mAhSensor = "" then ignore GVBatCap
-- 	GVBatCap - Battery capacity provided as mAh/100,
--									2800 mAh would be 28, 800 mAh would be 8
--
-- Change as desired
-- Use GV[6] for GV6, GV[7] for GV7 and so on
local GVCellCount = GV[6] -- Read the number of cells
local GVBatCap = GV[7] 	-- Read Battery Capacity, 8 for 800mAh, 22 for 2200mAh
-- The corresponding must be set under the FLIGHT MODES
-- screen on the Tx.
-- If the GV is 0 or not set on the Tx then
-- % remaining is calculated based on battery voltage
-- which may not be as accurate.
local GVFlightMode = 0 -- Use a different flight mode if running out of GVs

-- ----------------------------------------------------------------------------------------
-- ----------------------------------------------------------------------------------------
-- AVOID EDITING BELOW HERE
--
local DEBUG = false

local CanCallInitFuncAgain = false		-- updated in bg_func

-- Calculations
local UseVoltsNotmAh	-- updated in init_func
local BatCapFullmAh		-- updated in init_func
local BatCapmAh				-- updated in init_func
local BatUsedmAh 			-- updated in bg_func
local BatRemainmAh 		-- updated in init_func, bg_func
local BatRemPer 			-- updated in init_func, bg_func
local VoltsPercentRem -- updated in init_func, bg_func
local VoltsNow 	= 0			-- updated in bg_func
local CellCount 			-- updated in init_func, bg_func

function loadSched()
	if not libSCHED then
	-- Loadable code chunk is called immediately and returns libGUI
		libSCHED = loadScript("/WIDGETS/" .. name .. "/libscheduler.lua")
	end

	return libSCHED()
end
libscheduler = libscheduler or loadSched()
local scheduler = libscheduler.new()

function loadHistory()
	if not libHISTORY then
	-- Loadable code chunk is called immediately and returns libGUI
		libHISTORY = loadScript("/WIDGETS/" .. name .. "/libhistory.lua")
	end

	return libHISTORY()
end
libhistory = libhistory or loadHistory()
local history = libhistory.new(ThrottleId, CurrentSensor, VoltageSensor)

-- Voltage Checking flags
local CheckBatNotFull = true

-- Announcements
local BatRemPerFileName = 0		-- updated in PlayPercentRemaining
local BatRemPerPlayed = 0			-- updated in PlayPercentRemaining
local AtZeroPlayedCount				-- updated in init_func, PlayPercentRemaining
local PlayAtZero = 1

-- Display
local fontSize

local BlinkWhenZero = 0 -- updated in run_func
local Color = BLACK

-- Based on results from http://rcdiy.ca/taranis-q-x7-battery-run-time/
local VoltToPercentTable = {
  {3.60, 10},{3.70, 15},{3.72, 20},{3.74, 25},
  {3.76, 30},{3.78, 35},{3.80, 40},{3.81, 45},
  {3.83, 50},{3.85, 55},{3.87, 60},{3.98, 65},
  {3.99, 70},{4.00, 75},{4.03, 80},{4.06, 85},
  {4.10, 90},{4.15, 95},{4.20, 100}
}

local SoundsTable = {[5] = "Bat5L.wav",[10] = "Bat10L.wav",[20] = "Bat20L.wav"
  ,[30] = "Bat30L.wav",[40] = "Bat40L.wav",[50] = "Bat50L.wav"
  ,[60] = "Bat60L.wav",[70] = "Bat70L.wav",[80] = "Bat80L.wav"
  ,[90] = "Bat90L.wav"}

-- ####################################################################
local function getThrottlePercentValue(rawThrottle )
  -- read the throttle value and return it as a percentage
  -- -1000  == 0%
  -- 0      == 50%
  -- 1000   == 100%
  return 50 + rawThrottle/20
end


-- ####################################################################
local function findPercentRem( cellVoltage )
  if cellVoltage > 4.200 then
    return 100
  elseif	cellVoltage < 3.60 then
    return 0
  else
    -- method of finding percent in my array provided by on4mh (Mike)
    for i, v in ipairs( VoltToPercentTable ) do
      if v[ 1 ] >= cellVoltage then
        return v[ 2 ]
      end
    end
  end
end

-- ####################################################################
local function PlayPercentRemaining()
  -- Announces percent remaining using the accompanying sound files.
  -- Announcements ever 10% change when percent remaining is above 10 else
  --	every 5%
  local myModVal

  if BatRemPer < 10 then
    myModVal = BatRemPer % 5
  else
    myModVal = BatRemPer % 10
  end

  if myModVal == 0 and BatRemPer ~= BatRemPerPlayed then
    BatRemPerFileName = ""
    BatRemPerFileName = (SoundsTable[BatRemPer])
    if BatRemPerFileName ~= nil then
      playFile(soundDirPath..BatRemPerFileName)
      BatRemPerPlayed = BatRemPer	-- do not keep playing the same sound file over and
    end
  end

  if BatRemPer <= 0 and AtZeroPlayedCount < PlayAtZero and getRSSI() > 0 then
    print(BatRemPer,AtZeroPlayedCount)
    playFile(soundDirPath.."BatNo.wav")
    AtZeroPlayedCount = AtZeroPlayedCount + 1
  elseif AtZeroPlayedCount == PlayAtZero and BatRemPer > 0 then
    AtZeroPlayedCount = 0
  end
end

-- ####################################################################
local function check_for_full_battery()
  -- check condition 1: at reset that all voltages > CellFullVoltage volts
  --print(string.format("CheckBatNotFull: %s type: %s", CheckBatNotFull, type(voltageSensorValue)))
  if CheckBatNotFull and VoltageSensor ~= "" then  -- global variable to gate this so this check is only done once after reset
    local playBatNotFullWarning = false
    local voltageSensorValue  = getValue(VoltageSensor)
    if (type(voltageSensorValue) == "table") then -- check to see if this is the dedicated voltage sensor
      --print("flvss cell detection")
      for i, v in ipairs(voltageSensorValue) do
        if v < CellFullVoltage then
          --print(string.format("flvss i: %d v: %f", i,v))
          playBatNotFullWarning = true
          break
        end
      end
      CheckBatNotFull = false  -- since we have done the check, set to false so it is not ran again
    elseif VoltageSensor == "VFAS" and type(voltageSensorValue) == "number" then --this is for the vfas sensor
      if voltageSensorValue < (CellFullVoltage * CellCount ) then
        playBatNotFullWarning = true
      end
      CheckBatNotFull = false  -- since we have done the check, set to false so it is not ran again
    end
    if playBatNotFullWarning then
      playFile(soundDirPath.."BNFull.wav")
      playBatNotFullWarning = false
    end
  end -- CheckBatNotfull
end

-- ####################################################################
local function check_cell_delta_voltage(voltageSensorValue)
  -- Check to see if all cells are within VoltageDelta volts of each other
  --  default is .3 volts, can be changed above
  if (type(voltageSensorValue) == "table") then -- check to see if this is the dedicated voltage sensor
    for i, v1 in ipairs(voltageSensorValue) do
      for j,v2 in ipairs(voltageSensorValue) do
        -- print(string.format("i: %d v: %f j: %d v: %f", i, v1, j,v2))
        if i~=j and (math.abs(v1 - v2) > VoltageDelta) then
          --print(string.format("i: %d v: %f j: %d v: %f", i, v1, j,v2))
          scheduler.add("icw", 10, playFile, soundDirPath.."icw.wav")
          return
        end
      end
    end
    scheduler.remove("icw")
  end
end

-- ####################################################################
local function check_for_missing_cells(voltageSensorValue)
  -- If the number of cells detected by the voltage sensor does not match the value in GV6 then play the warning message
  -- This is only for the dedicated voltage sensor
  --print(string.format("CellCount: %d voltageSensorValue:", CellCount))
  if CellCount > 0 then
    if type(voltageSensorValue) == "table" and #voltageSensorValue ~= CellCount then
      --print(string.format("CellCount: %d tableSize: %d", CellCount, tableSize))
      scheduler.add("mcw", 10, playFile, soundDirPath.."mcw.wav")
      return
    elseif VoltageSensor == "VFAS" and type(voltageSensorValue) == "number" and (CellCount * 3.2) > voltageSensorValue then
        --print(string.format("vfas missing cell: %d", voltageSensorValue))
        scheduler.add("mcw", 10, playFile, soundDirPath.."mcw.wav")
        return
    end
    scheduler.remove("mcw")
  end
end

-- ####################################################################
local function voltage_sensor_tests()
  -- 1. at reset check to see that the cell voltage is > 4.1 for all cellSum
  -- 2. check to see that all cells are within VoltageDelta volts of each other
  -- 3. if number of cells are set in GV6, check to see that all are showing voltage

  --print("check_initial_battery_voltage")

  -- check condition 1: at reset that all voltages > 4.0 volts
  check_for_full_battery()

  if history.now ~= nil and history.now.voltage ~= nil then
    --print("getting VoltageSensor data")
    cellResult = history.now.voltage

    -- check condition 2: delta voltage
      check_cell_delta_voltage(cellResult)

    -- check condition 3: all cells present
      check_for_missing_cells(cellResult)

  end
end

-- ####################################################################
local function init_func()
  -- Called once when model is loaded
  BatCapFullmAh = model.getGlobalVariable(GVBatCap, GVFlightMode) * 100
  -- BatCapmAh = BatCapFullmAh
  BatCapmAh = BatCapFullmAh * (100-CapacityReservePercent)/100
  BatRemainmAh = BatCapmAh
  CellCount = model.getGlobalVariable(GVCellCount, GVFlightMode)
  VoltsPercentRem = 0
  BatRemPer = 0
  AtZeroPlayedCount = 0
  if (mAhSensor == "") or (BatCapmAh == 0) then
    UseVoltsNotmAh = true
  else
    UseVoltsNotmAh = false
  end
end

-- ####################################################################
local function reset_if_needed()
  -- test if the reset switch is toggled, if so then reset all internal flags
  -- print("reset_sw: " .. getValue(SwReset))
  if SwReset ~= "" then -- Update switch position
    --if ResetDebounced and HasSecondsElapsed(2) and -1024 ~= getValue(SwReset) then -- reset switch
    local debounced = scheduler.check('reset_sw')
    if (debounced == nil or debounced == true) and -1024 ~= getValue(SwReset) then -- reset switch
      scheduler.add('reset_sw', 2)
      scheduler.clear('reset_sw')
      print("reset switch toggled")
      CheckBatNotFull = true
      VoltsNow = 0
      scheduler.reset()
      history = libhistory.new(ThrottleId, CurrentSensor, VoltageSensor)
      --print("reset event")
    elseif -1024 == getValue(SwReset) then
      scheduler.remove('reset_sw')
    end
  end
end

-- ####################################################################
local function bg_func()

  reset_if_needed() -- test if the reset switch is toggled, if so then reset all internal flags
  scheduler.tick() -- deal with all scheduled tasks
  history.tick()

  -- Check in battery capacity was changed
  if BatCapFullmAh ~= model.getGlobalVariable(GVBatCap, GVFlightMode) * 100 then
    init_func()
  end

  if mAhSensor ~= "" then
    BatUsedmAh = getValue(mAhSensor)
    if (BatUsedmAh == 0) and CanCallInitFuncAgain then
      -- BatUsedmAh == 0 when Telemetry has been reset or model loaded
      -- BatUsedmAh == 0 when no battery used which could be a long time
      --	so don't keep calling the init_func unnecessarily.
      init_func()
      CanCallInitFuncAgain = false
    elseif BatUsedmAh > 0 then
      -- Call init function again when Telemetry has been reset
      CanCallInitFuncAgain = true
    end
    BatRemainmAh = BatCapmAh - BatUsedmAh
  end -- mAhSensor ~= ""

  if VoltageSensor ~= "" then
    volts = history.getTotalVolts()
    if VoltsNow < 1 or volts > 1 then
      VoltsNow = volts
    end

    if CellCount > 0 then
      VoltsPercentRem  = findPercentRem( VoltsNow/CellCount )
    end
  end

  -- Update battery remaining percent
  if UseVoltsNotmAh then
    BatRemPer = VoltsPercentRem - CapacityReservePercent
  elseif BatCapmAh > 0 then
    BatRemPer = math.floor( (BatRemainmAh / BatCapFullmAh) * 100 )
  end
  if AnnouncePercentRemaining then
    PlayPercentRemaining()
  end
  voltage_sensor_tests()
end

-- ####################################################################
local function getPercentColor(cpercent)
  -- This function returns green at 100%, red bellow 30% and graduate in between
  if cpercent < 30 then
    return lcd.RGB(0xff, 0, 0)
  else
    g = math.floor(0xdf * cpercent / 100)
    r = 0xdf - g
    return lcd.RGB(r, g, 0)
  end
end

-- ####################################################################
local function formatCellVoltage(voltage)
  if type(voltage) == "number" then
    vColor, blinking = Color, 0
    if voltage < 3.7 then vColor, blinking = RED, BLINK end
    return string.format("%.2f", voltage), vColor, 0
  else
    return "------", Color, 0
  end
end

-- ####################################################################
local function drawCellVoltage(wgt)
  -- Draw the voltage table for the current/low cell voltages
  -- this should use ~1/4 screen
  local cell1, cell1Color, cell1Blink
  local history1, history1Color, history1Blink
  local cell2, cell2Color, cell2Blink
  local history2, history2Color,history2Blink

  local cellResult = {}
  if history.now and history.now.voltage then
    cellResult = history.now.voltage
  end

  for i=1, 7, 2 do
    cell1, cell1Color, cell1Blink = formatCellVoltage(cellResult[i])
    history1, history1Color, history1Blink = formatCellVoltage(history.cellLowVoltage[i])
    cell2, cell2Color, cell2Blink = formatCellVoltage(cellResult[i+1])
    history2, history2Color, history2Blink = formatCellVoltage(history.cellLowVoltage[i+1])

    -- C1: C.cc/H.hh  C2: C.cc/H.hh
    lcd.drawText(wgt.zone.x, wgt.zone.y  + 10*(i-1), string.format("C%d:", i), Color)
    lcd.drawText(wgt.zone.x + 25, wgt.zone.y  + 10*(i-1), string.format("%s", cell1), cell1Color+cell1Blink)
    lcd.drawText(wgt.zone.x + 55, wgt.zone.y  + 10*(i-1), string.format("/"), Color)
    lcd.drawText(wgt.zone.x + 60, wgt.zone.y  + 10*(i-1), string.format("%s", history1), history1Color+history1Blink)

    lcd.drawText(wgt.zone.x + 100, wgt.zone.y  + 10*(i-1), string.format("C%d:", i+1), Color)
    lcd.drawText(wgt.zone.x + 125, wgt.zone.y  + 10*(i-1), string.format("%s", cell2), cell2Color+cell2Blink)
    lcd.drawText(wgt.zone.x + 155, wgt.zone.y  + 10*(i-1), string.format("/"), Color)
    lcd.drawText(wgt.zone.x + 160, wgt.zone.y  + 10*(i-1), string.format("%s", history2), history2Color+history2Blink)
  end
end

-- ####################################################################
local function drawBattery(xOrigin, yOrigin, wgt)
    local myBatt = { ["x"] = xOrigin,
                     ["y"] = yOrigin,
                     ["w"] = 85,
                     ["h"] = 35,
                     ["segments_w"] = 15,
                     ["color"] = WHITE,
                     ["cath_w"] = 6,
                     ["cath_h"] = 20 }

  --lcd.setColor(CUSTOM_COLOR, wgt.options.Color)

  if BatRemPer > 0 then -- Don't blink
    BlinkWhenZero = 0
  else
    BlinkWhenZero = BLINK
  end

  -- fill batt
  lcd.setColor(CUSTOM_COLOR, getPercentColor(BatRemPer))
  lcd.drawGauge(wgt.zone.x + myBatt.x, wgt.zone.y + myBatt.y, myBatt.w, myBatt.h, BatRemPer, 100, CUSTOM_COLOR)

  -- draws bat
  lcd.setColor(CUSTOM_COLOR, WHITE)
  lcd.drawRectangle(wgt.zone.x + myBatt.x, wgt.zone.y + myBatt.y, myBatt.w, myBatt.h, CUSTOM_COLOR, 2)
  lcd.drawFilledRectangle(wgt.zone.x + myBatt.x + myBatt.w,
          --wgt.zone.y + myBatt.h / 2 - myBatt.cath_h / 2,
          wgt.zone.y + myBatt.y + myBatt.cath_h / 2 - 2.5,
          myBatt.cath_w,
          myBatt.cath_h,
          CUSTOM_COLOR)
  lcd.drawText(wgt.zone.x + myBatt.x + 20, wgt.zone.y + myBatt.y + 5, string.format("%d%%", BatRemPer), LEFT + MIDSIZE + CUSTOM_COLOR)

    -- draw values
  lcd.drawText(wgt.zone.x + myBatt.x, wgt.zone.y + myBatt.y + 35,
          string.format("%d mAh", BatRemainmAh), DBLSIZE + Color + BlinkWhenZero)
end

-- ####################################################################
local function refreshZoneTiny(wgt)
  -- This size is for top bar wgts
  --- Zone size: 70x39 1/8th top bar
  local myString = string.format("%d", BatRemainmAh)
  lcd.drawText(wgt.zone.x + wgt.zone.w -25, wgt.zone.y + 5, BatRemPer .. "%", RIGHT + SMLSIZE + CUSTOM_COLOR + BlinkWhenZero)
  lcd.drawText(wgt.zone.x + wgt.zone.w -25, wgt.zone.y + 20, myString, RIGHT + SMLSIZE + CUSTOM_COLOR + BlinkWhenZero)
  -- draw batt
  lcd.drawRectangle(wgt.zone.x + 50, wgt.zone.y + 9, 16, 25, CUSTOM_COLOR, 2)
  lcd.drawFilledRectangle(wgt.zone.x +50 + 4, wgt.zone.y + 7, 6, 3, CUSTOM_COLOR)
  local rect_h = math.floor(25 * BatRemPer / 100)
  lcd.drawFilledRectangle(wgt.zone.x +50, wgt.zone.y + 9 + 25 - rect_h, 16, rect_h, CUSTOM_COLOR + BlinkWhenZero)
end

-- ####################################################################
local function refreshZoneSmall(wgt)
  --- Size is 160x32 1/8th
  local myBatt = { ["x"] = 0, ["y"] = 0, ["w"] = 155, ["h"] = 35, ["segments_w"] = 25, ["color"] = WHITE, ["cath_w"] = 6, ["cath_h"] = 20 }

  -- draws bat
  lcd.setColor(CUSTOM_COLOR, WHITE)
  lcd.drawRectangle(wgt.zone.x + myBatt.x, wgt.zone.y + myBatt.y, myBatt.w, myBatt.h, CUSTOM_COLOR, 2)

  -- fill batt
  lcd.setColor(CUSTOM_COLOR, getPercentColor(BatRemPer))
  lcd.drawGauge(wgt.zone.x + 2, wgt.zone.y + 2, myBatt.w - 4, wgt.zone.h, BatRemPer, 100, CUSTOM_COLOR)

  -- write text
  --lcd.setColor(CUSTOM_COLOR, wgt.options.Color)
  local topLine = string.format("%d      %d%%", BatRemainmAh, BatRemPer)
  lcd.drawText(wgt.zone.x + 20, wgt.zone.y + 2, topLine, MIDSIZE + CUSTOM_COLOR + BlinkWhenZero)
end

-- ####################################################################
local function refreshZoneMedium(wgt)
  --- Size is 225x98 1/4th  (no sliders/trim)
  drawBattery(0,0, wgt)
end

-- ####################################################################
local function refreshZoneLarge(wgt)
  --- Size is 192x152 1/2
  --lcd.setColor(CUSTOM_COLOR, wgt.options.Color)
  
  fontSize = 10
  
    if BatRemPer > 0 then -- Don't blink
    BlinkWhenZero = 0
  else
    BlinkWhenZero = BLINK
  end
  lcd.drawText(wgt.zone.x + 5, wgt.zone.y + fontSize, "BATTERY LEFT", SHADOWED)
  lcd.setColor(CUSTOM_COLOR, getPercentColor(BatRemPer))
  lcd.drawText(wgt.zone.x + 5, wgt.zone.y + fontSize + 25, round(BatRemPer).."%" , DBLSIZE + SHADOWED + BlinkWhenZero)
  lcd.drawText(wgt.zone.x + 5, wgt.zone.y + fontSize + 55, math.floor(BatRemainmAh).."mAh" , DBLSIZE + SHADOWED + BlinkWhenZero)

  --lcd.setColor(CUSTOM_COLOR, wgt.options.Color)
  lcd.drawRectangle((wgt.zone.x - 1) , (wgt.zone.y + (wgt.zone.h - 31)), (wgt.zone.w + 2), 32, 0)
  lcd.setColor(CUSTOM_COLOR, getPercentColor(BatRemPer))
  lcd.drawGauge(wgt.zone.x , (wgt.zone.y + (wgt.zone.h - 30)), wgt.zone.w, 30, BatRemPer, 100, BlinkWhenZero)
end

-- ####################################################################

local function refreshZoneXLarge(wgt)
  --- Size is 390x172 1/1
  --- Size is 460x252 1/1 (no sliders/trim/topbar)
  --lcd.setColor(CUSTOM_COLOR, wgt.options.Color)
  fontSize = 10

  if BatRemPer > 0 then -- Don't blink
    BlinkWhenZero = 0
  else
    BlinkWhenZero = BLINK
  end

  -- Draw the top-left 1/4 of the screen
  drawCellVoltage(wgt)

  -- Draw the bottom-left 1/4 of the screen
  drawBattery(0, 100, wgt)

  -- Draw the top-right 1/4 of the screen
  --lcd.drawText(wgt.zone.x + 270, wgt.zone.y + -5, string.format("%.2fV", VoltsNow), DBLSIZE + Color)
  lcd.drawText(wgt.zone.x + 210, wgt.zone.y + -5, "Current/Max", DBLSIZE + Color + SHADOWED)
  local amps = 0
  if history.now and history.now.amps then
    amps = history.now.amps
  end

  --print("maxAmps:", history.maxAmps)
  if type(history.maxAmps) == 'string' then
    lcd.drawText(wgt.zone.x + 210, wgt.zone.y + 30, string.format("%.0fA/%s", amps, history.maxAmps), MIDSIZE + Color)
  else
    lcd.drawText(wgt.zone.x + 210, wgt.zone.y + 30, string.format("%.0fA/%.0fA", amps, history.maxAmps), MIDSIZE + Color)
  end
  watts = math.floor(amps * VoltsNow)

  if type(history.maxWatts) == "string" then
    sMaxWatts = history.maxWatts
  elseif type(history.maxWatts) == "number" then
    sMaxWatts = string.format("%.0f", history.maxWatts)
  end
  lcd.drawText(wgt.zone.x + 210, wgt.zone.y + 55, string.format("%.0fW/%sW", watts, sMaxWatts), MIDSIZE + Color)

  -- Draw the bottom-right of the screen
  --lcd.drawText(wgt.zone.x + 190, wgt.zone.y + 85, string.format("%sW", MaxWatts), XXLSIZE + Color)
  lcd.drawText(wgt.zone.x + 185, wgt.zone.y + 85, string.format("%.2fV", VoltsNow), XXLSIZE + Color)

end

-- ####################################################################
function create(zone, options)
  init_func()
  local Context = { zone=zone, options=options }
  return Context
end

-- ####################################################################
function update(Context, options)
  mAhSensor = options.mAh
  VoltageSensor = options.Voltage
  CurrentSensor = options.Current
  --Color = options.Color
  Context.options = options
  Context.back = nil
  SwReset = options.Reset
  ThrottleId = options.Throttle
end

-- ####################################################################
function background(Context)
  bg_func()
end

-- ####################################################################
function refresh(wgt, event, touchState)
  -- Called periodically when screen is visible
  if event == nil then -- Widget mode
    bg_func()
    if     wgt.zone.w  > 380 and wgt.zone.h > 165 then refreshZoneXLarge(wgt)
    elseif wgt.zone.w  > 180 and wgt.zone.h > 145 then refreshZoneLarge(wgt)
    elseif wgt.zone.w  > 170 and wgt.zone.h >  65 then refreshZoneMedium(wgt)
    elseif wgt.zone.w  > 150 and wgt.zone.h >  28 then refreshZoneSmall(wgt)
    elseif wgt.zone.w  >  65 and wgt.zone.h >  35 then refreshZoneTiny(wgt)
    end
  else
    print("full screen")
  end
end

local options = {
  { "mAh", SOURCE, mAh }, -- Defines source Battery Current Sensor
  { "Voltage", SOURCE, Cels }, -- Defines source Battery Voltage Sensor
  { "Current", SOURCE, Curr },
  { "Reset", SOURCE, 125 }, -- Defines the switch to use to reset the stored data
  { "Throttle", SOURCE, 1 }, -- 204==CH3
  -- { "Color", COLOR, GREY },
}

return { name="mahRe2", options=options, create=create, update=update, refresh=refresh, background=background }