guard 'rspec', cmd: 'rspec --color' do
  watch(%r{^lib/(.+)\.rb$}) { |m| "spec/#{m[1]}_spec.rb" }
  watch(%r|^spec/(.*)_spec\.rb|)
end
