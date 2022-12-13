-- ============================================================= --
-- KEYBOARD STEERING MOD
-- ============================================================= --
KeyboardSteering = {}
KeyboardSteering.name = g_currentModName
KeyboardSteering.path = g_currentModDirectory
KeyboardSteering.NAME = ("%s.keyboardSteering"):format(g_currentModName)
KeyboardSteering.specName = ("spec_%s.keyboardSteering"):format(g_currentModName)

KeyboardSteering.debug = false
KeyboardSteering.USE_WHEEL = {}
KeyboardSteering.USE_JOYSTICK = {}

--SETTINGS
KeyboardSteering.maxKeyHeldTime         = 500        -- maximum key down time (ms)
KeyboardSteering.maxMaxAccnKeyHeldTime  = 500        -- maximum for the max acceleration key down time (ms)
KeyboardSteering.goStraightReleaseDelay = 150        -- both keys down release delay    
KeyboardSteering.frameAverageNumber     = 20         -- number of frames to average

--DEFAULT KEYS FOR STEERING
KeyboardSteering.leftKey                = {}
KeyboardSteering.rightKey               = {}
KeyboardSteering.forwardKey             = {}
KeyboardSteering.reverseKey             = {}

--VARIABLES
KeyboardSteering.turnLeft               = false        -- input left turn (via key press)
KeyboardSteering.turnRight              = false        -- input right turn (via key press)
KeyboardSteering.goStraight             = false        -- flag to go straight after pressing left+right
KeyboardSteering.timeKeyHeld            = 0            -- key down time for any steering input
KeyboardSteering.goStraightReleaseTime  = 0            -- both keys down released time

KeyboardSteering.forward                = false        -- input forward/acclerate (via key press)
KeyboardSteering.reverse                = false        -- input reverse/brake (via key press)
KeyboardSteering.timeForwardKeyHeld     = 0            -- key down time for forward/acclerate input
KeyboardSteering.timeReverseKeyHeld     = 0            -- key down time for reverse/brake input
KeyboardSteering.maxAccnKeyHeldTime     = 500          -- maximum acceleration key down time (ms)
    

function KeyboardSteering.prerequisitesPresent(specializations)
    return    SpecializationUtil.hasSpecialization(Drivable, specializations) and
            SpecializationUtil.hasSpecialization(Motorized, specializations) and
            SpecializationUtil.hasSpecialization(Enterable, specializations)
end

function KeyboardSteering.initSpecialization()
    
    KeyboardSteering.xmlSchema = XMLSchema.new("keyboardSteering")

    local globalKey = "keyboardSteering"
    KeyboardSteering.xmlSchema:register(XMLValueType.BOOL, globalKey.."#debug", "Show the debugging display for all vehicles in game", false)
    
    local useWheelKey = "keyboardSteering.useWheelForVehicleTypes.vehicleType(?)"
    KeyboardSteering.xmlSchema:register(XMLValueType.STRING, useWheelKey.."#name", "Use wheel rather than joystick for steering", nil)
    local useJoystickKey = "keyboardSteering.useJoystickForVehicleTypes.vehicleType(?)"
    KeyboardSteering.xmlSchema:register(XMLValueType.STRING, useJoystickKey.."#name", "Use joystick rather than wheel for steering", nil)
    
    local schemaSavegame = Vehicle.xmlSchemaSavegame
    local specKey = "vehicles.vehicle(?).keyboardSteering"
    schemaSavegame:register(XMLValueType.BOOL, specKey.."#enabled", "Is Keyboard Steering enabled for this vehicle", true)

end

function KeyboardSteering.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", KeyboardSteering)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", KeyboardSteering)
    SpecializationUtil.registerEventListener(vehicleType, "onEnterVehicle", KeyboardSteering)
    SpecializationUtil.registerEventListener(vehicleType, "onLeaveVehicle", KeyboardSteering)
    SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents", KeyboardSteering)
end

function KeyboardSteering.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "controlVehicle", KeyboardSteering.kbsControlVehicle)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateVehiclePhysics", KeyboardSteering.kbsUpdateVehiclePhysics)
end

