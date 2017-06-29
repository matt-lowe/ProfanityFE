#!/usr/bin/env ruby
# encoding: US-ASCII
# vim: set sts=2 noet ts=2:
=begin

	ProfanityFE v0.4
	Copyright (C) 2013  Matthew Lowe

	This program is free software; you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation; either version 2 of the License, or
	(at your option) any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License along
	with this program; if not, write to the Free Software Foundation, Inc.,
	51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

	matt@lichproject.org

=end

$version = 0.4

require 'thread'
require 'socket'
require 'rexml/document'
require 'curses'
include Curses

Curses.init_screen
Curses.start_color
Curses.cbreak
Curses.noecho

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
			if @value.class == Fixnum
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

server = nil
command_buffer        = String.new
command_buffer_pos    = 0
command_buffer_offset = 0
command_history       = Array.new
command_history_pos   = 0
max_command_history   = 20
min_cmd_length_for_history = 4
$server_time_offset     = 0
skip_server_time_offset = false
key_binding = Hash.new
key_action = Hash.new
need_prompt = false
prompt_text = ">"
stream_handler = Hash.new
indicator_handler = Hash.new
progress_handler = Hash.new
countdown_handler = Hash.new
command_window = nil
command_window_layout = nil
# We need a mutex for the settings because highlights can be accessed during a
# reload.  For now, it is just used to protect access to HIGHLIGHT, but if we
# ever support reloading other settings in the future it will have to protect
# those.
SETTINGS_LOCK = Mutex.new
HIGHLIGHT = Hash.new
PRESET = Hash.new
LAYOUT = Hash.new
WINDOWS = Hash.new
SCROLL_WINDOW = Array.new

def add_prompt(window, prompt_text, cmd="")
  window.add_string("#{prompt_text}#{cmd}", [ h={ :start => 0, :end => (prompt_text.length + cmd.length), :fg => '555555' } ])
end

for arg in ARGV
	if arg =~ /^\-\-help|^\-h|^\-\?/
		puts ""
		puts "Profanity FrontEnd v#{$version}"
		puts ""
		puts "   --port=<port>"
		puts "   --default-color-id=<id>"
		puts "   --default-background-color-id=<id>"
		puts "   --custom-colors=<on|off>"
		puts "   --settings-file=<filename>"
		puts ""
		exit
	elsif arg =~ /^\-\-port=([0-9]+)$/
		PORT = $1.to_i
	elsif arg =~ /^\-\-default\-color\-id=([0-9]+)$/
		DEFAULT_COLOR_ID = $1.to_i
	elsif arg =~ /^\-\-default\-background\-color\-id=([0-9]+)$/
		DEFAULT_BACKGROUND_COLOR_ID = $1.to_i
	elsif arg =~ /^\-\-custom\-colors=(on|off|yes|no)$/
		fix_setting = { 'on' => true, 'yes' => true, 'off' => false, 'no' => false }
		CUSTOM_COLORS = fix_setting[$1]
	elsif arg =~ /^\-\-settings\-file=(.*?)$/
		SETTINGS_FILENAME = $1
	end
end

def log(value)
		File.open('profanity.log', 'a') { |f| f.puts value }
end

unless defined?(PORT)
	PORT = 8000
end
unless defined?(DEFAULT_COLOR_ID)
	DEFAULT_COLOR_ID = 7
end
unless defined?(DEFAULT_BACKGROUND_COLOR_ID)
	DEFAULT_BACKGROUND_COLOR_ID = 0
end
unless defined?(SETTINGS_FILENAME)
	SETTINGS_FILENAME = File.expand_path('~/.profanity.xml')
end
unless defined?(CUSTOM_COLORS)
	CUSTOM_COLORS = Curses.can_change_color?
end

DEFAULT_COLOR_CODE = Curses.color_content(DEFAULT_COLOR_ID).collect { |num| ((num/1000.0)*255).round.to_s(16) }.join('').rjust(6, '0')
DEFAULT_BACKGROUND_COLOR_CODE = Curses.color_content(DEFAULT_BACKGROUND_COLOR_ID).collect { |num| ((num/1000.0)*255).round.to_s(16) }.join('').rjust(6, '0')

