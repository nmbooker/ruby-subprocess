require "subprocess"
require "tmpdir"

  require 'tmpdir'
  def in_test_dir
    Dir.mktmpdir do |tmp|
      Dir.chdir(tmp) do |tempdir|
        yield tempdir
      end
    end
  end
  in_test_dir do |tempdir|
    puts "Working in temp directory #{Dir.pwd}"
    FileUtils.touch("hello.rb")
    Dir.mkdir("doc")
    Dir.chdir("doc") do
      FileUtils.touch("index.html")
    end
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

    puts ""
    puts "Testing signal -- launching something that catches HUP..."
    preexec = proc {
      Signal.trap("HUP") {
        puts "CHILD: I'm PID #{Process.pid}, and I got HUP.  I'll exit now."
        exit
      }
      puts "CHILD: Sleeping for 10 seconds..."
      sleep 10
    }
    child = Subprocess.new(["true"],
                           :preexec => preexec)
    puts "PARENT: Sleeping for 2 seconds"
    sleep 2
    puts "PARENT: Sending HUP to the child (PID: #{child.pid})..."
    child.send_signal("HUP")
    child.wait

    puts ""
    puts "Testing Subprocess::call"
    status = Subprocess::call(["ls"])
    puts "Exit status was: #{status.exitstatus}"
    
    puts ""
    puts "Testing Subprocess::check_call for exit status 0"
    Subprocess::check_call(["true"])
    puts "Testing Subprocess::check_call for non-zero exit status"
    begin
      Subprocess::check_call(["false"])
      puts "ERROR - CalledProcessException should have been raised!"
    rescue Subprocess::CalledProcessException => exc
      puts "#{exc.class} was raised. #{exc}"
    end
  end


