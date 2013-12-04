require 'socket'
require './syscalls'

class Client
  attr_reader :pid, :version
  attr_reader :host, :port
  attr_reader :s

  include Syscalls
  def initialize(host = 'localhost', port = 32000, lazy = false)
    @host = host
    @port = port
    @lazy = lazy
    connect(@host, @port) unless @lazy
  end

  def disconnect
    @s.close
    @s = nil
  end

  def connect(host, port)
    disconnect if @s
    @s = TCPSocket.new host, port
    @version = @s.read(16).unpack("H32")
    @pid = self.call! Syscalls::NR_getpid
  end

  def pack(snr, *args)
    raise ArgumentError, "too many arguments" if args.size > 6
    data = [snr] + args
    data << 0 until data.size == 7
    data.pack("q7")
  end

  def [](snr, *args)
    connect(@host, @port) unless @s
    @s.write self.pack(snr, *args)
    data = @s.read(8)
    return nil if data.nil?
    data.unpack("q").first
  end

  def call!(snr, *args)
    result = self[snr, *args]
    if result.nil?
      raise IOError.new "Connection lost"
    end
    if (-255 ... 0) === result
      raise SystemCallError.new(-result)
    else
      result
    end
  end

  def scratch(s=nil)
    scratch! unless @scratch
    return @scratch if s.nil?
    @s << self.pack(NR_read, 3, @scratch, s.bytesize)
    @s << s
    @s.read(8).unpack("q").first
    @scratch
  end

  def readptr(p, b=Syscalls::PAGE_SIZE)
    @s << self.pack(NR_write, 3, p, b)
    data = @s.read(b)
    @s.read(8).unpack("q").first
    data
  end

  def write(buf)
    raise RuntimeError unless @scratch
    buf.bytes.each_slice(Syscalls::PAGE_SIZE) do |bb|
      b = bb.pack("C*")
      @s << self.pack(NR_read, 3, @scratch, b.size)
      data = @s.write(b)
      b = @s.read(8).unpack("q").first
      raise SystemCallError.new(-b) if (-255 ... 0) === b
      yield b if block_given?
    end
  end

  def read(b=Syscalls::PAGE_SIZE)
    raise RuntimeError unless @scratch
    @s << self.pack(NR_write, 3, @scratch, b)
    data = @s.read(b)
    @s.read(8).unpack("q").first
    data
  end

  def execve(filename, argv=nil, envp=[])
    argv ||= [filename, nil]
    scratch! unless @scratch
    p_filename = scratch
    s = ""
    s.force_encoding Encoding::BINARY
    s += filename 
    s += "\0"
    ep = s.size
    p_argv = scratch + s.size
    s += [0].pack("q") * (argv.size + 1)
    p_envp = scratch + s.size
    s += [0].pack("q") * (envp.size + 1)
    argv.each do |x|
      s[ep,8] = [scratch + s.size].pack("q")
      ep += 8
      s += x
      s += "\0"
    end
    ep += 8
    envp.each do |x|
      s[ep,8] = [scratch + s.size].pack("q")
      ep += 8
      s += x
      s += "\0"
    end
    s += argv.map{|x| x + "\0"}.join
    s += envp.map{|x| x + "\0"}.join
    scratch(s)

    @s.write self.pack(Syscalls::NR_execve, p_filename, p_argv, p_envp)
    @s
  end

  def scratch!
    @scratch = self[NR_mmap, 0, Syscalls::PAGE_SIZE, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, 0, 0]
    raise RuntimeError, "Unable to allocate scratch page" if (-1 .. -255) === @scratch
  end

  def open_with(filename, mode=Syscalls::O_RDONLY)
    raise ArgumentError, "no block given" unless block_given?
    fd = call! Syscalls::NR_open, scratch(filename + "\0"), mode
    yield fd
  ensure
    call! Syscalls::NR_close, fd if fd
  end
end