unless File.exists?(SETTINGS_FILENAME)

	File.open(SETTINGS_FILENAME, 'w') { |file| file.write "<settings>
	<highlight fg='9090ff'>^(?:You gesture|You intone a phrase of elemental power|You recite a series of mystical phrases|You trace a series of glowing runes|Your hands glow with power as you invoke|You trace a simple rune while intoning|You trace a sign while petitioning the spirits|You trace an intricate sign that contorts in the air).*$</highlight>
	<highlight fg='9090ff'>^(?:Cast Roundtime 3 Seconds\\.|Your spell is ready\\.)$</highlight>
	<highlight fg='9090ff'>^.*remaining\\. \\]$</highlight>
	<highlight fg='88aaff'>([A-Z][a-z]+ disk)</highlight>
	<highlight fg='555555'>^\\[.*?\\](?:>|&gt;).*$</highlight>
	<highlight fg='555555'>\\([0-9][0-9]\\:[0-9][0-9]\\:[0-9][0-9]\\)$</highlight>
	<highlight fg='0000ff'>^\\[LNet\\]</highlight>
	<highlight fg='008000'>^\\[code\\]</highlight>
	<highlight fg='808000'>^\\[Shattered\\]</highlight>
	<highlight fg='ffffff'>^\\[Private(?:To)?\\]</highlight>
	<highlight fg='008000'>^--- Lich:.*</highlight>
	<highlight fg='565656'>\\((?:calmed|dead|flying|hiding|kneeling|prone|sitting|sleeping|stunned)\\)</highlight>
	<highlight fg='ff0000'>^.* throws (?:his|her) arms skyward!$|swirling black void|(?:Dozens of flaming meteors light the sky nearby!|Several flaming meteors light the nearby sky!|Several flaming rocks burst from the sky and smite the area!|A low roar of quickly parting air can be heard above!)</highlight>
	<highlight fg='ffffff'>^.*(?:falls slack against the floor|falls slack against the ground|falls to the floor, motionless|falls to the ground dead|falls to the ground motionless|and dies|and lies still|goes still|going still)\\.$</highlight>
	<highlight fg='ffffff'>^.* is stunned!$|^You come out of hiding\\.$</highlight>
	<highlight fg='ffaaaa'>.*ruining your hiding place\\.$|^You are no longer hidden\\.$|^\\s*You are (?:stunned|knocked to the ground).*|^You are unable to remain hidden!$|^You are visible again\\.$|^You fade into sight\\.$|^You fade into view.*|^You feel drained!$|^You have overextended yourself!$|^You feel yourself going into shock!$</highlight>
	<preset id='whisper' fg='66ff66'/>
	<preset id='speech' fg='66ff66'/>
	<preset id='roomName' fg='ffffff'/>
	<preset id='monsterbold' fg='d2bc2a'/>
	<preset id='familiar' bg='00001a'/>
	<preset id='thoughts' bg='001a00'/>
	<preset id='voln' bg='001a00'/>
	<key id='alt'>
		<key id='f' macro='something'/>
	</key>
	<key id='enter' action='send_command'/>
	<key id='left' action='cursor_left'/>
	<key id='right' action='cursor_right'/>
	<key id='ctrl+left' action='cursor_word_left'/>
	<key id='ctrl+right' action='cursor_word_right'/>
	<key id='home' action='cursor_home'/>
	<key id='end' action='cursor_end'/>
	<key id='backspace' action='cursor_backspace'/>
	<key id='win_backspace' action='cursor_backspace'/>
	<key id='ctrl+?' action='cursor_backspace'/>
	<key id='delete' action='cursor_delete'/>
	<key id='tab' action='switch_current_window'/>
	<key id='alt+page_up' action='scroll_current_window_up_one'/>
	<key id='alt+page_down' action='scroll_current_window_down_one'/>
	<key id='page_up' action='scroll_current_window_up_page'/>
	<key id='page_down' action='scroll_current_window_down_page'/>
	<key id='up' action='previous_command'/>
	<key id='down' action='next_command'/>
	<key id='ctrl+up' action='send_last_command'/>
	<key id='alt+up' action='send_second_last_command'/>
	<key id='resize' action='resize'/>
	<key id='ctrl+d' macro='\\xstance defensive\\r'/>
	<key id='ctrl+o' macro='\\xstance offensive\\r'/>
	<key id='ctrl+g' macro='\\xremove my buckler\\r'/>
	<key id='ctrl+p' macro='\\xwear my buckler\\r'/>
	<key id='ctrl+f' macro='\\xtell familiar to '/>
	<layout id='default'>
		<window class='text' top='6' left='12' width='cols-12' height='lines-7' value='main' buffer-size='2000' />
		<window class='text' top='0' left='0' height='6' width='cols' value='lnet,thoughts,voln' buffer-size='1000' />
		<window class='text' top='7' left='0' width='11' height='lines-31' value='death,logons' buffer-size='500' />

		<window class='indicator' top='lines-1' left='12' height='1' width='1' label='&gt;' value='prompt' fg='444444,44444'/>
		<window class='command' top='lines-1' left='13' width='cols-13' height='1' />

		<window class='progress' top='lines-11' left='0' width='11' height='1' label='stance:' value='stance' bg='290055'/>
		<window class='progress' top='lines-10' left='0' width='11' height='1' label='mind:' value='mind' bg='663000,442000'/>
		<window class='progress' top='lines-8' left='0' width='11' height='1' label='health:' value='health' bg='004800,003300'/>
		<window class='progress' top='lines-7' left='0' width='11' height='1' label='spirit:' value='spirit' bg='333300,222200'/>
		<window class='progress' top='lines-6' left='0' width='11' height='1' label='mana:' value='mana' bg='0000a0,000055'/>
		<window class='progress' top='lines-5' left='0' width='11' height='1' label='stam:' value='stamina' bg='003333,002222'/>
		<window class='progress' top='lines-3' left='0' width='11' height='1' label='load:' value='encumbrance' bg='990033,4c0019' fg='nil,nil,nil,444444'/>

		<window class='countdown' top='lines-2' left='0' width='11' height='1' label='stun:' value='stunned' fg='444444,dddddd' bg='nil,aa0000'/>
		<window class='countdown' top='lines-1' left='0' width='11' height='1' label='rndtime:' value='roundtime' fg='444444,dddddd,dddddd,dddddd' bg='nil,aa0000,0000aa'/>

		<window class='indicator' top='lines-15' left='1' height='1' width='1' label='^' value='compass:up' fg='444444,ffff00'/>
		<window class='indicator' top='lines-14' left='1' height='1' width='1' label='o' value='compass:out' fg='444444,ffff00'/>
		<window class='indicator' top='lines-13' left='1' height='1' width='1' label='v' value='compass:down' fg='444444,ffff00'/>
		<window class='indicator' top='lines-15' left='5' height='1' width='1' label='*' value='compass:nw' fg='444444,ffff00'/>
		<window class='indicator' top='lines-14' left='5' height='1' width='1' label='&lt;' value='compass:w' fg='444444,ffff00'/>
		<window class='indicator' top='lines-13' left='5' height='1' width='1' label='*' value='compass:sw' fg='444444,ffff00'/>
		<window class='indicator' top='lines-15' left='7' height='1' width='1' label='^' value='compass:n' fg='444444,ffff00'/>
		<window class='indicator' top='lines-13' left='7' height='1' width='1' label='v' value='compass:s' fg='444444,ffff00'/>
		<window class='indicator' top='lines-15' left='9' height='1' width='1' label='*' value='compass:ne' fg='444444,ffff00'/>
		<window class='indicator' top='lines-14' left='9' height='1' width='1' label='&gt;' value='compass:e' fg='444444,ffff00'/>
		<window class='indicator' top='lines-13' left='9' height='1' width='1' label='*' value='compass:se' fg='444444,ffff00'/>

		<window class='indicator' top='lines-23' left='1' height='1' width='1' label='e' value='leftEye' fg='444444,ffff00,ff6600,ff0000,00ffff,0066ff,0000ff'/>
		<window class='indicator' top='lines-23' left='5' height='1' width='1' label='e' value='rightEye' fg='444444,ffff00,ff6600,ff0000,00ffff,0066ff,0000ff'/>
		<window class='indicator' top='lines-22' left='3' height='1' width='1' label='O' value='head' fg='444444,ffff00,ff6600,ff0000,00ffff,0066ff,0000ff'/>
		<window class='indicator' top='lines-21' left='2' height='1' width='1' label='/' value='leftArm' fg='444444,ffff00,ff6600,ff0000,00ffff,0066ff,0000ff'/>
		<window class='indicator' top='lines-21' left='3' height='1' width='1' label='|' value='chest' fg='444444,ffff00,ff6600,ff0000,00ffff,0066ff,0000ff'/>
		<window class='indicator' top='lines-21' left='4' height='1' width='1' label='\\' value='rightArm' fg='444444,ffff00,ff6600,ff0000,00ffff,0066ff,0000ff'/>
		<window class='indicator' top='lines-20' left='1' height='1' width='1' label='o' value='leftHand' fg='444444,ffff00,ff6600,ff0000,00ffff,0066ff,0000ff'/>
		<window class='indicator' top='lines-20' left='3' height='1' width='1' label='|' value='abdomen' fg='444444,ffff00,ff6600,ff0000,00ffff,0066ff,0000ff'/>
		<window class='indicator' top='lines-20' left='5' height='1' width='1' label='o' value='rightHand' fg='444444,ffff00,ff6600,ff0000,00ffff,0066ff,0000ff'/>
		<window class='indicator' top='lines-19' left='1' height='2' width='2' label=' /o' value='leftLeg' fg='444444,ffff00,ff6600,ff0000,00ffff,0066ff,0000ff'/>
		<window class='indicator' top='lines-19' left='4' height='2' width='2' label='\\  o' value='rightLeg' fg='444444,ffff00,ff6600,ff0000,00ffff,0066ff,0000ff'/>
		<window class='indicator' top='lines-23' left='8' height='1' width='2' label='ns' value='nsys' fg='444444,ffff00,ff6600,ff0000,00ffff,0066ff,0000ff'/>
		<window class='indicator' top='lines-21' left='8' height='1' width='2' label='nk' value='neck' fg='444444,ffff00,ff6600,ff0000,00ffff,0066ff,0000ff'/>
		<window class='indicator' top='lines-19' left='8' height='1' width='2' label='bk' value='back' fg='444444,ffff00,ff6600,ff0000,00ffff,0066ff,0000ff'/>

		<window class='indicator' top='lines-17' left='0' height='1' width='3' label='psn' value='poisoned' fg='444444,ff0000'/>
		<window class='indicator' top='lines-17' left='4' height='1' width='3' label='dis' value='diseased' fg='444444,ff0000'/>
		<window class='indicator' top='lines-17' left='8' height='1' width='3' label='bld' value='bleeding' fg='444444,ff0000'/>
	</layout>
</settings>
" }

end

xml_escape_list = {
	'&lt;'   => '<',
	'&gt;'   => '>',
	'&quot;' => '"',
	'&apos;' => "'",
	'&amp;'  => '&',
#	'&#xA'   => "\n",
}

key_name = {
	'ctrl+a'    => 1,
	'ctrl+b'    => 2,
#	'ctrl+c'    => 3,
	'ctrl+d'    => 4,
	'ctrl+e'    => 5,
	'ctrl+f'    => 6,
	'ctrl+g'    => 7,
	'ctrl+h'    => 8,
	'win_backspace' => 8,
	'ctrl+i'    => 9,
	'tab'       => 9,
	'ctrl+j'    => 10,
	'enter'     => 10,
	'ctrl+k'    => 11,
	'ctrl+l'    => 12,
	'return'    => 13,
	'ctrl+m'    => 13,
	'ctrl+n'    => 14,
	'ctrl+o'    => 15,
	'ctrl+p'    => 16,
#	'ctrl+q'    => 17,
	'ctrl+r'    => 18,
#	'ctrl+s'    => 19,
	'ctrl+t'    => 20,
	'ctrl+u'    => 21,
	'ctrl+v'    => 22,
	'ctrl+w'    => 23,
	'ctrl+x'    => 24,
	'ctrl+y'    => 25,
#	'ctrl+z'    => 26,
	'alt'       => 27,
	'escape'    => 27,
	'ctrl+?'    => 127,
	'down'      => 258,
	'up'        => 259,
	'left'      => 260,
	'right'     => 261,
	'home'      => 262,
	'backspace' => 263,
	'f1'        => 265,
	'f2'        => 266,
	'f3'        => 267,
	'f4'        => 268,
	'f5'        => 269,
	'f6'        => 270,
	'f7'        => 271,
	'f8'        => 272,
	'f9'        => 273,
	'f10'       => 274,
	'f11'       => 275,
	'f12'       => 276,
	'delete'    => 330,
	'insert'    => 331,
	'page_down' => 338,
	'page_up'   => 339,
	'end'       => 360,
	'resize'    => 410,
	'ctrl+delete' => 513,
	'alt+down'    => 517,
	'ctrl+down'   => 519,
	'alt+left'    => 537,
	'ctrl+left'   => 539,
	'alt+page_down' => 542,
	'alt+page_up'   => 547,
	'alt+right'     => 552,
	'ctrl+right'    => 554,
	'alt+up'        => 558,
	'ctrl+up'       => 560,
}

if CUSTOM_COLORS
	COLOR_ID_LOOKUP = Hash.new
	COLOR_ID_LOOKUP[DEFAULT_COLOR_CODE] = DEFAULT_COLOR_ID
	COLOR_ID_LOOKUP[DEFAULT_BACKGROUND_COLOR_CODE] = DEFAULT_BACKGROUND_COLOR_ID
	COLOR_ID_HISTORY = Array.new
	for num in 0...Curses.colors
		unless (num == DEFAULT_COLOR_ID) or (num == DEFAULT_BACKGROUND_COLOR_ID)
			COLOR_ID_HISTORY.push(num)
		end
	end

	def get_color_id(code)
		if color_id = COLOR_ID_LOOKUP[code]
			color_id
		else
			color_id = COLOR_ID_HISTORY.shift
			COLOR_ID_LOOKUP.delete_if { |k,v| v == color_id }
			sleep 0.01 # somehow this keeps Curses.init_color from failing sometimes
			Curses.init_color(color_id, ((code[0..1].to_s.hex/255.0)*1000).round, ((code[2..3].to_s.hex/255.0)*1000).round, ((code[4..5].to_s.hex/255.0)*1000).round)
			COLOR_ID_LOOKUP[code] = color_id
			COLOR_ID_HISTORY.push(color_id)
			color_id
		end
	end
