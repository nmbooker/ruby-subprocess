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
  # set to the status of the child when wait is called
  attr_reader :status
  # the argument list originally passed
  attr_reader :args

  # args: The argument list, including the program path at position 0
  def initialize(args)
    @status = nil
    @args = args
    @pid = Process.fork do
      exec(*args)
    end      
  end

  # Wait for the child process to exit.
  # Returns and sets @status to a Status
  def wait
    pid, status = Process.wait2(@pid)
    @status = status
    return status
  end
end

if $PROGRAM_NAME == __FILE__
  puts "Testing ls..."
  child = Subprocess.new(['ls', '-l'])
  status = child.wait
  puts "ls exited with status #{status.exitstatus}"
end
