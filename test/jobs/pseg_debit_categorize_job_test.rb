require "test_helper"

class PsegDebitCategorizeJobTest < ActiveJob::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @account = accounts(:connected)
    plaid_accounts(:one).update!(mask: PsegDebitCategorizeJob::ACCOUNT_MASK)
    @utilities = @family.categories.create!(name: "Utilities", color: "#123456", lucide_icon: "lightbulb")
    @loans = @family.categories.create!(name: "Loan Payments", color: "#654321", lucide_icon: "landmark")
  end

  test "files the late-month debit under Utilities" do
    entry = debit(amount: 251.28, date: Date.new(2026, 9, 25))

    PsegDebitCategorizeJob.perform_now(since: Date.new(2026, 9, 1))

    assert_equal @utilities, entry.transaction.reload.category
  end

  test "leaves debits early in the month, outside the range or locked alone" do
    early = debit(amount: 251.28, date: Date.new(2026, 9, 8))
    small = debit(amount: 65, date: Date.new(2026, 9, 30))
    locked = debit(amount: 195.02, date: Date.new(2026, 10, 28))
    locked.transaction.lock_attr!(:category_id)

    PsegDebitCategorizeJob.perform_now(since: Date.new(2026, 9, 1))

    assert_equal @loans, early.transaction.reload.category
    assert_equal @loans, small.transaction.reload.category
    assert_equal @loans, locked.transaction.reload.category
  end

  test "leaves a month with two candidates alone" do
    first = debit(amount: 251.28, date: Date.new(2026, 9, 25))
    second = debit(amount: 300, date: Date.new(2026, 9, 27))

    PsegDebitCategorizeJob.perform_now(since: Date.new(2026, 9, 1))

    assert_equal @loans, first.transaction.reload.category
    assert_equal @loans, second.transaction.reload.category
  end

  private
    def debit(amount:, date:)
      create_transaction(account: @account, name: PsegDebitCategorizeJob::NAME, amount: amount, date: date, category: @loans)
    end
end
