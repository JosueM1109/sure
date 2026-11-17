require "test_helper"

# GoalBasisDefaultOnCreate: keeps a goal's progress_basis once it is set to balance.
class GoalBasisDefaultOnCreateTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @investment = accounts(:investment)
  end

  test "a new goal on an investment account still starts on contributions" do
    goal = @family.goals.new(name: "Car", target_amount: 2_580, currency: "USD")
    goal.goal_accounts.build(account: @investment)
    goal.save!

    assert_equal "contributions", goal.reload.progress_basis
  end

  test "a goal moved to the balance basis keeps it on later saves" do
    goal = @family.goals.new(name: "Car", target_amount: 2_580, currency: "USD")
    goal.goal_accounts.build(account: @investment)
    goal.save!
    goal.update_column(:progress_basis, "balance")

    goal.reload.update!(name: "Car down payment")

    assert_equal "balance", goal.reload.progress_basis
  end
end
