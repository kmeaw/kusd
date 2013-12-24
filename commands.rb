require 'stringio'
require 'scanf'

class Command
  attr_accessor :in

  def initialize(t)
    @parent_manifest = t
  end

  def fetch
    return unless @in
    Marshal.load(@in)
  end

  def eof?
    @in.eof?
  end

  def fetchall
    return unless @in
    if block_given?
      yield fetch until @in.eof?
    else
      data = []

      until @in.eof?
	data << fetch
      end

      data
    end
  end

  def manifest
    @parent_manifest
  end

  protected

  def parent_index(v)
    return v if v.is_a? Integer
    i = @parent_manifest.index(v.to_sym)
    if i
      i
    else
      raise ArgumentError, "Unknown field: #{v}"
    end
  end
end

module Commands
  class Cd < Command
    def manifest
      nil
    end

    def initialize(t, dir)
      super(t)
      @dir = dir
    end

    def run(cli)
      cli.call! Syscalls::NR_chdir, cli.scratch(@dir + "\0")
    end
  end

  class Uname < Command
    def manifest
      [:sysname, :nodename, :release, :version, :machine]
    end

    def run(cli)
      cli.call! Syscalls::NR_uname, cli.scratch, Syscalls::PAGE_SIZE
      yield cli.read((Syscalls::NEW_UTS_LEN + 1) * manifest.size).unpack("A#{Syscalls::NEW_UTS_LEN + 1}" * manifest.size)
    end
  end

  class Stat < Command
    FORMAT = "L!L!L!IIIIL!l!l!l!L!L!L!L!L!L!l!"
    # [:dev, :ino, :nlink, :mode, :uid, :gid, :pad0, :rdev, :size, :blksize, :blocks, :atime, :atime_nsec, :mtime, :mtime_nsec, :ctime, :ctime_nsec, :unused]
    def manifest
      [:dev, :ino, :nlink, :mode, :uid, :gid, :rdev, :size, :blksize, :blocks, :atime, :mtime, :ctime]
    end

    def initialize(t, *names)
      super(t)
      @names = names
    end

    def run(cli)
      @names.each do |name|
	cli.call! Syscalls::NR_stat, cli.scratch(name + "\0"), cli.scratch
	result = cli.read(128).unpack(FORMAT)
	result.delete_at -1 # :unused
	result.delete_at 6  # :pad0
	(-6..-1).step(2){|i| result[i] = Time.at(result[i] + result[i+1] * 1e-9)}
	result.delete_at -1 # :ctime_nsec
	result.delete_at -2 # :mtime_nsec
	result.delete_at -3 # :atime_nsec
	yield result
      end
    end
  end

  class Sort < Command
    def initialize(t, field=0)
      super(t)
      @field = parent_index(field)
    end

    def run(cli)
      data = fetchall
      data.sort_by! {|data| data[@field]}
      data.each{|data| yield data}
    end
  end

  class Select < Command
    def initialize(t, *fields)
      super(t)
      @fields = fields.map{|f| parent_index f}
    end

    def run(cli)
      fetchall {|data| yield @fields.map{|n| data[n]}}
    end

    def manifest
      @fields.map{|n| @parent_manifest[n]}
    end
  end

  class True < Command
    def run(cli)
    end

    def manifest
      nil
    end
  end

  class Grep < Command
    def initialize(t, car, *cdr)
      super(t)
      raise ArgumentError, "grep needs either one or even number of arguments" unless cdr.empty? or cdr.size.odd?
      if cdr.empty?
	@conditions = [[0, car]]
      else
	args = [car] + cdr
	@conditions = args.each_slice(2).map{|k,v| [parent_index(k), v]}
      end
    end

    def run(cli)
      fetchall { |data| yield data if @conditions.all?{|k,v| (data[k].to_s)[v]} }
    end
  end

  class Where < Command
    def initialize(t, condition)
      super(t)
      @condition = condition
    end

    def run(cli)
      v = nil
      b = binding
      fetchall do |data| 
	# Regexp.new( (["(.*)"]*data.size).join("\0") ) =~ data.join("\0") # fill $1..$n
	@parent_manifest.each_with_index{|k,i| v=data[i]; eval("#{k}=v", b)}
	yield data if eval(@condition, b)
      end
    end
  end

  class Pwd < Command
    def manifest
      [:name]
    end

    def run(cli)
      cli.call! Syscalls::NR_getcwd, cli.scratch, Syscalls::PAGE_SIZE
      yield [cli.read.split("\0").first]
    end
  end

  class Write < Command
    def manifest
      []
    end

    def initialize(t, data, *files)
      super(t)
      @data = data
      @files = files
    end

    def run(cli)
      fds = []
      @files.each do |f|
	buf = cli.scratch(f + "\000")
        fds << cli.call!( Syscalls::NR_open, buf, Syscalls::O_WRONLY | Syscalls::O_CREAT, 0666 )
      end

      cli.write(@data) do |nbytes|
	fds.each do |fd|
	  cli.call! Syscalls::NR_write, fd, cli.scratch, nbytes
	end
      end
    ensure
      fds.each { |fd| cli.call! Syscalls::NR_close, fd }
    end
  end

  class Tee < Command
    def manifest
      [:data]
    end

    def initialize(t, *files)
      super(t)
      @files = files
    end

    def run(cli)
      fds = []
      @files.each do |f|
	buf = cli.scratch(f + "\000")
        fds << cli.call!( Syscalls::NR_open, buf, Syscalls::O_WRONLY | Syscalls::O_CREAT, 0666 )
      end

      fetchall do |data|
	buf = data.join
	cli.write(buf) do |nbytes|
	  fds.each do |fd|
	    cli.call! Syscalls::NR_write, fd, cli.scratch, nbytes
	  end
	end
	yield data
      end
    ensure
      fds.each { |fd| cli.call! Syscalls::NR_close, fd }
    end
  end

  class Cat < Command
    def manifest
      [:data]
    end

    def initialize(t, *files)
      super(t)
      @files = files
    end

    def run(cli)
      @files.each do |file|
	cli.open_with file do |fd|
	  while (n = cli.call! Syscalls::NR_read, fd, cli.scratch, Syscalls::PAGE_SIZE) > 0
	    yield [cli.read(n)]
	  end
	end
      end
    end
  end

  class Ls < Command
    def manifest
      [:name, :inode, :dtype]
    end

    def run(cli, dir=nil)
      dir ||= "."
      fd = cli.call! Syscalls::NR_open, cli.scratch(dir + "\000"), Syscalls::O_RDONLY
      while (n = cli.call! Syscalls::NR_getdents, fd, cli.scratch, Syscalls::PAGE_SIZE) > 0
	dents = StringIO.new cli.read(n)
	while data = dents.read(8+8+2)
	  data = data.unpack("qqs")
	  d_ino, d_off, d_reclen = data
	  break if d_reclen == 0
	  rest = dents.read(d_reclen-(8+8+2))
	  lastbyte = rest.bytes.to_a[-1]
	  d_name = rest.sub /\x00.*/m, ''
	  d_name.force_encoding Encoding::UTF_8
	  yield [d_name, d_ino, lastbyte]
	end
      end
      cli.call! Syscalls::NR_close, fd
    end
  end

  class Exit < Command
    def manifest
      nil
    end

    def initialize(t, n)
      super(t)
      @n = n.to_i
    end

    def run(cli)
      cli[Syscalls::NR_exit, @n]
    end
  end

  class Echo < Command
    def run(cli)
      fetchall { |d| yield d }
    end
  end

  class Print < Command
    def initialize(t, *args)
      super(t)
      @args = args
    end

    def manifest
      [:string] * @args.size
    end

    def run(cli)
      yield @args
    end
  end

  class Basename < Command
    def manifest
      [:string] * @names.size
    end

    def initialize(t, *names)
      super(t)
      @names = names
    end

    def run(cli)
      @names.each {|n| yield File.basename(n) }
    end
  end

  class Chown < Command
    def manifest
      nil
    end

    def initialize(t, uid, gid, *names)
      super(t)
      @uid = uid
      @gid = gid
      @names = names
    end

    def run(cli)
      @names.each {|n| cli.call! Syscalls::NR_chown, cli.scratch(n), @uid, @gid}
    end
  end

  class Chroot < Command
    def manifest
      nil
    end

    def initialize(t, dir)
      super(t)
      @dir = dir
    end

    def run(cli)
      cli.call! Syscalls::NR_chroot, cli.scratch(@dir)
    end
  end

  class Cmp < Command
    def manifest
      [:same, :diff]
    end

    def initialize(t, file1, file2)
      @file1 = file1
      @file2 = file2
    end

    def run(cli)
      cli.open_with @file1 do |f1|
	cli.open_with @file2 do |f2|
	  i = 0
	  while (a = cli.call! Syscalls::NR_read, fd1, cli.scratch, Syscalls::PAGE_SIZE / 2) > 0
	    break unless (b = cli.call! Syscalls::NR_read, fd2, cli.scratch + Syscalls::PAGE_SIZE / 2, Syscalls::PAGE_SIZE / 2) > 0
	    data = cli.read
	    aa = data[0,a].each_byte
	    bb = data[Syscalls::PAGE_SIZE/2,b].each_byte
	    begin
	      i += 1 while aa.next == bb.next
	    rescue StopIteration
	      return yield [false, i]
	    end
	  end

          return yield [false, i] unless a == b
	  yield [true, i]
	end
      end
    end
  end

  class Ps < Command
    def manifest
      [:pid]
    end

    def run(cli)
      dir = "/proc"
      fd = cli.call! Syscalls::NR_open, cli.scratch(dir + "\000"), Syscalls::O_RDONLY
      while (n = cli.call! Syscalls::NR_getdents, fd, cli.scratch, Syscalls::PAGE_SIZE) > 0
	dents = StringIO.new cli.read(n)
	while data = dents.read(8+8+2)
	  data = data.unpack("qqs")
	  d_ino, d_off, d_reclen = data
	  break if d_reclen == 0
	  rest = dents.read(d_reclen-(8+8+2))
	  lastbyte = rest.bytes.to_a[-1]
	  d_name = rest.sub /\x00.*/m, ''
	  d_name.force_encoding Encoding::UTF_8
	  yield [d_name.to_i] if d_name =~ /\A\d+\Z/ and lastbyte == 4
	end
      end
      cli.call! Syscalls::NR_close, fd
    end
  end

  class Pstat < Command
    def initialize(t, *pids)
      super(t)
      @pids = pids
    end

    def manifest
      [:pid, :comm, :state, :ppid, 
	      :pgid, :sid, :tty, :tpgid, 
	      :flags, :min_flt, :cmin_flt, :maj_flt, :cmaj_flt, 
	      :utime, :stime, 
	      :cutime, :cstime, :priority, 
	      :nice, 
	      :timeout, :it_real_value, 
	      :start_time, 
	      :vsize, 
	      :rss, 
	      :rss_rlim, :start_code, :end_code, :start_stack, :kstk_esp, :kstk_eip, 
	      :signal, :blocked, :sigignore, :sigcatch, 
	      :wchan, :nswap, :cnswap, :exit_signal, 
	      :cpu_last_seen_on]
    end

    def run(cli)
      @pids.each do |pid|
	begin
	  cli.open_with "/proc/#{pid}/stat" do |fd|
	    stat = ""
	    while (n = cli.call! Syscalls::NR_read, fd, cli.scratch, Syscalls::PAGE_SIZE) > 0
	      stat += cli.read(n)
	    end
	    pid, comm, rest = stat.scan(/(\d+) [(](.*)[)] (.*)/).first
	    state, ppid, 
	      pgid, sid, tty, tpgid, 
	      flags, min_flt, cmin_flt, maj_flt, cmaj_flt, 
	      utime, stime, 
	      cutime, cstime, priority, 
	      nice, 
	      timeout, it_real_value, 
	      start_time, 
	      vsize, 
	      rss, 
	      rss_rlim, start_code, end_code, start_stack, kstk_esp, kstk_eip, 
	      signal, blocked, sigignore, sigcatch, 
	      wchan, nswap, cnswap, exit_signal, 
	      cpu_last_seen_on = 
	    rest.scanf("%c %u " \
	               "%u %u %d %d " \
		       "%d %d %d %d %d " \
		       "%u %u " \
		       "%d %d %d " \
		       "%d " \
		       "%d %d " \
		       "%u " \
		       "%u " \
		       "%u " \
		       "%d %d %d %d %d %d " \
		       "%d %d %d %d " \
		       "%d %d %d %d " \
		       "%d")
	    yield [pid.to_i, comm, state, ppid, 
	      pgid, sid, tty, tpgid, 
	      flags, min_flt, cmin_flt, maj_flt, cmaj_flt, 
	      utime, stime, 
	      cutime, cstime, priority, 
	      nice, 
	      timeout, it_real_value, 
	      start_time, 
	      vsize, 
	      rss, 
	      rss_rlim, start_code, end_code, start_stack, kstk_esp, kstk_eip, 
	      signal, blocked, sigignore, sigcatch, 
	      wchan, nswap, cnswap, exit_signal, 
	      cpu_last_seen_on] if pid
	  end
	rescue Errno::ENOENT
	  nil
	end
      end
    end
  end

  class Head < Command
    def initialize(t, n=10)
      super(t)
      @n = n
    end

    def run(cli)
      c = 0
      return if @n.zero?
      fetchall do |d|
	yield d
	c += 1
	return if c >= @n
      end
    end
  end

  class Tail < Command
    def initialize(t, n=10)
      super(t)
      @n = n
    end

    def run(cli)
      data = []
      return if @n.zero?
      fetchall do |d|
	data << d
	data.shift if data.size > @n
      end
      data.each {|d| yield d}
    end
  end

  class Dmesg < Command
    def run(cli)
      sz = cli.call! Syscalls::NR_syslog, 10, 0, 0 rescue 262144
      sz += [0].pack("q").size
      sz1 = ( (((sz)) + Syscalls::PAGE_SIZE - 1) & (~(Syscalls::PAGE_SIZE - 1))) # round up to page size
      ptr = cli.call! Syscalls::NR_mmap, 0, sz1, Syscalls::PROT_READ | Syscalls::PROT_WRITE, Syscalls::MAP_PRIVATE | Syscalls::MAP_ANONYMOUS, -1, 0
      cli.call! Syscalls::NR_syslog, 3, ptr, sz
      buf = cli.readptr(ptr, sz).sub(/[\000]+\Z/, '')
      File.open("/tmp/dmesg", "w") {|f| f << buf }
      cli.call! Syscalls::NR_munmap, ptr, sz1
      buf.chomp.split("\n").each do |line|
	loglevel, time, message = line.scan(/^<(\d+)>(?:\[([0-9.]+)\]) (.*)$/).first
	yield [[:emerg, :alert, :crit, :err, :warning, :notice, :info, :debug][loglevel.to_i], time.to_f, message]
      end
    end

    def manifest
      [:loglevel, :time, :message]
    end
  end

  class Xargs < Command
    def initialize(t, cmd, *args)
      super(t)
      cmd = cmd.capitalize.to_sym
      raise KeyError unless Commands.constants.include? cmd
      @cmd = Commands.const_get cmd
      @args = args
      @instance = @cmd.new([:arg] * @args.size + (@parent_manifest || []), *(@args + [nil] * t.size))
    end

    def run(cli)
      fetchall { |d| @cmd.new([:arg] * @args.size + (@parent_manifest || []), *(@args + d)).run( cli ) { |e| yield e } }
    end

    def manifest
      @instance.manifest
    end
  end

  class Kill < Command
    def initialize(t, sig, pid)
      super(t)
      @pid = Integer(pid)
      @sig = (Signal.list[sig.upcase] or Integer(sig))
    end

    def run(cli)
      cli.call! Syscalls::NR_kill, @pid, @sig
      yield [@pid]
    end

    def manifest
      [:pid]
    end
  end
end

