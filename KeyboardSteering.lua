-- ============================================================= --
-- KEYBOARD STEERING MOD
-- ============================================================= --
KeyboardSteering = {}
KeyboardSteering.specName = ("spec_%s.keyboardSteering"):format(g_currentModName)

addModEventListener(KeyboardSteering)

function KeyboardSteering.prerequisitesPresent(specializations)
	return	SpecializationUtil.hasSpecialization(Drivable, specializations) and
			SpecializationUtil.hasSpecialization(Motorized, specializations) and
			SpecializationUtil.hasSpecialization(Enterable, specializations)
end

function KeyboardSteering.registerEventListeners(vehicleType)
	SpecializationUtil.registerEventListener(vehicleType, "onLoad", KeyboardSteering)
	SpecializationUtil.registerEventListener(vehicleType, "onEnterVehicle", KeyboardSteering)
	SpecializationUtil.registerEventListener(vehicleType, "onLeaveVehicle", KeyboardSteering)
	SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents", KeyboardSteering)
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
	kbs_spec.vehicleId					= self.rootNode
	kbs_spec.vehicleDisabled			= false
	kbs_spec.justEnteredVehicle 		= false
	kbs_spec.wasDrivenByAI				= false
	kbs_spec.accelerationFactor			= 1
	kbs_spec.smoothingCount				= 0
	kbs_spec.smoothingTotal				= 0
	kbs_spec.smoothingArray				= {}
	for i=1, KeyboardSteering.frameAverageNumber do
		kbs_spec.smoothingArray[i] = 0
    end
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
		kbs_spec.justEnteredVehicle 		= false
		kbs_spec.accelerationFactor			= 1
		kbs_spec.smoothingCount				= 0
		kbs_spec.smoothingTotal				= 0
		for i=1, KeyboardSteering.frameAverageNumber do
			kbs_spec.smoothingArray[i] = 0
		end

		KeyboardSteering.displayToggleState	= false
	end
end

