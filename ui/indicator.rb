require "curses"

class IndicatorWindow < Curses::Window
	@@list = Array.new

	def IndicatorWindow.list
		@@list
	end

	attr_accessor :fg, :bg, :layout
	attr_reader :label, :value

	def label=(str)
		@label = str
		redraw
	end

	def initialize(*args)
		@fg = [ '444444', 'ffff00' ]
		@bg = [ nil, nil ]
		@label = '*'
		@value = nil
		@@list.push(self)
		super(*args)
	end
	def update(new_value)
		if new_value == @value
			false
		else
			@value = new_value
			redraw
		end
	end

	def redraw
		setpos(0,0)
		if @value
			if @value.is_a?(Integer)
				attron(color_pair(get_color_pair_id(@fg[@value], @bg[@value]))|Curses::A_NORMAL) { addstr @label }
			else
				attron(color_pair(get_color_pair_id(@fg[1], @bg[1]))|Curses::A_NORMAL) { addstr @label }
			end
		else
			attron(color_pair(get_color_pair_id(@fg[0], @bg[0]))|Curses::A_NORMAL) { addstr @label }
		end
		noutrefresh
		true
	end
end