function KeyboardSteering:kbsControlVehicle(superFunc, acceleratorPedal, maxSpeed, maxAcceleration, minMotorRotSpeed, maxMotorRotSpeed, maxMotorRotAcceleration, minGearRatio, maxGearRatio, maxClutchTorque, neededPtoTorque)
    local kbs_spec = self.spec_keyboardSteering
    if kbs_spec~=nil and kbs_spec.vehicleEnabled then
        -- APPLY REDUCED ACCELERATION
        -- print("controlVehicle: " .. kbs_spec.accelerationFactor)
        maxAcceleration = maxAcceleration * kbs_spec.accelerationFactor
        maxMotorRotAcceleration = maxMotorRotAcceleration * kbs_spec.accelerationFactor
    end
    return superFunc(self, acceleratorPedal, maxSpeed, maxAcceleration, minMotorRotSpeed, maxMotorRotSpeed, maxMotorRotAcceleration, minGearRatio, maxGearRatio, maxClutchTorque, neededPtoTorque)
end

function KeyboardSteering:kbsUpdateVehiclePhysics(superFunc, axisForward, axisSide, doHandbrake, dt)
    local kbs_spec = self.spec_keyboardSteering
    if kbs_spec~=nil and kbs_spec.vehicleEnabled then
        -- print("updateVehiclePhysics")
    end
    return superFunc(self, axisForward, axisSide, doHandbrake, dt)
end

function KeyboardSteering:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
    if self.isClient then
        local spec = self.spec_keyboardSteering
        self:clearActionEventsTable(spec.actionEvents)

        if isActiveForInputIgnoreSelection then
            --print("*** " .. self:getFullName() .. " ***")
            local actionEventId --(actionEventsTable, inputAction, target, callback, triggerUp, triggerDown, triggerAlways, startActive, callbackState, customIconName)
            _, actionEventId = self:addActionEvent(spec.actionEvents, "KBSTEERING_ENABLE_DISABLE", self, KeyboardSteering.toggleEnable, false, true, false, true, true, nil )
            g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_VERY_LOW)
            g_inputBinding:setActionEventTextVisibility(actionEventId, false)
            _, actionEventId = InputBinding.registerActionEvent(g_inputBinding, 'KBSTEERING_ENABLE_DISABLE', self, KeyboardSteering.toggleEnable, false, true, false, true)
            g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_VERY_LOW)
            g_inputBinding:setActionEventTextVisibility(actionEventId, false)    
        end
    end
end

function KeyboardSteering:onLoad(savegame)
    self.spec_keyboardSteering = self[KeyboardSteering.specName]

    local kbs_spec = self.spec_keyboardSteering
    kbs_spec.vehicleId                  = self.rootNode
    kbs_spec.vehicleEnabled             = true
    kbs_spec.justEnteredVehicle         = false
    kbs_spec.wasDrivenByAI              = false
    kbs_spec.accelerationFactor         = 1
    kbs_spec.smoothingCount             = 0
    kbs_spec.smoothingTotal             = 0
    kbs_spec.smoothingArray             = {}
    for i=1, KeyboardSteering.frameAverageNumber do
        kbs_spec.smoothingArray[i] = 0
    end
    
    kbs_spec.useWheel = false    
    for i, name in pairs(KeyboardSteering.USE_WHEEL) do
        if self.typeName:find(name) then
            kbs_spec.useWheel = true
        end
    end
    
    kbs_spec.useJoystick = false    
    for i, name in pairs(KeyboardSteering.USE_JOYSTICK) do
        if self.typeName:find(name) then
            kbs_spec.useJoystick = true
        end
    end
end

function KeyboardSteering:onPostLoad(savegame)
    if self.isServer and savegame ~= nil then
        local spec = self.spec_keyboardSteering
        spec.vehicleEnabled = savegame.xmlFile:getValue(savegame.key..".keyboardSteering#enabled", true)
    end
end

function KeyboardSteering:saveToXMLFile(xmlFile, key, usedModNames)

    local spec = self.spec_keyboardSteering
    local correctedKey = key:gsub(KeyboardSteering.name..".", "")
    xmlFile:setValue(correctedKey.."#enabled", spec.vehicleEnabled)
