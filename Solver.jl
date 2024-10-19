module Solver

using JuMP
using HiGHS
using MathOptInterface
using Pkg
using DataFrames
using Dates
using CSV
using JSON
using DataStructures 
  
export Solve 

#%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%
#%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@ FUNctions %@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@
#%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%@%

function get_or_default(dict, key, default)
    return get(dict, key, default) === nothing ? default : get(dict, key, default)
end

#-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-

function create_specification_nutrient_records(df)
    specification_nutrient_records = OrderedDict()
    grouped = groupby(df_lsn_resp, [:LocationId, :SpecificationId])
    for (group, specification_groups) in pairs(grouped)
        nutrient_list = []
        for row in eachrow(specification_groups)
            nutrient_dict = OrderedDict{String, Any}()
            for (key, value) in pairs(row)
                if !(key in [:LocationId, :SpecificationId]) &&
                   !(value isa Real && (isnan(value) || isinf(value))) &&
                   !ismissing(value)
                    nutrient_dict[string(key)] = value
                end
            end
            push!(nutrient_list, nutrient_dict)
        end
        specification_nutrient_records[group] = nutrient_list
    end
    return specification_nutrient_records
end

#-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-

function create_specification_ingredient_records(df)
    specification_ingredient_records = OrderedDict()
    grouped = groupby(df, [:LocationId, :SpecificationId])
    for (group, specification_groups) in pairs(grouped)
        ingredient_list = []
        for row in eachrow(specification_groups)
            ingredient_dict = OrderedDict{String, Any}()
            for (key, value) in pairs(row)
                if !(key in [:LocationId, :SpecificationId]) &&
                   !(value isa Real && (isnan(value) || isinf(value))) &&
                   !ismissing(value)
                    ingredient_dict[string(key)] = value
                end
            end
            push!(ingredient_list, ingredient_dict)
        end
        specification_ingredient_records[group] = ingredient_list
    end
    return specification_ingredient_records
end

#-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-

function create_location_ingredient_records(df)
    location_ingredient_records = OrderedDict()
    grouped = groupby(df, [:LocationId])
    for (location_id, ingredient_groups) in pairs(grouped)
        ingredient_list = []
        for row in eachrow(ingredient_groups)
            ingredient_dict = OrderedDict{String, Any}()
            for (key, value) in pairs(row)
                if key != :LocationId &&
                   !(value isa Real && (isnan(value) || isinf(value))) &&
                   !ismissing(value)
                    ingredient_dict[string(key)] = value
                end
            end
            push!(ingredient_list, ingredient_dict)
        end
        location_ingredient_records[location_id] = ingredient_list
    end
    return location_ingredient_records
end

#-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-
#-------------------------------------------------------------------------------------------------

  
function Solve(json_string::String)::String  

############# START model.jl ############### 

total_start_timestamp = now()

#-------------------------------------------------------------------------------------------------
### SETTINGS ###
#-------------------------------------------------------------------------------------------------

write_shit_in = 0
write_shit_in_for_realz = 0
write_shit_out = 1

#-------------------------------------------------------------------------------------------------
### CONSTANTS ###
#-------------------------------------------------------------------------------------------------

NEG_COST_TOL = -0.01
COST_SCALAR = 0.01

BADDEST = 1000000000

LS_BAD = BADDEST / 1000.0
I_BAD = BADDEST / 100.0
LI_BAD = BADDEST / 10.0
LSN_BAD = BADDEST / 1.0

#-------------------------------------------------------------------------------------------------
### RIP JSON FOUR ASSHOLES ###
#-------------------------------------------------------------------------------------------------

json_start_timestamp = now()

#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-

#file_path = "temp.json"
#file_path = "test_1.json"
#json_string = read(file_path, String)
json_data = JSON.parse(json_string)

#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-

optimization_id = get(json_data, "OptimizationId", nothing)

has_vol_nut = 0
vol_nut = nothing
details = get(json_data, "Details", nothing)

if details !== nothing
    if haskey(details, "VolumeNutrientId") && details["VolumeNutrientId"] !== nothing
        has_vol_nut = 1
        vol_nut = details["VolumeNutrientId"]
    end
end

if has_vol_nut == 1
    df_deetz = DataFrame(details)
else
    df_deetz = DataFrame(Dict("VolNut" => "Nope"))
end

#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-

df_lsn = DataFrame(LocationId=String[], SpecificationId=String[], Tons=Float64[], TonsStep=Float64[], NutrientId=String[], Min=Float64[], Max=Float64[], MinStep=Float64[], MaxStep=Float64[], NumeratorId=String[], DenominatorId=String[])
df_lsi = DataFrame(LocationId=String[], SpecificationId=String[], Tons=Float64[], IngredientId=String[], Min=Float64[], Max=Float64[], MinStep=Float64[], MaxStep=Float64[], FixedLevel=Float64[])
df_lin = DataFrame(LocationId=String[], IngredientId=String[], Min=Float64[], Max=Float64[], Cost=Float64[], MinStep=Float64[], MaxStep=Float64[], CostStep=Float64[], Available=Bool[], Global=Bool[], NutrientId=String[], Level=Float64[])

DUMMY_NUTRIENT_LIST = [Dict("NutrientId" => "NO_NUT", "Level" => 0.0)]
DUMMY_NUTRIENT_LIST_2 = [Dict("NutrientId" => "NO_NUT", "Min" => nothing, "Max" => nothing, "NumeratorId" => nothing, "DenominatorId" => nothing)]

for location in json_data["Locations"]
    location_id = location["LocationId"]
    
    for spec in location["Specifications"]
        spec_id = spec["SpecificationId"]
        tons = get_or_default(spec, "Tons", 1.0)
        tons_step = get_or_default(spec, "TonsStep", 0.0)
        nutrient_requirements = isempty(spec["NutrientRequirements"]) ? DUMMY_NUTRIENT_LIST_2 : spec["NutrientRequirements"]
        for nutrient in nutrient_requirements
            min_step = get_or_default(nutrient, "MinStep", 0.0)
            max_step = get_or_default(nutrient, "MaxStep", 0.0)
            min_val = get_or_default(nutrient, "Min", NaN)
            max_val = get_or_default(nutrient, "Max", NaN)
            numerator_id = get_or_default(nutrient, "NumeratorId", "")
            denominator_id = get_or_default(nutrient, "DenominatorId", "")
            push!(df_lsn, (location_id, spec_id, tons, tons_step, nutrient["NutrientId"], min_val, max_val, min_step, max_step, numerator_id, denominator_id))
        end
        
        for ingredient in spec["IngredientRequirements"]
            min_step = get_or_default(ingredient, "MinStep", 0.0)
            max_step = get_or_default(ingredient, "MaxStep", 0.0)
            min_val = get_or_default(ingredient, "Min", NaN)
            max_val = get_or_default(ingredient, "Max", NaN)
            fixed_level = get_or_default(ingredient, "FixedLevel", 0.0)
            push!(df_lsi, (location_id, spec_id, tons, ingredient["IngredientId"], min_val, max_val, min_step, max_step, fixed_level))
        end
    end
    
    for ingredient in location["Ingredients"]
        cost_step = get_or_default(ingredient, "CostStep", 0.0)
        min_step = get_or_default(ingredient, "MinStep", 0.0)
        max_step = get_or_default(ingredient, "MaxStep", 0.0)
        min_val = get_or_default(ingredient, "Min", NaN)
        max_val = get_or_default(ingredient, "Max", NaN)
        cost = get_or_default(ingredient, "Cost", 0.0)
        available = get_or_default(ingredient, "Available", true)
        is_global = get_or_default(ingredient, "Global", true)
        nutrient_levels = isempty(ingredient["NutrientLevels"]) ? DUMMY_NUTRIENT_LIST : ingredient["NutrientLevels"]
        for nutrient in nutrient_levels
            level = get_or_default(nutrient, "Level", 0.0)
            push!(df_lin, (location_id, ingredient["IngredientId"], min_val, max_val, cost, min_step, max_step, cost_step, available, is_global, nutrient["NutrientId"], level))
        end
    end
