module Opts
  FLAG_PREFIX    = "--"
  
  def self.parse_command(h, c)
    h[c.to_sym] = true
  end

  def self.parse_flag(h, f)
    (name, val) = f[2..-1].split("=")
    if val.nil?
      h[name.to_sym] = true
    else
      val = val.split(",")

      h[name.to_sym] = val.size == 1 ? val.first : val
    end
  end

  def self.parse(args = ARGV)    
    config = OpenStruct.new  
		if args.size > 0
			config = OpenStruct.new(**args.reduce(Hash.new) do |h, v|
				if v.start_with?(FLAG_PREFIX)
					parse_flag(h, v)
				else
					parse_command(h, v)
				end
				h
			end)
		end
    config
	end
	
	PARSED = parse()

  def self.method_missing(method, *args)
    PARSED.send(method, *args)
  end
end