else
	COLOR_CODE = [ '000000', '800000', '008000', '808000', '000080', '800080', '008080', 'c0c0c0', '808080', 'ff0000', '00ff00', 'ffff00', '0000ff', 'ff00ff', '00ffff', 'ffffff', '000000', '00005f', '000087', '0000af', '0000d7', '0000ff', '005f00', '005f5f', '005f87', '005faf', '005fd7', '005fff', '008700', '00875f', '008787', '0087af', '0087d7', '0087ff', '00af00', '00af5f', '00af87', '00afaf', '00afd7', '00afff', '00d700', '00d75f', '00d787', '00d7af', '00d7d7', '00d7ff', '00ff00', '00ff5f', '00ff87', '00ffaf', '00ffd7', '00ffff', '5f0000', '5f005f', '5f0087', '5f00af', '5f00d7', '5f00ff', '5f5f00', '5f5f5f', '5f5f87', '5f5faf', '5f5fd7', '5f5fff', '5f8700', '5f875f', '5f8787', '5f87af', '5f87d7', '5f87ff', '5faf00', '5faf5f', '5faf87', '5fafaf', '5fafd7', '5fafff', '5fd700', '5fd75f', '5fd787', '5fd7af', '5fd7d7', '5fd7ff', '5fff00', '5fff5f', '5fff87', '5fffaf', '5fffd7', '5fffff', '870000', '87005f', '870087', '8700af', '8700d7', '8700ff', '875f00', '875f5f', '875f87', '875faf', '875fd7', '875fff', '878700', '87875f', '878787', '8787af', '8787d7', '8787ff', '87af00', '87af5f', '87af87', '87afaf', '87afd7', '87afff', '87d700', '87d75f', '87d787', '87d7af', '87d7d7', '87d7ff', '87ff00', '87ff5f', '87ff87', '87ffaf', '87ffd7', '87ffff', 'af0000', 'af005f', 'af0087', 'af00af', 'af00d7', 'af00ff', 'af5f00', 'af5f5f', 'af5f87', 'af5faf', 'af5fd7', 'af5fff', 'af8700', 'af875f', 'af8787', 'af87af', 'af87d7', 'af87ff', 'afaf00', 'afaf5f', 'afaf87', 'afafaf', 'afafd7', 'afafff', 'afd700', 'afd75f', 'afd787', 'afd7af', 'afd7d7', 'afd7ff', 'afff00', 'afff5f', 'afff87', 'afffaf', 'afffd7', 'afffff', 'd70000', 'd7005f', 'd70087', 'd700af', 'd700d7', 'd700ff', 'd75f00', 'd75f5f', 'd75f87', 'd75faf', 'd75fd7', 'd75fff', 'd78700', 'd7875f', 'd78787', 'd787af', 'd787d7', 'd787ff', 'd7af00', 'd7af5f', 'd7af87', 'd7afaf', 'd7afd7', 'd7afff', 'd7d700', 'd7d75f', 'd7d787', 'd7d7af', 'd7d7d7', 'd7d7ff', 'd7ff00', 'd7ff5f', 'd7ff87', 'd7ffaf', 'd7ffd7', 'd7ffff', 'ff0000', 'ff005f', 'ff0087', 'ff00af', 'ff00d7', 'ff00ff', 'ff5f00', 'ff5f5f', 'ff5f87', 'ff5faf', 'ff5fd7', 'ff5fff', 'ff8700', 'ff875f', 'ff8787', 'ff87af', 'ff87d7', 'ff87ff', 'ffaf00', 'ffaf5f', 'ffaf87', 'ffafaf', 'ffafd7', 'ffafff', 'ffd700', 'ffd75f', 'ffd787', 'ffd7af', 'ffd7d7', 'ffd7ff', 'ffff00', 'ffff5f', 'ffff87', 'ffffaf', 'ffffd7', 'ffffff', '080808', '121212', '1c1c1c', '262626', '303030', '3a3a3a', '444444', '4e4e4e', '585858', '626262', '6c6c6c', '767676', '808080', '8a8a8a', '949494', '9e9e9e', 'a8a8a8', 'b2b2b2', 'bcbcbc', 'c6c6c6', 'd0d0d0', 'dadada', 'e4e4e4', 'eeeeee' ][0...Curses.colors]
	COLOR_ID_LOOKUP = Hash.new

	def get_color_id(code)
		if color_id = COLOR_ID_LOOKUP[code]
			color_id
		else
			least_error = nil
			least_error_id = nil
			COLOR_CODE.each_index { |color_id|
				error = ((COLOR_CODE[color_id][0..1].hex - code[0..1].hex)**2) + ((COLOR_CODE[color_id][2..3].hex - code[2..3].hex)**2) + ((COLOR_CODE[color_id][4..6].hex - code[4..6].hex)**2)
				if least_error.nil? or (error < least_error)
					least_error = error
					least_error_id = color_id
				end
			}
			COLOR_ID_LOOKUP[code] = least_error_id
			least_error_id
		end
	end
end

#COLOR_PAIR_LIST = Array.new
#for num in 1...Curses::color_pairs
#	COLOR_PAIR_LIST.push h={ :color_id => nil, :background_id => nil, :id => num }
#end

#157+12+1 = 180
#38+1+6 = 45
#32767

COLOR_PAIR_ID_LOOKUP = Hash.new
COLOR_PAIR_HISTORY = Array.new

# fixme: high color pair id's change text?
# A_NORMAL = 0
# A_STANDOUT = 65536
# A_UNDERLINE = 131072
# 15000 = black background, dark blue-green text
# 10000 = dark yellow background, black text
#  5000 = black
#  2000 = black
#  1000 = highlights show up black
#   100 = normal
#   500 = black and some underline

for num in 1...Curses::color_pairs # fixme: things go to hell at about pair 256
#for num in 1...([Curses::color_pairs, 256].min)
	COLOR_PAIR_HISTORY.push(num)
end

def get_color_pair_id(fg_code, bg_code)
	if fg_code.nil?
		fg_id = DEFAULT_COLOR_ID
	else
		fg_id = get_color_id(fg_code)
	end
	if bg_code.nil?
		bg_id = DEFAULT_BACKGROUND_COLOR_ID
	else
		bg_id = get_color_id(bg_code)
	end
	if (COLOR_PAIR_ID_LOOKUP[fg_id]) and (color_pair_id = COLOR_PAIR_ID_LOOKUP[fg_id][bg_id])
		color_pair_id
	else
		color_pair_id = COLOR_PAIR_HISTORY.shift
		COLOR_PAIR_ID_LOOKUP.each { |w,x| x.delete_if { |y,z| z == color_pair_id } }
		sleep 0.01
		Curses.init_pair(color_pair_id, fg_id, bg_id)
		COLOR_PAIR_ID_LOOKUP[fg_id] ||= Hash.new
		COLOR_PAIR_ID_LOOKUP[fg_id][bg_id] = color_pair_id
		COLOR_PAIR_HISTORY.push(color_pair_id)
		color_pair_id
	end
end

# Implement support for basic readline-style kill and yank (cut and paste)
# commands.  Successive calls to delete_word, backspace_word, kill_forward, and
# kill_line will accumulate text into the kill_buffer as long as no other
# commands have changed the command buffer.  These commands call kill_before to
# reset the kill_buffer if the command buffer has changed, add the newly
# deleted text to the kill_buffer, and finally call kill_after to remember the
# state of the command buffer for next time.
kill_buffer   = ''
kill_original = ''
kill_last     = ''
kill_last_pos = 0
kill_before = proc {
	if kill_last != command_buffer || kill_last_pos != command_buffer_pos
		kill_buffer = ''
		kill_original = command_buffer
	end
}
kill_after = proc {
	kill_last = command_buffer.dup
	kill_last_pos = command_buffer_pos
}

fix_layout_number = proc { |str|
	str = str.gsub('lines', Curses.lines.to_s).gsub('cols', Curses.cols.to_s)
	str.untaint
	begin
		proc { $SAFE = 1; eval(str) }.call.to_i
	rescue
		$stderr.puts $!
		$stderr.puts $!.backtrace[0..1]
		0
	end
}

