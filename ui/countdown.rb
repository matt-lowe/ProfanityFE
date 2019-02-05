require "curses"

class CountdownWindow < Curses::Window
	attr_accessor :label, :fg, :bg, :end_time, :secondary_end_time, :active, :layout
	attr_reader :value, :secondary_value

	@@list = Array.new

	def CountdownWindow.list
		@@list
	end

	def initialize(*args)
		@label = String.new
		@fg = [ ]
		@bg = [ nil, 'ff0000', '0000ff' ]
		@active = nil
		@end_time = 0
		@secondary_end_time = 0
		@@list.push(self)
		super(*args)
	end
	def update
		old_value, old_secondary_value = @value, @secondary_value
		@value = [(@end_time.to_f - Time.now.to_f + $server_time_offset.to_f - 0.2).ceil, 0].max
		@secondary_value = [(@secondary_end_time.to_f - Time.now.to_f + $server_time_offset.to_f - 0.2).ceil, 0].max
		if (old_value != @value) or (old_secondary_value != @secondary_value) or (@old_active != @active)
			str = "#{@label}#{[ @value, @secondary_value ].max.to_s.rjust(self.maxx - @label.length)}"
			setpos(0, 0)
			if ((@value == 0) and (@secondary_value == 0)) or (@active == false)
				if @active
					str = "#{@label}#{'?'.rjust(self.maxx - @label.length)}"
					left_background_str = str[0,1].to_s
					right_background_str = str[(left_background_str.length),(@label.length + (self.maxx - @label.length))].to_s
					attron(color_pair(get_color_pair_id(@fg[1], @bg[1]))|Curses::A_NORMAL) {
						addstr left_background_str
					}
					attron(color_pair(get_color_pair_id(@fg[2], @bg[2]))|Curses::A_NORMAL) {
						addstr right_background_str
					}
				else
					attron(color_pair(get_color_pair_id(@fg[0], @bg[0]))|Curses::A_NORMAL) {
						addstr str
					}
				end
			else
				left_background_str = str[0,@value].to_s
				secondary_background_str = str[left_background_str.length,(@secondary_value - @value)].to_s
				right_background_str = str[(left_background_str.length + secondary_background_str.length),(@label.length + (self.maxx - @label.length))].to_s
				if left_background_str.length > 0
					attron(color_pair(get_color_pair_id(@fg[1], @bg[1]))|Curses::A_NORMAL) {
						addstr left_background_str
					}
				end
				if secondary_background_str.length > 0
					attron(color_pair(get_color_pair_id(@fg[2], @bg[2]))|Curses::A_NORMAL) {
						addstr secondary_background_str
					}
				end
				if right_background_str.length > 0
					attron(color_pair(get_color_pair_id(@fg[3], @bg[3]))|Curses::A_NORMAL) {
						addstr right_background_str
					}
				end
			end
			@old_active = @active
			noutrefresh
			true
		else
			false
		end
	end
end
