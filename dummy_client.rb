require './syscalls'
require 'fiddle'

class DummyClient
  attr_reader :pid, :version
  attr_reader :host, :port
  attr_reader :s

  include Syscalls
  def initialize
    @host = "localhost"
    @version = "dummy0"
    connect
  end

  def dup
    DummyClient.new
  end

  def disconnect
  end

  def connect(host=nil, port=nil)
    @pid = $$
  end

  def pack(snr, *args)
    raise ArgumentError, "too many arguments" if args.size > 6
    data = [snr] + args
    data << 0 until data.size == 7
    data.pack("q7")
  end

  def [](snr, *args)
    begin
      syscall snr, *args
    rescue SystemCallError => e
      0 - e.errno
    end
  end

  def call!(snr, *args)
    syscall snr, *args
  end

  def scratch(s=nil)
    scratch! unless @scratch
    return @scratch if s.nil?
    Fiddle::Pointer.new(@scratch)[0, s.bytesize] = s
    @scratch
  end

  def readptr(p, b=Syscalls::PAGE_SIZE)
    Fiddle::Pointer.new(p)[0,b]
  end

  def write(buf)
    raise RuntimeError unless @scratch
    buf.bytes.each_slice(Syscalls::PAGE_SIZE) do |bb|
      scratch(bb.pack("C*"))
      yield b if block_given?
    end
  end

  def read(b=Syscalls::PAGE_SIZE)
    raise RuntimeError unless @scratch
    readptr @scratch, b
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

