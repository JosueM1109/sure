require "test_helper"

# Josue's fork: Sure must only read from Plaid production. See
# app/models/plaid_guardrails.rb.
class PlaidGuardrailsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  PLAID = "https://production.plaid.com".freeze

  setup do
    with_env_overrides("PLAID_CLIENT_ID" => "foo", "PLAID_SECRET" => "bar", "PLAID_ENV" => "production") do
      Provider::PlaidAdapter.reload_configuration
    end
    @provider = Provider::Plaid.new(Rails.application.config.plaid, region: :us)
    @plaid_item = plaid_items(:one)
  end

  teardown do
    Provider::PlaidAdapter.reload_configuration
  end

  test "never sends /item/remove, even when called on the client directly" do
    assert_raises(PlaidGuardrails::Blocked) do
      @provider.client.item_remove(Plaid::ItemRemoveRequest.new(access_token: "access-production-x"))
    end
    assert_not_requested :post, "#{PLAID}/item/remove"
  end

  test "never sends calls that edit an Item" do
    assert_raises(PlaidGuardrails::Blocked) do
      @provider.client.item_webhook_update(
        Plaid::ItemWebhookUpdateRequest.new(access_token: "access-production-x", webhook: "https://example.com")
      )
    end
    assert_raises(PlaidGuardrails::Blocked) do
      @provider.client.item_access_token_invalidate(
        Plaid::ItemAccessTokenInvalidateRequest.new(access_token: "access-production-x")
      )
    end
    assert_not_requested :post, "#{PLAID}/item/webhook/update"
    assert_not_requested :post, "#{PLAID}/item/access_token/invalidate"
  end

  test "lets read calls through" do
    stub_request(:post, "#{PLAID}/item/get").to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: { item: { item_id: "item-1", institution_id: "ins_1", available_products: [], billed_products: [] }, request_id: "r" }.to_json
    )

    assert_equal "item-1", @provider.get_item("access-production-x").item.item_id
  end

  test "removing an item skips Plaid and logs it" do
    Rails.logger.expects(:warn).with(regexp_matches(/Skipped Plaid \/item\/remove/))

    assert_nil @provider.remove_item("access-production-x")
    assert_not_requested :post, "#{PLAID}/item/remove"
  end

  test "deleting a connection deletes it in Sure only" do
    PlaidItem.any_instance.stubs(:plaid_provider).returns(@provider)

    assert_difference -> { PlaidItem.count }, -1 do
      @plaid_item.destroy
    end
    assert_not_requested :post, "#{PLAID}/item/remove"
  end

  test "Link is off unless PLAID_ALLOW_LINK=true" do
    error = assert_raises(Plaid::ApiError) do
      @provider.get_link_token(user_id: "u", webhooks_url: "https://x/webhooks/plaid", redirect_url: "https://x/accounts")
    end
    assert_equal "BLOCKED_BY_FORK", JSON.parse(error.response_body)["error_code"]

    assert_raises(PlaidGuardrails::Blocked) { @provider.exchange_public_token("public-production-x") }
    assert_not_requested :post, "#{PLAID}/link/token/create"
    assert_not_requested :post, "#{PLAID}/item/public_token/exchange"

    stub_request(:post, "#{PLAID}/link/token/create").to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: { link_token: "link-production-x", expiration: "2026-01-01T00:00:00Z", request_id: "r" }.to_json
    )
    with_env_overrides("PLAID_ALLOW_LINK" => "true") do
      @provider.get_link_token(user_id: "u", webhooks_url: "https://x/webhooks/plaid", redirect_url: "https://x/accounts")
    end
    assert_requested :post, "#{PLAID}/link/token/create", times: 1
  end

  test "transactions refresh is off unless PLAID_ALLOW_TRANSACTIONS_REFRESH=true" do
    @plaid_item.stubs(:supports_product?).with("transactions").returns(true)
    @plaid_item.stubs(:shared_transactions_refresh_cache?).returns(true)

    assert_raises(PlaidGuardrails::Blocked) { @provider.refresh_transactions("access-production-x") }

    PlaidGuardrails.enforce do
      assert_no_enqueued_jobs only: PlaidTransactionsRefreshJob do
        assert_nil @plaid_item.request_transactions_refresh_later
      end

      Rails.cache.delete("plaid_item:#{@plaid_item.id}:transactions_refresh_requested")
      with_env_overrides("PLAID_ALLOW_TRANSACTIONS_REFRESH" => "true") do
        assert_enqueued_with(job: PlaidTransactionsRefreshJob) do
          @plaid_item.request_transactions_refresh_later
        end
      end
    end
  ensure
    Rails.cache.delete("plaid_item:#{@plaid_item.id}:transactions_refresh_requested")
  end

  test "the refresh gate is always on outside tests" do
    assert PlaidGuardrails.enforce { PlaidGuardrails.enforced? }
    Rails.env.stubs(:test?).returns(false)
    assert PlaidGuardrails.enforced?
  end

  test "the sandbox is left alone" do
    sandbox = Plaid::Configuration.new
    sandbox.server_index = Plaid::Configuration::Environment["sandbox"]

    assert PlaidGuardrails.sandbox?(sandbox)
    assert_not PlaidGuardrails.sandbox?(Rails.application.config.plaid)
  end
end
