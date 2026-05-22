module LibPhreeqcRM

using PhreeqcRM_jll
export PhreeqcRM_jll

# Prologue prepended to the generated LibPhreeqcRM.jl by Clang.jl.
# Anything that the generated bindings need to reference (e.g. the libphreeqcrm
# handle from the JLL) is brought into scope here.

using PhreeqcRM_jll


@enum IRM_RESULT::Int32 begin
    IRM_OK = 0
    IRM_OUTOFMEMORY = -1
    IRM_BADVARTYPE = -2
    IRM_INVALIDARG = -3
    IRM_INVALIDROW = -4
    IRM_INVALIDCOL = -5
    IRM_BADINSTANCE = -6
    IRM_FAIL = -7
end

function RM_BmiCreate(nxyz, nthreads)
    @ccall libphreeqcrm.RM_BmiCreate(nxyz::Cint, nthreads::Cint)::Cint
end

function RM_BmiDestroy(id)
    @ccall libphreeqcrm.RM_BmiDestroy(id::Cint)::IRM_RESULT
end

function RM_BmiAddOutputVars(id, option, def)
    @ccall libphreeqcrm.RM_BmiAddOutputVars(id::Cint, option::Cstring, def::Cstring)::IRM_RESULT
end

function RM_BmiFinalize(id)
    @ccall libphreeqcrm.RM_BmiFinalize(id::Cint)::IRM_RESULT
end

function RM_BmiGetComponentName(id, component_name, l)
    @ccall libphreeqcrm.RM_BmiGetComponentName(id::Cint, component_name::Cstring, l::Cint)::IRM_RESULT
end

function RM_BmiGetCurrentTime(id)
    @ccall libphreeqcrm.RM_BmiGetCurrentTime(id::Cint)::Cdouble
end

function RM_BmiGetEndTime(id)
    @ccall libphreeqcrm.RM_BmiGetEndTime(id::Cint)::Cdouble
end

function RM_BmiGetGridRank(id, grid)
    @ccall libphreeqcrm.RM_BmiGetGridRank(id::Cint, grid::Cint)::Cint
end

function RM_BmiGetGridSize(id, grid)
    @ccall libphreeqcrm.RM_BmiGetGridSize(id::Cint, grid::Cint)::Cint
end

function RM_BmiGetGridType(id, grid, str, l)
    @ccall libphreeqcrm.RM_BmiGetGridType(id::Cint, grid::Cint, str::Cstring, l::Cint)::IRM_RESULT
end

function RM_BmiGetInputItemCount(id)
    @ccall libphreeqcrm.RM_BmiGetInputItemCount(id::Cint)::Cint
end

function RM_BmiGetInputVarName(id, i, name, l)
    @ccall libphreeqcrm.RM_BmiGetInputVarName(id::Cint, i::Cint, name::Cstring, l::Cint)::IRM_RESULT
end

function RM_BmiGetOutputItemCount(id)
    @ccall libphreeqcrm.RM_BmiGetOutputItemCount(id::Cint)::Cint
end

function RM_BmiGetOutputVarName(id, i, name, l)
    @ccall libphreeqcrm.RM_BmiGetOutputVarName(id::Cint, i::Cint, name::Cstring, l::Cint)::IRM_RESULT
end

function RM_BmiGetPointableItemCount(id)
    @ccall libphreeqcrm.RM_BmiGetPointableItemCount(id::Cint)::Cint
end

function RM_BmiGetPointableVarName(id, i, name, l)
    @ccall libphreeqcrm.RM_BmiGetPointableVarName(id::Cint, i::Cint, name::Cstring, l::Cint)::IRM_RESULT
end

function RM_BmiGetStartTime(id)
    @ccall libphreeqcrm.RM_BmiGetStartTime(id::Cint)::Cdouble
end

function RM_BmiGetTime(id)
    @ccall libphreeqcrm.RM_BmiGetTime(id::Cint)::Cdouble
end

function RM_BmiGetTimeStep(id)
    @ccall libphreeqcrm.RM_BmiGetTimeStep(id::Cint)::Cdouble
end

function RM_BmiGetTimeUnits(id, units, l)
    @ccall libphreeqcrm.RM_BmiGetTimeUnits(id::Cint, units::Cstring, l::Cint)::IRM_RESULT
end

function RM_BmiGetValueInt(id, var, dest)
    @ccall libphreeqcrm.RM_BmiGetValueInt(id::Cint, var::Cstring, dest::Ptr{Cint})::IRM_RESULT
end

function RM_BmiGetValueDouble(id, var, dest)
    @ccall libphreeqcrm.RM_BmiGetValueDouble(id::Cint, var::Cstring, dest::Ptr{Cdouble})::IRM_RESULT
end

function RM_BmiGetValueChar(id, var, dest, l)
    @ccall libphreeqcrm.RM_BmiGetValueChar(id::Cint, var::Cstring, dest::Cstring, l::Cint)::IRM_RESULT
