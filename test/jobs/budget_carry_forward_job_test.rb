require "test_helper"

class BudgetCarryForwardJobTest < ActiveJob::TestCase
  setup do
    @family = families(:dylan_family)
    @source = budgets(:one)
  end

  test "starts next month from the previous month's amounts" do
    next_month = @source.start_date.next_month

    travel_to(next_month + 2.days) do
      BudgetCarryForwardJob.perform_now

      budget = @family.budgets.find_by(start_date: next_month, user_id: nil)
      assert budget.initialized?
      assert_equal @source.budgeted_spending, budget.budgeted_spending
    end
  end

  test "leaves a month that is already set up alone" do
    next_month = @source.start_date.next_month

    travel_to(next_month + 2.days) do
      BudgetCarryForwardJob.perform_now
      budget = @family.budgets.find_by(start_date: next_month, user_id: nil)
      budget.update!(budgeted_spending: 1234)

      BudgetCarryForwardJob.perform_now

      assert_equal 1234, budget.reload.budgeted_spending
    end
  end
end
