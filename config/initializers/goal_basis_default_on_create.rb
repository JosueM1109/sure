# See app/models/goal_basis_default_on_create.rb.
Rails.application.config.to_prepare do
  Goal.prepend(GoalBasisDefaultOnCreate) unless Goal < GoalBasisDefaultOnCreate
end