end

function RM_BmiGetValuePtr(id, var)
    @ccall libphreeqcrm.RM_BmiGetValuePtr(id::Cint, var::Cstring)::Ptr{Cvoid}
end

function RM_BmiGetVarGrid(id, var)
    @ccall libphreeqcrm.RM_BmiGetVarGrid(id::Cint, var::Cstring)::Cint
end

function RM_BmiGetVarItemsize(id, name)
    @ccall libphreeqcrm.RM_BmiGetVarItemsize(id::Cint, name::Cstring)::Cint
end

function RM_BmiGetVarNbytes(id, name)
    @ccall libphreeqcrm.RM_BmiGetVarNbytes(id::Cint, name::Cstring)::Cint
end

function RM_BmiGetVarType(id, name, vtype, l)
    @ccall libphreeqcrm.RM_BmiGetVarType(id::Cint, name::Cstring, vtype::Cstring, l::Cint)::IRM_RESULT
end

function RM_BmiGetVarUnits(id, name, units, l)
    @ccall libphreeqcrm.RM_BmiGetVarUnits(id::Cint, name::Cstring, units::Cstring, l::Cint)::IRM_RESULT
end

function RM_BmiInitialize(id, config_file)
    @ccall libphreeqcrm.RM_BmiInitialize(id::Cint, config_file::Cstring)::IRM_RESULT
end

function RM_BmiSetValueChar(id, name, src)
    @ccall libphreeqcrm.RM_BmiSetValueChar(id::Cint, name::Cstring, src::Cstring)::IRM_RESULT
end

function RM_BmiSetValueDouble(id, name, src)
    @ccall libphreeqcrm.RM_BmiSetValueDouble(id::Cint, name::Cstring, src::Cdouble)::IRM_RESULT
end

function RM_BmiSetValueDoubleArray(id, name, src)
    @ccall libphreeqcrm.RM_BmiSetValueDoubleArray(id::Cint, name::Cstring, src::Ptr{Cdouble})::IRM_RESULT
end

function RM_BmiSetValueInt(id, name, src)
    @ccall libphreeqcrm.RM_BmiSetValueInt(id::Cint, name::Cstring, src::Cint)::IRM_RESULT
end

function RM_BmiUpdate(id)
    @ccall libphreeqcrm.RM_BmiUpdate(id::Cint)::IRM_RESULT
end

function RM_BmiUpdateUntil(id, end_time)
    @ccall libphreeqcrm.RM_BmiUpdateUntil(id::Cint, end_time::Cdouble)::IRM_RESULT
end

function RM_BmiGetValueAtIndices(id, name, dest, inds, count)
    @ccall libphreeqcrm.RM_BmiGetValueAtIndices(id::Cint, name::Cstring, dest::Ptr{Cvoid}, inds::Ptr{Cint}, count::Cint)::Cvoid
end

function RM_BmiSetValueAtIndices(id, name, inds, count, src)
    @ccall libphreeqcrm.RM_BmiSetValueAtIndices(id::Cint, name::Cstring, inds::Ptr{Cint}, count::Cint, src::Ptr{Cvoid})::Cvoid
end

function RM_BmiGetGridShape(id, grid, shape)
    @ccall libphreeqcrm.RM_BmiGetGridShape(id::Cint, grid::Cint, shape::Ptr{Cint})::Cvoid
end

function RM_BmiGetGridSpacing(id, grid, spacing)
    @ccall libphreeqcrm.RM_BmiGetGridSpacing(id::Cint, grid::Cint, spacing::Ptr{Cdouble})::Cvoid
end

function RM_BmiGetGridOrigin(id, grid, origin)
    @ccall libphreeqcrm.RM_BmiGetGridOrigin(id::Cint, grid::Cint, origin::Ptr{Cdouble})::Cvoid
end

function RM_BmiGetGridX(id, grid, x)
    @ccall libphreeqcrm.RM_BmiGetGridX(id::Cint, grid::Cint, x::Ptr{Cdouble})::Cvoid
end

function RM_BmiGetGridY(id, grid, y)
    @ccall libphreeqcrm.RM_BmiGetGridY(id::Cint, grid::Cint, y::Ptr{Cdouble})::Cvoid
end

function RM_BmiGetGridZ(id, grid, z)
    @ccall libphreeqcrm.RM_BmiGetGridZ(id::Cint, grid::Cint, z::Ptr{Cdouble})::Cvoid
end

function RM_BmiGetGridNodeCount(id, grid)
    @ccall libphreeqcrm.RM_BmiGetGridNodeCount(id::Cint, grid::Cint)::Cint
end

function RM_BmiGetGridEdgeCount(id, grid)
    @ccall libphreeqcrm.RM_BmiGetGridEdgeCount(id::Cint, grid::Cint)::Cint
end

