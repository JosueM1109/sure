require "test_helper"

class PlaidItem::TokenImportTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    @provider = mock
    Provider::Registry.stubs(:plaid_provider_for_region).returns(@provider)
  end

  def stub_item(item_id: "item-new", institution_id: "ins_3")
    item = OpenStruct.new(item_id: item_id, institution_id: institution_id)
    @provider.stubs(:get_item).with("access-production-new").returns(OpenStruct.new(item: item))
    @provider.stubs(:get_institution).with(institution_id)
      .returns(OpenStruct.new(institution: OpenStruct.new(name: "Chase", institution_id: institution_id)))
  end

  test "creates the item from /item/get, schedules it and starts a sync" do
    stub_item
    @provider.expects(:remove_item).never

    result = nil
    assert_difference -> { @family.plaid_items.count }, 1 do
      assert_enqueued_with(job: SyncJob) do
        result = PlaidItem::TokenImport.new(family: @family, owner: @user, access_token: "access-production-new\n").import!
      end
    end

    item = result.plaid_item
    assert result.created
    assert_equal "Chase", item.name
    assert_equal "item-new", item.plaid_id
    assert_equal "ins_3", item.institution_id
    assert_equal "access-production-new", item.access_token
    assert_equal @user, item.owner
    assert_equal 120, item.sync_schedule.interval_minutes
  end

  test "importing the same Item again changes nothing" do
    stub_item
    PlaidItem::TokenImport.new(family: @family, owner: @user, access_token: "access-production-new").import!

    result = nil
    assert_no_difference -> { PlaidItem.count } do
      result = PlaidItem::TokenImport.new(family: @family, owner: @user, access_token: "access-production-new").import!
    end

    assert_not result.created
  end

  test "refuses an Item that belongs to another family" do
    stub_item(item_id: plaid_items(:one).plaid_id)
    other_family = families(:empty)

    assert_raises(PlaidItem::TokenImport::Error) do
      PlaidItem::TokenImport.new(family: other_family, access_token: "access-production-new").import!
    end
  end

  test "refuses an empty token" do
    assert_raises(PlaidItem::TokenImport::Error) do
      PlaidItem::TokenImport.new(family: @family, access_token: " ").import!
    end
  end
end
