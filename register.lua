-- ============================================================= --
-- KEYBOARD STEERING MOD
-- ============================================================= --
KeyboardSteeringREGISTER = {};

g_specializationManager:addSpecialization('keyboardSteering', 'KeyboardSteering', Utils.getFilename('KeyboardSteering.lua', g_currentModDirectory), nil);

for vehicleName, vehicleType in pairs(g_vehicleTypeManager.types) do
	if  SpecializationUtil.hasSpecialization(Drivable,  vehicleType.specializations) and
		SpecializationUtil.hasSpecialization(Motorized, vehicleType.specializations) and
		SpecializationUtil.hasSpecialization(Enterable, vehicleType.specializations) and
		SpecializationUtil.hasSpecialization(Dashboard, vehicleType.specializations) and
		not SpecializationUtil.hasSpecialization(Locomotive, vehicleType.specializations) then
			g_vehicleTypeManager:addSpecialization(vehicleName, g_currentModName .. '.keyboardSteering') 
	end
end
