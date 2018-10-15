dofile("Graphics.lua")
dofile("Bitmap.lua")
dofile("GA_Common.lua")

local POPULATION_SIZE       = 2 * 40
local MAX_GENERATIONS       = 200
local CROSSOVER_RATE        = 0.6
local CHROMOSOME_LENGTH     = 32
local CHROMOSOME_NORM       = math.pow(2, CHROMOSOME_LENGTH) - 1
local MUTATION_RATE         = 0.001 / CHROMOSOME_LENGTH
local SIGMA_SHARE           = 0.1
local NON_DOMINATED_SORT    = true

local GRAPH_PARAM_MIN       = -2.0
local GRAPH_PARAM_MAX       = 4.0
local GRAPH_POINTS          = 1000

local IMAGE_WIDTH           = 1280
local IMAGE_HEIGHT          = 720
local IMAGE_NAME            = string.format("MultiObjective/MultiObjective_%%04d.bmp")
local WRITE_FRAMES          = 10

local function Min(a, b) return (not a or b < a) and b or a end
local function Max(a, b) return (not a or b > a) and b or a end

function clamp(x, a, b)
	if x < a then
		return a
	elseif x > b then
		return b
	else
		return x
	end
end

local function DecodeChromosome(chrom)
  return GRAPH_PARAM_MIN + (chrom[1] / CHROMOSOME_NORM) * (GRAPH_PARAM_MAX - GRAPH_PARAM_MIN)
end

function F21(t)
  return t * t
end

function F22(t)
  return (t - 2) * (t - 2)
end

local function GenRandomChromoze(len)
  local bits = {}
  for i = 1, len do
    bits[i] = FlipCoin(0.5) and "1" or "0"
  end
  
  return table.concat(bits, "")
end

local function EvaluateChromosome(t)
  return { F21(t), F22(t) }
end

local function GenInitPopulation(size, chromosome_len)
  local population = { crossovers = 0, mutations = 0}
  for i = 1, size do
    local bitstring = GenRandomChromoze(chromosome_len)
    local chrom_words = PackBitstring(bitstring)
    population[i] = { chromosome = chrom_words, fitness = {}, objective = {}, part_total_fitness = {} }
  end
  
  return population
end

local function CalcSharing(individual, pop)
  local max, min = 1.0, 0.0
  local sharing = 0.0
  for _, other in ipairs(pop) do
    local dist = clamp(math.abs(individual.decoded - other.decoded), 0.0, SIGMA_SHARE)
    local s = max - math.pow((max - min) * dist / SIGMA_SHARE, 2)
    sharing = sharing + s
  end
  
  return sharing
end

local function CalcDegradedFitness(individual, pop)
  local sharing = CalcSharing(individual, pop)
  local degraded = {}
  for idx, objective in ipairs(individual.objective) do
    degraded[idx] = objective / sharing
  end
  
  return degraded
end

local function EvaluatePopulation(pop)
  for _, individual in ipairs(pop) do
    local decoded = DecodeChromosome(individual.chromosome)
    individual.decoded = decoded
    individual.objective = EvaluateChromosome(decoded)
  end
  
  local total_fitness, min_fitness, max_fitness = { 0.0, 0.0 }, {}, {}
  for _, individual in ipairs(pop) do
    local vector = (not SIGMA_SHARE or NON_DOMINATED_SORT) and individual.objective or CalcDegradedFitness(individual, pop)
    for idx, fitness in ipairs(vector) do
      min_fitness[idx] = Min(min_fitness[idx], fitness)
      max_fitness[idx] = Max(max_fitness[idx], fitness)
      individual.fitness[idx] = fitness
      individual.part_total_fitness[idx] = total_fitness[idx]
      total_fitness[idx] = total_fitness[idx] + fitness
    end
  end
  pop[0] = { fitness = {}, part_total_fitness = {} }
  pop.avg_fitness = {}
  local num_objectives = #pop[1].objective
  for idx = 1, num_objectives do
    pop[0].fitness[idx] = 0.0
    pop[0].part_total_fitness[idx] = 0.0
    pop.avg_fitness[idx] = total_fitness[idx] / #pop
  end
  pop.total_fitness = total_fitness
  pop.min_fitness, pop.max_fitness = min_fitness, max_fitness
