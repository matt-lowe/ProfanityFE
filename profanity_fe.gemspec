Gem::Specification.new do |s|
  s.name        = 'profanity_fe'
  s.version     = '0.5.0'
  s.date        = '2019-02-18'
  s.summary     = "ProfanityFE is a third party frontend for Simutronics games."
  s.description = "ProfanityFE is a third party frontend for Simutronics MUD games."
  s.authors     = ['Matt Lowe']
  s.email       = 'matt@io4.us'
  s.files       = ['lib/profanity_fe/countdown_window.rb',
                   'lib/profanity_fe/indicator_window.rb',
                   'lib/profanity_fe/progress_window.rb',
                   'lib/profanity_fe/text_window.rb']
  s.executables = ['profanity']
  s.homepage    = 'https://github.com/matt-lowe/ProfanityFE'
  s.license     = 'GPL-2.0+'
  s.required_ruby_version = '>=2.0'
end