end

select!(df_lsi, Not([:Tons]))

#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-

ingredients = json_data["GlobalIngredients"]

for ingredient in ingredients
    if !haskey(ingredient, "MinStep")
        ingredient["MinStep"] = 0.0
    end
    if !haskey(ingredient, "MaxStep")
        ingredient["MaxStep"] = 0.0
    end
end

df_i = DataFrame(ingredients)
df_i = df_i[:, ["IngredientId", "Min", "Max", "MinStep", "MaxStep"]]

df_i.Min = ifelse.(df_i.Min .=== nothing, 0.0, df_i.Min)
df_i.Max = ifelse.(df_i.Max .=== nothing, Inf, df_i.Max)
df_i.HasMax .= ifelse.(df_i.Max .== Inf, 0, 1)

df_i.Index_I = 1:nrow(df_i)
sort!(df_i, :Index_I)

#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-

json_end_timestamp = now()
json_total_time = json_end_timestamp - json_start_timestamp
println("Reading and ripping JSON request file: ", json_total_time)

#-------------------------------------------------------------------------------------------------
### PREP SOLVER DATA ARRAYS ###
#-------------------------------------------------------------------------------------------------

arrays_start_timestamp = now()

#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-
# LI LI LI LI LI LI LI LI LI LI LI LI LI LI LI LI LI LI LI LI LI LI LI LI LI LI LI LI LI LI LI LI 

df_li = unique(select(df_lin, [:LocationId, :IngredientId, :Min, :Max, :Cost, :MinStep, :MaxStep, :CostStep, :Available, :Global]))

df_li.Min = ifelse.(isnan.(df_li.Min), 0.0, df_li.Min)
df_li.Max = ifelse.(isnan.(df_li.Max), Inf, df_li.Max)
df_li.HasMax .= ifelse.(df_li.Max .== Inf, 0, 1)

df_li = innerjoin(df_li, df_i[:, ["IngredientId", "Index_I"]], on = :IngredientId)

df_li.IsAvailable .= ifelse.(string.(df_li.Available) .== "true", 1, 0)
df_li.IsGlobal .= ifelse.(string.(df_li.Global) .== "true", 1, 0)

df_li.Index_LI = 1:nrow(df_li)
sort!(df_li, :Index_LI)

#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-
# LS LS LS LS LS LS LS LS LS LS LS LS LS LS LS LS LS LS LS LS LS LS LS LS LS LS LS LS LS LS LS LS 

df_ls = unique(select(df_lsn, [:LocationId, :SpecificationId, :Tons, :TonsStep]))

df_ls.IsZero .= ifelse.(df_ls.Tons .== 0, 1, 0)
df_ls.Tons .= ifelse.(df_ls.IsZero .== 1, 1.0, df_ls.Tons)

df_ls.Index_LS = 1:nrow(df_ls)
sort!(df_ls, :Index_LS)

#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-
# LIN LIN LIN LIN LIN LIN LIN LIN LIN LIN LIN LIN LIN LIN LIN LIN LIN LIN LIN LIN LIN LIN LIN LIN 

df_lin = innerjoin(df_lin, df_li[:, ["LocationId", "IngredientId", "Index_LI", "Index_I"]], on = [:LocationId, :IngredientId])
select!(df_lin, Not([:Min, :Max, :MinStep, :MaxStep, :CostStep]))

df_lin.Level .= ifelse.(abs.(df_lin.Level) .== 999999999, 0, df_lin.Level)
df_lin.Level .= ifelse.(abs.(df_lin.Level) .== 99999999, 0, df_lin.Level)

df_lin.IsHuge = ifelse.(abs.(df_lin.Level) .> 9999999.9, 1, 0)

df_lin.Index_LIN = 1:nrow(df_lin)
sort!(df_lin, :Index_LIN)

#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-
# LSN LSN LSN LSN LSN LSN LSN LSN LSN LSN LSN LSN LSN LSN LSN LSN LSN LSN LSN LSN LSN LSN LSN LSN 

df_lsn = innerjoin(df_lsn, df_ls, on=[:LocationId, :SpecificationId], makeunique=true)
select!(df_lsn, Not([:Tons, :Tons_1, :TonsStep, :TonsStep_1]))

df_lsn.HasMin .= ifelse.(ismissing.(df_lsn.Min) .| isnan.(df_lsn.Min), 0, 1)
df_lsn.HasMax .= ifelse.(ismissing.(df_lsn.Max) .| isnan.(df_lsn.Max), 0, 1)

df_lsn.IsRatio .= ifelse.(length.(df_lsn.NumeratorId) .> 0 .&& length.(df_lsn.DenominatorId) .> 0, 1, 0)

df_lsn.Index_LSN = 1:nrow(df_lsn)
sort!(df_lsn, :Index_LSN)

df_lsn.All3 = string.(df_lsn.LocationId, "_", df_lsn.SpecificationId, "_", df_lsn.NutrientId)
df_lsn.All3_N = string.(df_lsn.LocationId, "_", df_lsn.SpecificationId, "_", df_lsn.NumeratorId)
df_lsn.All3_D = string.(df_lsn.LocationId, "_", df_lsn.SpecificationId, "_", df_lsn.DenominatorId)

lookup_dict = Dict(df_lsn.All3 .=> df_lsn.Index_LSN)
df_lsn.NumeratorLsnId = [get(lookup_dict, id, missing) for id in df_lsn.All3_N]
df_lsn.DenominatorLsnId = [get(lookup_dict, id, missing) for id in df_lsn.All3_D]

