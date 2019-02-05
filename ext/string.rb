class String
	def alnum?
		!!match(/^[[:alnum:]]+$/)
	end
  
  def digits?
		!!match(/^[[:digit:]]+$/)
	end
  
  def punct?
		!!match(/^[[:punct:]]+$/)
	end
  
  def space?
		!!match(/^[[:space:]]+$/)
  end
  
  def &(other)
		shortest, longest = [self, other].sort { |a, b| a.size - b.size }

		shortest.each_char.to_a
			.zip(longest.each_char.to_a)
			.take_while { |a, b| a == b }
			.transpose
			.first
			.join("")
	end
end