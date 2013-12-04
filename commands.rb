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

  class Pwd < Command
    def manifest
      [:name]
    end

    def run(cli)
      cli.call! Syscalls::NR_getcwd, cli.scratch, Syscalls::PAGE_SIZE
      yield [cli.read.split("\0").first]
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
	  lastbyte = rest.bytes[-1]
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
      @n = n
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
	  lastbyte = rest.bytes[-1]
	  d_name = rest.sub /\x00.*/m, ''
	  d_name.force_encoding Encoding::UTF_8
	  yield [d_name.to_i] if d_name =~ /\A\d+\Z/ and lastbyte == 4
	end
      end
      cli.call! Syscalls::NR_close, fd
    end
  end

  class Pstat < Command
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
      fetchall do |pid,cdr|
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
	               "%u %u %d %*s " \
		       "%*s %*s %*s %*s %*s " \
		       "%lu %lu " \
		       "%*s %*s %*s " \
		       "%ld " \
		       "%*s %*s " \
		       "%lu " \
		       "%lu " \
		       "%lu " \
		       "%*s %*s %*s %*s %*s %*s " \
		       "%*s %*s %*s %*s " \
		       "%*s %*s %*s %*s " \
		       "%d")
	    yield [pid.to_i, comm, state, ppid , \
	      pgid, sid, tty, tpgid , \
	      flags, min_flt, cmin_flt, maj_flt, cmaj_flt , \
	      utime, stime , \
	      cutime, cstime, priority , \
	      nice , \
	      timeout, it_real_value , \
	      start_time , \
	      vsize , \
	      rss , \
	      rss_rlim, start_code, end_code, start_stack, kstk_esp, kstk_eip , \
	      signal, blocked, sigignore, sigcatch , \
	      wchan, nswap, cnswap, exit_signal , \
	      cpu_last_seen_on]
	  end
	rescue Errno::ENOENT
	  nil
	end
      end
    end
  end
end