function KeyboardSteering:updateWheelsPhysics(superFunc, dt, currentSpeed, acceleration, doHandbrake, stopAndGoBraking)
	-- RETURN NORMAL FUNCTION WHEN KB STEERING IS NOT INSTALLED (ALSO MULTIPLAYER or VCA)
	if self.spec_drivable == nil or self.spec_keyboardSteering == nil or g_currentMission.missionDynamicInfo.isMultiplayer or g_modIsLoaded['FS22_VehicleControlAddon'] then
		return superFunc(self, dt, currentSpeed, acceleration, doHandbrake, stopAndGoBraking)
	end

	local acceleratorPedal = 0
	local brakePedal = 0
	local reverserDirection = 1

	if self.spec_drivable ~= nil then
		reverserDirection = self.spec_drivable.reverserDirection
	end

	local motor = self.spec_motorized.motor
	local isManualTransmission = motor.backwardGears ~= nil or motor.forwardGears ~= nil
	local useManualDirectionChange = isManualTransmission and motor.gearShiftMode ~= VehicleMotor.SHIFT_MODE_AUTOMATIC or motor.directionChangeMode == VehicleMotor.DIRECTION_CHANGE_MODE_MANUAL
	useManualDirectionChange = useManualDirectionChange and not self:getIsAIActive()
	
	if useManualDirectionChange then
		acceleration = acceleration * motor.currentDirection * reverserDirection
	else
		acceleration = acceleration * reverserDirection
	end

	local absCurrentSpeed = math.abs(currentSpeed)
	local accSign = MathUtil.sign(acceleration)
	self.nextMovingDirection = self.nextMovingDirection or 0
	self.nextMovingDirectionTimer = self.nextMovingDirectionTimer or 0
	local automaticBrake = false

	if math.abs(acceleration) < 0.001 then
		automaticBrake = true

		if stopAndGoBraking or currentSpeed * self.nextMovingDirection < 0.0003 then
			self.nextMovingDirection = 0
		end
	else
		if self.nextMovingDirection * currentSpeed < -0.0014 then
			self.nextMovingDirection = 0
		end

		if accSign == self.nextMovingDirection or currentSpeed * accSign > -0.0003 and (stopAndGoBraking or self.nextMovingDirection == 0) then
			self.nextMovingDirectionTimer = math.max(self.nextMovingDirectionTimer - dt, 0)
		
			if self.nextMovingDirectionTimer == 0 then
				acceleratorPedal = acceleration
				brakePedal = 0
				self.nextMovingDirection = accSign
			else
				acceleratorPedal = 0
				brakePedal = math.abs(acceleration)
			end
		else
			acceleratorPedal = 0
			brakePedal = math.abs(acceleration)

			if stopAndGoBraking then
				self.nextMovingDirectionTimer = 100
			end
		end
	end

	if useManualDirectionChange and acceleratorPedal ~= 0 and MathUtil.sign(acceleratorPedal) ~= motor.currentDirection * reverserDirection then
		brakePedal = math.abs(acceleratorPedal)
		acceleratorPedal = 0
	end

	if automaticBrake then
		acceleratorPedal = 0
	end

	acceleratorPedal, brakePedal = motor:updateGear(acceleratorPedal, brakePedal, dt)

	if motor.gear == 0 and motor.targetGear ~= 0 and currentSpeed * MathUtil.sign(motor.targetGear) < 0 then
		automaticBrake = true
	end

	if automaticBrake then
		local isSlow = absCurrentSpeed < motor.lowBrakeForceSpeedLimit
		local isArticulatedSteering = self.spec_articulatedAxis ~= nil and self.spec_articulatedAxis.componentJoint ~= nil and math.abs(self.rotatedTime) > 0.01

		if (isSlow or doHandbrake) and not isArticulatedSteering then
			brakePedal = 1
		else
			local factor = math.min(absCurrentSpeed / 0.001, 1)
			brakePedal = MathUtil.lerp(1, motor.lowBrakeForceScale, factor)
		end
	end

	SpecializationUtil.raiseEvent(self, "onVehiclePhysicsUpdate", acceleratorPedal, brakePedal, automaticBrake, currentSpeed)

	acceleratorPedal, brakePedal = WheelsUtil.getSmoothedAcceleratorAndBrakePedals(self, acceleratorPedal, brakePedal, dt)
	local maxSpeed = motor:getMaximumForwardSpeed() * 3.6

	if self.movingDirection < 0 then
		maxSpeed = motor:getMaximumBackwardSpeed() * 3.6
	end

	local overSpeedLimit = self:getLastSpeed() - math.min(motor:getSpeedLimit(), maxSpeed)

	if overSpeedLimit > 0 then
		if overSpeedLimit > 0.3 then
			motor.overSpeedTimer = math.min(motor.overSpeedTimer + dt, 2000)
		else
			motor.overSpeedTimer = math.max(motor.overSpeedTimer - dt, 0)
		end

		local factor = 0.5 + motor.overSpeedTimer / 2000 * 1
		brakePedal = math.max(math.min(math.pow(overSpeedLimit * factor, 2), 1), brakePedal)
		acceleratorPedal = 0.2 * math.max(1 - overSpeedLimit / 0.2, 0) * acceleratorPedal
	else
		acceleratorPedal = acceleratorPedal * math.min(math.abs(overSpeedLimit) / 0.3 + 0.2, 1)
		motor.overSpeedTimer = 0					  
	end

	if next(self.spec_motorized.differentials) ~= nil and self.spec_motorized.motorizedNode ~= nil then
		local absAcceleratorPedal = math.abs(acceleratorPedal)
		local minGearRatio, maxGearRatio = motor:getMinMaxGearRatio()
		local maxSpeed = nil

		if maxGearRatio >= 0 then
			maxSpeed = motor:getMaximumForwardSpeed()
		else
			maxSpeed = motor:getMaximumBackwardSpeed()
		end

		local acceleratorPedalControlsSpeed = false

		if acceleratorPedalControlsSpeed then
			maxSpeed = maxSpeed * absAcceleratorPedal

			if absAcceleratorPedal > 0.001 then
				absAcceleratorPedal = 1
			end
		end
		
		maxSpeed = math.min(maxSpeed, motor:getSpeedLimit() / 3.6)
		local maxAcceleration = motor:getAccelerationLimit()
		local maxMotorRotAcceleration = motor:getMotorRotationAccelerationLimit()
		local minMotorRpm, maxMotorRpm = motor:getRequiredMotorRpmRange()
		local neededPtoTorque, ptoTorqueVirtualMultiplicator = PowerConsumer.getTotalConsumedPtoTorque(self)
		neededPtoTorque = neededPtoTorque / motor:getPtoMotorRpmRatio()
		local neutralActive = minGearRatio == 0 and maxGearRatio == 0 or motor:getManualClutchPedal() == 1

		motor:setExternalTorqueVirtualMultiplicator(ptoTorqueVirtualMultiplicator)
		
		if not neutralActive then
			if math.abs(brakePedal) == 0 then
				-- APPLY REDUCED ACCELERATION
				kbs_spec = self.spec_keyboardSteering
				--print("wheels: " .. kbs_spec.accelerationFactor)
				maxAcceleration = maxAcceleration * kbs_spec.accelerationFactor
				maxMotorRotAcceleration = maxMotorRotAcceleration * kbs_spec.accelerationFactor
			end
			self:controlVehicle(absAcceleratorPedal, maxSpeed, maxAcceleration, minMotorRpm * math.pi / 30, maxMotorRpm * math.pi / 30, maxMotorRotAcceleration, minGearRatio, maxGearRatio, motor:getMaxClutchTorque(), neededPtoTorque)
		else
			self:controlVehicle(0, 0, 0, 0, math.huge, 0, 0, 0, 0, 0)

			brakePedal = math.max(brakePedal, 0.1)
		end

	end

	self:brake(brakePedal)
