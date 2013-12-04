require './bash'
require './commands'

class Eval
  def initialize(cli)
    @cli = cli
  end

  def go(stmt)
    if stmt[:type] == :exec
      cmd = stmt[:word].capitalize.to_sym
      raise KeyError unless Commands.constants.include? cmd
      cmd = Commands.const_get cmd
      arity = cmd.instance_method(:initialize).arity
      uarity = stmt[:arguments].size + 1
      unless arity == uarity or (arity < 0 and uarity + 1 >= -arity)
	if arity < 0
	  arity = "at least #{-(arity+2)}"
	else
	  arity = arity - 1
	end
	raise ArgumentError, "Invalid number of arguments: expecting #{arity} arguments"
      end

      cmd
    else
      raise NotImplementedError, "Unknown statement type: #{stmt[:type]}"
    end
  end

  def run(d)
    parsed = Bash.new.parse(d)
    rd, wr, cont = nil
    ischild = false
    manifest = nil

    parsed.each do |command|
      until command.empty?
	begin
	  async, stmt = command.shift
	  if stmt[:word] == ":"
	    stmt[:word] = "true"
	  end
	  cmd = go stmt
	  rd, wr, prevrd = *IO.pipe, rd
	  cont = fork
	  if cont
	    rd.close
	    begin
	      instance = cmd.new(manifest, *stmt[:arguments])
	      instance.in = prevrd
	      instance.run(@cli) do |out|
		Marshal.dump out, wr
	      end
	    rescue SystemCallError => e
	      STDERR << e.inspect << "\n"
	    end
	    wr.close
	    Process.wait cont
	    break
	  else
	    ischild = true
	    wr.close
	    manifest = cmd.new(manifest, *stmt[:arguments]).manifest
	    if command.empty?
	      p manifest
	      until rd.eof?
		p Marshal.load(rd)
	      end
	    else
	      @cli = Client.new @cli.host, @cli.port
	    end
	  end
	rescue Exception => e
	  if ischild
	    STDERR << e.inspect << "\n"
	    exit
	  else
	    raise
	  end
	end
      end # until
      exit if ischild
    end
  end
end