load_layout = proc { |layout_id|
	if xml = LAYOUT[layout_id]
		old_windows = IndicatorWindow.list | TextWindow.list | CountdownWindow.list | ProgressWindow.list

		previous_indicator_handler = indicator_handler
		indicator_handler = Hash.new

		previous_stream_handler = stream_handler
		stream_handler = Hash.new

		previous_progress_handler = progress_handler
		progress_handler = Hash.new

		previous_countdown_handler = countdown_handler
		progress_handler = Hash.new

		xml.elements.each { |e|
			if e.name == 'window'
				height, width, top, left = fix_layout_number.call(e.attributes['height']), fix_layout_number.call(e.attributes['width']), fix_layout_number.call(e.attributes['top']), fix_layout_number.call(e.attributes['left'])
				if (height > 0) and (width > 0) and (top >= 0) and (left >= 0) and (top < Curses.lines) and (left < Curses.cols)
					if e.attributes['class'] == 'indicator'
						if e.attributes['value'] and (window = previous_indicator_handler[e.attributes['value']])
							previous_indicator_handler[e.attributes['value']] = nil
							old_windows.delete(window)
						else
							window = IndicatorWindow.new(height, width, top, left)
						end
						window.layout = [ e.attributes['height'], e.attributes['width'], e.attributes['top'], e.attributes['left'] ]
						window.scrollok(false)
						window.label = e.attributes['label'] if e.attributes['label']
						window.fg = e.attributes['fg'].split(',').collect { |val| if val == 'nil'; nil; else; val; end  } if e.attributes['fg']
						window.bg = e.attributes['bg'].split(',').collect { |val| if val == 'nil'; nil; else; val; end  } if e.attributes['bg']
						if e.attributes['value']
							indicator_handler[e.attributes['value']] = window
						end
						window.redraw
					elsif e.attributes['class'] == 'text'
						if width > 1
							if e.attributes['value'] and (window = previous_stream_handler[previous_stream_handler.keys.find { |key| e.attributes['value'].split(',').include?(key) }])
								previous_stream_handler[e.attributes['value']] = nil
								old_windows.delete(window)
							else
								window = TextWindow.new(height, width - 1, top, left)
								window.scrollbar = Curses::Window.new(window.maxy, 1, window.begy, window.begx + window.maxx)
							end
							window.layout = [ e.attributes['height'], e.attributes['width'], e.attributes['top'], e.attributes['left'] ]
							window.scrollok(true)
							window.max_buffer_size = e.attributes['buffer-size'] || 1000
							e.attributes['value'].split(',').each { |str|
								stream_handler[str] = window
							}
						end
					elsif e.attributes['class'] == 'countdown'
						if e.attributes['value'] and (window = previous_countdown_handler[e.attributes['value']])
							previous_countdown_handler[e.attributes['value']] = nil
							old_windows.delete(window)
						else
							window = CountdownWindow.new(height, width, top, left)
						end
						window.layout = [ e.attributes['height'], e.attributes['width'], e.attributes['top'], e.attributes['left'] ]
						window.scrollok(false)
						window.label = e.attributes['label'] if e.attributes['label']
						window.fg = e.attributes['fg'].split(',').collect { |val| if val == 'nil'; nil; else; val; end  } if e.attributes['fg']
						window.bg = e.attributes['bg'].split(',').collect { |val| if val == 'nil'; nil; else; val; end  } if e.attributes['bg']
						if e.attributes['value']
							countdown_handler[e.attributes['value']] = window
						end
						window.update
					elsif e.attributes['class'] == 'progress'
						if e.attributes['value'] and (window = previous_progress_handler[e.attributes['value']])
							previous_progress_handler[e.attributes['value']] = nil
							old_windows.delete(window)
						else
							window = ProgressWindow.new(height, width, top, left)
						end
						window.layout = [ e.attributes['height'], e.attributes['width'], e.attributes['top'], e.attributes['left'] ]
						window.scrollok(false)
						window.label = e.attributes['label'] if e.attributes['label']
						window.fg = e.attributes['fg'].split(',').collect { |val| if val == 'nil'; nil; else; val; end  } if e.attributes['fg']
						window.bg = e.attributes['bg'].split(',').collect { |val| if val == 'nil'; nil; else; val; end  } if e.attributes['bg']
						if e.attributes['value']
							progress_handler[e.attributes['value']] = window
						end
						window.redraw
					elsif e.attributes['class'] == 'command'
						unless command_window
							command_window = Curses::Window.new(height, width, top, left)
						end
						command_window_layout = [ e.attributes['height'], e.attributes['width'], e.attributes['top'], e.attributes['left'] ]
						command_window.scrollok(false)
						command_window.keypad(true)
					end
				end
			end
		}
		if current_scroll_window = TextWindow.list[0]
			current_scroll_window.update_scrollbar
		end
		for window in old_windows
			IndicatorWindow.list.delete(window)
			TextWindow.list.delete(window)
			CountdownWindow.list.delete(window)
			ProgressWindow.list.delete(window)
			if window.class == TextWindow
				window.scrollbar.close
			end
			window.close
		end
		Curses.doupdate
	end
}

do_macro = nil

setup_key = proc { |xml,binding|
	if key = xml.attributes['id']
		if key =~ /^[0-9]+$/
			key = key.to_i
		elsif (key.class) == String and (key.length == 1)
			nil
		else
			key = key_name[key]
		end
		if key
			if macro = xml.attributes['macro']
				binding[key] = proc { do_macro.call(macro) }
			elsif xml.attributes['action'] and action = key_action[xml.attributes['action']]
				binding[key] = action
			else
				binding[key] ||= Hash.new
				xml.elements.each { |e|
					setup_key.call(e, binding[key])
				}
			end
		end
	end
}

load_settings_file = proc { |reload|
	SETTINGS_LOCK.synchronize {
		begin
			HIGHLIGHT.clear()
			File.open(SETTINGS_FILENAME) { |file|
				xml_doc = REXML::Document.new(file)
				xml_root = xml_doc.root
				xml_root.elements.each { |e|
					if e.name == 'highlight'
						begin
							r = Regexp.new(e.text)
						rescue
							r = nil
							$stderr.puts e.to_s
							$stderr.puts $!
						end
						if r
							HIGHLIGHT[r] = [ e.attributes['fg'], e.attributes['bg'], e.attributes['ul'] ]
						end
					end
					# These are things that we ignore if we're doing a reload of the settings file
					if !reload
						if e.name == 'preset'
							PRESET[e.attributes['id']] = [ e.attributes['fg'], e.attributes['bg'] ]
						elsif (e.name == 'layout') and (layout_id = e.attributes['id'])
							LAYOUT[layout_id] = e
						elsif e.name == 'key'
							setup_key.call(e, key_binding)
						end
					end
				}
			}
		rescue
			$stdout.puts $!
			$stdout.puts $!.backtrace[0..1]
			log $!
			log $!.backtrace[0..1]

		end
	}
}

command_window_put_ch = proc { |ch|
	if (command_buffer_pos - command_buffer_offset + 1) >= command_window.maxx
		command_window.setpos(0,0)
		command_window.delch
		command_buffer_offset += 1
		command_window.setpos(0, command_buffer_pos - command_buffer_offset)
	end
	command_buffer.insert(command_buffer_pos, ch)
	command_buffer_pos += 1
	command_window.insch(ch)
	command_window.setpos(0, command_buffer_pos - command_buffer_offset)
}

do_macro = proc { |macro|
	# fixme: gsub %whatever
	backslash = false
	at_pos = nil
	backfill = nil
	macro.split('').each_with_index { |ch, i|
		if backslash
			if ch == '\\'
				command_window_put_ch.call('\\')
			elsif ch == 'x'
				command_buffer.clear
				command_buffer_pos = 0
				command_buffer_offset = 0
				command_window.deleteln
				command_window.setpos(0,0)
			elsif ch == 'r'
				at_pos = nil
				key_action['send_command'].call
			elsif ch == '@'
				command_window_put_ch.call('@')
			elsif ch == '?'
				backfill = i - 3
			else
				nil
			end
			backslash = false
		else
			if ch == '\\'
				backslash = true
			elsif ch == '@'
				at_pos = command_buffer_pos
			else
				command_window_put_ch.call(ch)
			end
		end
	}
	if at_pos
		while at_pos < command_buffer_pos
			key_action['cursor_left'].call
		end
		while at_pos > command_buffer_pos
			key_action['cursor_right'].call
		end
	end
	command_window.noutrefresh
	if backfill then
		command_window.setpos(0,backfill)
		command_buffer_pos = backfill
		backfill = nil
	end
	Curses.doupdate
}

key_action['resize'] = proc {
	# fixme: re-word-wrap
	window = Window.new(0,0,0,0)
	window.refresh
	window.close
	first_text_window = true
	for window in TextWindow.list.to_a
		window.resize(fix_layout_number.call(window.layout[0]), fix_layout_number.call(window.layout[1]) - 1)
		window.move(fix_layout_number.call(window.layout[2]), fix_layout_number.call(window.layout[3]))
		window.scrollbar.resize(window.maxy, 1)
		window.scrollbar.move(window.begy, window.begx + window.maxx)
		window.scroll(-window.maxy)
		window.scroll(window.maxy)
		window.clear_scrollbar
		if first_text_window
			window.update_scrollbar
			first_text_window = false
		end
		window.noutrefresh
	end
	for window in [ IndicatorWindow.list.to_a, ProgressWindow.list.to_a, CountdownWindow.list.to_a ].flatten
		window.resize(fix_layout_number.call(window.layout[0]), fix_layout_number.call(window.layout[1]))
		window.move(fix_layout_number.call(window.layout[2]), fix_layout_number.call(window.layout[3]))
		window.noutrefresh
	end
	if command_window
		command_window.resize(fix_layout_number.call(command_window_layout[0]), fix_layout_number.call(command_window_layout[1]))
		command_window.move(fix_layout_number.call(command_window_layout[2]), fix_layout_number.call(command_window_layout[3]))
		command_window.noutrefresh
	end
	Curses.doupdate
}

key_action['cursor_left'] = proc {
	if (command_buffer_offset > 0) and (command_buffer_pos - command_buffer_offset == 0)
		command_buffer_pos -= 1
		command_buffer_offset -= 1
		command_window.insch(command_buffer[command_buffer_pos])
	else
		command_buffer_pos = [command_buffer_pos - 1, 0].max
	end
	command_window.setpos(0, command_buffer_pos - command_buffer_offset)
	command_window.noutrefresh
	Curses.doupdate
}