function RM_BmiGetGridFaceCount(id, grid)
    @ccall libphreeqcrm.RM_BmiGetGridFaceCount(id::Cint, grid::Cint)::Cint
end

function RM_BmiGetGridEdgeNodes(id, grid, edge_nodes)
    @ccall libphreeqcrm.RM_BmiGetGridEdgeNodes(id::Cint, grid::Cint, edge_nodes::Ptr{Cint})::Cvoid
end

function RM_BmiGetGridFaceEdges(id, grid, face_edges)
    @ccall libphreeqcrm.RM_BmiGetGridFaceEdges(id::Cint, grid::Cint, face_edges::Ptr{Cint})::Cvoid
end

function RM_BmiGetGridFaceNodes(id, grid, face_nodes)
    @ccall libphreeqcrm.RM_BmiGetGridFaceNodes(id::Cint, grid::Cint, face_nodes::Ptr{Cint})::Cvoid
end

function RM_BmiGetGridNodesPerFace(id, grid, nodes_per_face)
    @ccall libphreeqcrm.RM_BmiGetGridNodesPerFace(id::Cint, grid::Cint, nodes_per_face::Ptr{Cint})::Cvoid
end

function RM_Abort(id, result, err_str)
    @ccall libphreeqcrm.RM_Abort(id::Cint, result::Cint, err_str::Cstring)::IRM_RESULT
end

function RM_CloseFiles(id)
    @ccall libphreeqcrm.RM_CloseFiles(id::Cint)::IRM_RESULT
end

function RM_Concentrations2Utility(id, c, n, tc, p_atm)
    @ccall libphreeqcrm.RM_Concentrations2Utility(id::Cint, c::Ptr{Cdouble}, n::Cint, tc::Ptr{Cdouble}, p_atm::Ptr{Cdouble})::Cint
end

function RM_Create(nxyz, nthreads)
    @ccall libphreeqcrm.RM_Create(nxyz::Cint, nthreads::Cint)::Cint
end

function RM_CreateMapping(id, grid2chem)
    @ccall libphreeqcrm.RM_CreateMapping(id::Cint, grid2chem::Ptr{Cint})::IRM_RESULT
end

function RM_DecodeError(id, e)
    @ccall libphreeqcrm.RM_DecodeError(id::Cint, e::Cint)::IRM_RESULT
end

function RM_Destroy(id)
    @ccall libphreeqcrm.RM_Destroy(id::Cint)::IRM_RESULT
end

function RM_DumpModule(id, dump_on, append)
    @ccall libphreeqcrm.RM_DumpModule(id::Cint, dump_on::Cint, append::Cint)::IRM_RESULT
end

function RM_ErrorMessage(id, errstr)
    @ccall libphreeqcrm.RM_ErrorMessage(id::Cint, errstr::Cstring)::IRM_RESULT
end

function RM_FindComponents(id)
    @ccall libphreeqcrm.RM_FindComponents(id::Cint)::Cint
end

function RM_GetBackwardMapping(id, n, list, size)
    @ccall libphreeqcrm.RM_GetBackwardMapping(id::Cint, n::Cint, list::Ptr{Cint}, size::Ptr{Cint})::IRM_RESULT
end

function RM_GetChemistryCellCount(id)
    @ccall libphreeqcrm.RM_GetChemistryCellCount(id::Cint)::Cint
end

function RM_GetComponent(id, num, chem_name, l)
    @ccall libphreeqcrm.RM_GetComponent(id::Cint, num::Cint, chem_name::Cstring, l::Cint)::IRM_RESULT
end

function RM_GetComponentCount(id)
    @ccall libphreeqcrm.RM_GetComponentCount(id::Cint)::Cint
end

function RM_GetConcentrations(id, c)
    @ccall libphreeqcrm.RM_GetConcentrations(id::Cint, c::Ptr{Cdouble})::IRM_RESULT
end

function RM_GetIthConcentration(id, i, c)
    @ccall libphreeqcrm.RM_GetIthConcentration(id::Cint, i::Cint, c::Ptr{Cdouble})::IRM_RESULT
end

function RM_GetIthSpeciesConcentration(id, i, c)
    @ccall libphreeqcrm.RM_GetIthSpeciesConcentration(id::Cint, i::Cint, c::Ptr{Cdouble})::IRM_RESULT
end

function RM_SetIthConcentration(id, i, c)
    @ccall libphreeqcrm.RM_SetIthConcentration(id::Cint, i::Cint, c::Ptr{Cdouble})::IRM_RESULT
end

function RM_SetIthSpeciesConcentration(id, i, c)
    @ccall libphreeqcrm.RM_SetIthSpeciesConcentration(id::Cint, i::Cint, c::Ptr{Cdouble})::IRM_RESULT
end

function RM_GetCurrentSelectedOutputUserNumber(id)
    @ccall libphreeqcrm.RM_GetCurrentSelectedOutputUserNumber(id::Cint)::Cint
end

