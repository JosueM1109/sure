# Josue's fork: Sure only reads from Plaid. See app/models/plaid_guardrails.rb.
Rails.application.config.to_prepare do
  # Plaid::ApiClient comes from the gem and is never reloaded, so it is
  # prepended once; the app classes are reloaded and prepended each time.
  unless Plaid::ApiClient.ancestors.any? { |mod| mod.name == "PlaidGuardrails::ApiClientGuard" }
    Plaid::ApiClient.prepend(PlaidGuardrails::ApiClientGuard)
  end
  Provider::Plaid.prepend(PlaidGuardrails::ProviderGuard)
  PlaidItem.prepend(PlaidGuardrails::ItemGuard)
end