key_action['cursor_right'] = proc {
	if ((command_buffer.length - command_buffer_offset) >= (command_window.maxx - 1)) and (command_buffer_pos - command_buffer_offset + 1) >= command_window.maxx
		if command_buffer_pos < command_buffer.length
			command_window.setpos(0,0)
			command_window.delch
			command_buffer_offset += 1
			command_buffer_pos += 1
			command_window.setpos(0, command_buffer_pos - command_buffer_offset)
			unless command_buffer_pos >= command_buffer.length
				command_window.insch(command_buffer[command_buffer_pos])
			end
		end
	else
		command_buffer_pos = [command_buffer_pos + 1, command_buffer.length].min
		command_window.setpos(0, command_buffer_pos - command_buffer_offset)
	end
	command_window.noutrefresh
	Curses.doupdate
}

key_action['cursor_word_left'] = proc {
	if command_buffer_pos > 0
		if m = command_buffer[0...(command_buffer_pos-1)].match(/.*(\w[^\w\s]|\W\w|\s\S)/)
			new_pos = m.begin(1) + 1
		else
			new_pos = 0
		end
		if (command_buffer_offset > new_pos)
			command_window.setpos(0, 0)
			command_buffer[new_pos, (command_buffer_offset - new_pos)].split('').reverse.each { |ch| command_window.insch(ch) }
			command_buffer_pos = new_pos
			command_buffer_offset = new_pos
		else
			command_buffer_pos = new_pos
		end
		command_window.setpos(0, command_buffer_pos - command_buffer_offset)
		command_window.noutrefresh
		Curses.doupdate
	end
}

key_action['cursor_word_right'] = proc {
	if command_buffer_pos < command_buffer.length
		if m = command_buffer[command_buffer_pos..-1].match(/\w[^\w\s]|\W\w|\s\S/)
			new_pos = command_buffer_pos + m.begin(0) + 1
		else
			new_pos = command_buffer.length
		end
		overflow = new_pos - command_window.maxx - command_buffer_offset + 1
		if overflow > 0
			command_window.setpos(0,0)
			overflow.times {
				command_window.delch
				command_buffer_offset += 1
			}
			command_window.setpos(0, command_window.maxx - overflow)
			command_window.addstr command_buffer[(command_window.maxx - overflow + command_buffer_offset),overflow]
		end
		command_buffer_pos = new_pos
		command_window.setpos(0, command_buffer_pos - command_buffer_offset)
		command_window.noutrefresh
		Curses.doupdate
	end
}

key_action['cursor_home'] = proc {
	command_buffer_pos = 0
	command_window.setpos(0, 0)
	for num in 1..command_buffer_offset
		begin
			command_window.insch(command_buffer[command_buffer_offset-num])
		rescue
			File.open('profanity.log', 'a') { |f| f.puts "command_buffer: #{command_buffer.inspect}"; f.puts "command_buffer_offset: #{command_buffer_offset.inspect}"; f.puts "num: #{num.inspect}"; f.puts $!; f.puts $!.backtrace[0...4] }
			exit
		end
	end
	command_buffer_offset = 0
	command_window.noutrefresh
	Curses.doupdate
}

key_action['cursor_end'] = proc {
	if command_buffer.length < (command_window.maxx - 1)
		command_buffer_pos = command_buffer.length
		command_window.setpos(0, command_buffer_pos)
	else
		scroll_left_num = command_buffer.length - command_window.maxx + 1 - command_buffer_offset
		command_window.setpos(0, 0)
		scroll_left_num.times {
			command_window.delch
			command_buffer_offset += 1
		}
		command_buffer_pos = command_buffer_offset + command_window.maxx - 1 - scroll_left_num
		command_window.setpos(0, command_buffer_pos - command_buffer_offset)
		scroll_left_num.times {
			command_window.addch(command_buffer[command_buffer_pos])
			command_buffer_pos += 1
		}
	end
	command_window.noutrefresh
	Curses.doupdate
}

key_action['cursor_backspace'] = proc {
	if command_buffer_pos > 0
		command_buffer_pos -= 1
		if command_buffer_pos == 0
			command_buffer = command_buffer[(command_buffer_pos+1)..-1]
		else
			command_buffer = command_buffer[0..(command_buffer_pos-1)] + command_buffer[(command_buffer_pos+1)..-1]
		end
		command_window.setpos(0, command_buffer_pos - command_buffer_offset)
		command_window.delch
		if (command_buffer.length - command_buffer_offset + 1) > command_window.maxx
			command_window.setpos(0, command_window.maxx - 1)
			command_window.addch command_buffer[command_window.maxx - command_buffer_offset - 1]
			command_window.setpos(0, command_buffer_pos - command_buffer_offset)
		end
		command_window.noutrefresh
		Curses.doupdate
	end
}

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
end

key_action['cursor_delete'] = proc {
	if (command_buffer.length > 0) and (command_buffer_pos < command_buffer.length)
		if command_buffer_pos == 0
			command_buffer = command_buffer[(command_buffer_pos+1)..-1]
		elsif command_buffer_pos < command_buffer.length
			command_buffer = command_buffer[0..(command_buffer_pos-1)] + command_buffer[(command_buffer_pos+1)..-1]
		end
		command_window.delch
		if (command_buffer.length - command_buffer_offset + 1) > command_window.maxx
			command_window.setpos(0, command_window.maxx - 1)
			command_window.addch command_buffer[command_window.maxx - command_buffer_offset - 1]
			command_window.setpos(0, command_buffer_pos - command_buffer_offset)
		end
		command_window.noutrefresh
		Curses.doupdate
	end
}


key_action['cursor_backspace_word'] = proc {
	num_deleted = 0
	deleted_alnum = false
	deleted_nonspace = false
	while command_buffer_pos > 0 do
		next_char = command_buffer[command_buffer_pos - 1]
		if num_deleted == 0 || (!deleted_alnum && next_char.punct?) || (!deleted_nonspace && next_char.space?) || next_char.alnum?
			deleted_alnum = deleted_alnum || next_char.alnum?
			deleted_nonspace = !next_char.space?
			num_deleted += 1
			kill_before.call
			kill_buffer = next_char + kill_buffer
			key_action['cursor_backspace'].call
			kill_after.call
		else
			break
		end
	end
}

key_action['cursor_delete_word'] = proc {
	num_deleted = 0
	deleted_alnum = false
	deleted_nonspace = false
	while command_buffer_pos < command_buffer.length do
		next_char = command_buffer[command_buffer_pos]
		if num_deleted == 0 || (!deleted_alnum && next_char.punct?) || (!deleted_nonspace && next_char.space?) || next_char.alnum?
			deleted_alnum = deleted_alnum || next_char.alnum?
			deleted_nonspace = !next_char.space?
			num_deleted += 1
			kill_before.call
			kill_buffer = kill_buffer + next_char
			key_action['cursor_delete'].call
			kill_after.call
		else
			break
		end
	end
}

key_action['cursor_kill_forward'] = proc {
	if command_buffer_pos < command_buffer.length
		kill_before.call
		if command_buffer_pos == 0
			kill_buffer = kill_buffer + command_buffer
			command_buffer = ''
		else
			kill_buffer = kill_buffer + command_buffer[command_buffer_pos..-1]
			command_buffer = command_buffer[0..(command_buffer_pos-1)]
		end
		kill_after.call
		command_window.clrtoeol
		command_window.noutrefresh
		Curses.doupdate
	end
}

key_action['cursor_kill_line'] = proc {
	if command_buffer.length != 0
		kill_before.call
		kill_buffer = kill_original
		command_buffer = ''
		command_buffer_pos = 0
		command_buffer_offset = 0
		kill_after.call
		command_window.setpos(0, 0)
		command_window.clrtoeol
		command_window.noutrefresh
		Curses.doupdate
	end
}

key_action['cursor_yank'] = proc {
	kill_buffer.each_char { |c| command_window_put_ch.call(c) }
}

key_action['switch_current_window'] = proc {
	if current_scroll_window = TextWindow.list[0]
		current_scroll_window.clear_scrollbar
	end
	TextWindow.list.push(TextWindow.list.shift)
	if current_scroll_window = TextWindow.list[0]
		current_scroll_window.update_scrollbar
	end
	command_window.noutrefresh
	Curses.doupdate
}

key_action['scroll_current_window_up_one'] = proc {
	if current_scroll_window = TextWindow.list[0]
		current_scroll_window.scroll(-1)
	end
	command_window.noutrefresh
	Curses.doupdate
}

key_action['scroll_current_window_down_one'] = proc {
	if current_scroll_window = TextWindow.list[0]
		current_scroll_window.scroll(1)
	end
	command_window.noutrefresh
	Curses.doupdate
}

key_action['scroll_current_window_up_page'] = proc {
	if current_scroll_window = TextWindow.list[0]
		current_scroll_window.scroll(0 - current_scroll_window.maxy + 1)
	end
	command_window.noutrefresh
	Curses.doupdate
}

key_action['scroll_current_window_down_page'] = proc {
	if current_scroll_window = TextWindow.list[0]
		current_scroll_window.scroll(current_scroll_window.maxy - 1)
	end
	command_window.noutrefresh
	Curses.doupdate
}

key_action['scroll_current_window_bottom'] = proc {
	if current_scroll_window = TextWindow.list[0]
		current_scroll_window.scroll(current_scroll_window.max_buffer_size)
	end
	command_window.noutrefresh
	Curses.doupdate
}

