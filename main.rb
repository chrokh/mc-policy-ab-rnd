class UniDist
  def initialize min, max
    @min = min.to_f
    @max = max.to_f
  end
  def sample!
    rand * (@max - @min) + @min
  end
end

class ValDist
  def initialize x
    @x = x.to_f
  end
  def sample!
    @x
  end
end

class PhaseDist
  def initialize time, cost, cash, prob
    @time = time
    @cost = cost
    @cash = cash
    @prob = prob
  end
  def sample!
    Phase.new(
      @time.sample!,
      @cost.sample!,
      @cash.sample!,
      @prob.sample!
    )
  end
end

class Phase
  attr_reader :time, :cost, :cash, :prob
  def initialize time, cost, cash, prob
    @time = time
    @cost = cost
    @cash = cash
    @prob = prob
  end
  def cashflow
    @cash - @cost
  end
end

class WorldDist
  def initialize phases, rate, mini
    @phases = phases
    @rate = rate
    @mini = mini
  end
  def sample!
    World.new(
      @phases.map { |p| p.sample! },
      @rate.sample!,
      @mini.sample!
    )
  end
end

class World
  def initialize phases, rate, mini
    @phases = phases
    @rate = rate
    @mini = mini
  end
  def decision_points
    @decision_points ||= ladder(@phases).map do |phases|
      DecisionPoint.new phases, @rate, @mini
    end
  end
  def run
    enpvs   = decision_points.map(&:enpv)
    gonos   = decision_points.map(&:decision)
    conseqs = gonos.reduce([true]) { |acc, x| acc << (acc.last && x) }.drop(1)
    {
      discount_rate:    @rate,
      threshold:        @mini,
      enpv:             enpvs,
      decision:         gonos,
      conseq_decision:  conseqs
    }
  end
end

class DecisionPoint
  def initialize phases, rate, mini
    @phases = phases
    @rate   = rate
    @mini   = mini
  end
  def remaining_prob
    @phases.map(&:prob).reduce(&:*)
  end
  def enpv
    @enpv ||= npv * remaining_prob
  end
  def npv
    pvs.reduce(&:+)
  end
  def pvs
    cashflows.map { |c| c.pv @rate }
  end
  def cashflows
    ladder(@phases).map do |flows|
      Cashflow.new(
        flows.last.cost,
        flows.last.cash,
        flows.drop(1).map(&:time).reduce(0, &:+)
      )
    end
  end
  def decision
    enpv >= @mini
  end
end

class Cashflow
  def initialize cost, cash, time_to
    @cost = cost
    @cash = cash
    @time_to = time_to
  end
  def pv rate
    (@cash - @cost) / ((1 + rate) ** @time_to)
  end
end

def ladder xs
  xs.reduce([]) { |xs, x| (xs.map{|y| y<<x}) << [x] }
end

require 'yaml'
def parse input1, input2
  mini   = parse_dist YAML.load_file(input1)['threshold']
  rate   = parse_dist YAML.load_file(input1)['discount_rate']
  phases = File.readlines(input2)
    .reject { |l| l=="\r\n" || l=="\r" || l=="\n" }
    .drop(1)
    .map { |l| parse_phase_dist l }
  WorldDist.new(phases, rate, mini)
end

def parse_dist dist
  if dist.index '-'
    args = dist.split('-')
    UniDist.new args[0], args[1]
  else
    ValDist.new dist
  end
end

def parse_phase_dist phase
  args = phase.gsub(' ', '').split ','
  PhaseDist.new(
    parse_dist(args[0]),
    parse_dist(args[1]),
    parse_dist(args[2]),
    parse_dist(args[3]),
  )
end

def write file, lines
  line
  puts lines.first
  exit
end

class CSVFormatter
  def initialize line
  end
end

class Writer
  def initialize output
    @output = output
    @cache  = []
    @has_written_header = false
  end
  def append data
    @cache << data
  end
  def flush!
    @cache.each do |data|
      csv = CSVFormatter.new data
      if @has_written_header
        open(@output, 'a') { |f| f.puts csv.data }
      else
        open(@output, 'w') { |f| f.puts csv.header }
        @has_written_header = true
      end
    end
    @cache = []
  end
end

class CSVFormatter
  def initialize data
    @data = data
  end
  def header
    @data.keys.map { |k|
      if @data[k].is_a? Array
        @data[k].length.times.map { |n| "#{k}_#{n}" }.join(',')
      else
        k
      end
    }.join(',')
  end
  def data
    @data.values.map do |v|
      if v.is_a? Array
        v.join(',')
      else
        v
      end
    end.join(',')
  end
end

def run n, params, phases, output
  dist = parse params, phases
  writer = Writer.new output
  n.times do |i|
    world  = dist.sample!
    result = world.run
    writer.append result
    if (i > 0 && i % 100 == 0) || i == n - 1
      system "clear" or system "cls"
      puts "#{(i / n.to_f * 100).round} %"
      writer.flush!
    end
  end
  writer.flush!
end

run(ARGV[0].to_i, ARGV[1], ARGV[2], ARGV[3]).map do |r|
  puts r
end
