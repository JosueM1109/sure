# Confirms Sure's own auto-matched transfers so card payments and brokerage
# deposits stop counting as income or spending without a manual click.
# Only clear-cut pairs: money leaving a checking account for a card, loan,
# brokerage or another checking account in the same family, the same amount
# on both sides, at most 4 days apart, matched within the last 30 days.
# Anything else stays pending for a person to review.
class TransferAutoConfirmJob < ApplicationJob
  queue_as :scheduled

  DESTINATION_TYPES = %w[CreditCard Loan Investment Depository].freeze

  def perform
    Transfer.pending.where(created_at: 30.days.ago..).find_each do |transfer|
      next unless clear_cut?(transfer)

      transfer.confirm!
      Rails.logger.info("[TransferAutoConfirm] confirmed transfer #{transfer.id}")
    end
  end

  private
    def clear_cut?(transfer)
      outflow = transfer.outflow_transaction&.entry
      inflow = transfer.inflow_transaction&.entry
      return false unless outflow && inflow

      from = outflow.account
      to = inflow.account
      return false unless from.family_id == to.family_id && from.id != to.id
      return false unless from.accountable_type == "Depository"
      return false unless DESTINATION_TYPES.include?(to.accountable_type)
      return false unless outflow.currency == inflow.currency
      return false unless outflow.amount.abs == inflow.amount.abs

      (outflow.date - inflow.date).abs <= 4
    end
end