key_action['previous_command'] = proc {
	if command_history_pos < (command_history.length - 1)
		command_history[command_history_pos] = command_buffer.dup
		command_history_pos += 1
		command_buffer = command_history[command_history_pos].dup
		command_buffer_offset = [ (command_buffer.length - command_window.maxx + 1), 0 ].max
		command_buffer_pos = command_buffer.length
		command_window.setpos(0, 0)
		command_window.deleteln
		command_window.addstr command_buffer[command_buffer_offset,(command_buffer.length - command_buffer_offset)]
		command_window.setpos(0, command_buffer_pos - command_buffer_offset)
		command_window.noutrefresh
		Curses.doupdate
	end
}

key_action['next_command'] = proc {
	if command_history_pos == 0
		unless command_buffer.empty?
			command_history[command_history_pos] = command_buffer.dup
			command_history.unshift String.new
			command_buffer.clear
			command_window.deleteln
			command_buffer_pos = 0
			command_buffer_offset = 0
			command_window.setpos(0,0)
			command_window.noutrefresh
			Curses.doupdate
		end
	else
		command_history[command_history_pos] = command_buffer.dup
		command_history_pos -= 1
		command_buffer = command_history[command_history_pos].dup
		command_buffer_offset = [ (command_buffer.length - command_window.maxx + 1), 0 ].max
		command_buffer_pos = command_buffer.length
		command_window.setpos(0, 0)
		command_window.deleteln
		command_window.addstr command_buffer[command_buffer_offset,(command_buffer.length - command_buffer_offset)]
		command_window.setpos(0, command_buffer_pos - command_buffer_offset)
		command_window.noutrefresh
		Curses.doupdate
	end
}

key_action['switch_arrow_mode'] = proc {
	if key_binding[Curses::KEY_UP] == key_action['previous_command']
		key_binding[Curses::KEY_UP] = key_action['scroll_current_window_up_page']
		key_binding[Curses::KEY_DOWN] = key_action['scroll_current_window_down_page']
	else
		key_binding[Curses::KEY_UP] = key_action['previous_command']
		key_binding[Curses::KEY_DOWN] = key_action['next_command']
	end
}

key_action['send_command'] = proc {
	cmd = command_buffer.dup
	command_buffer.clear
	command_buffer_pos = 0
	command_buffer_offset = 0
	need_prompt = false
	if window = stream_handler['main']
		add_prompt(window, prompt_text, cmd)
	end
	command_window.deleteln
	command_window.setpos(0,0)
	command_window.noutrefresh
	Curses.doupdate
	command_history_pos = 0
	# Remember all digit commands because they are likely spells for voodoo.lic
	if (cmd.length >= min_cmd_length_for_history || cmd.digits?) and (cmd != command_history[1])
		if command_history[0].nil? or command_history[0].empty?
			command_history[0] = cmd
		else
			command_history.unshift cmd
		end
		command_history.unshift String.new
	end
	if cmd =~ /^\.quit/
		exit
	elsif cmd =~ /^\.key/i
		window = stream_handler['main']
		window.add_string("* ")
		window.add_string("* Waiting for key press...")
		command_window.noutrefresh
		Curses.doupdate
		window.add_string("* Detected keycode: #{command_window.getch.to_s}")
		window.add_string("* ")
		Curses.doupdate
	elsif cmd =~ /^\.copy/
		# fixme
	elsif cmd =~ /^\.fixcolor/i
		if CUSTOM_COLORS
			COLOR_ID_LOOKUP.each { |code,id|
				Curses.init_color(id, ((code[0..1].to_s.hex/255.0)*1000).round, ((code[2..3].to_s.hex/255.0)*1000).round, ((code[4..5].to_s.hex/255.0)*1000).round)
			}
		end
	elsif cmd =~ /^\.resync/i
		skip_server_time_offset = false
	elsif cmd =~ /^\.reload/i
		load_settings_file.call(true)
	elsif cmd =~ /^\.layout\s+(.+)/
		load_layout.call($1)
		key_action['resize'].call
	elsif cmd =~ /^\.arrow/i
		key_action['switch_arrow_mode'].call
	elsif cmd =~ /^\.e (.*)/
		eval(cmd.sub(/^\.e /, ''))
	else
		server.puts cmd.sub(/^\./, ';')
	end
}

key_action['send_last_command'] = proc {
	if cmd = command_history[1]
		if window = stream_handler['main']
			add_prompt(window, prompt_text, cmd)
			#window.add_string(">#{cmd}", [ h={ :start => 0, :end => (cmd.length + 1), :fg => '555555' } ])
			command_window.noutrefresh
			Curses.doupdate
		end
		if cmd =~ /^\.quit/i
			exit
		elsif cmd =~ /^\.fixcolor/i
			if CUSTOM_COLORS
				COLOR_ID_LOOKUP.each { |code,id|
					Curses.init_color(id, ((code[0..1].to_s.hex/255.0)*1000).round, ((code[2..3].to_s.hex/255.0)*1000).round, ((code[4..5].to_s.hex/255.0)*1000).round)
				}
			end
		elsif cmd =~ /^\.resync/i
			skip_server_time_offset = false
		elsif cmd =~ /^\.arrow/i
			key_action['switch_arrow_mode'].call
		elsif cmd =~ /^\.e (.*)/
			eval(cmd.sub(/^\.e /, ''))
		else
			server.puts cmd.sub(/^\./, ';')
		end
	end
}

key_action['send_second_last_command'] = proc {
	if cmd = command_history[2]
		if window = stream_handler['main']
			add_prompt(window, prompt_text, cmd)
			#window.add_string(">#{cmd}", [ h={ :start => 0, :end => (cmd.length + 1), :fg => '555555' } ])
			command_window.noutrefresh
			Curses.doupdate
		end
		if cmd =~ /^\.quit/i
			exit
		elsif cmd =~ /^\.fixcolor/i
			if CUSTOM_COLORS
				COLOR_ID_LOOKUP.each { |code,id|
					Curses.init_color(id, ((code[0..1].to_s.hex/255.0)*1000).round, ((code[2..3].to_s.hex/255.0)*1000).round, ((code[4..5].to_s.hex/255.0)*1000).round)
				}
			end
		elsif cmd =~ /^\.resync/i
			skip_server_time_offset = false
		elsif cmd =~ /^\.arrow/i
			key_action['switch_arrow_mode'].call
		elsif cmd =~ /^\.e (.*)/
			eval(cmd.sub(/^\.e /, ''))
		else
			server.puts cmd.sub(/^\./, ';')
		end
	end
}

new_stun = proc { |seconds|
	if window = countdown_handler['stunned']
		temp_stun_end = Time.now.to_f - $server_time_offset.to_f + seconds.to_f
		window.end_time = temp_stun_end
		window.update
		need_update = true
		Thread.new {
			while (countdown_handler['stunned'].end_time == temp_stun_end) and (countdown_handler['stunned'].value > 0)
				sleep 0.15
				if countdown_handler['stunned'].update
					command_window.noutrefresh
					Curses.doupdate
				end
			end
		}
	end
}

load_settings_file.call(false)
load_layout.call('default')

TextWindow.list.each { |w| w.maxy.times { w.add_string "\n" } }

server = TCPSocket.open('127.0.0.1', PORT)

Thread.new { sleep 15; skip_server_time_offset = false }

