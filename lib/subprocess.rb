#!/usr/bin/env ruby

# Defines Subprocess, which provides a consistent API for calling, waiting on
# and interacting with other programs.
#
# This is unlikely to work under non-Unix platforms, and the tests at the
# end of the script definitely won't.
# Support for Windows would be a welcome addition -- please contribute.
#
# Author::      Nick Booker (mailto:NMBooker@googlemail.com)
# Copyright::   Copyright (c) 2010 Nicholas Booker
# License::     Not yet decided.  Assume no license until I decide.

# This class gives a consistent interface for spawning and managing child
# processes.
# It aims to be similar to Python's subprocess module, wherever this is also
# ruby-like
class Subprocess
  PIPE = :Subprocess_PIPE
  # the process id of the child
  attr_reader :pid
  # set to the Process::Status of the child when wait is called
  attr_reader :status
  # the argument list originally passed
  attr_reader :args
  # the options passed
  attr_reader :opts
  # the stdout stream if the option :stdout is given as PIPE
  attr_reader :stdout
  # the stdin stream if the options :stdin is given as PIPE
  attr_reader :stdin
  # the stderr stream if the option :stderr is given as PIPE
  attr_reader :stderr

  # Arguments:
  # *args*:: The argument list to run, including the program path at position 0.
  #          A list of strings.
  # *opts*:: A hash of options modifying the default behaviour.
  #
  # Options (the opts argument):
  # *:cwd*:: Change directory to the given path after forking.
  #          If nil (the default), no directory change is performed.
  # *:preexec*:: If set to a proc, that proc will be executed in the
  #              child process just before exec is called.
  # *:env*:: If not nil, the child's environment is _replaced_ with the
  #          environment specified in the hash you provide, just before
  #          calling the preexec proc.
  # *:stdout*:: Specifies the child's standard output file handle.
  #             If nil (the default), then the child's standard output remains
  #             the same as the caller (your program).
  #             An open IO will cause the child's standard output to be
  #             redirected to that file.
  #             If Subprocess::PIPE, then a new pipe file object will be opened
  #             accessible as stdout, for you to read data from.
  # *:stdin*:: Specifies the child's input file handle.
  #            If nil (the default) then the child's standard input remains the
  #            same as the caller.
  #            An open IO will cause the child's standard input to be taken
  #            from that file.
  #            If Subprocess::PIPE, then a new pipe object will be opened
  #            accessible as stdin, for you to write data to.
  # *:stderr*:: Specifies the child's standard error file handle.
  #             If nil (the default), then the child's standard error remains
  #             the same as the caller (your program).
  #             An open IO will cause the child's standard error to be
  #             redirected to that file.
  #             If Subprocess::PIPE, then a new pipe file object will be opened
  #             accessible as stderr, for you to read data from.
  def initialize(args, opts={})
    # --
    @opts = {
      # These are the default options
      :cwd => nil,
      :preexec => nil,
      :env => nil,
      :stdout => nil,
      :stderr => nil,
    }.merge!(opts)   # Merge passed in options into the defaults
    @status = nil
    @args = args
    @stdout = nil
    @pid = start_child()
    # ++
  end

  # Wait for the child process to exit.
  # * Sets status to a Process::Status object.
  # * Returns the same Process::Status object.
  def wait
    pid, statusobj = Process.wait2(@pid)
    @status = statusobj
    return statusobj
  end

  # Return whether we're piping a particular stream
  # *identifier*:: One of :stdout, :stdin or :stderr
  private
  def must_pipe(identifier)
    return @opts[identifier] == Subprocess::PIPE
  end

  # Return whether we're redirecting a particular stream
  # *identifier*:: One of :stdout, :stdin or :stderr
  private
  def must_redirect(identifier)
    return @opts[identifier].is_a?(IO)
  end

  private
  def select_child_stream(stream_id)
    stream = case stream_id
      when :stdin then $stdin
      when :stdout then $stdout
      when :stderr then $stderr
      else nil
    end
    return stream
  end

  # Specifies whether the given stream is written to by the child.
  private
  def written_by_child?(stream_id)
    result = case stream_id
             when :stdin then false
             when :stdout then true
             when :stderr then true
             else nil
    end
    return result
  end

  # Called inside the child to set up the streams.
  private
  def setup_stream_inchild(stream_id, parent_end, child_end)
    stream = select_child_stream(stream_id)
    if must_pipe(stream_id)
      parent_end.close
      stream.reopen(child_end)
    elsif must_redirect(stream_id)
      stream.reopen(@opts[stream_id])
    end
  end

  # Called inside the parent after forking to set up the stream.
  private
  def setup_stream_inparent(stream_id, parent_end, child_end)
    if must_pipe(stream_id)
      child_end.close
      if stream_id == :stdin
        @stdin = parent_end
      elsif stream_id == :stdout
        @stdout = parent_end
      elsif stream_id == :stderr
        @stderr = parent_end
      end
    end
  end

  # If a pipe is required, returns the array [parent_end, child_end].
  # If no pipe is required, returns [nil, nil].
  private
  def get_pipe(stream_id)
    if must_pipe(stream_id)
      read_end, write_end = IO.pipe
      if written_by_child?(stream_id)
        return read_end, write_end
      else
        return write_end, read_end
      end
    else
      return nil, nil
    end
  end

  # Fork, creating pipes.  => pid
  #
  # The block is executed in the child process with stdout set as appropriate.
  private
  def fork_with_pipes
    stdout_parent, stdout_child = get_pipe(:stdout)
    stdin_parent, stdin_child = get_pipe(:stdin)
    stderr_parent, stderr_child = get_pipe(:stderr)
    pid = Process.fork do
      setup_stream_inchild(:stdout, stdout_parent, stdout_child)
      setup_stream_inchild(:stdin, stdin_parent, stdin_child)
      setup_stream_inchild(:stderr, stderr_parent, stderr_child)
      yield
    end
    setup_stream_inparent(:stdout, stdout_parent, stdout_child)
    setup_stream_inparent(:stdin, stdin_parent, stdin_child)
    setup_stream_inparent(:stderr, stderr_parent, stderr_child)
    return pid
  end

  # Start the child process.
  # Needs @opts and @args to have been defined before it is run
  private
  def start_child
    pid = fork_with_pipes do
      opt_chdir do |path|
        opt_env
        opt_preexec path
        exec *@args
      end
    end
    return pid
  end

  # Change directory if requested in opts, and execute the block.
  # _cwd_ is the working directory.
  private
  def opt_chdir            # :yields: cwd
    if @opts[:cwd].nil?
      yield Dir.getwd
    else
      Dir.chdir(opts[:cwd]) do |path|
        yield path
      end
    end
  end

  # Optionally execute the preexec proc
  private
  def opt_preexec(path)
    if not @opts[:preexec].nil?
      @opts[:preexec].call(path)
    end
  end

  # Optionally replace the environment
  private
  def opt_env
    if not @opts[:env].nil?
      ENV.replace(@opts[:env])
    end
  end
