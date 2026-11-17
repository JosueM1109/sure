# Josue's fork: import a Plaid Item that already exists, by access token.
#
#   docker compose exec -T web bin/rails "plaid:import_item[you@example.com]" < token.txt
#
# The token is read from PLAID_ACCESS_TOKEN or, if that is unset, from stdin,
# so it never shows up in a process list. PLAID_SYNC_INTERVAL_MINUTES sets the
# sync schedule (default 120, one of SyncSchedule::INTERVALS; 0 for none).
namespace :plaid do
  desc "Import an existing Plaid Item by access token, without Plaid Link"
  task :import_item, [ :email ] => :environment do |_task, args|
    email = args[:email].to_s.strip
    abort "Usage: bin/rails \"plaid:import_item[you@example.com]\" < token.txt" if email.empty?

    user = User.find_by(email: email)
    abort "No user with email #{email}" unless user

    token = ENV["PLAID_ACCESS_TOKEN"].presence || $stdin.read.to_s
    interval = ENV.fetch("PLAID_SYNC_INTERVAL_MINUTES", PlaidItem::TokenImport::DEFAULT_SYNC_INTERVAL_MINUTES)

    result = PlaidItem::TokenImport.new(
      family: user.family,
      owner: user,
      access_token: token,
      sync_interval_minutes: interval
    ).import!

    item = result.plaid_item
    verb = result.created ? "Imported" : "Already imported"
    schedule = item.sync_schedule ? "every #{item.sync_schedule.interval_minutes} min" : "no schedule"
    puts "#{verb}: #{item.name} (plaid item #{item.id}, #{schedule})"
  rescue PlaidItem::TokenImport::Error, Plaid::ApiError => e
    abort "Import failed: #{e.message.lines.first&.strip}"
  end
end
