require "curses"

class TextWindow < Curses::Window
	attr_reader :color_stack, :buffer
	attr_accessor :scrollbar, :indent_word_wrap, :layout
	@@list = Array.new

	def TextWindow.list
		@@list
	end

	def initialize(*args)
		@buffer = Array.new
		@buffer_pos = 0
		@max_buffer_size = 250
		@indent_word_wrap = true
		@@list.push(self)
		super(*args)
	end
	def max_buffer_size
		@max_buffer_size
	end
	def max_buffer_size=(val)
		# fixme: minimum size?  Curses.lines?
		@max_buffer_size = val.to_i
	end
	def add_line(line, line_colors=Array.new)
		part = [ 0, line.length ]
		line_colors.each { |h| part.push(h[:start]); part.push(h[:end]) }
		part.uniq!
		part.sort!
		for i in 0...(part.length-1)
			str = line[part[i]...part[i+1]]
			color_list = line_colors.find_all { |h| (h[:start] <= part[i]) and (h[:end] >= part[i+1]) }
			if color_list.empty?
				addstr str
			else
				# shortest length highlight takes precedence when multiple highlights cover the same substring
				# fixme: allow multiple highlights on a substring when one specifies fg and the other specifies bg
				color_list = color_list.sort_by { |h| h[:end] - h[:start] }
				#log("line: #{line}, list: #{color_list}")
				fg = color_list.map { |h| h[:fg] }.find { |fg| !fg.nil? }
				bg = color_list.map { |h| h[:bg] }.find { |bg| !bg.nil? }
				ul = color_list.map { |h| h[:ul] == "true" }.find { |ul| ul }
				attron(color_pair(get_color_pair_id(fg, bg))|(ul ? Curses::A_UNDERLINE : Curses::A_NORMAL)) {
					addstr str
				}
			end
		end
	end
	def add_string(string, string_colors=Array.new)
		#
		# word wrap string, split highlights if needed so each wrapped line is independent, update buffer, update window if needed
		#
		while (line = string.slice!(/^.{2,#{maxx-1}}(?=\s|$)/)) or (line = string.slice!(0,(maxx-1)))
			line_colors = Array.new
			for h in string_colors
				line_colors.push(h.dup) if (h[:start] < line.length)
				h[:end] -= line.length
				h[:start] = [(h[:start] - line.length), 0].max
			end
			string_colors.delete_if { |h| h[:end] < 0 }
			line_colors.each { |h| h[:end] = [h[:end], line.length].min }
			@buffer.unshift([line,line_colors])
			@buffer.pop if @buffer.length > @max_buffer_size
			if @buffer_pos == 0
				addstr "\n"
				add_line(line, line_colors)
			else
				@buffer_pos += 1
				scroll(1) if @buffer_pos > (@max_buffer_size - maxy)
				update_scrollbar
			end
			break if string.chomp.empty?
			if @indent_word_wrap
				if string[0,1] == ' '
					string = " #{string}"
					string_colors.each { |h|
						h[:end] += 1;
						# Never let the highlighting hang off the edge -- it looks weird
						h[:start] += h[:start] == 0 ? 2 : 1
					}
				else
					string = "  #{string}"
					string_colors.each { |h| h[:end] += 2; h[:start] += 2 }
				end
			else
				if string[0,1] == ' '
					string = string[1,string.length]
					string_colors.each { |h| h[:end] -= 1; h[:start] -= 1 }
				end
			end
		end
		if @buffer_pos == 0
			noutrefresh
		end
	end
	def scroll(scroll_num)
		if scroll_num < 0
			if (@buffer_pos + maxy + scroll_num.abs) >= @buffer.length
				scroll_num = 0 - (@buffer.length - @buffer_pos - maxy)
			end
			if scroll_num < 0
				@buffer_pos += scroll_num.abs
				scrl(scroll_num)
				setpos(0,0)
				pos = @buffer_pos + maxy - 1
				scroll_num.abs.times {
					add_line(@buffer[pos][0], @buffer[pos][1])
					addstr "\n"
					pos -=1
				}
				noutrefresh
			end
			update_scrollbar
		elsif scroll_num > 0
			if @buffer_pos == 0
				nil
			else
				if (@buffer_pos - scroll_num) < 0
					scroll_num = @buffer_pos
				end
				@buffer_pos -= scroll_num
				scrl(scroll_num)
				setpos(maxy - scroll_num, 0)
				pos = @buffer_pos + scroll_num - 1
				(scroll_num - 1).times {
					add_line(@buffer[pos][0], @buffer[pos][1])
					addstr "\n"
					pos -= 1
				}
				add_line(@buffer[pos][0], @buffer[pos][1])
				noutrefresh
			end
		end
		update_scrollbar
	end
	def update_scrollbar
		if @scrollbar
			last_scrollbar_pos = @scrollbar_pos
			@scrollbar_pos = maxy - ((@buffer_pos/[(@buffer.length - maxy), 1].max.to_f) * (maxy - 1)).round - 1
			if last_scrollbar_pos
				unless last_scrollbar_pos == @scrollbar_pos
					@scrollbar.setpos(last_scrollbar_pos, 0)
					@scrollbar.addch '|'
					@scrollbar.setpos(@scrollbar_pos, 0)
					@scrollbar.attron(Curses::A_REVERSE) {
						@scrollbar.addch ' '
					}
					@scrollbar.noutrefresh
				end
			else
				for num in 0...maxy
					@scrollbar.setpos(num, 0)
					if num == @scrollbar_pos
						@scrollbar.attron(Curses::A_REVERSE) {
							@scrollbar.addch ' '
						}
					else
						@scrollbar.addch '|'
					end
				end
				@scrollbar.noutrefresh
			end
		end
	end
	def clear_scrollbar
		@scrollbar_pos = nil
		@scrollbar.clear
		@scrollbar.noutrefresh
	end
	def resize_buffer
		# fixme
	end
end