select!(df_lsn, Not(:All3, :All3_N, :All3_D))

#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-
# LSI LSI LSI LSI LSI LSI LSI LSI LSI LSI LSI LSI LSI LSI LSI LSI LSI LSI LSI LSI LSI LSI LSI LSI 

df_lsi = innerjoin(df_lsi, df_ls, on=[:LocationId, :SpecificationId], makeunique=true)
rename!(df_lsi, :Tons => :SpecTons)

df_lsi = innerjoin(df_lsi, select(df_li, [:LocationId, :IngredientId, :Index_LI, :Index_I, :Cost]), on = [:LocationId, :IngredientId])

df_lsi = transform(groupby(df_lsi, [:LocationId, :SpecificationId]), :FixedLevel => (d -> any(d .> 0) ? 1 : 0) => :IsFixed)

df_lsi.Min[df_lsi.IsFixed .== 1] .= df_lsi.FixedLevel[df_lsi.IsFixed .== 1]
df_lsi.Max[df_lsi.IsFixed .== 1] .= df_lsi.FixedLevel[df_lsi.IsFixed .== 1]
df_lsi.FixedTonsIn .= ifelse.(df_lsi.IsFixed .== 1, df_lsi.SpecTons .* df_lsi.FixedLevel ./ 100.0, 0.0)

df_lsi.Index_LSI = 1:nrow(df_lsi)
sort!(df_lsi, :Index_LSI)

#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-
# LSIN LSIN LSIN LSIN LSIN LSIN LSIN LSIN LSIN LSIN LSIN LSIN LSIN LSIN LSIN LSIN LSIN LSIN LSIN

df_lsi_0 = df_lsi[:, [:LocationId, :SpecificationId, :IngredientId, :Index_LSI]]
df_lsn_0 = df_lsn[(df_lsn.IsRatio .== 0) .& (df_lsn.NutrientId .!= vol_nut), [:LocationId, :SpecificationId, :NutrientId, :Index_LSN]]
df_lin_0 = df_lin[df_lin.Level .!= 0.0, [:LocationId, :IngredientId, :NutrientId, :Index_LIN]]

df_lsin_0 = outerjoin(df_lsi_0, df_lsn_0, on = [:LocationId, :SpecificationId])
df_lsin_0 = dropmissing(df_lsin_0, [:NutrientId])
df_lsin = innerjoin(df_lsin_0, df_lin_0, on = [:LocationId, :IngredientId, :NutrientId])

#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-
# LS_2 LS_2 LS_2 LS_2 LS_2 LS_2 LS_2 LS_2 LS_2 LS_2 LS_2 LS_2 LS_2 LS_2 LS_2 LS_2 LS_2 LS_2 LS_2

df_ls_2a = combine(groupby(df_lsi, [:LocationId, :SpecificationId]), :IsFixed => sum => :IsFixedTot)
df_ls_2b = combine(groupby(df_lsi, [:LocationId, :SpecificationId]), :FixedTonsIn => sum => :FixedTonsIn)

df_ls = leftjoin(df_ls, df_ls_2a, on = [:LocationId, :SpecificationId])
df_ls = leftjoin(df_ls, df_ls_2b, on = [:LocationId, :SpecificationId])

df_ls.IsFixed = ifelse.(df_ls.IsFixedTot .> 0, 1, 0)

df_lsin_1 = df_lsin[df_lsin.NutrientId .== vol_nut, :]
df_ls_1 = combine(groupby(df_lsin_1, [:LocationId, :SpecificationId]), nrow => :VolNutTot)
df_ls_1.HasVolNut .= 1
df_ls_1.HasVolNut[df_ls_1.VolNutTot .== 0] .= 0

df_ls = leftjoin(df_ls, df_ls_1[:, [:LocationId, :SpecificationId, :VolNutTot, :HasVolNut]], on = [:LocationId, :SpecificationId])
df_ls.VolNutTot = coalesce.(df_ls.VolNutTot, 0)
df_ls.HasVolNut = coalesce.(df_ls.HasVolNut, 0)

#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-
# I_2 I_2 I_2 I_2 I_2 I_2 I_2 I_2 I_2 I_2 I_2 I_2 I_2 I_2 I_2 I_2 I_2 I_2 I_2 I_2 I_2 I_2 I_2 I_2 

df_i_2 = combine(groupby(df_li, :IngredientId), :IsGlobal => sum => :NumGlobal)
df_i = leftjoin(df_i, df_i_2, on = :IngredientId)
df_i.NumGlobal = coalesce.(df_i.NumGlobal, 0)

sort!(df_i, :Index_I)

#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-
# LI_2 LSI_2 LS_3 LSN_2 LI_2 LSI_2 LS_3 LSN_2 LI_2 LSI_2 LS_3 LSN_2 LI_2 LSI_2 LS_3 LSN_2 LI_2

if has_vol_nut == 0 || count(x -> x == vol_nut, df_lin.NutrientId) == 0
    df_li.Volume .= 1
else
    df_li.Volume1 .= 0

    t_df = df_lin[df_lin.NutrientId .== vol_nut, [:LocationId, :IngredientId, :Level]]
    rename!(t_df, :Level => :Volume2)

    df_li = leftjoin(df_li, t_df[:, [:LocationId, :IngredientId, :Volume2]], on = [:LocationId, :IngredientId])
    df_li.Volume2 = coalesce.(df_li.Volume2, 0)
    df_li.Volume = (df_li.Volume1 .+ df_li.Volume2) ./ 100.0
    select!(df_li, Not([:Volume1, :Volume2]))
end

df_lsi = leftjoin(df_lsi, df_li[:, [:LocationId, :IngredientId, :Volume]], on = [:LocationId, :IngredientId])

df_lsn = leftjoin(df_lsn, df_ls[:, [:LocationId, :SpecificationId, :IsFixed]], on = [:LocationId, :SpecificationId])
df_lsn.Min .= ifelse.(df_lsn.IsFixed .== 1, -Inf, df_lsn.Min)
df_lsn.HasMin .= ifelse.(df_lsn.IsFixed .== 1, 0, df_lsn.HasMin)
df_lsn.Max .= ifelse.(df_lsn.IsFixed .== 1, Inf, df_lsn.Max)
df_lsn.HasMax .= ifelse.(df_lsn.IsFixed .== 1, 0, df_lsn.HasMax)

#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-

arrays_end_timestamp = now()
arrays_total_time = arrays_end_timestamp - arrays_start_timestamp
println("Building solver arrays: ", arrays_total_time)

#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-

write_csv_in_start_timestamp = now()

