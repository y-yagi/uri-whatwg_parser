# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.test_files = FileList["test/**/test_*.rb"]
end

task :download_wpt_resources do
  Dir.chdir "test/resources" do
    system("curl -O https://raw.githubusercontent.com/web-platform-tests/wpt/master/url/resources/urltestdata.json", exception: true)
  end
end

task default: :test
