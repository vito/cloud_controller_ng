# Copyright (c) 2009-2012 VMware, Inc.

require File.expand_path("../spec_helper", __FILE__)

describe "Sequel::Plugins::VcapNormalization" do
  before(:all) do
    reset_database
    test_migration
  end

  after(:all) { reset_test }

  def test_migration
    ActiveRecord::Migration.class_eval do
      create_table :test do |t|
        t.string :val1
        t.string :val2
        t.string :val3
      end
    end
  end

  def reset_test
    ActiveRecord::Migration.class_eval do
      drop_table :test
    end
  end

  before do
    reset_test
    test_migration

    @c = Class.new(ActiveRecord::Base)
    @c.table_name = "test"
    @m = @c.new
  end

  describe "#strip_attributes" do
    it "should not cause anything to be normalized if not called" do
      @m.val1 = "hi "
      @m.val2 = " bye"
      @m.val1.should == "hi "
      @m.val2.should == " bye"
    end

    it "should only result in provided strings being normalized" do
      @c.strip_attributes :val2, :val3
      @m.val1 = "hi "
      @m.val2 = " bye"
      @m.val3 = " with spaces "
      @m.save
      @m.val1.should == "hi "
      @m.val2.should == "bye"
      @m.val3.should == "with spaces"
    end
  end
end
