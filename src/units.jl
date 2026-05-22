# Unit enums for the seven reactant categories.
#
# Upstream PhreeqcRM uses small integer codes for each unit, but the **same
# integer means different things across categories** (e.g. `1` is mg/L for
# solutions but mol/L of rock for PP_assemblage). One shared enum would silently
# misinterpret values, so each category gets its own `@enum`.
#
# Values come from the PhreeqcRM C++ header / documentation:
#   SOLUTION                : 1=mg/L,   2=mol/L,        3=kg/kgs
#   PP_ASSEMBLAGE           : 0=mol/L rock, 1=mol/L water, 2=mol/L rock-frac
#   EXCHANGE / SURFACE
#   GAS_PHASE / SS_ASSEMBLAGE / KINETICS : same three options as PP_ASSEMBLAGE

baremodule SolutionUnits
    using Base: @enum
    @enum T::Int32 begin
        MgPerL = 1
        MolPerL = 2
        KgPerKgSolution = 3
    end
end

baremodule PPAssemblageUnits
    using Base: @enum
    @enum T::Int32 begin
        MolPerLRock = 0
        MolPerLWater = 1
        MolPerLRockFraction = 2
    end
end

baremodule ExchangeUnits
    using Base: @enum
    @enum T::Int32 begin
        MolPerLRock = 0
        MolPerLWater = 1
        MolPerLRockFraction = 2
    end
end

baremodule SurfaceUnits
    using Base: @enum
    @enum T::Int32 begin
        MolPerLRock = 0
        MolPerLWater = 1
        MolPerLRockFraction = 2
    end
end

baremodule GasPhaseUnits
    using Base: @enum
    @enum T::Int32 begin
        MolPerLRock = 0
        MolPerLWater = 1
        MolPerLRockFraction = 2
    end
end

baremodule SSAssemblageUnits
    using Base: @enum
    @enum T::Int32 begin
        MolPerLRock = 0
        MolPerLWater = 1
        MolPerLRockFraction = 2
    end
end

baremodule KineticsUnits
    using Base: @enum
    @enum T::Int32 begin
        MolPerLRock = 0
        MolPerLWater = 1
        MolPerLRockFraction = 2
    end
end