if write_shit_in == 1
    CSV.write("DEETZ_df.csv", df_deetz)
    CSV.write("LSN_df.csv", df_lsn)
    CSV.write("LSI_df.csv", df_lsi)
    CSV.write("LS_df.csv", df_ls)
    CSV.write("LI_df.csv", df_li)
    CSV.write("I_df.csv", df_i)
    if write_shit_in_for_realz == 1
        CSV.write("LSIN_df.csv", df_lsin)
        CSV.write("LIN_df.csv", df_lin)
    end
end

write_csv_in_end_timestamp = now()
write_csv_in_total_time = write_csv_in_end_timestamp - write_csv_in_start_timestamp
println("Write Input CSVs: ", write_csv_in_total_time)

#~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~
# Get Solver Data Ready
#~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~

data_start_timestamp = now()

lin_level = collect(df_lin.Level)

s_lsn = collect(df_lsn.Index_LSN)
lsn_min = collect(df_lsn.Min)
lsn_has_min = collect(df_lsn.HasMin)
lsn_max = collect(df_lsn.Max)
lsn_has_max = collect(df_lsn.HasMax)
lsn_is_ratio = collect(df_lsn.IsRatio)
lsn_nut_ids = collect(df_lsn.NutrientId)
lsn_top_ids = collect(df_lsn.NumeratorLsnId)
lsn_bot_ids = collect(df_lsn.DenominatorLsnId)
lsn_2_ls = collect(df_lsn.Index_LS)

s_lsi = collect(df_lsi.Index_LSI)
lsi_min = collect(df_lsi.Min)
lsi_max = collect(df_lsi.Max)
lsi_zero = collect(df_lsi.IsZero)
lsi_vol = collect(df_lsi.Volume)
lsi_2_ls = collect(df_lsi.Index_LS)

s_ls = collect(df_ls.Index_LS)
ls_tons = collect(df_ls.Tons)

s_li = collect(df_li.Index_LI)
li_min = collect(df_li.Min)
li_max = collect(df_li.Max)
li_has_max = collect(df_li.HasMax)
li_cost = collect(df_li.Cost)
li_global = collect(df_li.IsGlobal)

s_i = collect(df_i.Index_I)
i_min = collect(df_i.Min)
i_max = collect(df_i.Max)
i_has_max = collect(df_i.HasMax)

#~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~

grouped_df = combine(groupby(df_lsin, :Index_LSN), :Index_LSI => (x -> collect(x)) => :Index_LSI, :Index_LIN => (x -> collect(x)) => :Index_LIN)
range_lsn = DataFrame(Index_LSN = 1:(nrow(df_lsin)))
t_df_0 = outerjoin(range_lsn, grouped_df, on = :Index_LSN)
t_df = groupby(t_df_0, :Index_LSN)
lsn_2_lsi = [group.Index_LSI for group in t_df]
lsn_2_lin = [group.Index_LIN for group in t_df]

t_df = groupby(df_lsi, :Index_LS)
ls_2_lsi = [group.Index_LSI for group in t_df]

t_df = groupby(df_lsi, :Index_LI)
li_2_lsi = [group.Index_LSI for group in t_df]

grouped_df = combine(groupby(df_li, :Index_I), :Index_LI => (x -> collect(x)) => :Index_LI)
range_i = DataFrame(Index_I = 1:(nrow(df_i)))
t_df_0 = outerjoin(range_i, grouped_df, on = :Index_I)
t_df = groupby(t_df_0, :Index_I)
i_2_li = [group.Index_LI for group in t_df]

#^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^

cnt_lsin = nrow(df_lsin)
cnt_lsn = length(s_lsn)
cnt_lsi = length(s_lsi)
cnt_ls = length(s_ls)
cnt_li = length(s_li)
cnt_i = length(s_i)

OBJ_SCALAR = 1.0
if cnt_lsin >= 1e6
    OBJ_SCALAR = (1e5) * (1.0)
elseif cnt_lsin >= 1e7
    OBJ_SCALAR = (1e8) * (1.0)
elseif cnt_lsin >= 1e8
    OBJ_SCALAR = (1e12) * (1.0)
end

data_end_timestamp = now()
data_total_time = data_end_timestamp - data_start_timestamp
println("Prepping Solver Data: ", data_total_time)

#^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^

# Create a model with the HiGHS solver
CNC = Model(HiGHS.Optimizer)

set_optimizer_attribute(CNC, "presolve", "on")
set_optimizer_attribute(CNC, "time_limit", 60.0)
set_optimizer_attribute(CNC, "primal_feasibility_tolerance", 0.00000001)
set_optimizer_attribute(CNC, "dual_feasibility_tolerance", 0.00000001)

#*************************************************************************************************
# Define variables
#*************************************************************************************************

initialize_variables_start_timestamp = now()

#^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^

df_lsn.x_lsn_index = Vector{Union{Missing, Int}}(missing, nrow(df_lsn))
df_lsn.x_lsn_pos_index = Vector{Union{Missing, Int}}(missing, nrow(df_lsn))
df_lsn.x_lsn_neg_index = Vector{Union{Missing, Int}}(missing, nrow(df_lsn))

@variable(CNC, x_lsn[lsn in s_lsn])
@variable(CNC, x_lsn_pos[lsn in s_lsn] >= 0)
@variable(CNC, x_lsn_neg[lsn in s_lsn] >= 0)
@variable(CNC, sum_lsn[lsn in s_lsn])

for lsn in 1:cnt_lsn
    if lsn_is_ratio[lsn] == 0
        if lsn_has_min[lsn] == 1
            set_lower_bound(x_lsn[lsn], lsn_min[lsn])
        end
        if lsn_has_max[lsn] == 1
            set_upper_bound(x_lsn[lsn], lsn_max[lsn])
        end
    end
    df_lsn.x_lsn_index[lsn] = index(x_lsn[lsn]).value
    df_lsn.x_lsn_pos_index[lsn] = index(x_lsn_pos[lsn]).value
    df_lsn.x_lsn_neg_index[lsn] = index(x_lsn_neg[lsn]).value    
end

#*************************************************************************************************

df_lsi.x_lsi_index = Vector{Union{Missing, Int}}(missing, nrow(df_lsi))

@variable(CNC, x_lsi[lsi in s_lsi] >= 0)

for lsi in 1:cnt_lsi
    if lsi_min[lsi] != lsi_max[lsi]
        set_lower_bound(x_lsi[lsi], (ls_tons[lsi_2_ls[lsi]] / 100.0) * lsi_min[lsi])
        set_upper_bound(x_lsi[lsi], (ls_tons[lsi_2_ls[lsi]] / 100.0) * lsi_max[lsi])
    else
        set_lower_bound(x_lsi[lsi], (ls_tons[lsi_2_ls[lsi]] / 100.0) * (lsi_min[lsi]))
        set_upper_bound(x_lsi[lsi], (ls_tons[lsi_2_ls[lsi]] / 100.0) * (lsi_max[lsi]))
    end
    df_lsi.x_lsi_index[lsi] = index(x_lsi[lsi]).value
