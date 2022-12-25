# mahRe2

## OpenTX/EdgeTX Widget for Voltage and Current Telemetry

--  License  [https://www.gnu.org/licenses/gpl-3.0.en.html](https://www.gnu.org/licenses/gpl-3.0.en.html)  
--  OpenTX Lua script  
--  TELEMETRY

--  File Locations On The Transmitter's SD Card 
/SCRIPTS/WIDGETS/                               --  This script file  
/SCRIPTS/WIDGETS/mahRe2/sounds/  --  Sound files  

--  Works On OpenTX Companion Version:  2.2  
-- Works With Sensor: FrSky FAS40S, FCS-150A, FAS100, FLVS Voltage Sensors
--  Author:  RCdiy  
--  Web:  [http://RCdiy.ca](http://rcdiy.ca/)  
--  Date:  2016 June 28  
--  Update:  2017 March 27   
--  Reauthored:  Dean Church  --  Date:  2017 March 25  --  Thanks:  TrueBuild  (ideas)  
--  Update:  2019 November 21 by daveEccleston  (Handles sensors returning a table of cell voltages)  
--  Update:  2022 December 1 by David Morrison  (Converted to OpenTX Widget for Horus and TX16S radios) 

## Changes/Additions:

  Choose between using consumption sensor or voltage sensor to calculate  

 - battery capacity remaining.
 - Choose between simple and detailed display.  
 - Voice announcements of percentage remaining during active use
 - After reset, warn if battery is not fully charged  
 - After reset, check cells to verify that they are within VoltageDelta of each other
 - Notify if the number of cells falls below the value set in GV6
 - Show current/low voltage, per cell, in full screen widget
 - Show current/high Amps in full screen widget
 - Show current/high Watts in full screen widget

 
## Description
  Reads an OpenTX global variable to determine battery capacity in mAh  

 - The sensors used are configurable
 - Reads an battery consumption sensor and/or a voltage sensor to estimate mAh and  %  battery capacity remaining  
 - A consumption sensor is a calculated sensor based on a current sensor and the time elapsed.  [http://rcdiy.ca/calculated-sensor-consumption/](http://rcdiy.ca/calculated-sensor-consumption/) 
 - Displays remaining battery mAh and percent based on mAh used
 - Displays battery voltage and remaining percent based on volts   
 - Write remaining battery mAh to a Tx global variable 
 - Write remaining battery percent to a Tx global variable  
	 - Writes are optional,  off by default  
 - Announces percentage remaining every 10%  change 
	 - Announcements are optional,  off by default  
 - Reserve Percentage  
	 - All values are calculated with reference to this reserve.  
	 - %  Remaining  =  Estimated  %  Remaining  -  Reserve  %  
	 - mAh Remaining  =  Calculated mAh Remaining  -  (Size mAh x Reserve  %)  
	 - The reserve is configurable,  20%  is the set default  
 - The following is an example of what is dislayed at start up  --  800mAh remaining for a 1000mAh battery  
	 - 80%  remaining  

## Notes & Suggestions

 - The OpenTX global variables  (GV)  have a 1024 limit.
 - mAh values are stored in them as mAh/100  
	 - 2800 mAh will be 28  
	 - 800 mAh will be 8  
 - The GVs are global to that model,  not between models.  
 
| Global Variable | Use |
|--|--|
| GV6 | Number of Cells In Lipo |
| GV7 | Lipo Capacity / 100 |
| GV8 | Write remaining mAh (off by default) |
| GV9 | Write remaining bat percentage (off by default) |

## Configurations

 - For help using telemetry scripts  --  [http://rcdiy.ca/telemetry-scripts-getting-started/](http://rcdiy.ca/telemetry-scripts-getting-started/)
 - The following additional configurations are available within the script

| Variable | Use |
|--|--|
| VoltageSenor | The name of the voltage sensor in the model configuration |
| mAhSensor | The name of the mAh sensor in the model configuration |
| CurrentSensor | The name of the Current sensor in the model configuration |
| CapacityReservePercent | The battery capacity reserve, set to 0 to disable |
| SwReset| The switch assigned to reset all values back to defaults |
| CellFullVoltage| The value of individual cell voltage when the pack is considered full (default is 4.0v) |
| VoltageDelta | The delta value used to alert when cells are too far out of sync |
| soundDirPath | The path to the directory where the sound files are located |
| AnnouncePercentRemaining | Play the percent remaining every 10 percent |
| SillyStuff | Play some silly/fun sounds |

