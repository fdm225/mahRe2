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
-- Update: 2019 November 21 by daveEccleston (Handles sensors returning a table of cell voltages)
-- Update: 2022 July 15 by David Morrison (Converted to OpenTX Widget for Horus and TX16S radios)
--
-- Reauthored: Dean Church
-- Date: 2017 March 25
-- Thanks: TrueBuild (ideas)
--
-- Changes/Additions:
-- 	Choose between using consumption sensor or voltage sensor to calculate
--		battery capacity remaining.
--	Choose between simple and detailed display.
--  Voice announcements of percentage remaining during active use.


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
--  Displays details such as minumum voltage, maximum current, mAh used, # of cells
--	Switchs between simple and detailed display using a switch
--		Switch is optional and configurable, SF down by default
-- 	Write remaining battery mAh to a Tx global variable
-- 	Write remaining battery percent to a Tx global variable
-- 		Writes are optional, off by default
--	Announces percentage remaining every 10% change
--		Announcements are optional, off by default
-- Reserve Percentage
-- 	All values are calculated with reference to this reserve.
--	% Remaining = Estimated % Remaining - Reserve %
--	mAh Remaining = Calculated mAh Remaining - (Size mAh x Reserve %)
--	The reserve is configurable, 20% is the set default
-- 	The following is an example of what is dislayed at start up
-- 		800mAh remaining for a 1000mAh battery
--		80% remaining
--
-- 	Notes & Suggestions
-- 		The OpenTX global variables (GV) have a 1024 limit.
-- 		mAh values are stored in them as mAh/100
-- 		2800 mAh will be 28
-- 		800 mAh will be 8
--
-- 	 The GVs are global to that model, not between models.
-- 	 Standardize accross your models which GV will be used for battery
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
-- 				After the remaining battery capicity drops below 50% the percentage
-- 				remaining will be announced every 30 seconds.
-- 	L12 - GV9 < 10
-- 	SF3 - L12 Play Track batcrit
-- 				After the remaining battery capicity drops below 50% a battery
-- 				critical announcement will be made every 10 seconds.

-- Configurations
--  For help using telemetry scripts
--    http://rcdiy.ca/telemetry-scripts-getting-started/
local Title = "Flight Battery Monitor"

-- Sensors
-- 	Use Voltage and or mAh consumed calculated sensor based on VFAS, FrSky FAS-40
-- 	Use sensor names from OpenTX TELEMETRY screen
--  If you need help setting up a consumption sensor visit
--		http://rcdiy.ca/calculated-sensor-consumption/
-- Change as desired
local VoltageSensor = "VFAS" -- optional set to "" to ignore
local mAhSensor = "mAh" -- optional set to "" to ignore

-- Reserve Capacity
-- 	Remaining % Displayed = Calculated Remaining % - Reserve %
-- Change as desired
local CapacityReservePercent = 20 -- set to zero to disable

--	Switch between simple and detailed display using a switch
-- 	SA to SH Taranis X9 series, Q X7 missing switches SE and SG
-- 	Use "sa" for switch A and so on.
-- 	Change as desired
local SwVerbose = "sf"	-- "" to ignore
local SwVerboseOnPos = "Down"	-- Up, Mid, Down

-- Announcements
local soundDirPath = "/WIDGETS/mahRe2/sounds/" -- where you put the sound files
local AnnouncePercentRemaining = true -- true to turn on, false for off
local SillyStuff = true  -- Play some silly/fun sounds

-- Do not change the next line
local GV = {[1] = 0, [2] = 1, [3] = 2,[4] = 3,[5] = 4,[6] = 5, [7] = 6, [8] = 7, [9] = 8}

-- OpenTX Global Variables (GV)
--	These are global to the model and not between models.
--
--	Each flight mode (FM) has its own set of GVs. Using this script you could
--		be flying in FM 0 but access variables from FM 8. This is usefull when
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