end

#*************************************************************************************************

df_ls.x_ls_index = Vector{Union{Missing, Int}}(missing, nrow(df_ls))
df_ls.x_ls_pos_index = Vector{Union{Missing, Int}}(missing, nrow(df_ls))
df_ls.x_ls_neg_index = Vector{Union{Missing, Int}}(missing, nrow(df_ls))

@variable(CNC, x_ls[ls in s_ls] >= 0)
@variable(CNC, x_ls_pos[ls in s_ls] >= 0)
@variable(CNC, x_ls_neg[ls in s_ls] >= 0)
@variable(CNC, sum_ls[ls in s_ls] >= 0)

for ls in 1:cnt_ls
    set_lower_bound(x_ls[ls], ls_tons[ls])
    set_upper_bound(x_ls[ls], ls_tons[ls])
    df_ls.x_ls_index[ls] = index(x_ls[ls]).value
    df_ls.x_ls_pos_index[ls] = index(x_ls_pos[ls]).value
    df_ls.x_ls_neg_index[ls] = index(x_ls_neg[ls]).value    
end

#*************************************************************************************************

df_li.x_li_index = Vector{Union{Missing, Int}}(missing, nrow(df_li))
df_li.x_li_pos_index = Vector{Union{Missing, Int}}(missing, nrow(df_li))
df_li.x_li_neg_index = Vector{Union{Missing, Int}}(missing, nrow(df_li))
df_li.x_li_cost_index = Vector{Union{Missing, Int}}(missing, nrow(df_li))
df_li.x_li_cost_zero_index = Vector{Union{Missing, Int}}(missing, nrow(df_li))

@variable(CNC, x_li[li in s_li] >= 0)
@variable(CNC, x_li_pos[li in s_li] >= 0)
@variable(CNC, x_li_neg[li in s_li] >= 0)
@variable(CNC, x_li_cost[li in s_li] >= NEG_COST_TOL)
@variable(CNC, x_li_cost_zero[li in s_li] >= NEG_COST_TOL)
@variable(CNC, sum_li[li in s_li] >= 0)
@variable(CNC, sum_li_zero[li in s_li] >= 0)

for li in 1:cnt_li
    set_lower_bound(x_li[li], li_min[li])
    if li_has_max[li] == 1
        set_upper_bound(x_li[li], li_max[li])
    end
    df_li.x_li_index[li] = index(x_li[li]).value
    df_li.x_li_pos_index[li] = index(x_li_pos[li]).value
    df_li.x_li_neg_index[li] = index(x_li_neg[li]).value    
    df_li.x_li_cost_index[li] = index(x_li_cost[li]).value  
    df_li.x_li_cost_zero_index[li] = index(x_li_cost_zero[li]).value  
end

#*************************************************************************************************

df_i.x_i_index = Vector{Union{Missing, Int}}(missing, nrow(df_i))
df_i.x_i_pos_index = Vector{Union{Missing, Int}}(missing, nrow(df_i))
df_i.x_i_neg_index = Vector{Union{Missing, Int}}(missing, nrow(df_i))

@variable(CNC, x_i[i in s_i] >= 0)
@variable(CNC, x_i_pos[i in s_i] >= 0)
@variable(CNC, x_i_neg[i in s_i] >= 0)
@variable(CNC, sum_i[i in s_i] >= 0)

for i in 1:cnt_i
    set_lower_bound(x_i[i], i_min[i])
    if i_has_max[i] == 1
        set_upper_bound(x_i[i], i_max[i])
    end
    df_i.x_i_index[i] = index(x_i[i]).value
    df_i.x_i_pos_index[i] = index(x_i_pos[i]).value
    df_i.x_i_neg_index[i] = index(x_i_neg[i]).value    
end

#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-

@variable(CNC, tot_cost >= 0)
@variable(CNC, tot_cost_zero >= 0)
@variable(CNC, tot_lsn_bad_n_rat >= 0)
@variable(CNC, tot_lsn_bad_y_rat >= 0)
@variable(CNC, tot_ls_bad >= 0)
@variable(CNC, tot_li_bad >= 0)
@variable(CNC, tot_i_bad >= 0)
@variable(CNC, obj >= 0)

df_obj = DataFrame(
    big_vars = ["tot_cost", "tot_cost_zero", "tot_lsn_bad_n_rat", "tot_lsn_bad_y_rat", "tot_ls_bad","tot_li_bad", "tot_i_bad", "obj" ],
    big_vars_index = [index(tot_cost).value, index(tot_cost_zero).value, index(tot_lsn_bad_n_rat).value, index(tot_lsn_bad_y_rat).value, index(tot_ls_bad).value, index(tot_li_bad).value, index(tot_i_bad).value, index(obj).value ]
)

#^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^

initialize_variables_end_timestamp = now()
initialize_variables_total_time = initialize_variables_end_timestamp - initialize_variables_start_timestamp
println("Initialize variables: ", initialize_variables_total_time)

#^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^v^
#$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$
# Define the constraints
#$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$%$
#*************************************************************************************************
#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-

#-------------------------------------------------------------------------------------------------
### X_LSN ###
#-------------------------------------------------------------------------------------------------

x_lsn_start_timestamp = now()

indexLsn_not_ratio = findall(row -> row.IsRatio == 0, eachrow(df_lsn))
indexLsn_not_ratio = collect(indexLsn_not_ratio)

for a in 1:length(indexLsn_not_ratio)
    lsn = indexLsn_not_ratio[a]
    
    if !ismissing(lsn_2_lsi[lsn][1])
        @constraint(CNC, sum(x_lsi[lsn_2_lsi[lsn][n]] * lin_level[lsn_2_lin[lsn][n]] / ls_tons[lsn_2_ls[lsn]] for n in 1:length(lsn_2_lsi[lsn])) == sum_lsn[lsn])
    else
        @constraint(CNC, 0.0 == sum_lsn[lsn])
    end

    if lsn_nut_ids[lsn] == vol_nut
        @constraint(CNC, x_lsn[lsn] + x_lsn_pos[lsn] + x_lsn_neg[lsn] >= -BADDEST)
    end

    if lsn_nut_ids[lsn] != vol_nut
        @constraint(CNC, sum_lsn[lsn] == x_lsn[lsn] + x_lsn_pos[lsn] - x_lsn_neg[lsn])
    end
    
end

#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-

indexLsn_ratio = findall(row -> row.IsRatio == 1, eachrow(df_lsn))
indexLsn_ratio = collect(indexLsn_ratio)