end

if $PROGRAM_NAME == __FILE__
  puts "Testing ls..."
  puts "We also have a preexec command to show the child's pid"
  showpid = proc { |path| puts "Child's pid is: #{Process.pid}" }
  child = Subprocess.new(['ls', '-l'], :preexec => showpid)
  status = child.wait
  puts "ls had pid: #{child.pid}"
  puts "ls exited with status #{status.exitstatus}"
  puts ""
  puts "Testing ls in the doc directory..."
  child = Subprocess.new(['ls', '-l'], :cwd => 'doc')
  status = child.wait
  puts "Testing overriding the environment..."
  child = Subprocess.new(['true'],
                     :env => {'HOME' => 'Something'},
                     :preexec => proc { |path| puts "$HOME = '#{ENV['HOME']}'" }
                     )
  status = child.wait
  puts "Redirecting stdout to a pipe."
  child = Subprocess.new(['true'],
                         :preexec => proc { |path| puts "Hello" },
                         :stdout => Subprocess::PIPE
                         )
  output = child.stdout.read
  child.wait
  print "Output: #{output}"
  File::open("output.txt", "wb") do |outfile|
    child = Subprocess.new(['ls'],
                           :preexec => proc { |path| puts "Hello" },
                           :stdout => outfile
                           )
    child.wait
  end
  File::open("output.txt", "rb") do |infile|
    print "output.txt: #{infile.read}"
  end

  child = Subprocess.new(['grep', 'hello'],
                         :stdin => Subprocess::PIPE
                         )
  child.stdin.write("Hello\n")
  child.stdin.write("hello\n")
  child.stdin.write("hello world\n")
  child.stdin.close
  child.wait

  puts ""
  puts "Grepping for anything containing 'rb' in output.txt..."
  File::open("output.txt", "rb") do |infile|
    child = Subprocess.new(['grep', 'rb'],
                           :stdin => infile
                           )
    child.wait
  end

  puts ""
  puts "Running bad ls command while redirecting stderr to stderr.txt..."
  File::open("stderr.txt", "wb") do |errfile|
    child = Subprocess.new(['ls', '/fiddlesticks'],
                           :stderr => errfile
                           )
    child.wait
  end
  puts "stderr.txt: #{File::open("stderr.txt").read}"

  puts ""
  puts "Running bad ls command while piping stderr..."
  child = Subprocess.new(['ls', '/fiddlesticks'],
                         :stderr => Subprocess::PIPE
                         )
  errors = child.stderr.read
  child.wait
  puts "errors: #{errors}"
end
