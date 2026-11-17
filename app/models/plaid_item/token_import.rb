# Josue's fork: brings a Plaid Item that already exists into Sure by its access
# token, without Plaid Link or a public-token exchange (his Trial plan has no
# Item slots to spare). It reads /item/get and /institutions/get_by_id, creates
# the PlaidItem, puts it on a sync schedule (Plaid webhooks can't reach a
# tailnet-only host) and starts the first sync. Run it through
# `bin/rails "plaid:import_item[email]"` (lib/tasks/plaid_import.rake).
class PlaidItem::TokenImport
  DEFAULT_SYNC_INTERVAL_MINUTES = 120

  Error = Class.new(StandardError)
  Result = Data.define(:plaid_item, :created)

  def initialize(family:, access_token:, owner: nil, region: :us, sync_interval_minutes: DEFAULT_SYNC_INTERVAL_MINUTES)
    @family = family
    @access_token = access_token.to_s.strip
    @owner = owner
    @region = region.to_sym
    @sync_interval_minutes = sync_interval_minutes.to_i
  end

  def import!
    raise Error, "No access token given" if access_token.empty?

    provider = Provider::Registry.plaid_provider_for_region(region)
    raise Error, "Plaid is not configured (PLAID_CLIENT_ID and PLAID_SECRET)" unless provider

    item = provider.get_item(access_token).item

    if (existing = PlaidItem.find_by(plaid_id: item.item_id))
      raise Error, "That Item belongs to another family" unless existing.family_id == family.id
      raise Error, "That Item is being deleted in Sure" if existing.scheduled_for_deletion?

      schedule(existing)
      return Result.new(plaid_item: existing, created: false)
    end

    institution = item.institution_id.present? ? provider.get_institution(item.institution_id).institution : nil

    plaid_item = family.plaid_items.create!(
      name: institution&.name.presence || item.try(:institution_name).presence || "Plaid",
      plaid_id: item.item_id,
      access_token: access_token,
      plaid_region: region.to_s,
      institution_id: item.institution_id,
      owner: owner
    )

    schedule(plaid_item)
    plaid_item.sync_later

    Result.new(plaid_item: plaid_item, created: true)
  end

  private
    attr_reader :family, :access_token, :owner, :region, :sync_interval_minutes

    def schedule(plaid_item)
      return unless sync_interval_minutes.positive?

      schedule = SyncSchedule.assign(plaid_item, sync_interval_minutes)
      raise Error, schedule.errors.full_messages.to_sentence if schedule.errors.any?
    end
end