function RM_GetDensityCalculated(id, density)
    @ccall libphreeqcrm.RM_GetDensityCalculated(id::Cint, density::Ptr{Cdouble})::IRM_RESULT
end

function RM_GetDensity(id, density)
    @ccall libphreeqcrm.RM_GetDensity(id::Cint, density::Ptr{Cdouble})::IRM_RESULT
end

function RM_GetEndCell(id, ec)
    @ccall libphreeqcrm.RM_GetEndCell(id::Cint, ec::Ptr{Cint})::IRM_RESULT
end

function RM_GetEquilibriumPhasesCount(id)
    @ccall libphreeqcrm.RM_GetEquilibriumPhasesCount(id::Cint)::Cint
end

function RM_GetEquilibriumPhasesName(id, num, name, l1)
    @ccall libphreeqcrm.RM_GetEquilibriumPhasesName(id::Cint, num::Cint, name::Cstring, l1::Cint)::IRM_RESULT
end

function RM_GetErrorString(id, errstr, l)
    @ccall libphreeqcrm.RM_GetErrorString(id::Cint, errstr::Cstring, l::Cint)::IRM_RESULT
end

function RM_GetErrorStringLength(id)
    @ccall libphreeqcrm.RM_GetErrorStringLength(id::Cint)::Cint
end

function RM_GetExchangeName(id, num, name, l1)
    @ccall libphreeqcrm.RM_GetExchangeName(id::Cint, num::Cint, name::Cstring, l1::Cint)::IRM_RESULT
end

function RM_GetExchangeSpeciesCount(id)
    @ccall libphreeqcrm.RM_GetExchangeSpeciesCount(id::Cint)::Cint
end

function RM_GetExchangeSpeciesName(id, num, name, l1)
    @ccall libphreeqcrm.RM_GetExchangeSpeciesName(id::Cint, num::Cint, name::Cstring, l1::Cint)::IRM_RESULT
end

function RM_GetFilePrefix(id, prefix, l)
    @ccall libphreeqcrm.RM_GetFilePrefix(id::Cint, prefix::Cstring, l::Cint)::IRM_RESULT
end

function RM_GetGasComponentsCount(id)
    @ccall libphreeqcrm.RM_GetGasComponentsCount(id::Cint)::Cint
end

function RM_GetGasComponentsName(id, num, name, l1)
    @ccall libphreeqcrm.RM_GetGasComponentsName(id::Cint, num::Cint, name::Cstring, l1::Cint)::IRM_RESULT
end

function RM_GetGasCompMoles(id, gas_moles)
    @ccall libphreeqcrm.RM_GetGasCompMoles(id::Cint, gas_moles::Ptr{Cdouble})::IRM_RESULT
end

function RM_GetGasCompPressures(id, gas_pressure)
    @ccall libphreeqcrm.RM_GetGasCompPressures(id::Cint, gas_pressure::Ptr{Cdouble})::IRM_RESULT
end

function RM_GetGasCompPhi(id, gas_phi)
    @ccall libphreeqcrm.RM_GetGasCompPhi(id::Cint, gas_phi::Ptr{Cdouble})::IRM_RESULT
end

function RM_GetGasPhaseVolume(id, gas_volume)
    @ccall libphreeqcrm.RM_GetGasPhaseVolume(id::Cint, gas_volume::Ptr{Cdouble})::IRM_RESULT
end

function RM_GetGfw(id, gfw)
    @ccall libphreeqcrm.RM_GetGfw(id::Cint, gfw::Ptr{Cdouble})::IRM_RESULT
end

function RM_GetGridCellCount(id)
    @ccall libphreeqcrm.RM_GetGridCellCount(id::Cint)::Cint
end

function RM_GetIPhreeqcId(id, i)
    @ccall libphreeqcrm.RM_GetIPhreeqcId(id::Cint, i::Cint)::Cint
end

function RM_GetKineticReactionsCount(id)
    @ccall libphreeqcrm.RM_GetKineticReactionsCount(id::Cint)::Cint
end

function RM_GetKineticReactionsName(id, num, name, l1)
    @ccall libphreeqcrm.RM_GetKineticReactionsName(id::Cint, num::Cint, name::Cstring, l1::Cint)::IRM_RESULT
end

function RM_GetMpiMyself(id)
    @ccall libphreeqcrm.RM_GetMpiMyself(id::Cint)::Cint
end

function RM_GetMpiTasks(id)
    @ccall libphreeqcrm.RM_GetMpiTasks(id::Cint)::Cint
end

function RM_GetNthSelectedOutputUserNumber(id, n)
    @ccall libphreeqcrm.RM_GetNthSelectedOutputUserNumber(id::Cint, n::Cint)::Cint
end

function RM_GetPorosity(id, porosity)
    @ccall libphreeqcrm.RM_GetPorosity(id::Cint, porosity::Ptr{Cdouble})::IRM_RESULT
end

