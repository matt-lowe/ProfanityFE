class Autocomplete
	HIGHLIGHT = "a6e22e"

	@in_menu  = false

	def self.consume(key_code, history:, buffer:)
		Autocomplete.wrap do
			return @in_menu = true if key_code == 9 # tab
			return unless @in_menu
		end
	end
	##
	## @brief      checks to see if the historical command is a possible 
	## 						 completion of the current state of the command buffer
	##
	## @param      current    String  The current command string
	## @param      historical String  The historical command string
	##
	## @return     Boolean            if it is a possible completion
	##
	def self.compare(current, historical)
		current    = current.split("")
		historical = historical.split("")
		current.each_with_index.map { |char, i| char == historical[i] ? 1 : 0 }
			.reduce(&:+) == current.size
	end
	##
	## @brief      finds the first divergence in an array of Strings that should
	##
	## @param      suggestions Array(String)  The suggestions
	##
	## @return     String     a String<0..n> of which the characters exist in all suggestions
	##
	def self.find_branch(suggestions)
		suggestions.reduce(&:&)
	end

	def self.wrap()
		begin
			yield
		rescue Exception => e
			Profanity.log("[autocomplete error #{Time.now}] #{$e.message}")
			e.backtrace[0...4].each do |ln| Profanity.log(ln) end
		end
	end
end