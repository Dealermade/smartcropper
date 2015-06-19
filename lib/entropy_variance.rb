module Enumerable

    def sum
      self.inject(0){|accum, i| accum + i }
    end

    def mean
      self.sum/self.length.to_f
    end

    def sample_variance
      m = self.mean
      sum = self.inject(0){|accum, i| accum +(i-m)**2 }
      sum/(self.length - 1).to_f
    end

    def standard_deviation
      return Math.sqrt(self.sample_variance)
    end

end

class EntropyVariance

  def initialize
    @elements = Array.new
    @averages = Array.new
    @last_avg = 0
  end

  def elements
    @elements
  end

  def <<(arr)
    x, hist = arr[0], arr[1]
    hist_hash = {}
    hist.select { |k,v| v > 1 }.each_pair { |k,v| hist_hash[k.to_color] = v }

    @averages << { mean: @elements.mean, standard_deviation: @elements.standard_deviation,
      element_deviation: x-@elements.mean, large?: x-@elements.mean > @elements.standard_deviation * 1.05, hist_hash: hist_hash }

    @elements << x
  end

  def standard_deviation
    @elements.standard_deviation
  end

  def last_element_deviation
    @averages.last[:element_deviation]
  end

  def last_elements_abnormally_large?
    return false if @elements.size < 5
    @averages.last[:large?] && (@averages.last[:hist_hash].keys.select { |k| !@averages[@averages.length-2][:hist_hash].has_key?(k) }.count >= 14)
  end

  def current
    @elements.last
  end

  alias_method :cur, :current
  alias_method :last, :current

  private
  def equals?(x,x2)
    t = @elements[@elements.length-x] == @elements[@elements.length-x2]
    return t
  end

end
