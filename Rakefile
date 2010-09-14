task :default => [:all]

task :all => [:doc]

task :doc do
  sh "rdoc lib/subprocess.rb"
end

task :clobber do
  sh "rm -r doc"
end
