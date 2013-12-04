require 'readline'
require './eval'
require './client'
require './commands'

cli = Client.new *ARGV

Readline.completion_proc = lambda do |word|
  result = []
  orgword = word
  word ||= ""
  scan = word.scan %r{(.*/)([^/]*)}
  if scan.nil? or scan.empty?
    orgprefix, orgsuffix = "", word
  else
    orgprefix, orgsuffix = scan.first
  end
  orgprefix ||= ""
  orgsuffix ||= ""
  word = nil if word.empty?
  begin
    Commands::Ls.new(nil).run(cli, word) { |r| result << r }
  rescue Errno::ENOENT
    if word.end_with? '/'
      word.sub(%r{/$}, '')
    elsif word['/']
      word = word.sub(%r{/[^/]*$}, '/')
      retry
    else
      word = nil
      retry
    end
  end
  result.map(&:first).select{|x| orgword.nil? or x.start_with?(orgsuffix)}.map{|x| orgprefix + x}
end

def sysexec(d)
  old = `stty -g`
  child = fork do
    cli = Client.new *ARGV
    cli.call! Syscalls::NR_dup2, 3, 0
    cli.call! Syscalls::NR_dup2, 3, 1
    cli.call! Syscalls::NR_dup2, 3, 2
    fd = cli.execve "/bin/sh", ["sh", "-c", d]
    system "stty -icanon min 1 time 0 -echo"
    rs = [fd]
    while not fd.eof?
      fd.close_write if STDIN.eof?
      p rs
      if rs.include? STDIN
	buf = STDIN.readpartial(512)
	fd << buf
      elsif rs.include? fd
	buf = fd.readpartial(512)
	STDOUT << buf
      end
      rs, ws, es = IO.select([fd, STDIN], [], [fd], 1)
      break unless es.empty?
    end
  end
  Process.wait child
  system "stty #{old}"
end

ev = Eval.new cli
puts "Server (version = #{cli.version}) is ready."
while d = Readline.readline("(#{cli.pid})> ")
  d.strip!
  next if d.empty?
  Readline::HISTORY.push d
  begin
    ev.run d
  rescue ArgumentError => e
    STDERR << e << "\n"
  rescue KeyError
    STDERR << "Bad command or file name" << "\n"
  end
end
