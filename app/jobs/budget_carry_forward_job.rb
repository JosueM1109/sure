# Starts each new budget month from the previous month's amounts, so nobody
# has to press "copy previous" by hand. Runs daily; a month that is already
# set up is left alone, so edits made during the month are never overwritten.
class BudgetCarryForwardJob < ApplicationJob
  queue_as :scheduled

  def perform(date = Date.current)
    Family.find_each do |family|
      budget = Budget.find_or_bootstrap(family, start_date: date)
      next if budget.nil? || budget.initialized?

      source = budget.most_recent_initialized_budget
      next unless source

      budget.copy_from!(source)
      Rails.logger.info("[BudgetCarryForward] family=#{family.id} #{budget.start_date} copied from #{source.start_date}")
    end
  end
end