function RM_GetPressure(id, pressure)
    @ccall libphreeqcrm.RM_GetPressure(id::Cint, pressure::Ptr{Cdouble})::IRM_RESULT
end

function RM_GetSaturationCalculated(id, sat_calc)
    @ccall libphreeqcrm.RM_GetSaturationCalculated(id::Cint, sat_calc::Ptr{Cdouble})::IRM_RESULT
end

function RM_GetSaturation(id, sat_calc)
    @ccall libphreeqcrm.RM_GetSaturation(id::Cint, sat_calc::Ptr{Cdouble})::IRM_RESULT
end

function RM_GetSelectedOutput(id, so)
    @ccall libphreeqcrm.RM_GetSelectedOutput(id::Cint, so::Ptr{Cdouble})::IRM_RESULT
end

function RM_GetSelectedOutputColumnCount(id)
    @ccall libphreeqcrm.RM_GetSelectedOutputColumnCount(id::Cint)::Cint
end

function RM_GetSelectedOutputCount(id)
    @ccall libphreeqcrm.RM_GetSelectedOutputCount(id::Cint)::Cint
end

function RM_GetSelectedOutputHeading(id, icol, heading, length)
    @ccall libphreeqcrm.RM_GetSelectedOutputHeading(id::Cint, icol::Cint, heading::Cstring, length::Cint)::IRM_RESULT
end

function RM_GetSelectedOutputRowCount(id)
    @ccall libphreeqcrm.RM_GetSelectedOutputRowCount(id::Cint)::Cint
end

function RM_GetSICount(id)
    @ccall libphreeqcrm.RM_GetSICount(id::Cint)::Cint
end

function RM_GetSIName(id, num, name, l1)
    @ccall libphreeqcrm.RM_GetSIName(id::Cint, num::Cint, name::Cstring, l1::Cint)::IRM_RESULT
end

function RM_GetSolidSolutionComponentsCount(id)
    @ccall libphreeqcrm.RM_GetSolidSolutionComponentsCount(id::Cint)::Cint
end

function RM_GetSolidSolutionComponentsName(id, num, name, l1)
    @ccall libphreeqcrm.RM_GetSolidSolutionComponentsName(id::Cint, num::Cint, name::Cstring, l1::Cint)::IRM_RESULT
end

function RM_GetSolidSolutionName(id, num, name, l1)
    @ccall libphreeqcrm.RM_GetSolidSolutionName(id::Cint, num::Cint, name::Cstring, l1::Cint)::IRM_RESULT
end

function RM_GetSolutionVolume(id, vol)
    @ccall libphreeqcrm.RM_GetSolutionVolume(id::Cint, vol::Ptr{Cdouble})::IRM_RESULT
end

function RM_GetSpeciesConcentrations(id, species_conc)
    @ccall libphreeqcrm.RM_GetSpeciesConcentrations(id::Cint, species_conc::Ptr{Cdouble})::IRM_RESULT
end

function RM_GetSpeciesCount(id)
    @ccall libphreeqcrm.RM_GetSpeciesCount(id::Cint)::Cint
end

function RM_GetSpeciesD25(id, diffc)
    @ccall libphreeqcrm.RM_GetSpeciesD25(id::Cint, diffc::Ptr{Cdouble})::IRM_RESULT
end

function RM_GetSpeciesLog10Gammas(id, species_log10gammas)
    @ccall libphreeqcrm.RM_GetSpeciesLog10Gammas(id::Cint, species_log10gammas::Ptr{Cdouble})::IRM_RESULT
end

function RM_GetSpeciesLog10Molalities(id, species_log10molalities)
    @ccall libphreeqcrm.RM_GetSpeciesLog10Molalities(id::Cint, species_log10molalities::Ptr{Cdouble})::IRM_RESULT
end

function RM_GetSpeciesName(id, i, name, length)
    @ccall libphreeqcrm.RM_GetSpeciesName(id::Cint, i::Cint, name::Cstring, length::Cint)::IRM_RESULT
end

function RM_GetSpeciesSaveOn(id)
    @ccall libphreeqcrm.RM_GetSpeciesSaveOn(id::Cint)::Cint
end

function RM_GetSpeciesZ(id, z)
    @ccall libphreeqcrm.RM_GetSpeciesZ(id::Cint, z::Ptr{Cdouble})::IRM_RESULT
end

function RM_GetStartCell(id, sc)
    @ccall libphreeqcrm.RM_GetStartCell(id::Cint, sc::Ptr{Cint})::IRM_RESULT
end

function RM_GetTemperature(id, temperature)
    @ccall libphreeqcrm.RM_GetTemperature(id::Cint, temperature::Ptr{Cdouble})::IRM_RESULT
end

function RM_GetSurfaceName(id, num, name, l1)
    @ccall libphreeqcrm.RM_GetSurfaceName(id::Cint, num::Cint, name::Cstring, l1::Cint)::IRM_RESULT
end

