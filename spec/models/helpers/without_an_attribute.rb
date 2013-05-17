# Copyright (c) 2009-2012 VMware, Inc.

module VCAP::CloudController::ModelSpecHelper
  shared_examples "creation without an attribute" do |opts|
    opts[:required_attributes].each do |without_attr|
      context "without the :#{without_attr.to_s} attribute" do
        let(:filtered_opts) do
          creation_opts.select do |k, v|
            k != without_attr && k != "#{without_attr}_id"
          end
        end

        it "should fail due to validations" do
          val = described_class.new(filtered_opts)
          expect {
            val.save!
          }.to raise_error(ActiveRecord::RecordInvalid)
        end

        if !opts[:db_required_attributes] || opts[:db_required_attributes].include?(without_attr)
          it "should fail due to database integrity checks" do
            expect {
              described_class.new do |instance|
                instance.update_attributes(filtered_opts)
              end.save(:validate => false)
            }.to raise_error ActiveRecord::StatementInvalid, /#{without_attr}/
          end
        end
      end
    end
  end
end
