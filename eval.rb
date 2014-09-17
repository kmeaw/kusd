require './bash'
require './commands'

class Eval
  def initialize(cli)
    @cli = cli
  end

  def go(stmt)
    if stmt[:type] == :exec
      raise NotImplementedError if stmt[:car][:type] != :lit
      cmd = stmt[:car][:value].capitalize.to_sym
      raise KeyError unless Commands.constants.include? cmd
      cmd = Commands.const_get cmd
      arity = cmd.instance_method(:initialize).arity
      uarity = stmt[:cdr].size + 1
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
    parser = Bash.new
    parser.load(d)
    rd, wr, cont = nil
    ischild = false
    manifest = nil

    parser.each do |command|
      if command[:type] == :pipe
	command = command[:values]
      elsif command[:type] == :exec
	command = [command]
      else
	raise NotImplementedError, "Unknown type: #{command[:type]}"
      end
      until command.empty?
	begin
	  stmt = command.shift
	  if stmt[:word] == ":"
	    stmt[:word] = "true"
	  end
	  cmd = go stmt
	  rd, wr, prevrd = *IO.pipe, rd
	  cont = fork
	  arguments = stmt[:cdr] ? stmt[:cdr].map{|x| x[:value]} : []
	  if cont
	    rd.close
	    begin
	      instance = cmd.new(manifest, *arguments)
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
	    manifest = cmd.new(manifest, *arguments).manifest
	    if command.empty?
	      if STDOUT.tty?
		print "\e[33m"
	        p manifest
		print "\e[0m"
	      end
	      until rd.eof?
		d = Marshal.load(rd)
		if manifest == [:data]
		  print d.join
		else
		  p d
		end
	      end
	      puts if manifest == [:data]
	    else
	      @cli = @cli.dup
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