for a in 1:length(indexLsn_ratio)
    lsn = indexLsn_ratio[a]
    # Fake lsn must be zero
    @constraint(CNC, x_lsn[lsn] == 0)
    @constraint(CNC, sum_lsn[lsn] == 0)
    # a/b > c --> a > bc --> a - bc > 0 --> a - bc + e1 > 0
    # a/b < d --> a < bd --> a - bd < 0 --> a - bd - e2 < 0
    if lsn_has_min[lsn] == 1
        @constraint(CNC, sum_lsn[lsn_top_ids[lsn]] - sum_lsn[lsn_bot_ids[lsn]] * lsn_min[lsn] + x_lsn_neg[lsn] >= 0.0)
    end
    if lsn_has_max[lsn] == 1
        @constraint(CNC, sum_lsn[lsn_top_ids[lsn]] - sum_lsn[lsn_bot_ids[lsn]] * lsn_max[lsn] - x_lsn_pos[lsn] <= 0.0)
    end

end
    
#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-

# Bad that is NOT ratio
@constraint(CNC, sum(x_lsn_pos[lsn] + x_lsn_neg[lsn] for lsn in 1:cnt_lsn if lsn_is_ratio[lsn]==0) == tot_lsn_bad_n_rat)
# Bad that IS ratio
@constraint(CNC, sum(x_lsn_pos[lsn] + x_lsn_neg[lsn] for lsn in 1:cnt_lsn if lsn_is_ratio[lsn]==1) == tot_lsn_bad_y_rat)

x_lsn_end_timestamp = now()
x_lsn_total_time = x_lsn_end_timestamp - x_lsn_start_timestamp
println("X_LSN: ", x_lsn_total_time)

#-------------------------------------------------------------------------------------------------
### X_LS ###
#-------------------------------------------------------------------------------------------------

x_ls_start_timestamp = now()

for ls in 1:cnt_ls
                
    if !ismissing(ls_2_lsi[ls][1])
        @constraint(CNC, sum(x_lsi[ls_2_lsi[ls][n]] * lsi_vol[ls_2_lsi[ls][n]] for n in 1:length(ls_2_lsi[ls])) == sum_ls[ls])
    else
        @constraint(CNC, 0.0 == sum_ls[ls])
    end

    @constraint(CNC, sum_ls[ls] == x_ls[ls] + x_ls_pos[ls] - x_ls_neg[ls])
    
    #if ls_min_max_good[ls] == 1
    #    @constraint(CNC, x_ls_pos[ls] + x_ls_neg[ls] == 0.0)
    #end
    
end

@constraint(CNC, sum(x_ls_pos[ls] + x_ls_neg[ls] for ls in 1:cnt_ls) == tot_ls_bad)

x_ls_end_timestamp = now()
x_ls_total_time = x_ls_end_timestamp - x_ls_start_timestamp
println("X_LS: ", x_ls_total_time)

#-------------------------------------------------------------------------------------------------
### X_LI ###
#-------------------------------------------------------------------------------------------------
    
x_li_start_timestamp = now()

for li in 1:cnt_li
                
    if !ismissing(li_2_lsi[li][1])
        @constraint(CNC, sum(x_lsi[li_2_lsi[li][n]] for n in 1:length(li_2_lsi[li]) if lsi_zero[li_2_lsi[li][n]] == 0) == sum_li[li])
        @constraint(CNC, sum(x_lsi[li_2_lsi[li][n]] for n in 1:length(li_2_lsi[li]) if lsi_zero[li_2_lsi[li][n]] == 1) == sum_li_zero[li])
    else
        @constraint(CNC, 0.0 == sum_li[li])
        @constraint(CNC, 0.0 == sum_li_zero[li])
    end

    @constraint(CNC, (x_li[li] + x_li_pos[li] - x_li_neg[li]) * li_cost[li] == x_li_cost[li])
    @constraint(CNC, sum_li_zero[li] * li_cost[li] == x_li_cost_zero[li])
    
    if li_min[li] > 0 || li_has_max[li] == 1
        @constraint(CNC, sum_li[li] == x_li[li] + x_li_pos[li] - x_li_neg[li])    
    else
        @constraint(CNC, sum_li[li] == x_li[li])
        @constraint(CNC, x_li_pos[li] + x_li_neg[li] == 0.0)
    end 
    
end
    
@constraint(CNC, sum(x_li_cost[li] for li in 1:cnt_li) == tot_cost)
@constraint(CNC, sum(x_li_cost_zero[li] for li in 1:cnt_li) == tot_cost_zero)
@constraint(CNC, sum(x_li_pos[li] + x_li_neg[li] for li in 1:cnt_li) == tot_li_bad)

x_li_end_timestamp = now()
x_li_total_time = x_li_end_timestamp - x_li_start_timestamp
println("X_LI: ", x_li_total_time)

#-------------------------------------------------------------------------------------------------
### X_I ###
#-------------------------------------------------------------------------------------------------

x_i_start_timestamp = now()
    
for i in 1:cnt_i
                
    if !ismissing(i_2_li[i][1])
        @constraint(CNC, sum(x_li[i_2_li[i][n]] for n in 1:length(i_2_li[i]) if li_global[i_2_li[i][n]] == 1) == sum_i[i])
    else
        @constraint(CNC, 0.0 == sum_i[i])
    end
    
    if i_min[i] > 0 || i_has_max[i] == 1
        @constraint(CNC, sum_i[i] == x_i[i] + x_i_pos[i] - x_i_neg[i])    
    else
        @constraint(CNC, sum_i[i] == x_i[i])
        @constraint(CNC, x_i_pos[i] + x_i_neg[i] == 0.0)
    end 
    
end

@constraint(CNC, sum(x_i_pos[i] + x_i_neg[i] for i in 1:cnt_i) == tot_i_bad)
#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-
x_i_end_timestamp = now()
x_i_total_time = x_i_end_timestamp - x_i_start_timestamp
println("X_I: ", x_i_total_time)
#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-
#*********************************************************************************

# Define the objective function
obj = ((tot_cost*COST_SCALAR) + (tot_cost_zero*COST_SCALAR) + (tot_ls_bad*LS_BAD) + (tot_i_bad*I_BAD) + (tot_li_bad*LI_BAD) + (tot_lsn_bad_n_rat*LSN_BAD*(1.0)) + (tot_lsn_bad_y_rat*LSN_BAD*(1.0))) / OBJ_SCALAR
@objective(CNC, Min, obj)

# Solve the model for Cargill Feasibility
optimize!(CNC)

#*************************************************************************************************
# Post Processing
#*************************************************************************************************
postpro_start_timestamp = now()
#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-
# Get the results
h = backend(CNC).optimizer.model

obj_value = HiGHS.Highs_getObjectiveValue(h)

#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-

num_col = HiGHS.Highs_getNumCols(h)
num_row = HiGHS.Highs_getNumRows(h)
num_nz = HiGHS.Highs_getNumNz(h)

#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-