end

function KeyboardSteering:toggleEnable(actionName, inputValue)
	if actionName=='KBSTEERING_ENABLE_DISABLE' and inputValue==1 then
		KeyboardSteering.displayToggleState = true
		if not KeyboardSteering.enabled then
			--print("ENABLE")
			KeyboardSteering.enabled = true
		else
			--print("DISABLE")
			KeyboardSteering.enabled = false
		end
	end
end

function KeyboardSteering:onUpdate(superFunc, dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
	-- RETURN NORMAL FUNCTION WHEN KB STEERING IS NOT INSTALLED
	if self.spec_keyboardSteering == nil or g_gui:getIsGuiVisible() then
		return superFunc(self, dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
	end
	
	kbs_spec = self.spec_keyboardSteering
	-- RETURN NORMAL FUNCTION WHEN KB STEERING IS NOT ENABLED
	if KeyboardSteering.enabled == false or kbs_spec.vehicleDisabled then
		--print("onUpdate: disabled")
		kbs_spec.accelerationFactor = 1
		return superFunc(self, dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
	end

	local spec = self.spec_drivable
	-- update inputs on client side for basic controls
	if self.isClient and self.getIsEntered ~= nil and self:getIsEntered() then
		if self.isActiveForInputIgnoreSelectionIgnoreAI then
			if self:getIsVehicleControlledByPlayer() then
				KeyboardSteering.updateKeyPresses = true
				
				--	Check for keys that were pressed and held before entering vehicle or while AI was driving
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
			
				-- NEW accelerator and brake pedal (SINGLE PLAYER ONLY)
				if spec.cruiseControl.state ~= Drivable.CRUISECONTROL_STATE_OFF or g_currentMission.missionDynamicInfo.isMultiplayer then
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
					--print("keyHeld: "..tostring(keyHeld) .. "  accn: "..kbs_spec.accelerationFactor)
				end

				-- ORIGINAL accelerator and brake pedal
				local lastSpeed = self:getLastSpeed()
				local axisForward = MathUtil.clamp(spec.lastInputValues.axisAccelerate - spec.lastInputValues.axisBrake, -1, 1)
				spec.axisForward = axisForward
				spec.doHandbrake = false

				if spec.brakeToStop then
					spec.lastInputValues.targetSpeed = 0.51
					spec.lastInputValues.targetDirection = 1

					if lastSpeed < 1 then
						spec.brakeToStop = false
						spec.lastInputValues.targetSpeed = nil
						spec.lastInputValues.targetDirection = nil
					end
				end

				if spec.lastInputValues.targetSpeed ~= nil then
					local currentSpeed = lastSpeed * self.movingDirection
					local targetSpeed = spec.lastInputValues.targetSpeed * spec.lastInputValues.targetDirection
					local speedDifference = targetSpeed - currentSpeed

					if math.abs(speedDifference) > 0.1 and math.abs(targetSpeed) > 0.5 then
						spec.axisForward = MathUtil.clamp(speedDifference * 0.1, -1, 1)
					end
				end

				if self:getIsPowered() then
					local speedFactor = 1
					local sensitivitySetting = g_gameSettings:getValue(GameSettings.SETTING.STEERING_SENSITIVITY)
					local axisSteer = spec.lastInputValues.axisSteer

					if spec.lastInputValues.axisSteerIsAnalog then
						local isArticulatedSteering = self.spec_articulatedAxis ~= nil and self.spec_articulatedAxis.componentJoint ~= nil
						speedFactor = isArticulatedSteering and 1.5 or 2.5

						if GS_IS_MOBILE_VERSION then
							speedFactor = speedFactor * 1.5
							axisSteer = math.pow(math.abs(axisSteer), 1 / sensitivitySetting) * (axisSteer >= 0 and 1 or -1)
						elseif spec.lastInputValues.axisSteerDeviceCategory == InputDevice.CATEGORY.GAMEPAD then
							speedFactor = speedFactor * sensitivitySetting
						end

						local forceFeedback = spec.forceFeedback

						if forceFeedback.isActive then
							if forceFeedback.intensity > 0 then
								local angleFactor = math.abs(axisSteer)
								local speedForceFactor = math.max(math.min((lastSpeed - 2) / 15, 1), 0)
								local targetState = axisSteer - 0.2 * speedForceFactor * MathUtil.sign(axisSteer)
								local force = math.max(math.abs(targetState) * 0.4, 0.25) * speedForceFactor * angleFactor * 2 * forceFeedback.intensity

								forceFeedback.device:setForceFeedback(forceFeedback.axisIndex, force, targetState)
							else
								forceFeedback.device:setForceFeedback(forceFeedback.axisIndex, 0, axisSteer)
							end
						end
					else
						if spec.lastInputValues.axisSteer == 0 then
							local rotateBackSpeedSetting = g_gameSettings:getValue(GameSettings.SETTING.STEERING_BACK_SPEED) / 10

							if self.speedDependentRotateBack then
								local speed = lastSpeed --/ 36
								local setting = rotateBackSpeedSetting / 0.5
								local maxSpeed = 50 --self:getMotor():getMaximumForwardSpeed()*3.6
								local roadSpeedFactor = math.min(speed/maxSpeed, 1.0)
								local steeringAngleFactor = math.abs(spec.axisSide)
								speedFactor = speedFactor * math.min(setting * roadSpeedFactor * steeringAngleFactor, 2)
							end
							speedFactor = speedFactor * (self.autoRotateBackSpeed or 1) / 2
						else
							local keyPressTimeFactor = KeyboardSteering.timeKeyHeld/KeyboardSteering.maxKeyHeldTime
							speedFactor = math.min(1 / (self.lastSpeed * spec.speedRotScale + spec.speedRotScaleOffset), 1)
							speedFactor = speedFactor * sensitivitySetting * keyPressTimeFactor
						end
					end

					if spec.idleTurningAllowed then
						if axisForward == 0 and axisSteer ~= 0 and lastSpeed < 1 and not spec.idleTurningActive then
							spec.idleTurningActive = true
							spec.idleTurningDirection = MathUtil.sign(axisSteer) * spec.idleTurningDrivingDirection
						end

						if axisForward ~= 0 and spec.idleTurningActive then
							spec.idleTurningActive = false
							spec.lastInputValues.targetSpeed = nil
						end

						if spec.idleTurningActive then
							spec.lastInputValues.targetSpeed = spec.idleTurningMaxSpeed
							spec.lastInputValues.targetDirection = spec.idleTurningDirection * MathUtil.sign(axisSteer)
							axisSteer = math.abs(axisSteer) * spec.idleTurningDirection
							speedFactor = speedFactor * spec.idleTurningSteeringFactor
						end
					end

					local steeringDuration = (self.wheelSteeringDuration or 1) * 1000
					local rotDelta = dt / steeringDuration * speedFactor
					
					-- REMOVE ALWAYS TURNING RIGHT BEHAVIOUR WHEN HOLDING DOWN BOTH KEYS
					if KeyboardSteering.goStraight then
						--print("go straight")
						if math.abs(spec.axisSide)<0.01 then
							spec.axisSide = 0
							rotDelta = 0
						else
							if spec.axisSide>0.0 then
								if spec.axisSide==1.0 then
									spec.axisSide=spec.axisSide-rotDelta
								end
								rotDelta = -rotDelta
							end
						end
					end

					if spec.axisSide < axisSteer then
						spec.axisSide = math.min(axisSteer, spec.axisSide + rotDelta)
					elseif axisSteer < spec.axisSide then
						spec.axisSide = math.max(axisSteer, spec.axisSide - rotDelta)
					end
					
					--Limit steering angle depending on road speed
					local speed = self:getLastSpeed()
					local rotateBackSetting = g_gameSettings:getValue(GameSettings.SETTING.STEERING_BACK_SPEED) / 10
					rotateBackSetting = MathUtil.clamp(rotateBackSetting, 0, 1)
					local minSpeed = 50 - (30*rotateBackSetting)
					local maxSpeed = 500 - (360*rotateBackSetting)
					if speed>minSpeed then
						local maxAngle = MathUtil.clamp(1.0 - (speed-minSpeed)/(maxSpeed-minSpeed), 0.2, 1)
						spec.axisSide = MathUtil.clamp(spec.axisSide, -maxAngle, maxAngle)
					end

				end
			else
		
				KeyboardSteering.updateKeyPresses = false
				kbs_spec.wasDrivenByAI = true
				
				spec.axisForward = 0
				spec.idleTurningModeActive = false

				if self.rotatedTime < 0 then
					spec.axisSide = self.rotatedTime / -self.maxRotTime / self:getSteeringDirection()
				else
					spec.axisSide = self.rotatedTime / self.minRotTime / self:getSteeringDirection()
				end
			end
		else
					
			spec.doHandbrake = true
			spec.axisForward = 0
			spec.idleTurningModeActive = false
		end
		-- prepare for next frame
		spec.lastInputValues.axisAccelerate = 0
		spec.lastInputValues.axisBrake = 0
		spec.lastInputValues.axisSteer = 0
		-- prepare network update
		if spec.axisForward ~= spec.axisForwardSend or spec.axisSide ~= spec.axisSideSend or spec.doHandbrake ~= spec.doHandbrakeSend then
			spec.axisForwardSend = spec.axisForward
			spec.axisSideSend = spec.axisSide
			spec.doHandbrakeSend = spec.doHandbrake
			self:raiseDirtyFlags(spec.dirtyFlag)
		end
	end
	-- update inputs on client side for cruise control
	if self.isClient and self.getIsEntered ~= nil and self:getIsEntered() then
		local inputValue = spec.lastInputValues.cruiseControlState
		spec.lastInputValues.cruiseControlState = 0
		-- cruise control state
		if inputValue == 1 then
			if spec.cruiseControl.topSpeedTime == Drivable.CRUISECONTROL_FULL_TOGGLE_TIME then
				if spec.cruiseControl.state == Drivable.CRUISECONTROL_STATE_OFF then
					self:setCruiseControlState(Drivable.CRUISECONTROL_STATE_ACTIVE)
				else
					self:setCruiseControlState(Drivable.CRUISECONTROL_STATE_OFF)
				end
			end

			if spec.cruiseControl.topSpeedTime > 0 then
				spec.cruiseControl.topSpeedTime = spec.cruiseControl.topSpeedTime - dt

				if spec.cruiseControl.topSpeedTime < 0 then
					self:setCruiseControlState(Drivable.CRUISECONTROL_STATE_FULL)
				end
			end
		else
			spec.cruiseControl.topSpeedTime = Drivable.CRUISECONTROL_FULL_TOGGLE_TIME
		end
		-- cruise control value
		local lastCruiseControlValue = spec.lastInputValues.cruiseControlValue
		spec.lastInputValues.cruiseControlValue = 0

		if lastCruiseControlValue ~= 0 then
			spec.cruiseControl.changeCurrentDelay = spec.cruiseControl.changeCurrentDelay - dt * spec.cruiseControl.changeMultiplier
			spec.cruiseControl.changeMultiplier = math.min(spec.cruiseControl.changeMultiplier + dt * 0.003, 10)

			if spec.cruiseControl.changeCurrentDelay < 0 then
				spec.cruiseControl.changeCurrentDelay = spec.cruiseControl.changeDelay
				local dir = MathUtil.sign(lastCruiseControlValue)
				local speed = spec.cruiseControl.speed
				local speedReverse = spec.cruiseControl.speedReverse
				local useReverseSpeed = self:getDrivingDirection() < 0

				if self:getReverserDirection() < 0 then
					useReverseSpeed = not useReverseSpeed
				end

				if useReverseSpeed then
					speedReverse = speedReverse + dir
				else
					speed = speed + dir
				end

				self:setCruiseControlMaxSpeed(speed, speedReverse)

				if spec.cruiseControl.speed ~= spec.cruiseControl.speedSent or spec.cruiseControl.speedReverse ~= spec.cruiseControl.speedReverseSent then
					if g_server ~= nil then
						g_server:broadcastEvent(SetCruiseControlSpeedEvent.new(self, spec.cruiseControl.speed, spec.cruiseControl.speedReverse), nil, self)
					else
						g_client:getServerConnection():sendEvent(SetCruiseControlSpeedEvent.new(self, spec.cruiseControl.speed, spec.cruiseControl.speedReverse))
					end

					spec.cruiseControl.speedSent = spec.cruiseControl.speed
					spec.cruiseControl.speedReverseSent = spec.cruiseControl.speedReverse
				end
			end
		else
			spec.cruiseControl.changeCurrentDelay = 0
			spec.cruiseControl.changeMultiplier = 1
		end
	end

	local isControlled = self.getIsControlled ~= nil and self:getIsControlled()
	-- update vehicle physics on server side
	if self:getIsVehicleControlledByPlayer() and self.isServer then
		if isControlled then
			local cruiseControlSpeed = math.huge
			-- lock max speed to working tool
			if spec.cruiseControl.state == Drivable.CRUISECONTROL_STATE_ACTIVE then
				if self:getReverserDirection() < 0 then
					cruiseControlSpeed = spec.cruiseControl.speedReverse
				else
					cruiseControlSpeed = spec.cruiseControl.speed
				end
			end

			if self:getDrivingDirection() < 0 then
				if self:getReverserDirection() < 0 then
					cruiseControlSpeed = math.min(cruiseControlSpeed, spec.cruiseControl.speed)
				else
					cruiseControlSpeed = math.min(cruiseControlSpeed, spec.cruiseControl.speedReverse)
				end
			end

			if cruiseControlSpeed ~= math.huge then
				spec.cruiseControl.speedInterpolated = spec.cruiseControl.speedInterpolated or cruiseControlSpeed

				if cruiseControlSpeed ~= spec.cruiseControl.speedInterpolated then
					local diff = cruiseControlSpeed - spec.cruiseControl.speedInterpolated
					local dir = MathUtil.sign(diff)
					local limit = dir == 1 and math.min or math.max
					spec.cruiseControl.speedInterpolated = limit(spec.cruiseControl.speedInterpolated + dt * 0.0025 * math.max(1, math.abs(diff)) * dir, cruiseControlSpeed)
					cruiseControlSpeed = spec.cruiseControl.speedInterpolated
				end
			else
				spec.cruiseControl.speedInterpolated = nil
			end

			local maxSpeed, _ = self:getSpeedLimit(true)
			maxSpeed = math.min(maxSpeed, cruiseControlSpeed)

			self:getMotor():setSpeedLimit(maxSpeed)
			self:updateVehiclePhysics(spec.axisForward, spec.axisSide, spec.doHandbrake, dt)
		elseif spec.lastIsControlled then
			SpecializationUtil.raiseEvent(self, "onVehiclePhysicsUpdate", 0, 0, true, 0)
		end
	end

	-- just a visual update of the steering wheel
	if self.isClient and isControlled then
		if spec.steeringWheel ~= nil then

			local allowed = true
			if spec.idleTurningAllowed and spec.idleTurningActive and not spec.idleTurningUpdateSteeringWheel then
				allowed = false
			end

			if allowed then
				self:updateSteeringWheel(spec.steeringWheel, dt, 1)
			end
		
		end
	end

	spec.lastIsControlled = isControlled

	if self:getIsActiveForInput(true) then
		local inputHelpMode = g_inputBinding:getInputHelpMode()

		if (inputHelpMode ~= GS_INPUT_HELP_MODE_GAMEPAD or GS_PLATFORM_SWITCH) and g_gameSettings:getValue(GameSettings.SETTING.GYROSCOPE_STEERING) then
			local dx, dy, dz = getGravityDirection()
			local steeringValue = MathUtil.getSteeringAngleFromDeviceGravity(dx, dy, dz)

			self:setSteeringInput(steeringValue, true, InputDevice.CATEGORY.WHEEL)
		end
	end
end

function KeyboardSteering:loadMap(name)
	--print("Load Mod: 'Keyboard Steering'")
	Drivable.onUpdate = Utils.overwrittenFunction(Drivable.onUpdate, KeyboardSteering.onUpdate)
	WheelsUtil.updateWheelsPhysics = Utils.overwrittenFunction(WheelsUtil.updateWheelsPhysics, KeyboardSteering.updateWheelsPhysics)

	KeyboardSteering.enabled				= true		-- Enabled/Disabled
	KeyboardSteering.updateKeyPresses		= false		-- flag to capture key presses
	KeyboardSteering.displayToggleState 	= false		-- show toggled state in F1 menu
	KeyboardSteering.initialised			= false		-- inisitalised flag
	
	KeyboardSteering.turnLeft				= false		-- input left turn (via key press)
	KeyboardSteering.turnRight				= false		-- input right turn (via key press)
	KeyboardSteering.timeKeyHeld			= 0			-- key down time for any steering input
	KeyboardSteering.maxKeyHeldTime			= 500		-- maximum key down time (ms)
	KeyboardSteering.goStraight				= false		-- flag to go straight after pressing left+right
	KeyboardSteering.goStraightReleaseTime 	= 0			-- both keys down released time
	KeyboardSteering.goStraightReleaseDelay = 150		-- both keys down release delay	
	KeyboardSteering.frameAverageNumber		= 20		-- number of frames to average

	--DEFAULT KEYS FOR STEERING
	KeyboardSteering.leftKey				= {}
	KeyboardSteering.rightKey				= {}
	KeyboardSteering.forwardKey				= {}
	KeyboardSteering.reverseKey				= {}
	
	KeyboardSteering.forward				= false		-- input forward/acclerate (via key press)
	KeyboardSteering.reverse				= false		-- input reverse/brake (via key press)
	KeyboardSteering.timeForwardKeyHeld		= 0			-- key down time for forward/acclerate input
	KeyboardSteering.timeReverseKeyHeld		= 0			-- key down time for reverse/brake input
	KeyboardSteering.maxAccnKeyHeldTime		= 500		-- maximum acceleration key down time (ms)
	KeyboardSteering.maxMaxAccnKeyHeldTime	= 500		-- maximum for the max acceleration key down time (ms)
end

function KeyboardSteering:deleteMap()
end

function KeyboardSteering:mouseEvent(posX, posY, isDown, isUp, button)
end

function KeyboardSteering:keyEvent(unicode, sym, modifier, isDown)
	if KeyboardSteering.initialised==false or KeyboardSteering.updateKeyPresses==false then
		return
	end
	
	for _, data in pairs(KeyboardSteering.leftKey) do
		if sym==data.id then
			if isDown then
				KeyboardSteering.turnLeft = true
			else
				KeyboardSteering.turnLeft = false
			end
			return
		end
	end
	for _, data in pairs(KeyboardSteering.rightKey) do
		if sym==data.id then
			if isDown then
				KeyboardSteering.turnRight = true
			else
				KeyboardSteering.turnRight = false
			end
			return
		end
	end
	for _, data in pairs(KeyboardSteering.forwardKey) do
		if sym==data.id then
			if isDown then
				KeyboardSteering.forward = true
			else
				KeyboardSteering.forward = false
			end
			return
		end
	end
	for _, data in pairs(KeyboardSteering.reverseKey) do
		if sym==data.id then
			if isDown then
				KeyboardSteering.reverse = true
			else
				KeyboardSteering.reverse = false
			end
			return
		end
	end
end

function KeyboardSteering:draw()
	if KeyboardSteering.displayToggleState then
		if KeyboardSteering.enabled then
			g_currentMission:addExtraPrintText("Keyboard Steering: Enabled")
		else
			g_currentMission:addExtraPrintText("Keyboard Steering: Disabled")
		end
	end
end

function KeyboardSteering:update(dt)
	if not KeyboardSteering.initialised then
		if g_settingsScreen.settingsModel.steeringBackSpeedValues[12] == nil then
			--EXTEND RANGE OF STEERING BACK SPEED SETTINGS
			local newValues = {11.0, 12.0, 13.0, 14.0, 15.0, 16.0, 17.0, 18.0, 19.0, 20.0}
			local newStrings = {'110%', '120%', '130%', '140%', '150%', '160%', '170%', '180%', '190%', '200%'}
			for i = 1, 10 do
				table.insert(g_settingsScreen.settingsModel.steeringBackSpeedValues, newValues[i])
				table.insert(g_settingsScreen.settingsModel.steeringBackSpeedStrings, newStrings[i])
			end
		end

		--DETECT BOUND KEYS FOR STEERING	
		local xmlFile = loadXMLFile('TempXML', g_gui.inputManager.settingsPath)	
		local actionBindingCounter = 0
		if xmlFile ~= 0 then
			while true do
				local key = string.format('inputBinding.actionBinding(%d)', actionBindingCounter)
				local actionString = getXMLString(xmlFile, key .. '#action')
				if actionString == nil then
					break
				end
				if actionString == 'AXIS_MOVE_SIDE_VEHICLE' then
					local i = 0
					while true do
						local bindingKey = key .. string.format('.binding(%d)',i)
						local bindingName = getXMLString(xmlFile, bindingKey .. '#input')
						local bindingIndex = getXMLString(xmlFile, bindingKey .. '#index')
						local bindingAxisComponent = getXMLString(xmlFile, bindingKey .. '#axisComponent')
						if bindingName == nil then
							break
						end
						if bindingAxisComponent == '-' then
							table.insert(KeyboardSteering.leftKey, {name=bindingName, id=Input[bindingName], index=bindingIndex })
						else
							table.insert(KeyboardSteering.rightKey, {name=bindingName, id=Input[bindingName], index=bindingIndex })
						end
						i = i + 1
					end
				end
				
				if actionString == 'AXIS_BRAKE_VEHICLE' then
					local i = 0
					while true do
						local bindingKey = key .. string.format('.binding(%d)',i)
						local bindingName = getXMLString(xmlFile, bindingKey .. '#input')
						local bindingIndex = getXMLString(xmlFile, bindingKey .. '#index')
						local bindingAxisComponent = getXMLString(xmlFile, bindingKey .. '#axisComponent')
						if bindingName == nil then
							break
						end
						if bindingAxisComponent == '+' then
							table.insert(KeyboardSteering.reverseKey, {name=bindingName, id=Input[bindingName], index=bindingIndex })
						end
						i = i + 1
					end
				end
				
				if actionString == 'AXIS_ACCELERATE_VEHICLE' then
					local i = 0
					while true do
						local bindingKey = key .. string.format('.binding(%d)',i)
						local bindingName = getXMLString(xmlFile, bindingKey .. '#input')
						local bindingIndex = getXMLString(xmlFile, bindingKey .. '#index')
						local bindingAxisComponent = getXMLString(xmlFile, bindingKey .. '#axisComponent')
						if bindingName == nil then
							break
						end
						if bindingAxisComponent == '+' then
							table.insert(KeyboardSteering.forwardKey, {name=bindingName, id=Input[bindingName], index=bindingIndex })
						end
						i = i + 1
					end
				end

				actionBindingCounter = actionBindingCounter + 1
			end
		end
		delete(xmlFile)
				
		if next(KeyboardSteering.leftKey)==nil or next(KeyboardSteering.rightKey)==nil then
			print("Keyboard Steering: no keys bound to vehicle turn left/right")
			KeyboardSteering.enabled = false
		end
		if next(KeyboardSteering.reverseKey)==nil then
			print("Keyboard Steering: no key bound to vehicle brake")
			KeyboardSteering.enabled = false
		end
		if next(KeyboardSteering.forwardKey)==nil then
			print("Keyboard Steering: no key bound to vehicle accelerate")
			KeyboardSteering.enabled = false
		end
			
		KeyboardSteering.initialised = true
	end


	if KeyboardSteering.updateKeyPresses then
		-- UPDATE ACCELERATION KEY PRESS TIMES AND FLAGS
		if KeyboardSteering.forward and KeyboardSteering.reverse then
			KeyboardSteering.timeReverseKeyHeld = 0
			KeyboardSteering.timeForwardKeyHeld = 0
		else
			if KeyboardSteering.forward then
				KeyboardSteering.timeForwardKeyHeld = KeyboardSteering.timeForwardKeyHeld + dt
			else
				KeyboardSteering.timeForwardKeyHeld = KeyboardSteering.timeForwardKeyHeld - dt
			end
			KeyboardSteering.timeForwardKeyHeld = MathUtil.clamp(KeyboardSteering.timeForwardKeyHeld, 0, KeyboardSteering.maxAccnKeyHeldTime)
			
			if KeyboardSteering.reverse then
				KeyboardSteering.timeReverseKeyHeld = KeyboardSteering.timeReverseKeyHeld + dt
			else
				KeyboardSteering.timeReverseKeyHeld = KeyboardSteering.timeReverseKeyHeld - dt
			end
			KeyboardSteering.timeReverseKeyHeld = MathUtil.clamp(KeyboardSteering.timeReverseKeyHeld, 0, KeyboardSteering.maxAccnKeyHeldTime)
		end
		
		-- UPDATE STEERING KEY PRESS TIMES AND FLAGS
		if KeyboardSteering.turnLeft and KeyboardSteering.turnRight then
			-- GOING STRAIGHT
			KeyboardSteering.goStraight = true
			KeyboardSteering.timeKeyHeld = KeyboardSteering.timeKeyHeld + dt
			KeyboardSteering.goStraightReleaseTime = 0
		else
			if KeyboardSteering.turnLeft or KeyboardSteering.turnRight then
				-- TURNING LEFT OR RIGHT
				KeyboardSteering.timeKeyHeld = KeyboardSteering.timeKeyHeld + dt

				-- CREATE DEADTIME AFTER RELEASING BOTH KEYS
				if KeyboardSteering.goStraight then
					KeyboardSteering.goStraightReleaseTime = KeyboardSteering.goStraightReleaseTime + dt
					if KeyboardSteering.goStraightReleaseTime > KeyboardSteering.goStraightReleaseDelay then
						KeyboardSteering.goStraight = false
					end
				end
			else
				-- no keyboard input
				KeyboardSteering.timeKeyHeld = KeyboardSteering.timeKeyHeld - dt
				KeyboardSteering.goStraight = false
			end
			
		end
		KeyboardSteering.timeKeyHeld = MathUtil.clamp(KeyboardSteering.timeKeyHeld, 0, KeyboardSteering.maxKeyHeldTime)
	end
end