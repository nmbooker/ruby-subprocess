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
  def initialize(args, opts={})
    # --
    @opts = {
      # These are the default options
      :cwd => nil,
      :preexec => nil,
      :env => nil,
      :stdout => nil,
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


  private
  def pipe_stdout
    return @opts[:stdout] == Subprocess::PIPE
  end

  private
  def redirect_stdout
    return @opts[:stdout].is_a?(IO)
  end

  private
  def pipe_stdin
    return @opts[:stdin] == Subprocess::PIPE
  end

  private
  def set_stdout_inchild(read_end, write_end)
    if pipe_stdout
      read_end.close
      $stdout = write_end
    elsif redirect_stdout
      $stdout.reopen(@opts[:stdout])
    end
  end

  private
  def set_stdin_inchild(read_end, write_end)
    if pipe_stdin
      write_end.close
      $stdin.reopen(read_end)
    end
  end

  private
  def get_pipe(needs_pipe)
    if needs_pipe
      return IO.pipe
    else
      return nil, nil
    end
  end

  # Fork, creating pipes.  => pid, child_stdout, child_stdin
  #
  # The block is executed in the child process with stdout set as appropriate.
  private
  def fork_with_pipes
    stdout_read, stdout_write = get_pipe(pipe_stdout)
    stdin_read, stdin_write = get_pipe(pipe_stdin)
    pid = Process.fork do
      set_stdout_inchild(stdout_read, stdout_write)
      set_stdin_inchild(stdin_read, stdin_write)
      yield
    end
    if pipe_stdout
      stdout_write.close
    end
    if pipe_stdin
      stdin_read.close
    end
    return pid, stdout_read, stdin_write
  end

  # Start the child process.
  # Needs @opts and @args to have been defined before it is run
  private
  def start_child
    pid, child_stdout, child_stdin = fork_with_pipes do
      opt_chdir do |path|
        opt_env
        opt_preexec path
        exec *@args
      end
    end
    @stdout = child_stdout
    @stdin = child_stdin
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
end
