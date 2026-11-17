require "test_helper"

class TransferAutoConfirmJobTest < ActiveJob::TestCase
  include EntriesTestHelper

  setup do
    @checking = accounts(:depository)
    @card = accounts(:credit_card)
  end

  test "confirms a pending checking to card payment" do
    transfer = pending_transfer(from: @checking, to: @card, out_amount: 100, in_amount: 100)

    TransferAutoConfirmJob.perform_now

    assert transfer.reload.confirmed?
  end

  test "leaves a pair alone when the money leaves a card" do
    transfer = pending_transfer(from: @card, to: @checking, out_amount: 100, in_amount: 100)

    TransferAutoConfirmJob.perform_now

    assert transfer.reload.pending?
  end

  test "leaves a match older than 30 days alone" do
    transfer = pending_transfer(from: @checking, to: @card, out_amount: 100, in_amount: 100)
    transfer.update_column(:created_at, 31.days.ago)

    TransferAutoConfirmJob.perform_now

    assert transfer.reload.pending?
  end

  private
    def pending_transfer(from:, to:, out_amount:, in_amount:)
      outflow = create_transaction(account: from, amount: out_amount, name: "Payment out").entryable
      inflow = create_transaction(account: to, amount: -in_amount, name: "Payment in").entryable
      Transfer.create!(outflow_transaction: outflow, inflow_transaction: inflow, amount: out_amount, status: "pending")
    end
end