end

function KeyboardSteering:onEnterVehicle(isControlling, playerStyle, farmId)
    if isControlling then
        --print("Entered Vehicle:  " .. tostring(self.rootNode))
        kbs_spec = self.spec_keyboardSteering
        kbs_spec.justEnteredVehicle = true
    end
end
function KeyboardSteering:onLeaveVehicle(isControlling, playerStyle, farmId)
    if not isControlling then
        kbs_spec = self.spec_keyboardSteering
        kbs_spec.justEnteredVehicle         = false
        kbs_spec.accelerationFactor         = 1
        kbs_spec.smoothingCount             = 0
        kbs_spec.smoothingTotal             = 0
        for i=1, KeyboardSteering.frameAverageNumber do
            kbs_spec.smoothingArray[i] = 0
        end
    end
end

function KeyboardSteering:toggleEnable(actionName, inputValue)
    if actionName=='KBSTEERING_ENABLE_DISABLE' and inputValue==1 then
        kbs_spec = self.spec_keyboardSteering
        if not kbs_spec.vehicleEnabled then
            --print("ENABLE")
            kbs_spec.vehicleEnabled = true
        else
            --print("DISABLE")
            kbs_spec.vehicleEnabled = false
        end
    end
end

function KeyboardSteering:kbsOnUpdate(superFunc, dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)

    local spec = self.spec_drivable
    local kbs_spec = self.spec_keyboardSteering
    
    if kbs_spec~=nil then
    
        if kbs_spec.lastSpeedRotScale ~= nil then
            spec.speedRotScale = kbs_spec.lastSpeedRotScale
            kbs_spec.lastSpeedRotScale = nil
        end
        if kbs_spec.lastSpeedRotScaleOffset ~= nil then
            spec.speedRotScaleOffset = kbs_spec.lastSpeedRotScaleOffset
            kbs_spec.lastSpeedRotScaleOffset = nil
        end
        if kbs_spec.lastAutoRotateBackSpeed ~= nil then
            self.autoRotateBackSpeed = kbs_spec.lastAutoRotateBackSpeed
            kbs_spec.lastAutoRotateBackSpeed = nil
        end
        if kbs_spec.lastWheelSteeringDuration ~= nil then
            self.wheelSteeringDuration = kbs_spec.lastWheelSteeringDuration
            kbs_spec.lastWheelSteeringDuration = nil
        end
        
        if not kbs_spec.vehicleEnabled then
            if KeyboardSteering.debug then
                g_currentMission:addExtraPrintText("Keyboard Steering: Disabled")
            end
        else
            -- update inputs on client side for basic controls
            if self.isClient and self.getIsEntered ~= nil and self:getIsEntered() then
                if self.isActiveForInputIgnoreSelectionIgnoreAI then
                    if self:getIsVehicleControlledByPlayer() then
                    
                        if g_gui:getIsGuiVisible() then
                            KeyboardSteering.updateKeyPresses = false
                            if kbs_spec.useJoystick or not spec.lastInputValues.axisSteerIsAnalog then
                                spec.lastInputValues.axisSteer = spec.axisSide
                            end
                        else
                            KeyboardSteering.updateKeyPresses = true
                            
                            --    Check for keys that were pressed and held before entering vehicle or while AI was driving
                            if kbs_spec.justEnteredVehicle or kbs_spec.wasDrivenByAI then
                                for _, left in pairs(KeyboardSteering.leftKey) do
                                    if Input.isKeyPressed(left.id) then
                                        KeyboardSteering.turnLeft = true
                                    end
                                end
                                for _, right in pairs(KeyboardSteering.rightKey) do
                                    if Input.isKeyPressed(right.id) then
                                        KeyboardSteering.turnRight = true
                                    end
                                end
                                for _, forward in pairs(KeyboardSteering.forwardKey) do
                                    if Input.isKeyPressed(forward.id) then
                                        KeyboardSteering.forward = true
                                    end
                                end
                                for _, bakwards in pairs(KeyboardSteering.reverseKey) do
                                    if Input.isKeyPressed(bakwards.id) then
                                        KeyboardSteering.reverse = true
                                    end
                                end
                                if kbs_spec.justEnteredVehicle then
                                    kbs_spec.justEnteredVehicle = false
                                end
                                if kbs_spec.wasDrivenByAI then
                                    kbs_spec.wasDrivenByAI = false
                                end
                            end

                            -- KEEP RUNNING AVERAGE OF ROTATION
                            if kbs_spec.smoothingCount == KeyboardSteering.frameAverageNumber then
                                kbs_spec.smoothingCount = 0
                            end
                            kbs_spec.smoothingCount = kbs_spec.smoothingCount + 1
                            kbs_spec.smoothingTotal = kbs_spec.smoothingTotal - kbs_spec.smoothingArray[kbs_spec.smoothingCount]
                            kbs_spec.smoothingArray[kbs_spec.smoothingCount] = self.rotatedTime
                            kbs_spec.smoothingTotal = kbs_spec.smoothingTotal + self.rotatedTime
                            self.rotatedTime = kbs_spec.smoothingTotal / #kbs_spec.smoothingArray
                        
                            -- accelerator and brake pedal (SINGLE PLAYER ONLY)
                            if spec.cruiseControl.state ~= Drivable.CRUISECONTROL_STATE_OFF then
                            --or g_currentMission.missionDynamicInfo.isMultiplayer then
                                kbs_spec.accelerationFactor = 1
                            else
                                if KeyboardSteering.timeForwardKeyHeld>0 and KeyboardSteering.timeReverseKeyHeld==0 then
                                    spec.lastInputValues.axisAccelerate = 1
                                end
                                if KeyboardSteering.timeReverseKeyHeld>0 and KeyboardSteering.timeForwardKeyHeld==0 then
                                    spec.lastInputValues.axisBrake = 1
                                end
                                
                                -- CALCULATE REDUCED ACCELERATION
                                local motor = self.spec_motorized.motor
                                local brakePedal = self.spec_wheels.brakePedal
                                local keyHeld = KeyboardSteering.timeReverseKeyHeld~=0 or KeyboardSteering.timeForwardKeyHeld~=0
                                if math.abs(brakePedal) == 0 and keyHeld then
                                    local fullSpeed = MathUtil.clamp(motor:getMaximumForwardSpeed()*1.2, 10, 50) --Speed in m/s = kmph/3.6
                                    local accnFactorLowerLimit = 1.0 / (1.0+math.exp( -(10/fullSpeed)*(self:getLastSpeed()-(fullSpeed/2))) )
                                    local accnFactorUpperLimit = 1.0 - (0.9*math.exp( -10*self:getLastSpeed()/fullSpeed) )
                                    
                                    local keyHeldTimeFactor = 1.0
                                    if self.movingDirection < 0 then
                                        keyHeldTimeFactor = KeyboardSteering.timeReverseKeyHeld / KeyboardSteering.maxAccnKeyHeldTime
                                    else
                                        keyHeldTimeFactor = KeyboardSteering.timeForwardKeyHeld / KeyboardSteering.maxAccnKeyHeldTime
                                    end
                                    keyHeldTimeFactor = MathUtil.clamp(keyHeldTimeFactor, dt, 1)
                                    
                                    kbs_spec.accelerationFactor = accnFactorLowerLimit + ((accnFactorUpperLimit-accnFactorLowerLimit) * keyHeldTimeFactor)
                                    KeyboardSteering.maxAccnKeyHeldTime = dt + ((1.0-kbs_spec.accelerationFactor) * (KeyboardSteering.maxMaxAccnKeyHeldTime-(dt)))
                                else
                                    kbs_spec.accelerationFactor = 1
                                    KeyboardSteering.timeForwardKeyHeld = 0
                                    KeyboardSteering.timeReverseKeyHeld = 0
                                    KeyboardSteering.maxAccnKeyHeldTime = dt
                                end
                            end
                            
                            if self:getIsPowered() then
                                local axisSteer = spec.lastInputValues.axisSteer
                                local deviceCategory = spec.lastInputValues.axisSteerDeviceCategory

                                -- CONTROL STEERING INPUTS
                                if KeyboardSteering.debug then

                                    if deviceCategory == InputDevice.CATEGORY.KEYBOARD_MOUSE then
                                        g_currentMission:addExtraPrintText("deviceCategory: KEYBOARD_MOUSE")
                                    elseif deviceCategory == InputDevice.CATEGORY.WHEEL then
                                        g_currentMission:addExtraPrintText("deviceCategory: WHEEL")
                                    elseif deviceCategory == InputDevice.CATEGORY.GAMEPAD then
                                        g_currentMission:addExtraPrintText("deviceCategory: GAMEPAD")
                                    elseif deviceCategory == InputDevice.CATEGORY.JOYSTICK then
                                        g_currentMission:addExtraPrintText("deviceCategory: JOYSTICK")
                                    elseif deviceCategory == InputDevice.CATEGORY.FARMWHEEL then
                                        g_currentMission:addExtraPrintText("deviceCategory: FARMWHEEL")
                                    elseif deviceCategory == InputDevice.CATEGORY.FARMPANEL then
                                        g_currentMission:addExtraPrintText("deviceCategory: FARMPANEL")
                                    elseif deviceCategory == InputDevice.CATEGORY.WHEEL_AND_PANEL then
                                        g_currentMission:addExtraPrintText("deviceCategory: WHEEL_AND_PANEL")
                                    elseif deviceCategory == InputDevice.CATEGORY.FARMWHEEL_AND_PANEL then
                                        g_currentMission:addExtraPrintText("deviceCategory: FARMWHEEL_AND_PANEL")
                                    elseif deviceCategory == InputDevice.CATEGORY.UNKNOWN then
                                        g_currentMission:addExtraPrintText("deviceCategory: UNKNOWN")
                                    else
                                        g_currentMission:addExtraPrintText("deviceCategory: "..deviceCategory)
                                    end
                                end


                                --g_currentMission:addExtraPrintText("axisSteerIsAnalog: " .. tostring(spec.lastInputValues.axisSteerIsAnalog))
                                if deviceCategory == InputDevice.CATEGORY.KEYBOARD_MOUSE then
                                    if spec.lastInputValues.axisSteer == 0 then
                                        -- ADJUST ROTATE BACK ACCORDING TO ROAD SPEED
                                        local rotateBackSpeedSetting = g_gameSettings:getValue(GameSettings.SETTING.STEERING_BACK_SPEED) / 10
                                        if self.speedDependentRotateBack then
                                            local speed = self:getLastSpeed()
                                            local setting = rotateBackSpeedSetting / 0.5
                                            local maxSpeed = 50 --self:getMotor():getMaximumForwardSpeed()*3.6
                                            local roadSpeedFactor = math.min(speed/maxSpeed, 1.0)
                                            local steeringAngleFactor = math.abs(spec.axisSide)
                                            kbs_spec.speedFactor = math.min(setting * roadSpeedFactor * steeringAngleFactor, 2)
                                            kbs_spec.lastAutoRotateBackSpeed = self.autoRotateBackSpeed
                                            self.autoRotateBackSpeed = self.autoRotateBackSpeed * kbs_spec.speedFactor
                                        end
                                    else
                                        -- CONTROL STEERING INPUT DEPENDING ON KEY PRESS TIME
                                        local keyPressTimeFactor = KeyboardSteering.timeKeyHeld/KeyboardSteering.maxKeyHeldTime
                                        local sensitivitySetting = g_gameSettings:getValue(GameSettings.SETTING.STEERING_SENSITIVITY)
                                        kbs_spec.speedFactor = sensitivitySetting * keyPressTimeFactor
                                        kbs_spec.lastSpeedRotScale = spec.speedRotScale
                                        kbs_spec.lastSpeedRotScaleOffset = spec.speedRotScaleOffset
                                        spec.speedRotScale = spec.speedRotScale / kbs_spec.speedFactor
                                        spec.speedRotScaleOffset = spec.speedRotScaleOffset / kbs_spec.speedFactor
                                    end
                                end


                                -- REMOVE ALWAYS TURNING RIGHT BEHAVIOUR WHEN HOLDING DOWN BOTH KEYS
                                if KeyboardSteering.goStraight then
                                    -- print("GO STRAIGHT")
                                    if math.abs(spec.axisSide) < 0.01 then
                                        spec.axisSide = 0
                                        kbs_spec.lastWheelSteeringDuration = self.wheelSteeringDuration
                                        self.wheelSteeringDuration = math.huge
                                    else
                                        if spec.axisSide > 0.0 then
                                            if spec.axisSide == 1.0 then
                                                spec.axisSide = 0.99
                                            end
                                            kbs_spec.lastWheelSteeringDuration = self.wheelSteeringDuration
                                            self.wheelSteeringDuration = -self.wheelSteeringDuration
                                        end
                                    end
                                end

                                -- LIMIT STEERING ANGLE DEPENDING ON ROAD SPEED
                                local speed = self:getLastSpeed()
                                local rotateBackSetting = g_gameSettings:getValue(GameSettings.SETTING.STEERING_BACK_SPEED) / 10
                                rotateBackSetting = MathUtil.clamp(rotateBackSetting, 0, 1)
                                local minSpeed = 50 - (30*rotateBackSetting)
                                local maxSpeed = 500 - (360*rotateBackSetting)
                                if speed>minSpeed then
                                    kbs_spec.maxAngle = MathUtil.clamp(1.0 - (speed-minSpeed)/(maxSpeed-minSpeed), 0.2, 1)
                                    spec.axisSide = MathUtil.clamp(spec.axisSide, -kbs_spec.maxAngle, kbs_spec.maxAngle)
                                end

                            end
                            
                            if KeyboardSteering.debug then
                                g_currentMission:addExtraPrintText( string.format("steer: %.3f | angle: %.3f | accn: %.3f",
                                    kbs_spec.speedFactor or 1, kbs_spec.maxAngle or 1, kbs_spec.accelerationFactor or 1))
                            end
                            
                        end
                        
                    else
                    
                        KeyboardSteering.updateKeyPresses = false
                        kbs_spec.wasDrivenByAI = true

                    end
                end
            end
        end
    end
    return superFunc(self, dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
end
Drivable.onUpdate = Utils.overwrittenFunction(Drivable.onUpdate, KeyboardSteering.kbsOnUpdate)


function KeyboardSteering:kbsActionEventSteer(superFunc, actionName, inputValue, callbackState, isAnalog, isMouse, deviceCategory, binding)

    if deviceCategory == InputDevice.CATEGORY.KEYBOARD_MOUSE then
        if kbs_spec.useJoystick or kbs_spec.useWheel then
            -- print("BLOCK KEYS")
            isAnalog = true
            inputValue = self.spec_drivable.axisSide
            deviceCategory = InputDevice.CATEGORY.WHEEL
        end
    elseif deviceCategory == InputDevice.CATEGORY.JOYSTICK
        or deviceCategory == InputDevice.CATEGORY.GAMEPAD then
        if kbs_spec.useWheel and not kbs_spec.useJoystick then
            -- print("BLOCK JOYSTICK")
            isAnalog = true
            inputValue = self.spec_drivable.axisSide
            deviceCategory = InputDevice.CATEGORY.WHEEL
        end
    elseif deviceCategory == InputDevice.CATEGORY.WHEEL
        or deviceCategory == InputDevice.CATEGORY.FARMWHEEL
        or deviceCategory == InputDevice.CATEGORY.WHEEL_AND_PANEL
        or deviceCategory == InputDevice.CATEGORY.FARMWHEEL_AND_PANEL then
        if kbs_spec.useJoystick and not kbs_spec.useWheel then
            -- print("BLOCK WHEEL")
            inputValue = self.spec_drivable.axisSide
        end
    end
    
    return superFunc(self, actionName, inputValue, callbackState, isAnalog, isMouse, deviceCategory, binding)
    
end
Drivable.actionEventSteer = Utils.overwrittenFunction(Drivable.actionEventSteer, KeyboardSteering.kbsActionEventSteer)
