task :default => :test

rule '.rb' => '.y' do |t|
    sh "racc -l -o #{t.name} #{t.source}"
end

task :compile => 'bash.rb'
task :test => :compile do
    sh "ruby bash.rb"
end