function RM_GetSurfaceSpeciesCount(id)
    @ccall libphreeqcrm.RM_GetSurfaceSpeciesCount(id::Cint)::Cint
end

function RM_GetSurfaceSpeciesName(id, num, name, l1)
    @ccall libphreeqcrm.RM_GetSurfaceSpeciesName(id::Cint, num::Cint, name::Cstring, l1::Cint)::IRM_RESULT
end

function RM_GetSurfaceType(id, num, name, l1)
    @ccall libphreeqcrm.RM_GetSurfaceType(id::Cint, num::Cint, name::Cstring, l1::Cint)::IRM_RESULT
end

function RM_GetThreadCount(id)
    @ccall libphreeqcrm.RM_GetThreadCount(id::Cint)::Cint
end

function RM_GetTime(id)
    @ccall libphreeqcrm.RM_GetTime(id::Cint)::Cdouble
end

function RM_GetTimeConversion(id)
    @ccall libphreeqcrm.RM_GetTimeConversion(id::Cint)::Cdouble
end

function RM_GetTimeStep(id)
    @ccall libphreeqcrm.RM_GetTimeStep(id::Cint)::Cdouble
end

function RM_GetViscosity(id, viscosity)
    @ccall libphreeqcrm.RM_GetViscosity(id::Cint, viscosity::Ptr{Cdouble})::IRM_RESULT
end

function RM_InitialPhreeqc2Concentrations(id, c, n_boundary, boundary_solution1, boundary_solution2, fraction1)
    @ccall libphreeqcrm.RM_InitialPhreeqc2Concentrations(id::Cint, c::Ptr{Cdouble}, n_boundary::Cint, boundary_solution1::Ptr{Cint}, boundary_solution2::Ptr{Cint}, fraction1::Ptr{Cdouble})::IRM_RESULT
end

function RM_InitialSolutions2Module(id, solutions)
    @ccall libphreeqcrm.RM_InitialSolutions2Module(id::Cint, solutions::Ptr{Cint})::IRM_RESULT
end

function RM_InitialEquilibriumPhases2Module(id, equilibrium_phases)
    @ccall libphreeqcrm.RM_InitialEquilibriumPhases2Module(id::Cint, equilibrium_phases::Ptr{Cint})::IRM_RESULT
end

function RM_InitialExchanges2Module(id, exchanges)
    @ccall libphreeqcrm.RM_InitialExchanges2Module(id::Cint, exchanges::Ptr{Cint})::IRM_RESULT
end

function RM_InitialSurfaces2Module(id, surfaces)
    @ccall libphreeqcrm.RM_InitialSurfaces2Module(id::Cint, surfaces::Ptr{Cint})::IRM_RESULT
end

function RM_InitialGasPhases2Module(id, gas_phases)
    @ccall libphreeqcrm.RM_InitialGasPhases2Module(id::Cint, gas_phases::Ptr{Cint})::IRM_RESULT
end

function RM_InitialSolidSolutions2Module(id, solid_solutions)
    @ccall libphreeqcrm.RM_InitialSolidSolutions2Module(id::Cint, solid_solutions::Ptr{Cint})::IRM_RESULT
end

function RM_InitialKinetics2Module(id, kinetics)
    @ccall libphreeqcrm.RM_InitialKinetics2Module(id::Cint, kinetics::Ptr{Cint})::IRM_RESULT
end

function RM_InitialPhreeqc2Module(id, initial_conditions1, initial_conditions2, fraction1)
    @ccall libphreeqcrm.RM_InitialPhreeqc2Module(id::Cint, initial_conditions1::Ptr{Cint}, initial_conditions2::Ptr{Cint}, fraction1::Ptr{Cdouble})::IRM_RESULT
end

function RM_InitialPhreeqc2SpeciesConcentrations(id, species_c, n_boundary, boundary_solution1, boundary_solution2, fraction1)
    @ccall libphreeqcrm.RM_InitialPhreeqc2SpeciesConcentrations(id::Cint, species_c::Ptr{Cdouble}, n_boundary::Cint, boundary_solution1::Ptr{Cint}, boundary_solution2::Ptr{Cint}, fraction1::Ptr{Cdouble})::IRM_RESULT
end

function RM_InitialPhreeqcCell2Module(id, n, module_numbers, dim_module_numbers)
    @ccall libphreeqcrm.RM_InitialPhreeqcCell2Module(id::Cint, n::Cint, module_numbers::Ptr{Cint}, dim_module_numbers::Cint)::IRM_RESULT
end

function RM_LoadDatabase(id, db_name)
    @ccall libphreeqcrm.RM_LoadDatabase(id::Cint, db_name::Cstring)::IRM_RESULT
end

function RM_LogMessage(id, str)
    @ccall libphreeqcrm.RM_LogMessage(id::Cint, str::Cstring)::IRM_RESULT
end

