task :default => [:all]

task :all => [:doc]

task :doc do
  sh "yardoc"
end

task :clobber do
  sh "rm -r doc"
end
