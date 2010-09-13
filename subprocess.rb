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
  #             An open file object or file descriptor (positive integer)
  #             will cause the child's standard output to be redirected to
  #             that file.
  #             If Subprocess::PIPE, then a new pipe file object will be opened
  #             accessible as stdout, for you to read data from.
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
    return (! @opts[:stdout].nil?) && (@opts[:stdout] == Subprocess::PIPE)
  end

  # Fork, creating pipes.  => pid, stdout
  #
  # The block is executed in the child process with stdout set as appropriate.
  private
  def fork_with_pipes
    if pipe_stdout
      stdout_read, stdout_write = IO.pipe
    else
      stdout_read = nil
      stdout_write = nil
    end
    pid = Process.fork do
      if pipe_stdout
        stdout_read.close
        $stdout = stdout_write
      end
      yield
    end
    if pipe_stdout
      stdout_write.close
    end
    return pid, stdout_read
  end

  # Start the child process.
  # Needs @opts and @args to have been defined before it is run
  private
  def start_child
    pid, stdout_read = fork_with_pipes do
      opt_chdir do |path|
        opt_env
        opt_preexec path
        exec *@args
      end
    end
    @stdout = stdout_read
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
end
