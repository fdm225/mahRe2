local lib = { }

function lib.new()
    local service = {
        -- Sensors
        -- 	Use Voltage and or mAh consumed calculated sensor based on VFAS, FrSky FAS-40
        -- 	Use sensor names from OpenTX TELEMETRY screen
        --  If you need help setting up a consumption sensor visit
        --		http://rcdiy.ca/calculated-sensor-consumption/
        -- Change as desired
        VoltageSensor = "Cels", -- optional set to "" to ignore
        mAhSensor = "mAh", -- optional set to "" to ignore
        CurrentSensor = "Curr",
        ThrottleId = 1,

        -- Reserve Capacity
        -- 	Remaining % Displayed = Calculated Remaining % - Reserve %
        -- Change as desired
        CapacityReservePercent = 20, -- set to zero to disable

        -- Switch used to reset the voltage checking features.
        --  typically set to the same switch used to reset timers
        SwReset = "sh",

        --   Value used when checking to see if the cell is full for the service.check_for_full_battery check
        CellFullVoltage = 4.0,

        --   Value used to when comparing cell voltages to each other.
        --    if any cell gets >= VoltageDelta volts of the other cells
        --    then play the Inconsistent Cell Warning message
        VoltageDelta = .3,


        -- Announcements
        soundDirPath = "/WIDGETS/" .. name .. "/sounds/", -- where you put the sound files
        AnnouncePercentRemaining = true, -- true to turn on, false for off

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
        GVCellCount = GV[6], -- Read the number of cells
        GVBatCap = GV[7], -- Read Battery Capacity, 8 for 800mAh, 22 for 2200mAh
        GVBatNumber = GV[8], -- Read the id of the battery that is currently in use
        -- The corresponding must be set under the FLIGHT MODES
        -- screen on the Tx.
        -- If the GV is 0 or not set on the Tx then
        -- % remaining is calculated based on battery voltage
        -- which may not be as accurate.
        GVFlightMode = 0, -- Use a different flight mode if running out of GVs

        -- ----------------------------------------------------------------------------------------
        -- ----------------------------------------------------------------------------------------
        -- AVOID EDITING BELOW HERE
        --
        CanCallInitFuncAgain = false, -- updated in bg_func

        -- Calculations
        UseVoltsNotmAh, -- updated in init_func
        BatCapFullmAh, -- updated in init_func
        BatCapmAh, -- updated in init_func
        BatUsedmAh, -- updated in bg_func
        BatRemainmAh, -- updated in init_func, bg_func
        BatRemPer, -- updated in init_func, bg_func
        VoltsPercentRem, -- updated in init_func, bg_func
        VoltsNow = 0, -- updated in bg_func
        CellCount = 6, -- updated in init_func, bg_func

        -- load some additional code from other lua files
        scheduler = libscheduler.new(),
        history = nil,
        gui = nil,

        -- Voltage Checking flags
        CheckBatNotFull = true,

        -- Announcements
        BatRemPerFileName = 0, -- updated in service.PlayPercentRemaining
        BatRemPerPlayed = 0, -- updated in service.PlayPercentRemaining
        AtZeroPlayedCount, -- updated in init_func, service.PlayPercentRemaining
        PlayAtZero = 1,

        -- Based on results from http://rcdiy.ca/taranis-q-x7-battery-run-time/
        VoltToPercentTable = {
            { 3.60, 10 }, { 3.70, 15 }, { 3.72, 20 }, { 3.74, 25 },
            { 3.76, 30 }, { 3.78, 35 }, { 3.80, 40 }, { 3.81, 45 },
            { 3.83, 50 }, { 3.85, 55 }, { 3.87, 60 }, { 3.98, 65 },
            { 3.99, 70 }, { 4.00, 75 }, { 4.03, 80 }, { 4.06, 85 },
            { 4.10, 90 }, { 4.15, 95 }, { 4.20, 100 }
        },

        SoundsTable = { [5] = "Bat5L.wav", [10] = "Bat10L.wav", [20] = "Bat20L.wav"
        , [30] = "Bat30L.wav", [40] = "Bat40L.wav", [50] = "Bat50L.wav"
        , [60] = "Bat60L.wav", [70] = "Bat70L.wav", [80] = "Bat80L.wav"
        , [90] = "Bat90L.wav" }
    }

    function service.getThrottlePercentValue(rawThrottle)
        -- read the throttle value and return it as a percentage
        -- -1000  == 0%
        -- 0      == 50%
        -- 1000   == 100%
        return 50 + rawThrottle / 20
    end

    function service.findPercentRem(cellVoltage)
        if cellVoltage > 4.200 then
            return 100
        elseif cellVoltage < 3.60 then
            return 0
        else
            -- method of finding percent in my array provided by on4mh (Mike)
            for i, v in ipairs(service.VoltToPercentTable) do
                if v[1] >= cellVoltage then
                    return v[2]
                end
            end
        end
    end

    function service.PlayPercentRemaining()
        -- Announces percent remaining using the accompanying sound files.
        -- Announcements ever 10% change when percent remaining is above 10 else
        --	every 5%
        local myModVal

        if service.BatRemPer < 10 then
            myModVal = service.BatRemPer % 5
        else
            myModVal = service.BatRemPer % 10
        end

        if myModVal == 0 and service.BatRemPer ~= service.BatRemPerPlayed then
            service.BatRemPerFileName = ""
            service.BatRemPerFileName = (service.SoundsTable[service.BatRemPer])
            if service.BatRemPerFileName ~= nil then
                playFile(service.soundDirPath .. service.BatRemPerFileName)
                service.BatRemPerPlayed = service.BatRemPer    -- do not keep playing the same sound file over and
            end
        end

        if service.BatRemPer <= 0 and service.AtZeroPlayedCount < service.PlayAtZero and getRSSI() > 0 then
            print(service.BatRemPer, service.AtZeroPlayedCount)
            playFile(service.soundDirPath .. "BatNo.wav")
            service.AtZeroPlayedCount = service.AtZeroPlayedCount + 1
        elseif service.AtZeroPlayedCount == service.PlayAtZero and service.BatRemPer > 0 then
            service.AtZeroPlayedCount = 0
        end
    end

    function service.check_for_full_battery()
        -- check condition 1: at reset that all voltages > service.CellFullVoltage volts
        --print(string.format("service.CheckBatNotFull: %s type: %s", service.CheckBatNotFull, type(voltageSensorValue)))
        if service.CheckBatNotFull and service.VoltageSensor ~= "" then
            -- global variable to gate this so this check is only done once after reset
            local playBatNotFullWarning = false
            local voltageSensorValue = getValue(service.VoltageSensor)
            if (type(voltageSensorValue) == "table") then
                -- check to see if this is the dedicated voltage sensor
                --print("flvss cell detection")
                for i, v in ipairs(voltageSensorValue) do
                    if v < service.CellFullVoltage then
                        --print(string.format("flvss i: %d v: %f", i,v))
                        playBatNotFullWarning = true
                        break
                    end
                end
                service.CheckBatNotFull = false  -- since we have done the check, set to false so it is not ran again
            elseif service.VoltageSensor == "VFAS" and type(voltageSensorValue) == "number" then
                --this is for the vfas sensor
                if voltageSensorValue < (service.CellFullVoltage * service.CellCount) then
                    playBatNotFullWarning = true
                end
                service.CheckBatNotFull = false  -- since we have done the check, set to false so it is not ran again
            end
            if playBatNotFullWarning then
                playFile(service.soundDirPath .. "BNFull.wav")
                playBatNotFullWarning = false
            end
        end -- CheckBatNotfull
    end

    function service.check_cell_delta_voltage(voltageSensorValue)
        -- Check to see if all cells are within VoltageDelta volts of each other
        --  default is .3 volts, can be changed above
        if (type(voltageSensorValue) == "table") then
            -- check to see if this is the dedicated voltage sensor
            for i, v1 in ipairs(voltageSensorValue) do
                for j, v2 in ipairs(voltageSensorValue) do
                    -- print(string.format("i: %d v: %f j: %d v: %f", i, v1, j,v2))
                    if i ~= j and (math.abs(v1 - v2) > service.VoltageDelta) then
                        --print(string.format("i: %d v: %f j: %d v: %f", i, v1, j,v2))
                        service.scheduler.add("icw", true, 10, playFile, service.soundDirPath .. "icw.wav")
                        return
                    end
                end
            end
            service.scheduler.remove("icw")
        end
    end

    function service.check_for_missing_cells(voltageSensorValue)
        -- If the number of cells detected by the voltage sensor does not match the value in GV6 then play the warning message
        -- This is only for the dedicated voltage sensor
        --print(string.format("service.CellCount: %d voltageSensorValue:", service.CellCount))
        if service.CellCount > 0 then
            if type(voltageSensorValue) == "table" and #voltageSensorValue ~= service.CellCount then
                --print(string.format("service.CellCount: %d tableSize: %d", service.CellCount, tableSize))
                service.scheduler.add("mcw", true, 10, playFile, service.soundDirPath .. "mcw.wav")
                return
            elseif service.VoltageSensor == "VFAS" and type(voltageSensorValue) == "number" and (service.CellCount * 3.2) > voltageSensorValue then
                --print(string.format("vfas missing cell: %d", voltageSensorValue))
                service.scheduler.add("mcw", true, 10, playFile, service.soundDirPath .. "mcw.wav")
                return
            end
            service.scheduler.remove("mcw")
        end
    end

    function service.voltage_sensor_tests()
        -- 1. at reset check to see that the cell voltage is > 4.1 for all cellSum
        -- 2. check to see that all cells are within VoltageDelta volts of each other
        -- 3. if number of cells are set in GV6, check to see that all are showing voltage

        --print("check_initial_battery_voltage")

        -- check condition 1: at reset that all voltages > 4.0 volts
        service.check_for_full_battery()

        if service.history.now ~= nil and service.history.now.voltage ~= nil then
            --print("getting service.VoltageSensor data")
            cellResult = service.history.now.voltage

            -- check condition 2: delta voltage
            service.check_cell_delta_voltage(cellResult)

            -- check condition 3: all cells present
            service.check_for_missing_cells(cellResult)

        end
    end

    function service.init_func()
        -- Called once when model is loaded
        service.history = service.history or libhistory.new(service.ThrottleId, service.CurrentSensor, service.VoltageSensor)
        service.gui = service.gui or libgui.new(service.history)

        service.BatCapFullmAh = model.getGlobalVariable(service.GVBatCap, service.GVFlightMode) * 100
        -- service.BatCapmAh = service.BatCapFullmAh
        service.BatCapmAh = service.BatCapFullmAh * (100 - service.CapacityReservePercent) / 100
        service.BatRemainmAh = service.BatCapmAh
        service.CellCount = model.getGlobalVariable(service.GVCellCount, service.GVFlightMode)
        service.VoltsPercentRem = 0
        service.BatRemPer = 0
        service.AtZeroPlayedCount = 0
        if (service.mAhSensor == "") or (service.BatCapmAh == 0) then
            service.UseVoltsNotmAh = true
        else
            service.UseVoltsNotmAh = false
        end
    end

    function service.reset_if_needed()
        -- test if the reset switch is toggled, if so then reset all internal flags
        -- print("reset_sw: " .. getValue(service.SwReset))
        if service.SwReset ~= "" then
            -- Update switch position
            local debounced = service.scheduler.check('reset_sw')
            --print("debounced: " .. tostring(debounced))
            if (debounced == nil or debounced == true) and -1024 ~= getValue(service.SwReset) then
                -- reset switch
                service.scheduler.add('reset_sw', false, 2) -- add the reset switch to the scheduler
                --print("reset start task: " .. tostring(service.scheduler.tasks['reset_sw'].ready))
                service.scheduler.clear('reset_sw') -- set the reset switch to false in the scheduler so we don't run again
                --print("reset task: " .. tostring(service.scheduler.tasks['reset_sw'].ready))
                --print("reset switch toggled - debounced: " .. tostring(debounced))
                service.history.write(service.GVFlightMode, service.GVBatNumber, service.finishReset)

                --service.service.finishReset()
                --print("reset event")
            elseif -1024 == getValue(service.SwReset) then
                --print("reset switch released")
                service.scheduler.remove('reset_sw')
            end
        end
    end

    function service.finishReset()
        print("service.finishReset()")
        service.CheckBatNotFull = true
        service.VoltsNow = 0
        service.scheduler.reset()
        service.history = libhistory.new(service.ThrottleId, service.CurrentSensor, service.VoltageSensor)
        --print("reset created new history: " .. tostring(service.history))
        service.gui.reset(service.history)
        --print("reset gui history: " .. tostring(service.gui.history))
    end

    function service.bg_func()

        service.reset_if_needed() -- test if the reset switch is toggled, if so then reset all internal flags
        service.scheduler.tick() -- deal with all scheduled tasks
        service.history.tick()

        -- Check in battery capacity was changed
        if service.BatCapFullmAh ~= model.getGlobalVariable(service.GVBatCap, service.GVFlightMode) * 100 then
            service.init_func()
        end

        if service.mAhSensor ~= "" then
            service.BatUsedmAh = getValue(service.mAhSensor)
            if (service.BatUsedmAh == 0) and service.CanCallInitFuncAgain then
                -- service.BatUsedmAh == 0 when Telemetry has been reset or model loaded
                -- service.BatUsedmAh == 0 when no battery used which could be a long time
                --	so don't keep calling the service.init_func unnecessarily.
                service.init_func()
                service.CanCallInitFuncAgain = false
            elseif service.BatUsedmAh > 0 then
                -- Call init function again when Telemetry has been reset
                service.CanCallInitFuncAgain = true
            end
            service.BatRemainmAh = service.BatCapmAh - service.BatUsedmAh
        end -- mAhSensor ~= ""

        if service.VoltageSensor ~= "" then
            volts = service.history.getTotalVolts()
            if service.VoltsNow < 1 or volts > 1 then
                service.VoltsNow = volts
            end

            if service.CellCount > 0 then
                service.VoltsPercentRem = service.findPercentRem(service.VoltsNow / service.CellCount)
            end
        end

        -- Update battery remaining percent
        if service.UseVoltsNotmAh then
            service.BatRemPer = service.VoltsPercentRem - service.CapacityReservePercent
        elseif service.BatCapmAh > 0 then
            service.BatRemPer = math.floor((service.BatRemainmAh / service.BatCapFullmAh) * 100)
        end
        if service.AnnouncePercentRemaining then
            service.PlayPercentRemaining()
        end
        service.voltage_sensor_tests()
    end

    function service.update(Context, options)
        service.mAhSensor = options.mAh
        service.VoltageSensor = options.Voltage
        service.CurrentSensor = options.Current
        --Color = options.Color
        Context.options = options
        Context.back = nil
        service.SwReset = options.Reset
        service.ThrottleId = options.Throttle
    end

    function service.refresh(wgt, event, touchState)
        -- Called periodically when screen is visible
        if event == nil then
            -- Widget mode
            writing = service.history.writing or false
            --print(service.history.dataSize .. " writing: " .. tostring(writing))
            if writing then
                service.history.write(service.GVFlightMode, service.GVBatNumber, service.finishReset)
                service.gui.writingZoneXLarge(wgt)
            else
                service.bg_func()
                if wgt.zone.w > 380 and wgt.zone.h > 165 then
                    service.gui.refreshZoneXLarge(wgt, service.BatRemainmAh, service.BatRemPer)
                elseif wgt.zone.w > 180 and wgt.zone.h > 145 then
                    service.gui.refreshZoneLarge(wgt, service.BatRemainmAh, service.BatRemPer)
                elseif wgt.zone.w > 170 and wgt.zone.h > 65 then
                    service.gui.refreshZoneMedium(wgt, service.BatRemainmAh, service.BatRemPer)
                elseif wgt.zone.w > 150 and wgt.zone.h > 28 then
                    service.gui.refreshZoneSmall(wgt, service.BatRemainmAh, service.BatRemPer)
                elseif wgt.zone.w > 65 and wgt.zone.h > 35 then
                    service.gui.refreshZoneTiny(wgt, service.BatRemainmAh, service.BatRemPer)
                end
            end
        else
            print("full screen")
        end
    end

    return service
end

return lib