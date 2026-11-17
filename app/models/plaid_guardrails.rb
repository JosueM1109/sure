# Josue's fork (see Local/README.md). His Plaid account is on the Trial plan:
# 10 Items in total, and removing an Item does not give its slot back. The same
# Items also feed other tools of his, so Sure only ever reads them:
#
# - Sure never calls /item/remove. Deleting a connection in the app deletes it
#   in Sure only and logs a line saying so.
# - Every Plaid request goes through ApiClientGuard, which only lets read
#   endpoints through. Anything else (/item/webhook/update, /item/remove,
#   /item/access_token/invalidate, ...) raises Blocked before it is sent.
# - Plaid Link (/link/token/create, /item/public_token/exchange) is off unless
#   PLAID_ALLOW_LINK=true, so Sure can't create Items or edit their accounts.
# - /transactions/refresh, which Plaid bills per call, is off unless
#   PLAID_ALLOW_TRANSACTIONS_REFRESH=true. Scheduled syncs still pick up
#   what Plaid has pulled from the bank on its own.
#
# Plaid's sandbox is left alone: its Items are fake, and upstream tests use it.
module PlaidGuardrails
  READ_PATHS = %w[
    /accounts/balance/get
    /accounts/get
    /institutions/get_by_id
    /investments/holdings/get
    /investments/transactions/get
    /item/get
    /liabilities/get
    /transactions/sync
    /webhook_verification_key/get
  ].freeze

  LINK_PATHS = %w[/link/token/create /item/public_token/exchange].freeze
  REFRESH_PATHS = %w[/transactions/refresh].freeze

  # A Plaid::ApiError, so the controllers' existing Plaid error handling turns
  # a blocked Link attempt into a normal alert instead of a 500.
  class Blocked < Plaid::ApiError
    def initialize(path)
      super(
        code: 403,
        message: "Blocked by the fork's Plaid guardrails: #{path}",
        response_body: {
          error_type: "FORK_GUARDRAIL",
          error_code: "BLOCKED_BY_FORK",
          error_message: "This Sure install never calls #{path} (see Local/README.md)."
        }.to_json
      )
    end
  end

  class << self
    def link_allowed?
      ENV["PLAID_ALLOW_LINK"] == "true"
    end

    def transactions_refresh_allowed?
      ENV["PLAID_ALLOW_TRANSACTIONS_REFRESH"] == "true"
    end

    def allowed_path?(path)
      path = path.to_s
      READ_PATHS.include?(path) ||
        (LINK_PATHS.include?(path) && link_allowed?) ||
        (REFRESH_PATHS.include?(path) && transactions_refresh_allowed?)
    end

    def sandbox?(config)
      config.present? && config.base_url.to_s.include?("sandbox.plaid.com")
    end

    # The refresh gate can't tell a fake Item from a real one, so it is always
    # on, except in upstream's tests, which expect upstream's behavior. The
    # fork's own tests turn it on with `enforce { ... }`.
    def enforced?
      !Rails.env.test? || Thread.current[:plaid_guardrails_enforced] == true
    end

    def enforce
      previous = Thread.current[:plaid_guardrails_enforced]
      Thread.current[:plaid_guardrails_enforced] = true
      yield
    ensure
      Thread.current[:plaid_guardrails_enforced] = previous
    end

    def log(message)
      Rails.logger.warn("[PlaidGuardrails] #{message}")
    end
  end

  # Prepended to Plaid::ApiClient: every Plaid endpoint goes through call_api.
  module ApiClientGuard
    def call_api(http_method, path, opts = {})
      unless PlaidGuardrails.sandbox?(config) || PlaidGuardrails.allowed_path?(path)
        PlaidGuardrails.log("Blocked Plaid #{path}")
        raise PlaidGuardrails::Blocked.new(path)
      end

      super
    end
  end

  # Prepended to Provider::Plaid.
  module ProviderGuard
    def remove_item(access_token)
      return super if PlaidGuardrails.sandbox?(client.api_client.config)

      PlaidGuardrails.log("Skipped Plaid /item/remove: the connection is deleted in Sure only and the Item stays at Plaid")
      nil
    end
  end

  # Prepended to PlaidItem.
  module ItemGuard
    def request_transactions_refresh_later
      return super if PlaidGuardrails.transactions_refresh_allowed? || !PlaidGuardrails.enforced?

      nil
    end
  end
end