function RM_MpiWorker(id)
    @ccall libphreeqcrm.RM_MpiWorker(id::Cint)::IRM_RESULT
end

function RM_MpiWorkerBreak(id)
    @ccall libphreeqcrm.RM_MpiWorkerBreak(id::Cint)::IRM_RESULT
end

function RM_OpenFiles(id)
    @ccall libphreeqcrm.RM_OpenFiles(id::Cint)::IRM_RESULT
end

function RM_OutputMessage(id, str)
    @ccall libphreeqcrm.RM_OutputMessage(id::Cint, str::Cstring)::IRM_RESULT
end

function RM_RunCells(id)
    @ccall libphreeqcrm.RM_RunCells(id::Cint)::IRM_RESULT
end

function RM_RunFile(id, workers, initial_phreeqc, utility, chem_name)
    @ccall libphreeqcrm.RM_RunFile(id::Cint, workers::Cint, initial_phreeqc::Cint, utility::Cint, chem_name::Cstring)::IRM_RESULT
end

function RM_RunString(id, workers, initial_phreeqc, utility, input_string)
    @ccall libphreeqcrm.RM_RunString(id::Cint, workers::Cint, initial_phreeqc::Cint, utility::Cint, input_string::Cstring)::IRM_RESULT
end

function RM_ScreenMessage(id, str)
    @ccall libphreeqcrm.RM_ScreenMessage(id::Cint, str::Cstring)::IRM_RESULT
end

function RM_SetComponentH2O(id, tf)
    @ccall libphreeqcrm.RM_SetComponentH2O(id::Cint, tf::Cint)::IRM_RESULT
end

function RM_SetConcentrations(id, c)
    @ccall libphreeqcrm.RM_SetConcentrations(id::Cint, c::Ptr{Cdouble})::IRM_RESULT
end

function RM_SetCurrentSelectedOutputUserNumber(id, n_user)
    @ccall libphreeqcrm.RM_SetCurrentSelectedOutputUserNumber(id::Cint, n_user::Cint)::IRM_RESULT
end

function RM_SetDensityUser(id, density)
    @ccall libphreeqcrm.RM_SetDensityUser(id::Cint, density::Ptr{Cdouble})::IRM_RESULT
end

function RM_SetDensity(id, density)
    @ccall libphreeqcrm.RM_SetDensity(id::Cint, density::Ptr{Cdouble})::IRM_RESULT
end

function RM_SetDumpFileName(id, dump_name)
    @ccall libphreeqcrm.RM_SetDumpFileName(id::Cint, dump_name::Cstring)::IRM_RESULT
end

function RM_SetErrorHandlerMode(id, mode)
    @ccall libphreeqcrm.RM_SetErrorHandlerMode(id::Cint, mode::Cint)::IRM_RESULT
end

function RM_SetErrorOn(id, tf)
    @ccall libphreeqcrm.RM_SetErrorOn(id::Cint, tf::Cint)::IRM_RESULT
end

function RM_SetFilePrefix(id, prefix)
    @ccall libphreeqcrm.RM_SetFilePrefix(id::Cint, prefix::Cstring)::IRM_RESULT
end

function RM_SetGasCompMoles(id, gas_moles)
    @ccall libphreeqcrm.RM_SetGasCompMoles(id::Cint, gas_moles::Ptr{Cdouble})::IRM_RESULT
end

function RM_SetGasPhaseVolume(id, gas_volume)
    @ccall libphreeqcrm.RM_SetGasPhaseVolume(id::Cint, gas_volume::Ptr{Cdouble})::IRM_RESULT
end

function RM_SetMpiWorkerCallback(id, fcn)
    @ccall libphreeqcrm.RM_SetMpiWorkerCallback(id::Cint, fcn::Ptr{Cvoid})::IRM_RESULT
end

function RM_SetMpiWorkerCallbackCookie(id, cookie)
    @ccall libphreeqcrm.RM_SetMpiWorkerCallbackCookie(id::Cint, cookie::Ptr{Cvoid})::IRM_RESULT
end

function RM_SetNthSelectedOutput(id, n)
    @ccall libphreeqcrm.RM_SetNthSelectedOutput(id::Cint, n::Cint)::IRM_RESULT
end

function RM_SetPartitionUZSolids(id, tf)
    @ccall libphreeqcrm.RM_SetPartitionUZSolids(id::Cint, tf::Cint)::IRM_RESULT
end

function RM_SetPorosity(id, por)
    @ccall libphreeqcrm.RM_SetPorosity(id::Cint, por::Ptr{Cdouble})::IRM_RESULT
end

function RM_SetPressure(id, p)
    @ccall libphreeqcrm.RM_SetPressure(id::Cint, p::Ptr{Cdouble})::IRM_RESULT
end

function RM_SetPrintChemistryMask(id, cell_mask)
    @ccall libphreeqcrm.RM_SetPrintChemistryMask(id::Cint, cell_mask::Ptr{Cint})::IRM_RESULT