local WriteGVBatRemmAh = false-- set to false to turn off write
local WriteGVBatRemPer = false
-- If writes are false then the corresponding GV below will not be used and these
--	lines can be ignored.
local GVBatRemmAh = GV[8] -- Write remaining mAh, 2345 mAh will be writen as 23, floor(2345/100)
local GVBatRemPer = GV[9] -- Write remaining percentage, 76.7% will be writen as 76, floor(76)

-- If you have set either write to false you may set the corresponding
--	variable to ""
-- example local GVBatRemmAh = ""

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
local VoltsNow 				-- updated in bg_func
local CellCount 			-- updated in init_func, bg_func
local VoltsMax 				-- updated in bg_func

-- Announcements
local BatRemPerFileName = 0		-- updated in PlayPercentRemaining
local BatRemPerPlayed = 0			-- updated in PlayPercentRemaining
local AtZeroPlayedCount				-- updated in init_func, PlayPercentRemaining
local PlayAtZero = 1
--local RxOperational = false
--local BatteryFound = false

-- Display
local SwVerbosePos = -1			-- updated in bg_func
local SwUp = -1024 	-- value returned for switch in up/away position
local SwMid = 0
local SwDown = 1024
local SwVerboseOnValue = 0

local x, y, fontSize, yColumn2
local xAlign = 0

local BlinkWhenZero = 0 -- updated in run_func
local Color = GREY

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
local function getCellVoltage( voltageSensorIn ) 
  -- For voltage sensors that return a table of sensors, add up the cell 
  -- voltages to get a total cell voltage.
  -- Otherwise, just return the value
  cellResult = getValue( voltageSensorIn )
  cellSum = 0

  if (type(cellResult) == "table") then
    for i, v in ipairs(cellResult) do
      cellSum = cellSum + v
    end
  else 
    cellSum = cellResult
  end

  return cellSum
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
    if SillyStuff then
      playFile(soundDirPath.."Scrash.wav")
      playFile(soundDirPath.."Samblc.wav")
      --playFile(soundDirPath.."WrnWzz.wav")
    end
    AtZeroPlayedCount = AtZeroPlayedCount + 1
  elseif AtZeroPlayedCount == PlayAtZero and BatRemPer > 0 then
    AtZeroPlayedCount = 0
  end
  -- elseif BatRemPer > 0 and AtZeroPlayedCount == PlayAtZero then
  -- 	-- Will happen when voltage based battery remaining percent
  -- 	-- Battery replaced without a Tx telemetry reset, model change or off+on
  -- 	AtZeroPlayedCount = 0
  -- end

end

-- ####################################################################
-- ####################################################################
local function init_func()
  -- Called once when model is loaded
  BatCapFullmAh = model.getGlobalVariable(GVBatCap, GVFlightMode) * 100
  -- BatCapmAh = BatCapFullmAh
  BatCapmAh = BatCapFullmAh * (100-CapacityReservePercent)/100
  BatRemainmAh = BatCapmAh
  CellCount = model.getGlobalVariable(GVBatCap, GVCellCount)
  VoltsPercentRem = 0
  BatRemPer = 0
  AtZeroPlayedCount = 0
  if (mAhSensor == "") then -- or (BatCapmAh == 0) then
    UseVoltsNotmAh = true
  else
    UseVoltsNotmAh = false
  end

  if SwVerboseOnPos == "Up" then
    SwVerboseOnValue = SwUp
  elseif SwVerboseOnPos == "Mid" then
    SwVerboseOnValue = SwMid
  elseif SwVerboseOnPos == "Down" then
    SwVerboseOnValue = SwDown
  end
end