end

local function SelectPopulationBestShuffle(pop)
  local num_objectives = #pop[1].objective
  local sub_pop_size = #pop // num_objectives
  local sub_pops = { crossovers = pop.crossovers, mutations = pop.mutations }
  local remainder = #pop - num_objectives * sub_pop_size
  for idx = 1, num_objectives do
    -- TODO: here fast algorithm for selecting best N elements can be applied instead of sorting
    table.sort(pop, function(a, b) return a.fitness[idx] < b.fitness[idx] end)
    for k = 1, sub_pop_size do
      sub_pops[(idx - 1) * sub_pop_size + k] = pop[k]
    end
    -- fill up the remainders if objectives number does not divide pop size with individuals from the 1st subpops
    if remainder > 0 then
      remainder = remainder - 1
      sub_pops[#pop - remainder] = pop[sub_pop_size + 1]
    end
  end
  
  return sub_pops
end

local function Dominates(individual1, individual2)
  local epsilon = 0.00001
  local objectives1, objectives2 = individual1.objective, individual2.objective
  
  local at_least_one_less = false
  for k = 1, #individual1.objective do
    local obj1, obj2 = objectives1[k], objectives2[k]
    if obj1 > obj2 + epsilon then
      return false
    end
    -- it is '<=' for sure - check for strict '<'
    at_least_one_less = at_least_one_less or (obj1 < obj2 - epsilon)
  end
  
  return at_least_one_less
end

local function NonDominatedSortRank(pop)
  local not_ranked, front_rank = pop, 1.0
  while #not_ranked > 0 do
    local front, dominated = {}, {}
    for idx, individual in ipairs(not_ranked) do
      local superior = true
      for _, other in ipairs(not_ranked) do
        if individual ~= other and Dominates(other, individual) then
          superior = false
          break
        end
      end
      table.insert(superior and front or dominated, individual)
    end
    
    local min_rank
    for _, individual in ipairs(front) do
      individual.rank = front_rank / CalcSharing(individual, front)
      min_rank = Min(min_rank, individual.rank)
    end
    front_rank = min_rank * 0.9
    not_ranked = dominated
  end
  
  local total_rank, min_rank, max_rank = 0
  for idx, individual in ipairs(pop) do
    min_rank = Min(min_rank, individual.rank)
    max_rank = Max(max_rank, individual.rank)
    individual.part_total_rank = total_rank
    total_rank = total_rank + individual.rank
  end
  pop[0].rank, pop[0].part_total_rank = 0, 0
  pop.total_rank, pop.avg_rank = total_rank, total_rank / #pop
  pop.min_rank, pop.max_rank = min_rank, max_rank
  
  return pop
end

local function PlotPopulation(bmp, pop, gen, transform1, transform2)
  local points, points2, points3, density = {}, {}, {}, {}
  for idx, individual in ipairs(pop) do
    local pt = transform1({x = individual.objective[1], y = individual.objective[2]})
    points[idx] = pt
    density[pt.x] = density[pt.x] or {}
    density[pt.x][pt.y] = (density[pt.x][pt.y] or 0) + 1
    points2[idx] = transform2({x = individual.decoded, y = individual.objective[1]})
    points3[idx] = transform2({x = individual.decoded, y = individual.objective[2]})
  end
  for idx, pt in ipairs(points) do
    local size = 3 + math.floor(10 * (density[pt.x][pt.y] / #pop))
    bmp:DrawLine(pt.x - size, pt.y - size, pt.x + size, pt.y + size, {255, 0, 255})
    bmp:DrawLine(pt.x + size, pt.y - size, pt.x - size, pt.y + size, {255, 0, 255})
    local count = tostring(density[pt.x][pt.y])
    local w, h = bmp:MeasureText(count)
    bmp:DrawText(pt.x - w // 2, pt.y - h - size - 2, count, {255, 255, 255})
    local pt2 = points2[idx]
    bmp:DrawLine(pt2.x - size, pt2.y - size, pt2.x + size, pt2.y + size, {255, 0, 255})
    bmp:DrawLine(pt2.x + size, pt2.y - size, pt2.x - size, pt2.y + size, {255, 0, 255})
    bmp:DrawText(pt2.x - w // 2, pt2.y - h - size - 2, count, {255, 255, 255})
    local pt3 = points3[idx]
    bmp:DrawLine(pt3.x - size, pt3.y - size, pt3.x + size, pt3.y + size, {255, 0, 255})
    bmp:DrawLine(pt3.x + size, pt3.y - size, pt3.x - size, pt3.y + size, {255, 0, 255})
    bmp:DrawText(pt3.x - w // 2, pt3.y - h - size - 2, count, {255, 255, 255})
  end

  top = 20
  local descr = string.format("Generation: %d, Crossovers: %d, Mutations: %d", gen, pop.crossovers, pop.mutations)
  w, h = bmp:MeasureText(descr)
  bmp:DrawText("halign", top, descr, {255, 255, 255})
end

local function RouletteWheelSelection(pop)
  local slot = math.random() * pop.total_rank
  if slot <= 0 then
    return 1
  elseif slot >= pop.total_rank then
    return #pop
  end
  
  local left, right = 1, #pop
  while left + 1 < right do
    local middle = (left + right) // 2
    local part_total = pop[middle].part_total_rank
    if slot == part_total then
      return middle
    elseif slot < part_total then
      right = middle
    else
      left = middle
    end
  end
  
  return (slot < pop[left].part_total_rank + pop[left].rank) and left or right
end

local function Crossover(mate1, mate2)
  local offspring1 = { chromosome = CopyBitstring(mate1.chromosome), fitness = {}, objective = {}, part_total_fitness = {} }
  local offspring2 = { chromosome = CopyBitstring(mate2.chromosome), fitness = {}, objective = {}, part_total_fitness = {}  }
  local crossovers = 0
  
  if FlipCoin(CROSSOVER_RATE) then
    local xsite = math.random(1, CHROMOSOME_LENGTH)
    ExchangeTailBits(offspring1.chromosome, offspring2.chromosome, xsite)
    crossovers = 1
  end
  
  return offspring1, offspring2, crossovers
end

local function Mutate(offspring)
  local mutations = 0
  
  local chromosome = offspring.chromosome
  local word_idx, bit_pos, power2 = 1, 1, 1
  for bit = 1, chromosome.bits do
    if FlipCoin(MUTATION_RATE) then
      local word = chromosome[word_idx]
      local allele = word & power2
      chromosome[word_idx] = (allele ~= 0) and (word - power2) or (word + power2)
      mutations = mutations + 1
    end
    bit_pos = bit_pos + 1
    power2 = power2 * 2
    if bit_pos > GetBitstringWordSize() then
      word_idx = word_idx + 1
      bit_pos, power2 = 1, 1
    end
  end
  
  return mutations
end

local function DrawFunction(bmp, min, max, pop, gen)
  local func_points1 = { color = {0, 255, 0} }
  local graph1 = { funcs = { ["{x=F21(t),y=F22(t)}"] = func_points1 }, name_x = "F21(t)", name_y = "F22(t)" }
  local func_points21, func_points22 = { color = {255, 0, 0} }, { color = {0, 0, 255} }
  local graphs2 = { funcs = { ["F21"] = func_points21, ["F22"] = func_points22 }, name_x = "t", name_y = "F21(t) or F22(t)" }
  for i = 0, GRAPH_POINTS - 1 do
    local t = min + (max - min) * i / (GRAPH_POINTS - 1)
    local f21, f22 = F21(t), F22(t)
    func_points1[i + 1] = {x = f21, y = f22}
    func_points21[i + 1] = {x = t, y = f21}
    func_points22[i + 1] = {x = t, y = f22}
  end
  
  local transform1 = DrawGraphsAt(bmp, graph1, "skip KP", 0, 0, IMAGE_WIDTH, IMAGE_HEIGHT)
  local transform2 = DrawGraphsAt(bmp, graphs2, "skip KP", 0, IMAGE_HEIGHT, IMAGE_WIDTH, IMAGE_HEIGHT, GRAPH_PARAM_MIN - 1.0, 0.0)
  
  local title = string.format("Multi-Objective Genetic Algorithm: Population Size %d, Crossover: %.2f, Mutation %f%s%s",#pop, CROSSOVER_RATE, MUTATION_RATE, NON_DOMINATED_SORT and " Non-Dominated Sort" or "", SIGMA_SHARE and string.format(" Sigma-Share=%.2f", SIGMA_SHARE) or "")
  local top = 5
  local w, h = bmp:MeasureText(title)
  bmp:DrawText("halign", top, title, {255, 255, 255})
  
  return transform1, transform2
end

local function RunMultiObjectiveGA()
  local start_clock = os.clock()
  
  local pop = GenInitPopulation(POPULATION_SIZE, CHROMOSOME_LENGTH)
  EvaluatePopulation(pop)
  
  local bmp = Bitmap.new(IMAGE_WIDTH, 2 * IMAGE_HEIGHT, {0, 0, 0})
  local transform1, transform2 = DrawFunction(bmp, GRAPH_PARAM_MIN, GRAPH_PARAM_MAX, pop, 1)
  if WRITE_FRAMES then
    local img = bmp:Clone()
    PlotPopulation(img, pop, 1, transform1, transform2)
    local filename = string.format(IMAGE_NAME, 1)
    print(string.format("Writing '%s' ...", filename))
    img:WriteBMP(filename)
  end
  if NON_DOMINATED_SORT then
    pop = NonDominatedSortRank(pop)
  else
    pop = SelectPopulationBestShuffle(pop)
  end
  
  for gen = 2, MAX_GENERATIONS do
    local new_pop = { crossovers = pop.crossovers, mutations = pop.mutations }
    while #new_pop < #pop do
      local idx1, idx2
      if NON_DOMINATED_SORT then
        idx1, idx2 = RouletteWheelSelection(pop), RouletteWheelSelection(pop)
      else
        idx1, idx2 = math.random(1, #pop), math.random(1, #pop)
      end
      local offspring1, offspring2, crossover = Crossover(pop[idx1], pop[idx2])
      new_pop.crossovers = new_pop.crossovers + crossover
      local mutations1 = Mutate(offspring1)
      table.insert(new_pop, offspring1)
      new_pop.mutations = new_pop.mutations + mutations1
      if #new_pop < #pop then         -- shield the case of odd size popuations
        local mutations2 = Mutate(offspring2)
        table.insert(new_pop, offspring2)
        new_pop.mutations = new_pop.mutations + mutations2
      end
    end
    EvaluatePopulation(new_pop)
    if WRITE_FRAMES and gen % WRITE_FRAMES == 0 then
      local img = bmp:Clone()
      PlotPopulation(img, new_pop, gen, transform1, transform2)
      local filename = string.format(IMAGE_NAME, (WRITE_FRAMES == 1) and gen or (1 + gen // WRITE_FRAMES))
      print(string.format("Writing '%s' ...", filename))
      img:WriteBMP(filename)
    end
    if NON_DOMINATED_SORT then
      pop = NonDominatedSortRank(new_pop)
    else
      pop = SelectPopulationBestShuffle(new_pop)
    end
  end
  
  local time = os.clock() - start_clock
  local time_text = string.format("Time (Lua 5.3): %ss", time)
  print(time_text)
end

RunMultiObjectiveGA()
