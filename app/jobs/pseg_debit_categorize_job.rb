# Amex strips the payee from debits on Rewards Checking (mask 5694), so the
# PSEG electric bill arrives as "Online Transfer / Payment: Debit" with a new
# amount every month, late in the month. Sure rules can match an amount range
# but not a day of the month, so this job files that debit under Utilities.
#
# A debit qualifies when it is on that account, has that name, falls on the
# 22nd or later, is between $100 and $400, is not part of a transfer and its
# category is not locked (a category you set by hand is never changed). When a
# month has more than one qualifying debit the job can't tell which is PSEG and
# leaves that month alone.
class PsegDebitCategorizeJob < ApplicationJob
  queue_as :scheduled

  ACCOUNT_MASK = "5694".freeze
  NAME = "Online Transfer / Payment: Debit".freeze
  FIRST_DAY = 22
  AMOUNTS = (100..400)
  CATEGORY_NAME = "Utilities".freeze
  LOOKBACK = 60.days

  def perform(since: LOOKBACK.ago.to_date)
    PlaidAccount.where(mask: ACCOUNT_MASK).find_each do |plaid_account|
      account = plaid_account.linked_account || plaid_account.account
      next unless account

      category = account.family.categories.find_by(name: CATEGORY_NAME)
      next unless category

      candidates(account, since).group_by { |transaction| transaction.entry.date.beginning_of_month }.each_value do |in_month|
        next unless in_month.one?

        transaction = in_month.first
        next if transaction.category_id == category.id

        transaction.enrich_attribute(:category_id, category.id, source: "rule")
        Rails.logger.info("[PsegDebitCategorize] #{transaction.entry.date} #{transaction.entry.amount} filed under #{CATEGORY_NAME}")
      end
    end
  end

  private
    def candidates(account, since)
      Transaction
        .joins(:entry)
        .includes(:entry)
        .where(kind: "standard")
        .where(entries: { account_id: account.id, name: NAME, amount: AMOUNTS, date: since.. })
        .where("EXTRACT(DAY FROM entries.date) >= ?", FIRST_DAY)
        .where.missing(:transfer_as_inflow, :transfer_as_outflow)
        .enrichable(:category_id)
    end
end