-- ####################################################################
-- ####################################################################
local function bg_func()
  -- Update switch position
  
  if SwVerbose ~= "" then
    SwVerbosePos = getValue(SwVerbose)
  end
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
    VoltsNow = getCellVoltage(VoltageSensor)
    VoltsMax = getCellVoltage(VoltageSensor.."+")
    --CellCount = math.ceil(VoltsMax / 4.25)
    if CellCount > 0 then
      VoltsPercentRem  = findPercentRem( VoltsNow/CellCount )
    end
  end

  -- Update battery remaining percent
  if UseVoltsNotmAh then
    BatRemPer = VoltsPercentRem - CapacityReservePercent
    --elseif BatCapFullmAh > 0 then
  elseif BatCapmAh > 0 then
    -- BatRemPer = math.floor( (BatRemainmAh / BatCapFullmAh) * 100 ) - CapacityReservePercent
    BatRemPer = math.floor( (BatRemainmAh / BatCapFullmAh) * 100 )
  end
  if AnnouncePercentRemaining then
    PlayPercentRemaining()
  end
  if WriteGVBatRemmAh == true then
    model.setGlobalVariable(GVBatRemmAh, GVFlightMode, math.floor(BatRemainmAh/100))
  end
  if WriteGVBatRemPer == true then
    model.setGlobalVariable(GVBatRemPer, GVFlightMode, BatRemPer)
  end
  print(string.format("BatRemainmAh: %d", BatRemainmAh))
  print(string.format("BatRemPer: %d", BatRemPer))
end
-- ####################################################################
-- This function returns green at 100%, red bellow 30% and graduate in betwwen
local function getPercentColor(cpercent)
  if cpercent < 30 then
    return lcd.RGB(0xff, 0, 0)
  else
    g = math.floor(0xdf * cpercent / 100)
    r = 0xdf - g
    return lcd.RGB(r, g, 0)
  end
end
-- ####################################################################
-- This size is for top bar wgts
--- Zone size: 70x39 1/8th top bar
local function refreshZoneTiny(wgt)
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
--- Size is 160x32 1/8th
local function refreshZoneSmall(wgt)
  local myBatt = { ["x"] = 0, ["y"] = 0, ["w"] = 155, ["h"] = 35, ["segments_w"] = 25, ["color"] = WHITE, ["cath_w"] = 6, ["cath_h"] = 20 }

  -- draws bat
  lcd.setColor(CUSTOM_COLOR, WHITE)
  lcd.drawRectangle(wgt.zone.x + myBatt.x, wgt.zone.y + myBatt.y, myBatt.w, myBatt.h, CUSTOM_COLOR, 2)

  -- fill batt
  lcd.setColor(CUSTOM_COLOR, getPercentColor(BatRemPer))
  lcd.drawGauge(wgt.zone.x + 2, wgt.zone.y + 2, myBatt.w - 4, wgt.zone.h, BatRemPer, 100, CUSTOM_COLOR)

  -- write text
  lcd.setColor(CUSTOM_COLOR, options.Color)
  local topLine = string.format("%d      %d%%", BatRemainmAh, BatRemPer)
  lcd.drawText(wgt.zone.x + 20, wgt.zone.y + 2, topLine, MIDSIZE + CUSTOM_COLOR + BlinkWhenZero)
end
-- ####################################################################
--- Size is 225x98 1/4th  (no sliders/trim)
local function refreshZoneMedium(wgt)
  local myBatt = { ["x"] = 0, ["y"] = 0, ["w"] = 85, ["h"] = 35, ["segments_w"] = 15, ["color"] = WHITE, ["cath_w"] = 6, ["cath_h"] = 20 }
  
  --lcd.setColor(CUSTOM_COLOR, options.Color)

  -- draw values
  lcd.drawText(wgt.zone.x, wgt.zone.y + 35, string.format("%d mAh", BatRemainmAh), DBLSIZE + CUSTOM_COLOR + BlinkWhenZero)
  
  -- fill batt
  lcd.setColor(CUSTOM_COLOR, getPercentColor(BatRemPer))
  lcd.drawGauge(wgt.zone.x + myBatt.x, wgt.zone.y + myBatt.y, myBatt.w, myBatt.h, BatRemPer, 100, CUSTOM_COLOR)

  -- draws bat
  lcd.setColor(CUSTOM_COLOR, WHITE)
  lcd.drawRectangle(wgt.zone.x + myBatt.x, wgt.zone.y + myBatt.y, myBatt.w, myBatt.h, CUSTOM_COLOR, 2)
  lcd.drawFilledRectangle(wgt.zone.x + myBatt.x + myBatt.w, wgt.zone.y + myBatt.h / 2 - myBatt.cath_h / 2, myBatt.cath_w, myBatt.cath_h, CUSTOM_COLOR)
  lcd.drawText(wgt.zone.x + myBatt.x + 20, wgt.zone.y + myBatt.y + 5, string.format("%d%%", BatRemPer), LEFT + MIDSIZE + CUSTOM_COLOR)

