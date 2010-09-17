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
# License::     GNU Lesser General Public License, version 3 or above.
#               See http://www.gnu.org/licenses/gpl.html

# This class gives a consistent interface for spawning and managing child
# processes.
# It aims to be similar to Python's subprocess module, wherever this is also
# ruby-like
class Subprocess
  class CalledProcessException < Exception
    attr_reader :status
    def initialize(args, status)
      @args = args
      @status = status
    end
    def to_s
      return "Child returned non-zero exit status: #{status.exitstatus}"
    end
  end
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
  # @param [Array] args The argument list to run, including the program path at position 0.
  # @param [Hash] opts A hash of options modifying the default behaviour.
  #
  # Options (the opts argument):
  # :cwd::
  #   Change directory to the given path after forking.
  #   If nil (the default), no directory change is performed.
  # :preexec:: If set to a proc, that proc will be executed in the
  #            child process just before exec is called.
  # :env:: If not nil, the child's environment is _replaced_ with the
  #        environment specified in the hash you provide, just before
  #        calling the preexec proc.
  # :stdout:: Specifies the child's standard output file handle.
  #           If nil (the default), then the child's standard output remains
  #           the same as the caller (your program).
  #           An open IO will cause the child's standard output to be
  #           redirected to that file.
  #           If Subprocess::PIPE, then a new pipe file object will be opened
  #           accessible as stdout, for you to read data from.
  # :stdin:: Specifies the child's input file handle.
  #          If nil (the default) then the child's standard input remains the
  #          same as the caller.
  #          An open IO will cause the child's standard input to be taken
  #          from that file.
  #          If Subprocess::PIPE, then a new pipe object will be opened
  #          accessible as stdin, for you to write data to.
  # :stderr:: Specifies the child's standard error file handle.
  #           If nil (the default), then the child's standard error remains
  #           the same as the caller (your program).
  #           An open IO will cause the child's standard error to be
  #           redirected to that file.
  #           If Subprocess::PIPE, then a new pipe file object will be opened
  #           accessible as stderr, for you to read data from.
  def initialize(args, opts={})
    # --
    @opts = {
      # These are the default options
      :cwd => nil,
      :preexec => nil,
      :env => nil,
      :stdout => nil,
      :stdin => nil,
      :stderr => nil,
    }.merge!(opts)   # Merge passed in options into the defaults
    @opts.freeze
    @status = nil
    @args = args
    @stdout = nil
    start_child
    # ++
  end

  # Wait for the child process to exit.
  #
  # Sets status to a Process::Status object, as well as returning it.
  #
  # @return [Process::Status] the status of the child process
  def wait
    pid, statusobj = Process.wait2(@pid)
    @status = statusobj
    @status.freeze
    return statusobj
  end

  # Sends the given signal to the child.
  # 
  # Not all signals are available on all platforms.
  #
  # @param [string, fixnum] signal An integer signal number or a POSIX signal
  #                                name (either with or without a SIG prefix).
  #
  # @return [Fixnum] the return value of Process.kill
  def send_signal(signal)
    Process.kill(signal, @pid)
  end

  # Call the given command, wait to complete and return a Process::Status.
  #
  # The arguments are the same as for initialize (new)
  #
  # <b>Warning:</b> Like wait, this will deadlock when using
  # :stdout=>PIPE and/or :stderr=>PIPE and the child process generates enough
  # output to a pipe such that it blocks waiting for the OS pipe buffer to
  # accept more data.
  def Subprocess::call(args, opts={})
    return Subprocess.new(args, opts).wait
  end

  # Call the given command, wait to complete and raise if exit status is non-zero.
  # If the exit status is zero, then this just returns.
  # If the exit status is non-zero, then Subprocess::CalledProcessException
  # is raised.
  #
  # <b>Warning:</b> See the warning for call().
  def Subprocess::check_call(args, opts={})
    status = Subprocess.new(args, opts).wait
    if status.exitstatus != 0
      raise CalledProcessException.new(args, status)
    end
    return 0
  end

  # Return whether we're piping a particular stream
  # *identifier*:: One of :stdout, :stdin or :stderr
  private
  def must_pipe?(identifier)
    return @opts[identifier] == Subprocess::PIPE
  end

  # Return whether we're redirecting a particular stream
  # *identifier*:: One of :stdout, :stdin or :stderr
  private
  def must_redirect?(identifier)
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
    if must_pipe?(stream_id)
      parent_end.close
      stream.reopen(child_end)
    elsif must_redirect?(stream_id)
      stream.reopen(@opts[stream_id])
    end
  end

  # Called inside the parent after forking to set up the stream.
  private
  def setup_stream_inparent(stream_id, parent_end, child_end)
    if must_pipe?(stream_id)
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
    if must_pipe?(stream_id)
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
    opt_chdir do |path|
      @pid = fork_with_pipes do
        opt_env
        opt_preexec path
        exec *@args
      end
    end
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
