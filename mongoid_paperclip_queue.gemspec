Gem::Specification.new do |s|
  s.name = %q{mongoid_paperclip_queue}
  s.version = "0.1.3"

  s.authors = ["Kelly Martin"]
  s.summary = %q{Process your Paperclip attachments in the background using Mongoid and Resque.}
  s.description = %q{Process your Paperclip attachments in the background using Mongoid and Resque. Loosely based on delayed_paperclip and mongoid-paperclip.}
  s.email = %q{kelly@fullybrand.com}
  s.homepage = %q{http://github.com/kellym/mongoid_paperclip_queue}

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")

  s.add_dependency 'paperclip', ["~>3.4.1"]
  s.add_dependency 'redis-namespace'
  s.add_dependency 'mongoid', [">= 3.0"]
  s.add_dependency 'resque'

end