Thread.new {
	begin
		line = nil
		need_update = false
		line_colors = Array.new
		open_monsterbold = Array.new
		open_preset = Array.new
		open_style = nil
		open_color = Array.new
		current_stream = nil

		handle_game_text = proc { |text|

			for escapable in xml_escape_list.keys
				search_pos = 0
				while (pos = text.index(escapable, search_pos))
					text = text.sub(escapable, xml_escape_list[escapable])
					line_colors.each { |h|
						h[:start] -= (escapable.length - 1) if h[:start] > pos
						h[:end] -= (escapable.length - 1) if h[:end] > pos
					}
					if open_style and (open_style[:start] > pos)
						open_style[:start] -= (escapable.length - 1)
					end
				end
			end

			if text =~ /^\[.*?\]>/
				need_prompt = false
			elsif text =~ /^\s*You are stunned for ([0-9]+) rounds?/
				new_stun.call($1.to_i * 5)
			elsif text =~ /^Deep and resonating, you feel the chant that falls from your lips instill within you with the strength of your faith\.  You crouch beside [A-Z][a-z]+ and gently lift (?:he|she|him|her) into your arms, your muscles swelling with the power of your deity, and cradle (?:him|her) close to your chest\.  Strength and life momentarily seep from your limbs, causing them to feel laden and heavy, and you are overcome with a sudden weakness\.  With a sigh, you are able to lay [A-Z][a-z]+ back down\.$|^Moisture beads upon your skin and you feel your eyes cloud over with the darkness of a rising storm\.  Power builds upon the air and when you utter the last syllable of your spell thunder rumbles from your lips\.  The sound ripples upon the air, and colling with [A-Z][a-z&apos;]+ prone form and a brilliant flash transfers the spiritual energy between you\.$|^Lifting your finger, you begin to chant and draw a series of conjoined circles in the air\.  Each circle turns to mist and takes on a different hue - white, blue, black, red, and green\.  As the last ring is completed, you spread your fingers and gently allow your tips to touch each color before pushing the misty creation towards [A-Z][a-z]+\.  A shock of energy courses through your body as the mist seeps into [A-Z][a-z&apos;]+ chest and life is slowly returned to (?:his|her) body\.$|^Crouching beside the prone form of [A-Z][a-z]+, you softly issue the last syllable of your chant\.  Breathing deeply, you take in the scents around you and let the feel of your surroundings infuse you\.  With only your gaze, you track the area and recreate the circumstances of [A-Z][a-z&apos;]+ within your mind\.  Touching [A-Z][a-z]+, you follow the lines of the web that holds (?:his|her) soul in place and force it back into (?:his|her) body\.  Raw energy courses through you and you feel your sense of justice and vengeance filling [A-Z][a-z]+ with life\.$|^Murmuring softly, you call upon your connection with the Destroyer,? and feel your words twist into an alien, spidery chant\.  Dark shadows laced with crimson swirl before your eyes and at your forceful command sink into the chest of [A-Z][a-z]+\.  The transference of energy is swift and immediate as you bind [A-Z][a-z]+ back into (?:his|her) body\.$|^Rich and lively, the scent of wild flowers suddenly fills the air as you finish your chant, and you feel alive with the energy of spring\.  With renewal at your fingertips, you gently touch [A-Z][a-z]+ on the brow and revel in the sweet rush of energy that passes through you into (?:him|her|his)\.$|^Breathing slowly, you extend your senses towards the world around you and draw into you the very essence of nature\.  You shift your gaze towards [A-z][a-z]+ and carefully release the energy you&apos;ve drawn into yourself towards (?:him|her)\.  A rush of energy briefly flows between the two of you as you feel life slowly return to (?:him|her)\.$|^Your surroundings grow dim\.\.\.you lapse into a state of awareness only, unable to do anything\.\.\.$|^Murmuring softly, a mournful chant slips from your lips and you feel welts appear upon your wrists\.  Dipping them briefly, you smear the crimson liquid the leaks from these sudden wounds in a thin line down [A-Z][a-z&apos;]+ face\.  Tingling with each second that your skin touches (?:his|hers), you feel the transference of your raw energy pass into [A-Z][a-z]+ and momentarily reel with the pain of its release\.  Slowly, the wounds on your wrists heal, though a lingering throb remains\.$|^Emptying all breathe from your body, you slowly still yourself and close your eyes\.  You reach out with all of your senses and feel a film shift across your vision\.  Opening your eyes, you gaze through a white haze and find images of [A-Z][a-z]+ floating above his prone form\.  Acts of [A-Z][a-z]&apos;s? past, present, and future play out before your clouded vision\.  With conviction and faith, you pluck a future image of [A-Z][a-z]+ from the air and coax (?:he|she|his|her) back into (?:he|she|his|her) body\.  Slowly, the film slips from your eyes and images fade away\.$|^Thin at first, a fine layer of rime tickles your hands and fingertips\.  The hoarfrost smoothly glides between you and [A-Z][a-z]+, turning to a light powder as it traverses the space\.  The white substance clings to [A-Z][a-z]+&apos;s? eyelashes and cheeks for a moment before it becomes charged with spiritual power, then it slowly melts away\.$|^As you begin to chant,? you notice the scent of dry, dusty parchment and feel a cool mist cling to your skin somewhere near your feet\.  You sense the ethereal tendrils of the mist as they coil about your body and notice that the world turns to a yellowish hue as the mist settles about your head\.  Focusing on [A-Z][a-z]+, you feel the transfer of energy pass between you as you return (?:him|her) to life\.$|^Wrapped in an aura of chill, you close your eyes and softly begin to chant\.  As the cold air that surrounds you condenses you feel it slowly ripple outward in waves that turn the breath of those nearby into a fine mist\.  This mist swiftly moves to encompass you and you feel a pair of wings arc over your back\.  With the last words of your chant, you open your eyes and watch as foggy wings rise above you and gently brush against [A-Z][a-z]+\.  As they dissipate in a cold rush against [A-Z][a-z]+, you feel a surge of power spill forth from you and into (?:him|her)\.$|^As .*? begins to chant, your spirit is drawn closer to your body by the scent of dusty, dry parchment\.  Topaz tendrils coil about .*?, and you feel an ancient presence demand that you return to your body\.  All at once .*? focuses upon you and you feel a surge of energy bind you back into your now-living body\.$/
				# raise dead stun
				new_stun.call(30.6)
			elsif text =~ /^Just as you think the falling will never end, you crash through an ethereal barrier which bursts into a dazzling kaleidoscope of color!  Your sensation of falling turns to dizziness and you feel unusually heavy for a moment\.  Everything seems to stop for a prolonged second and then WHUMP!!!/
				# Shadow Valley exit stun
				new_stun.call(16.2)
			elsif text =~ /^You have.*?(?:case of uncontrollable convulsions|case of sporadic convulsions|strange case of muscle twitching)/
				# nsys wound will be correctly set by xml, dont set the scar using health verb output
				skip_nsys = true
			else
				if skip_nsys
					skip_nsys = false
				elsif window = indicator_handler['nsys']
					if text =~ /^You have.*? very difficult time with muscle control/
						if window.update(3)
							need_update = true
						end
					elsif text =~ /^You have.*? constant muscle spasms/
						if window.update(2)
							need_update = true
						end
					elsif text =~ /^You have.*? developed slurred speech/
						if window.update(1)
							need_update = true
						end
					end
				end
			end

			if open_style
				h = open_style.dup
				h[:end] = text.length
				line_colors.push(h)
				open_style[:start] = 0
			end
			for oc in open_color
				ocd = oc.dup
				ocd[:end] = text.length
				line_colors.push(ocd)
				oc[:start] = 0
			end

			if current_stream.nil? or stream_handler[current_stream] or (current_stream =~ /^(?:death|logons|thoughts|voln|familiar)$/)
				SETTINGS_LOCK.synchronize {
					HIGHLIGHT.each_pair { |regex,colors|
						pos = 0
						while (match_data = text.match(regex, pos))
							h = {
								:start => match_data.begin(0),
								:end => match_data.end(0),
								:fg => colors[0],
								:bg => colors[1],
								:ul => colors[2]
							}
							line_colors.push(h)
							pos = match_data.end(0)
						end
					}
				}
			end

			unless text.empty?
				if current_stream
					if current_stream == 'thoughts'
						if text =~ /^\[.+?\]\-[A-z]+\:[A-Z][a-z]+\: "|^\[server\]\: /
							current_stream = 'lnet'
						end
					end
					if window = stream_handler[current_stream]
						if current_stream == 'death'
							# fixme: has been vaporized!
							# fixme: ~ off to a rough start
							if text =~ /^\s\*\s(The death cry of )?([A-Z][a-z]+) (?:just bit the dust!|echoes in your mind!)/
								front_count = 3
								front_count += 17 if $1
								name = $2
								text = "#{name} #{Time.now.strftime('%l:%M%P').sub(/^0/, '')}"
								line_colors.each { |h|
									h[:start] -= front_count
									h[:end] = [ h[:end], name.length ].min
								}
								line_colors.delete_if { |h| h[:start] >= h[:end] }
								h = {
									:start => (name.length+1),
									:end => text.length,
									:fg => 'ff0000',
								}
								line_colors.push(h)
							end
						elsif current_stream == 'logons'
							foo = { 'joins the adventure.' => '007700', 'returns home from a hard day of adventuring.' => '777700', 'has disconnected.' => 'aa7733' }
							if text =~ /^\s\*\s([A-Z][a-z]+) (#{foo.keys.join('|')})/
								name = $1
								logon_type = $2
								text = "#{name} #{Time.now.strftime('%l:%M%P').sub(/^0/, '')}"
								line_colors.each { |h|
									h[:start] -= 3
									h[:end] = [ h[:end], name.length ].min
								}
								line_colors.delete_if { |h| h[:start] >= h[:end] }
								h = {
									:start => (name.length+1),
									:end => text.length,
									:fg => foo[logon_type],
								}
								line_colors.push(h)
							end
						end
						unless text =~ /^\[server\]: "(?:kill|connect)/
							window.add_string(text, line_colors)
							need_update = true
						end
					elsif current_stream =~ /^(?:death|logons|thoughts|voln|familiar)$/
						if window = stream_handler['main']
							if PRESET[current_stream]
								line_colors.push(:start => 0, :fg => PRESET[current_stream][0], :bg => PRESET[current_stream][1], :end => text.length)
							end
							unless text.empty?
								if need_prompt
									need_prompt = false
									add_prompt(window, prompt_text)
								end
								window.add_string(text, line_colors)
								need_update = true
							end
						end
					else
						# stream_handler['main'].add_string "#{current_stream}: #{text.inspect}"
					end
				else
					if window = stream_handler['main']
						if need_prompt
							need_prompt = false
							add_prompt(window, prompt_text)
						end
						window.add_string(text, line_colors)
						need_update = true
					end
				end
			end
			line_colors = Array.new
			open_monsterbold.clear
			open_preset.clear
			# open_color.clear
		}

		while (line = server.gets)
			line.chomp!
			if line.empty?
				if current_stream.nil?
					if need_prompt
						need_prompt = false
						add_prompt(stream_handler['main'], prompt_text)
					end
					stream_handler['main'].add_string String.new
					need_update = true
				end
			else
				while (start_pos = (line =~ /(<(prompt|spell|right|left|inv|compass).*?\2>|<.*?>)/))
					xml = $1
					line.slice!(start_pos, xml.length)
					if xml =~ /^<prompt time=('|")([0-9]+)\1.*?>(.*?)&gt;<\/prompt>$/
						unless skip_server_time_offset
							$server_time_offset = Time.now.to_f - $2.to_f
							skip_server_time_offset = true
						end
						new_prompt_text = "#{$3}>"
						if prompt_text != new_prompt_text
							need_prompt = false
							prompt_text = new_prompt_text
							add_prompt(stream_handler['main'], new_prompt_text)
							if prompt_window = indicator_handler["prompt"]
								init_prompt_height, init_prompt_width = fix_layout_number.call(prompt_window.layout[0]), fix_layout_number.call(prompt_window.layout[1])
								new_prompt_width = new_prompt_text.length
								prompt_window.resize(init_prompt_height, new_prompt_width)
								prompt_width_diff = new_prompt_width - init_prompt_width
								command_window.resize(fix_layout_number.call(command_window_layout[0]), fix_layout_number.call(command_window_layout[1]) - prompt_width_diff)
								ctop, cleft = fix_layout_number.call(command_window_layout[2]), fix_layout_number.call(command_window_layout[3]) + prompt_width_diff
								command_window.move(ctop, cleft)
								prompt_window.label = new_prompt_text
							end
						else
							need_prompt = true
						end
					elsif xml =~ /^<spell(?:>|\s.*?>)(.*?)<\/spell>$/
						if window = indicator_handler['spell']
							window.clear
							window.label = $1
							window.update($1 == 'None' ? 0 : 1)
							need_update = true
						end
					elsif xml =~ /^<(right|left)(?:>|\s.*?>).*?(\S*?)<\/\1>/
						if window = indicator_handler[$1]
							window.clear
							window.label = $2
							window.update($2 == 'Empty' ? 0 : 1)
							need_update = true
						end
					elsif xml =~ /^<roundTime value=('|")([0-9]+)\1/
						if window = countdown_handler['roundtime']
							temp_roundtime_end = $2.to_i
							window.end_time = temp_roundtime_end
							window.update
							need_update = true
							Thread.new {
								sleep 0.15
								while (countdown_handler['roundtime'].end_time == temp_roundtime_end) and (countdown_handler['roundtime'].value > 0)
									sleep 0.15
									if countdown_handler['roundtime'].update
										command_window.noutrefresh
										Curses.doupdate
									end
								end
							}
						end
					elsif xml =~ /^<castTime value=('|")([0-9]+)\1/
						if window = countdown_handler['roundtime']
							temp_casttime_end = $2.to_i
							window.secondary_end_time = temp_casttime_end
							window.update
							need_update = true
							Thread.new {
								while (countdown_handler['roundtime'].secondary_end_time == temp_casttime_end) and (countdown_handler['roundtime'].secondary_value > 0)
									sleep 0.15
									if countdown_handler['roundtime'].update
										command_window.noutrefresh
										Curses.doupdate
									end
								end
							}
						end
					elsif xml =~ /^<compass/
						current_dirs = xml.scan(/<dir value="(.*?)"/).flatten
						for dir in [ 'up', 'down', 'out', 'n', 'ne', 'e', 'se', 's', 'sw', 'w', 'nw' ]
							if window = indicator_handler["compass:#{dir}"]
								if window.update(current_dirs.include?(dir))
									need_update = true
								end
							end
						end
					elsif xml =~ /^<progressBar id='(.*?)' value='[0-9]+' text='\1 (\-?[0-9]+)\/([0-9]+)'/
						if window = progress_handler[$1]
							if window.update($2.to_i, $3.to_i)
								need_update = true
							end
						end
					elsif xml =~ /^<progressBar id='encumlevel' value='([0-9]+)' text='(.*?)'/
						if window = progress_handler['encumbrance']
							if $2 == 'Overloaded'
								value = 110
							else
								value = $1.to_i
							end
							if window.update(value, 110)
								need_update = true
							end
						end
					elsif xml =~ /^<progressBar id='pbarStance' value='([0-9]+)'/
						if window = progress_handler['stance']
							if window.update($1.to_i, 100)
								need_update = true
							end
						end
					elsif xml =~ /^<progressBar id='mindState' value='(.*?)' text='(.*?)'/
						if window = progress_handler['mind']
							if $2 == 'saturated'
								value = 110
							else
								value = $1.to_i
							end
							if window.update(value, 110)
								need_update = true
							end
						end
					elsif xml == '<pushBold/>' or xml == '<b>'
						h = { :start => start_pos }
						if PRESET['monsterbold']
							h[:fg] = PRESET['monsterbold'][0]
							h[:bg] = PRESET['monsterbold'][1]
						end
						open_monsterbold.push(h)
					elsif xml == '<popBold/>' or xml == '</b>'
						if h = open_monsterbold.pop
							h[:end] = start_pos
							line_colors.push(h) if h[:fg] or h[:bg]
						end
					elsif xml =~ /^<preset id=('|")(.*?)\1>$/
						h = { :start => start_pos }
						if PRESET[$2]
							h[:fg] = PRESET[$2][0]
							h[:bg] = PRESET[$2][1]
						end
						open_preset.push(h)
					elsif xml == '</preset>'
						if h = open_preset.pop
							h[:end] = start_pos
							line_colors.push(h) if h[:fg] or h[:bg]
						end
					elsif xml =~ /^<color/
						h = { :start => start_pos }
						if xml =~ /\sfg=('|")(.*?)\1[\s>]/
							h[:fg] = $2.downcase
						end
						if xml =~ /\sbg=('|")(.*?)\1[\s>]/
							h[:bg] = $2.downcase
						end
						if xml =~ /\sul=('|")(.*?)\1[\s>]/
							h[:ul] = $2.downcase
						end
						open_color.push(h)
					elsif xml == '</color>'
						if h = open_color.pop
							h[:end] = start_pos
							line_colors.push(h)
						end
					elsif xml =~ /^<style id=('|")(.*?)\1/
						if $2.empty?
							if open_style
								open_style[:end] = start_pos
								if (open_style[:start] < open_style[:end]) and (open_style[:fg] or open_style[:bg])
									line_colors.push(open_style)
								end
								open_style = nil
							end
						else
							open_style = { :start => start_pos }
							if PRESET[$2]
								open_style[:fg] = PRESET[$2][0]
								open_style[:bg] = PRESET[$2][1]
							end
						end
					elsif xml =~ /^<(?:pushStream|component) id=("|')(.*?)\1[^>]*\/?>$/
						new_stream = $2
						game_text = line.slice!(0, start_pos)
						handle_game_text.call(game_text)
						current_stream = new_stream
					elsif xml =~ /^<popStream/ or xml == '</component>'
						game_text = line.slice!(0, start_pos)
						handle_game_text.call(game_text)
						current_stream = nil
					elsif xml =~ /^<progressBar/
						nil
					elsif xml =~ /^<(?:dialogdata|a|\/a|d|\/d|\/?component|label|skin|output)/
						nil
					elsif xml =~ /^<indicator id=('|")Icon([A-Z]+)\1 visible=('|")([yn])\3/
						if window = countdown_handler[$2.downcase]
							window.active = ($4 == 'y')
							if window.update
								need_update = true
							end
						end
						if window = indicator_handler[$2.downcase]
							if window.update($4 == 'y')
								need_update = true
							end
						end
					elsif xml =~ /^<image id=('|")(back|leftHand|rightHand|head|rightArm|abdomen|leftEye|leftArm|chest|rightLeg|neck|leftLeg|nsys|rightEye)\1 name=('|")(.*?)\3/
						if $2 == 'nsys'
							if window = indicator_handler['nsys']
								if rank = $4.slice(/[0-9]/)
									if window.update(rank.to_i)
										need_update = true
									end
								else
									if window.update(0)
										need_update = true
									end
								end
							end
						else
							fix_value = { 'Injury1' => 1, 'Injury2' => 2, 'Injury3' => 3, 'Scar1' => 4, 'Scar2' => 5, 'Scar3' => 6 }
							if window = indicator_handler[$2]
								if window.update(fix_value[$4] || 0)
									need_update = true
								end
							end
						end
					elsif xml =~ /^<LaunchURL src="([^"]+)"/
						url = "\"https://www.play.net#{$1}\""
						# assume linux if not mac
						cmd = RUBY_PLATFORM =~ /darwin/ ? "open" : "firefox"
						system("#{cmd} #{url}")
					else
						nil
					end
				end
				handle_game_text.call(line)
			end
			#
			# delay screen update if there are more game lines waiting
			#
			if need_update and not IO.select([server], nil, nil, 0.01)
				need_update = false
				command_window.noutrefresh
				Curses.doupdate
			end
		end
		stream_handler['main'].add_string ' *'
		stream_handler['main'].add_string ' * Connection closed'
		stream_handler['main'].add_string ' *'
		command_window.noutrefresh
		Curses.doupdate
	rescue
		File.open('profanity.log', 'a') { |f| f.puts $!; f.puts $!.backtrace[0...4] }
		exit
	end
}

begin
	key_combo = nil
	loop {
		ch = command_window.getch
		if key_combo
			if key_combo[ch].class == Proc
				key_combo[ch].call
				key_combo = nil
			elsif key_combo[ch].class == Hash
				key_combo = key_combo[ch]
			else
				key_combo = nil
			end
		elsif key_binding[ch].class == Proc
			key_binding[ch].call
		elsif key_binding[ch].class == Hash
			key_combo = key_binding[ch]
		elsif ch.class == String
			command_window_put_ch.call(ch)
			command_window.noutrefresh
			Curses.doupdate
		end
	}
rescue
	File.open('profanity.log', 'a') { |f| f.puts $!; f.puts $!.backtrace[0...4] }
ensure
	server.close rescue()
	Curses.close_screen
end
