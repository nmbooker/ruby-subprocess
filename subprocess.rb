#!/usr/bin/env ruby

# Defines Subprocess, which provides a consistent API for calling, waiting on
# and interacting with other programs.
#
# Author::      Nick Booker (mailto:NMBooker@googlemail.com)
# Copyright::   Copyright (c) 2010 Nicholas Booker
# License::     Not yet decided.  Assume no license until I decide.

# This class gives a consistent interface for spawning and managing child
# processes.
# It aims to be similar to Python's subprocess module, wherever this is also
# ruby-like
class Subprocess
  # the process id of the child
  attr_reader :pid
  # set to the Process::Status of the child when wait is called
  attr_reader :status
  # the argument list originally passed
  attr_reader :args
  # the options passed
  attr_reader :opts

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
  def initialize(args, opts={})
    # --
    @opts = {
      # These are the default options
      :cwd => nil,
      :preexec => nil,
    }.merge!(opts)   # Merge passed in options into the defaults
    @status = nil
    @args = args
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


  # Start the child process.
  # Needs @opts and @args to have been defined before it is run
  private
  def start_child
    pid = Process.fork do
      opt_chdir do |path|
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
end
