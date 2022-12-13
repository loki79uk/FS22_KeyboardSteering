-- ============================================================= --
-- KEYBOARD STEERING MOD
-- ============================================================= --
-- manager
KeyboardSteeringManager = {}
addModEventListener(KeyboardSteeringManager)

-- specialisation
g_specializationManager:addSpecialization('keyboardSteering', 'KeyboardSteering', Utils.getFilename('KeyboardSteering.lua', g_currentModDirectory), "")

for vehicleName, vehicleType in pairs(g_vehicleTypeManager.types) do
	if  SpecializationUtil.hasSpecialization(Drivable,  vehicleType.specializations) and
		SpecializationUtil.hasSpecialization(Motorized, vehicleType.specializations) and
		SpecializationUtil.hasSpecialization(Enterable, vehicleType.specializations) and
		SpecializationUtil.hasSpecialization(Dashboard, vehicleType.specializations) and
		not SpecializationUtil.hasSpecialization(Locomotive, vehicleType.specializations) then
			g_vehicleTypeManager:addSpecialization(vehicleName, KeyboardSteering.NAME) 
	end
end	
	
function KeyboardSteeringManager.readSettings()

	local userSettingsFile = Utils.getFilename("modSettings/KeyboardSteering.xml", getUserProfileAppPath())
	
	if not fileExists(userSettingsFile) then
		print("CREATING user settings file: " .. userSettingsFile)
		local defaultSettingsFile = Utils.getFilename("KeyboardSteering.xml", KeyboardSteering.path)
		copyFile(defaultSettingsFile, userSettingsFile, false)
	end
	
	local xmlFile = XMLFile.load("configXml", userSettingsFile, KeyboardSteering.xmlSchema)
	if xmlFile ~= 0 then
	
		KeyboardSteering.debug = xmlFile:getValue("keyboardSteering#debug", false)

		local useWheelKey = "keyboardSteering.useWheelForVehicleTypes"
		if xmlFile:hasProperty(useWheelKey) then
			print("  >> Adding USE WHEEL vehicle types:")
			local i = 0
			while true do
				local vehicleTypeKey = string.format(useWheelKey .. ".vehicleType(%d)", i)
				if not xmlFile:hasProperty(vehicleTypeKey) then
					break
				end
				local objectType = xmlFile:getValue(vehicleTypeKey.."#name")
				objectType = objectType:gsub(":", ".")
				
				local customEnvironment, _ = objectType:match( "^(.-)%.(.+)$" )
				if customEnvironment==nil or g_modIsLoaded[customEnvironment] then
					table.insert(KeyboardSteering.USE_WHEEL, objectType)
					print("   - " .. tostring(objectType))
				end
				
				i = i + 1
			end
		end
		
		local useJoystickKey = "keyboardSteering.useJoystickForVehicleTypes"
		if xmlFile:hasProperty(useJoystickKey) then
			print("  >> Adding USE JOYSTICK vehicle types:")
			local i = 0
			while true do
				local vehicleTypeKey = string.format(useJoystickKey .. ".vehicleType(%d)", i)
				if not xmlFile:hasProperty(vehicleTypeKey) then
					break
				end
				local objectType = xmlFile:getValue(vehicleTypeKey.."#name")
				objectType = objectType:gsub(":", ".")
				
				local customEnvironment, _ = objectType:match( "^(.-)%.(.+)$" )
				if customEnvironment==nil or g_modIsLoaded[customEnvironment] then
					table.insert(KeyboardSteering.USE_JOYSTICK, objectType)
					print("   - " .. tostring(objectType))
				end
				
				i = i + 1
			end
		end

		xmlFile:delete()
	end
	
end


function KeyboardSteeringManager:loadMap(name)
	print("Load Mod: 'Keyboard Steering'")
	if g_client and not g_dedicatedServer then
		KeyboardSteeringManager.readSettings()
	end
end

function KeyboardSteeringManager:keyEvent(unicode, sym, modifier, isDown)
	if not KeyboardSteering.initialised or not KeyboardSteering.updateKeyPresses then
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

function KeyboardSteeringManager:update(dt)
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