end

--- Size is 192x152 1/2
local function refreshZoneLarge(wgt)
  
  lcd.setColor(CUSTOM_COLOR, wgt.options.Color)
  
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

  lcd.setColor(CUSTOM_COLOR, wgt.options.Color)
  lcd.drawRectangle((wgt.zone.x - 1) , (wgt.zone.y + (wgt.zone.h - 31)), (wgt.zone.w + 2), 32, 0)
  lcd.setColor(CUSTOM_COLOR, getPercentColor(BatRemPer))
  lcd.drawGauge(wgt.zone.x , (wgt.zone.y + (wgt.zone.h - 30)), wgt.zone.w, 30, BatRemPer, 100, BlinkWhenZero)
end

--- Size is 390x172 1/1
--- Size is 460x252 1/1 (no sliders/trim/topbar)
local function refreshZoneXLarge(wgt)
lcd.setColor(CUSTOM_COLOR, wgt.options.Color)
  local CUSTOM_COLOR = WHITE
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

  lcd.setColor(CUSTOM_COLOR, wgt.options.Color)
  lcd.drawRectangle((wgt.zone.x - 1) , (wgt.zone.y + (wgt.zone.h - 31)), (wgt.zone.w + 2), 32, 0)
  lcd.setColor(CUSTOM_COLOR, getPercentColor(BatRemPer))
  lcd.drawGauge(wgt.zone.x , (wgt.zone.y + (wgt.zone.h - 30)), wgt.zone.w, 30, BatRemPer, 100, BlinkWhenZero)
end


local function run_func(wgt)	-- Called periodically when screen is visible
  bg_func()
  if     wgt.zone.w  > 380 and wgt.zone.h > 165 then refreshZoneXLarge(wgt)
  elseif wgt.zone.w  > 180 and wgt.zone.h > 145 then refreshZoneLarge(wgt)
  elseif wgt.zone.w  > 170 and wgt.zone.h >  65 then refreshZoneMedium(wgt)
  elseif wgt.zone.w  > 150 and wgt.zone.h >  28 then refreshZoneSmall(wgt)
  elseif wgt.zone.w  >  65 and wgt.zone.h >  35 then refreshZoneTiny(wgt)
  end
end

--return { run=run_func, background=bg_func, init=init_func	}
-- new code below

local options = {
  { "Current", SOURCE, mAh }, -- Defines source Battery Current Sensor
  { "Voltage", SOURCE, CELS }, -- Defines source Battery Voltage Sensor
  { "Color", COLOR, GREY },
  { "FunStuff", BOOL, 1  }
}

function create(zone, options)
  init_func()
  local Context = { zone=zone, options=options }
  return Context
end

function update(Context, options)
  mAhSensor = options.Current
  VoltageSensor = options.Voltage
  Context.options = options
  Context.back = nil
  SillyStuff = options.FunStuff
end

function background(Context)
  bg_func()
end

function refresh(Context)
  run_func(Context)
end

return { name="mahRe2", options=options, create=create, update=update, refresh=refresh, background=background }