col_value = Vector{Float64}(undef, num_col)
col_dual = Vector{Float64}(undef, num_col)
row_value = Vector{Float64}(undef, num_row)
row_dual = Vector{Float64}(undef, num_row)

HiGHS.Highs_getSolution(h, col_value, col_dual, row_value, row_dual)

#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-

col_cost_up_value = Vector{Float64}(undef, num_col)
col_cost_up_objective = Vector{Float64}(undef, num_col)
col_cost_up_in_var = Vector{Float64}(undef, num_col)
col_cost_up_ou_var = Vector{Float64}(undef, num_col)
col_cost_dn_value = Vector{Float64}(undef, num_col)
col_cost_dn_objective = Vector{Float64}(undef, num_col)
col_cost_dn_in_var = Vector{Float64}(undef, num_col)
col_cost_dn_ou_var = Vector{Float64}(undef, num_col)
col_bound_up_value = Vector{Float64}(undef, num_col)
col_bound_up_objective = Vector{Float64}(undef, num_col)
col_bound_up_in_var = Vector{Float64}(undef, num_col)
col_bound_up_ou_var = Vector{Float64}(undef, num_col)
col_bound_dn_value = Vector{Float64}(undef, num_col)
col_bound_dn_objective = Vector{Float64}(undef, num_col)
col_bound_dn_in_var = Vector{Float64}(undef, num_col)
col_bound_dn_ou_var = Vector{Float64}(undef, num_col)
row_bound_up_value = Vector{Float64}(undef, num_row)
row_bound_up_objective = Vector{Float64}(undef, num_row)
row_bound_up_in_var = Vector{Float64}(undef, num_row)
row_bound_up_ou_var = Vector{Float64}(undef, num_row)
row_bound_dn_value = Vector{Float64}(undef, num_row)
row_bound_dn_objective = Vector{Float64}(undef, num_row)
row_bound_dn_in_var = Vector{Float64}(undef, num_row)
row_bound_dn_ou_var = Vector{Float64}(undef, num_row)

HiGHS.Highs_getRanging(h, col_cost_up_value, col_cost_up_objective, col_cost_up_in_var, col_cost_up_ou_var, col_cost_dn_value, col_cost_dn_objective, col_cost_dn_in_var, col_cost_dn_ou_var, col_bound_up_value, col_bound_up_objective, col_bound_up_in_var, col_bound_up_ou_var, col_bound_dn_value, col_bound_dn_objective, col_bound_dn_in_var, col_bound_dn_ou_var, row_bound_up_value, row_bound_up_objective, row_bound_up_in_var, row_bound_up_ou_var, row_bound_dn_value, row_bound_dn_objective, row_bound_dn_in_var, row_bound_dn_ou_var)

#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-

set_set = ["lsn", "lsi", "ls", "li", "i"]
rounding_set = [5, 6, 5, 5, 5]
type_set = ["", "pos", "neg"]
for a in 1:length(set_set)
    set = set_set[a]
    df_name = Symbol("df_" * set)
    df_name_out = string("df_" * set * ".csv")
    df = @eval $df_name
    for b in 1:length(type_set)
        type = type_set[b]
        if b == 1
            in_name = Symbol("x_" * set * "_index")
            df.RawLevel = [col_value[i] for i in df[!, in_name]]
            df.Level = round.([col_value[i] for i in df[!, in_name]], digits=rounding_set[a])
            if set_set[a] .== "li"
                rename!(df, :Cost => :Price)
                in_name_cost = Symbol("x_" * set * "_cost_index")
                df.Cost = round.([col_value[i] for i in df[!, in_name_cost]], digits=rounding_set[a])
                in_name_cost_zero = Symbol("x_" * set * "_cost_zero_index")
                df.CostZero = round.([col_value[i] for i in df[!, in_name_cost_zero]], digits=rounding_set[a])
            end
            if set_set[a] .== "lsi"
                rename!(df, :Cost => :Price)
                df.Cost = round.(df.Level .* df.Price, digits=rounding_set[a])
            end
            df.Dual = round.([col_dual[i] for i in df[!, in_name]], digits=rounding_set[a])
            df.LowerLevel = round.([col_bound_dn_value[i] for i in df[!, in_name]], digits=rounding_set[a])
            df.LowerLevel = round.([col_bound_dn_value[i] for i in df[!, in_name]], digits=rounding_set[a])
            df.LowerObjValue = round.([col_bound_dn_objective[i] for i in df[!, in_name]], digits=rounding_set[a])
            df.UpperLevel = round.([col_bound_up_value[i] for i in df[!, in_name]], digits=rounding_set[a])
            df.UpperObjValue = round.([col_bound_up_objective[i] for i in df[!, in_name]], digits=rounding_set[a])
            df.LowerCost = round.([col_cost_dn_value[i] for i in df[!, in_name]], digits=rounding_set[a])
            df.UpperCost = round.([col_cost_up_value[i] for i in df[!, in_name]], digits=rounding_set[a])
            df.Obj = round.([obj_value for i in df[!, in_name]], digits=rounding_set[a])
        else
            if set_set[a] .!= "lsi"
                in_name = Symbol("x_" * set * "_" * type * "_index")
                if b == 2
                    df.Pos = round.([col_value[i] for i in df[!, in_name]], digits=rounding_set[a])
                end
                if b == 3
                    df.Neg = round.([col_value[i] for i in df[!, in_name]], digits=rounding_set[a])
                end
            end
        end
    end
    if set_set[a] .== "lsi"
        rename!(df, :Level => :LevelTons)
        df.Level = round.(100.0 * df.LevelTons ./ df.SpecTons, digits=rounding_set[a])
        rename!(df, :Dual => :DualTons)
        df.Dual = round.(df.SpecTons .* df.LevelTons / 100.0, digits=rounding_set[a])
    end
    if set_set[a] .== "lsn"
        for row in eachrow(df)
            if row.IsRatio == 1 && df.Level[row.DenominatorLsnId] != 0
                row.Level = round.(df.RawLevel[row.NumeratorLsnId] / df.RawLevel[row.DenominatorLsnId], digits=rounding_set[a])
            end
        end
    end
    if set_set[a] .!= "ls"
        df.Status .= missing
        df.Status .= ifelse.(df.Level .< df.Min, "below", df.Status)
        df.Status .= ifelse.(df.Level .== df.Min, "min", df.Status)
        df.Status .= ifelse.(df.Level .== df.Max, "max", df.Status)
        df.Status .= ifelse.(df.Level .> df.Max, "above", df.Status)
    end
    if set_set[a] .!= "lsi"
        df.Feasible .= ifelse.(df.Neg .+ df.Pos .> 0.0, false, true)
        df.FeasBin .= ifelse.(df.Neg .+ df.Pos .> 0.0, 0, 1)
    end
end
#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-

