# Sure moves a goal backed by an investment account to the contributions basis
# on every save, so a goal deliberately put on the balance basis flipped back
# the next time anything about it was saved. With this, a saved goal that is
# on the balance basis keeps it unless the save links a new account, which
# still gets upstream's default.
module GoalBasisDefaultOnCreate
  private
    def default_progress_basis_for_market_accounts
      return if persisted? && progress_basis_in_database == "balance" && goal_accounts.none?(&:new_record?)

      super
    end
end