end

function RM_SetPrintChemistryOn(id, workers, initial_phreeqc, utility)
    @ccall libphreeqcrm.RM_SetPrintChemistryOn(id::Cint, workers::Cint, initial_phreeqc::Cint, utility::Cint)::IRM_RESULT
end

function RM_SetRebalanceByCell(id, method)
    @ccall libphreeqcrm.RM_SetRebalanceByCell(id::Cint, method::Cint)::IRM_RESULT
end

function RM_SetRebalanceFraction(id, f)
    @ccall libphreeqcrm.RM_SetRebalanceFraction(id::Cint, f::Cdouble)::IRM_RESULT
end

function RM_SetRepresentativeVolume(id, rv)
    @ccall libphreeqcrm.RM_SetRepresentativeVolume(id::Cint, rv::Ptr{Cdouble})::IRM_RESULT
end

function RM_SetSaturationUser(id, sat)
    @ccall libphreeqcrm.RM_SetSaturationUser(id::Cint, sat::Ptr{Cdouble})::IRM_RESULT
end

function RM_SetSaturation(id, sat)
    @ccall libphreeqcrm.RM_SetSaturation(id::Cint, sat::Ptr{Cdouble})::IRM_RESULT
end

function RM_SetScreenOn(id, tf)
    @ccall libphreeqcrm.RM_SetScreenOn(id::Cint, tf::Cint)::IRM_RESULT
end

function RM_SetSelectedOutputOn(id, selected_output)
    @ccall libphreeqcrm.RM_SetSelectedOutputOn(id::Cint, selected_output::Cint)::IRM_RESULT
end

function RM_SetSpeciesSaveOn(id, save_on)
    @ccall libphreeqcrm.RM_SetSpeciesSaveOn(id::Cint, save_on::Cint)::IRM_RESULT
end

function RM_SetTemperature(id, t)
    @ccall libphreeqcrm.RM_SetTemperature(id::Cint, t::Ptr{Cdouble})::IRM_RESULT
end

function RM_SetTime(id, time)
    @ccall libphreeqcrm.RM_SetTime(id::Cint, time::Cdouble)::IRM_RESULT
end

function RM_SetTimeConversion(id, conv_factor)
    @ccall libphreeqcrm.RM_SetTimeConversion(id::Cint, conv_factor::Cdouble)::IRM_RESULT
end

function RM_SetTimeStep(id, time_step)
    @ccall libphreeqcrm.RM_SetTimeStep(id::Cint, time_step::Cdouble)::IRM_RESULT
end

function RM_SetUnitsExchange(id, option)
    @ccall libphreeqcrm.RM_SetUnitsExchange(id::Cint, option::Cint)::IRM_RESULT
end

function RM_SetUnitsGasPhase(id, option)
    @ccall libphreeqcrm.RM_SetUnitsGasPhase(id::Cint, option::Cint)::IRM_RESULT
end

function RM_SetUnitsKinetics(id, option)
    @ccall libphreeqcrm.RM_SetUnitsKinetics(id::Cint, option::Cint)::IRM_RESULT
end

function RM_SetUnitsPPassemblage(id, option)
    @ccall libphreeqcrm.RM_SetUnitsPPassemblage(id::Cint, option::Cint)::IRM_RESULT
end

function RM_SetUnitsSolution(id, option)
    @ccall libphreeqcrm.RM_SetUnitsSolution(id::Cint, option::Cint)::IRM_RESULT
end

function RM_SetUnitsSSassemblage(id, option)
    @ccall libphreeqcrm.RM_SetUnitsSSassemblage(id::Cint, option::Cint)::IRM_RESULT
end

function RM_SetUnitsSurface(id, option)
    @ccall libphreeqcrm.RM_SetUnitsSurface(id::Cint, option::Cint)::IRM_RESULT
end

function RM_SpeciesConcentrations2Module(id, species_conc)
    @ccall libphreeqcrm.RM_SpeciesConcentrations2Module(id::Cint, species_conc::Ptr{Cdouble})::IRM_RESULT
end

function RM_StateSave(id, istate)
    @ccall libphreeqcrm.RM_StateSave(id::Cint, istate::Cint)::IRM_RESULT
end

function RM_StateApply(id, istate)
    @ccall libphreeqcrm.RM_StateApply(id::Cint, istate::Cint)::IRM_RESULT
end

function RM_StateDelete(id, istate)
    @ccall libphreeqcrm.RM_StateDelete(id::Cint, istate::Cint)::IRM_RESULT
end

function RM_UseSolutionDensityVolume(id, tf)
    @ccall libphreeqcrm.RM_UseSolutionDensityVolume(id::Cint, tf::Cint)::IRM_RESULT
end

function RM_WarningMessage(id, warn_str)
    @ccall libphreeqcrm.RM_WarningMessage(id::Cint, warn_str::Cstring)::IRM_RESULT
end

end # module
