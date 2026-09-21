ENV["AMBER_ENV"] ||= "test"

# config/settings.cr lets DATABASE_URL override config/environments/test.yml.
# In the dev container that variable points at ratmachine_development, so
# leaving it set makes this suite -- including the Post.clear / Captcha.clear
# before_each hooks -- truncate real development data. Drop it before the
# config is loaded so test.yml wins and the specs stay on ratmachine_test.
ENV.delete("DATABASE_URL")

require "spec"
require "micrate"
#require "garnet_spec"

require "../config/*"

Micrate::DB.connection_url = Amber.settings.database_url

# Automatically run migrations on the test database
Micrate::Cli.run_up

# Disable Granite logs in tests
Log.setup("granite", :none)