tot_bad = sum(df_lsn.Pos) + sum(df_lsn.Neg) + 
          sum(df_ls.Pos) + sum(df_ls.Neg) +
          sum(df_li.Pos) + sum(df_li.Neg) +
          sum(df_i.Pos) + sum(df_i.Neg)

feas_bool = ifelse(tot_bad > 0, false, true)
println("FeasBool: ", feas_bool )

#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-

df_ls_1 = combine(groupby(df_lsi, [:LocationId, :SpecificationId]), 
               :Cost => sum => :TotalCost)

df_ls = leftjoin(df_ls, df_ls_1, on = [:LocationId, :SpecificationId])

df_l_1 = combine(groupby(df_li, :LocationId), 
               :Cost => sum => :TotalCost, 
               :CostZero => sum => :TotalCostZero,
               :FeasBin => prod => :TotalFeasBinLi)

df_ls.FixedTons .= df_ls.Tons .* df_ls.IsFixed
df_ls.FlexTons .= df_ls.Tons .* (1 .- df_ls.IsFixed)

df_l_2 = combine(groupby(df_ls, :LocationId), 
               :SpecificationId => length => :TotalSpecs, 
               :Tons => sum => :TotalTons,
               :FixedTons => sum => :TotalFixedTons,
               :FlexTons => sum => :TotalFlexTons,
               :FeasBin => prod => :TotalFeasBinLs)

df_l = leftjoin(df_l_1, df_l_2, on = [:LocationId])
df_l.FeasBin .= ifelse.(df_l.TotalFeasBinLi .* df_l.TotalFeasBinLs .== 1.0, 1, 0)
df_l.Feasible .= ifelse.(df_l.FeasBin .== 1, true, false)

#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-

df_c = DataFrame(select(df_l, [:TotalTons, :TotalFixedTons, :TotalFlexTons, :TotalCost, :TotalCostZero, :FeasBin] .=> sum))
rename!(df_c, :TotalTons_sum => :TotalTons, :TotalFixedTons_sum => :TotalFixedTons, :TotalFlexTons_sum => :TotalFlexTons, :TotalCost_sum => :TotalCost, :TotalCostZero_sum => :TotalCostZero, :FeasBin_sum => :FeasBin)
df_c.Feasible .= ifelse.(df_c.FeasBin .== 1, true, false)

if df_c[1, :Feasible] == feas_bool
    println("Feas Match Feas? --> YES")
else
    println("Feas Match Feas? --> NO")
end

#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-

for i in 1:nrow(df_obj)
    df_obj.level = [col_value[i] for i in df_obj.big_vars_index]
end

#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-
postpro_end_timestamp = now()
postpro_total_time = postpro_end_timestamp - postpro_start_timestamp
println("Post Processing: ", postpro_total_time)
#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-
#*************************************************************************************************
# Build Response File
#*************************************************************************************************
response_start_timestamp = now()
#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-

df_lsn_resp = df_lsn[:, [:LocationId, :SpecificationId, :NutrientId, :Level, :Status]]
df_lsi_resp = df_lsi[:, [:LocationId, :SpecificationId, :IngredientId, :Level, :Status]]
df_li_resp = df_li[:, [:LocationId, :IngredientId, :Level, :Status]]

specification_nutrient_records = create_specification_nutrient_records(df_lsn_resp)
specification_ingredient_records = create_specification_ingredient_records(df_lsi_resp)
location_ingredient_records = create_location_ingredient_records(df_li_resp)

unique_location_ids = unique(df_l.LocationId)

location_results = []

for location_id in unique_location_ids
    
    location_record = OrderedDict(
        "LocationId" => location_id,
        "Summary" => OrderedDict(
            "Feasible" => df_l[df_l.LocationId .== location_id, :Feasible][1],
            "TotalTons" => round(df_l[df_l.LocationId .== location_id, :TotalTons][1], digits=4),
            "FixedTons" => round(df_l[df_l.LocationId .== location_id, :TotalFixedTons][1], digits=4),
            "FlexibleTons" => round(df_l[df_l.LocationId .== location_id, :TotalFlexTons][1], digits=4),
            "TotalCost" => round(df_l[df_l.LocationId .== location_id, :TotalCost][1], digits=6),
            "AverageCost" => round(df_l[df_l.LocationId .== location_id, :TotalCost][1] / df_l[df_l.LocationId .== location_id, :TotalTons][1], digits=6)
        ),
        "IngredientResults" => location_ingredient_records[(LocationId = location_id,)]
    )

    specification_results = []
    grouped = groupby(df_ls[df_ls.LocationId .== location_id, :], [:LocationId, :SpecificationId])
    for (records_key, specification) in pairs(grouped)
        t_df_ls = df_ls[(df_ls.LocationId .== location_id) .& (df_ls.SpecificationId .== records_key[2]), :]
        push!(specification_results, OrderedDict(
            "SpecificationId" => records_key[2],
            "Feasible" => t_df_ls[1, :Feasible],
            "TotalTons" => round(t_df_ls[1, :Tons], digits=4),
            "TotalCost" => round(t_df_ls[1, :TotalCost], digits=6),
            "CostPerTon" => round(t_df_ls[1, :TotalCost] / t_df_ls[1, :Tons], digits=6),
            "IngredientLevels" => specification_ingredient_records[records_key],
            "NutrientLevels" => specification_nutrient_records[records_key]
        ))
    end
    location_record["SpecificationResults"] = specification_results

    push!(location_results, location_record)

end

#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-
#=
df_i_resp = select(df_i, [:IngredientId, :Level])

GlobalResults = []

a = unique(df_i.IngredientId)

for i in 1:length(a)
    Ingredient = Dict("IngredientId" => a[i])
    data_list = [:IngredientId, :Level]
    for b in data_list
        value = df_i[i, b]
        if !isa(value, String)
            if !isnan(value)
                if b != :Status
                    Ingredient[b] = value
                else
                    Ingredient[b] = value
                end
            end
        end
    end
    push!(GlobalResults, Ingredient)
end
=#
#-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-~-

summary = OrderedDict(
    "Feasible" => feas_bool,
    "TotalTons" => round(df_c[1, :TotalTons], digits=4),
    "FixedTons" => round(df_c[1, :TotalFixedTons], digits=4),
    "FlexibleTons" => round(df_c[1, :TotalFlexTons], digits=4),
    "TotalCost" => round(df_c[1, :TotalCost], digits=6),
    "AverageCost" => round(df_c[1, :TotalCost] / df_c[1, :TotalTons], digits=6)
)

resp = OrderedDict(
    "OptimizationId" => optimization_id,
    "Summary" => summary,
    "LocationResults" => location_results
    #"GlobalIngredientResults" => GlobalResults
)

# json_output = JSON.json(resp) 

############# END model.jl   
    return JSON.json(resp)  
end   ########## END Function Solve()
  
end  # End module