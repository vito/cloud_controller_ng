RSpec.configure do |config|
  config.before(:each, :skip_sqlite => true) do
    if $spec_env.db.adapter_name =~ /sqlite/i
      pending "This test is not valid for SQLite"
    end
  end
end
