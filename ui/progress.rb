require "curses"

class ProgressWindow < Curses::Window
	attr_accessor :fg, :bg, :label, :layout
	attr_reader :value, :max_value

	@@list = Array.new

	def ProgressWindow.list
		@@list
	end

	def initialize(*args)
		@label = String.new
		@fg = [ ]
		@bg = [ '0000aa', '000055' ]
		@value = 0
		@max_value = 100
		@@list.push(self)
		super(*args)
	end
	def update(new_value, new_max_value=nil)
		new_max_value ||= @max_value
		if (new_value == @value) and (new_max_value == @max_value)
			false
		else
			@value = new_value
			@max_value = [new_max_value, 1].max
			redraw
		end
	end
	def redraw
		str = "#{@label}#{@value.to_s.rjust(self.maxx - @label.length)}"
		percent = [[(@value/@max_value.to_f), 0.to_f].max, 1].min
		if (@value == 0) and (fg[3] or bg[3])
			setpos(0, 0)
			attron(color_pair(get_color_pair_id(@fg[3], @bg[3]))|Curses::A_NORMAL) {
				addstr str
			}
		else
			left_str = str[0,(str.length*percent).floor].to_s
			if (@fg[1] or @bg[1]) and (left_str.length < str.length) and (((left_str.length+0.5)*(1/str.length.to_f)) < percent)
				middle_str = str[left_str.length,1].to_s
			else
				middle_str = ''
			end
			right_str = str[(left_str.length + middle_str.length),(@label.length + (self.maxx - @label.length))].to_s
			setpos(0, 0)
			if left_str.length > 0
				attron(color_pair(get_color_pair_id(@fg[0], @bg[0]))|Curses::A_NORMAL) {
					addstr left_str
				}
			end
			if middle_str.length > 0
				attron(color_pair(get_color_pair_id(@fg[1], @bg[1]))|Curses::A_NORMAL) {
					addstr middle_str
				}
			end
			if right_str.length > 0
				attron(color_pair(get_color_pair_id(@fg[2], @bg[2]))|Curses::A_NORMAL) {
					addstr right_str
				}
			end
		end
		noutrefresh
		true
	end
end