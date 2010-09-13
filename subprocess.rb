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
  # args:: The argument list to run, including the program path at position 0.
  #        A list of strings.
  # opts:: A hash of options modifying the default behaviour.
  def initialize(args, opts={})
    @opts = {
      :chdir => nil,
    }.merge!(opts)
    @status = nil
    @args = args
    @pid = Process.fork do
      if opts[:chdir].nil?
        exec *args
      else
        Dir.chdir(opts[:chdir]) do
          exec *args
        end
      end
    end      
  end

  # Wait for the child process to exit.
  # * Sets status to a Process::Status object.
  # * Returns the same Process::Status object.
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
  puts "ls had pid: #{child.pid}"
  puts "ls exited with status #{status.exitstatus}"
  puts ""
  puts "Testing ls in the doc directory..."
  child = Subprocess.new(['ls', '-l'], :chdir => 'doc')
  status = child.wait
end
