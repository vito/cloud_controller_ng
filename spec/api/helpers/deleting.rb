module VCAP::CloudController::ApiSpecHelper
  shared_examples "deleting a valid object" do |opts|
    describe "deleting a valid object" do
      describe "DELETE #{opts[:path]}/:id" do
        let(:obj) { opts[:model].make }

        subject { delete "#{opts[:path]}/#{obj.guid}", {}, admin_headers }

        before(:all) { reset_database }

        context "when there are no child associations" do
          before do
            if obj.is_a? Models::Service
              # Blueprint makes a ServiceAuthToken. No other model has child associated models created by Blueprint.
              obj.service_auth_token.delete
            end
          end

          it "should return 204" do
            subject
            last_response.status.should == 204
          end

          it "should return an empty response body" do
            subject
            last_response.body.should be_empty
          end
        end

        context "when the object has a child associations" do
          let(:one_to_one_or_many) do
            obj.class.reflections.select do |association, meta|
              case meta.macro
              when :has_many
                !obj.send(association).empty?
              when :has_one
                !!obj.send(association)
              else
                false
              end
            end.keys
          end

          let!(:associations_without_url) do
            opts[:one_to_many_collection_ids_without_url].map do |key, child|
              [key, child.call(obj)]
            end
          end

          let!(:associations_with_url) do
            opts[:one_to_many_collection_ids].map do |key, child|
              [key, child.call(obj)]
            end
          end

          around { |example| example.call unless one_to_one_or_many.empty? }

          it "should return 400" do
            subject
            last_response.status.should == 400
          end

          it "should return the expected response body" do
            subject
            Yajl::Parser.parse(last_response.body).should == {
                "code" => 10006,
                "description" => "Please delete the #{one_to_one_or_many.join(", ")} associations for your #{obj.class.table_name}.",
            }
          end

          context "and the recursive param is passed in" do
            subject { delete "#{opts[:path]}/#{obj.guid}?recursive=true", {}, admin_headers }

            it "should return 204" do
              subject
              last_response.status.should == 204
            end

            it "should return an empty response body" do
              subject
              last_response.body.should be_empty
            end

            it "should delete all the child associations" do
              subject
              (associations_without_url | associations_with_url).map do |name, association|
                unless obj.class.reflections[name].macro == :has_and_belongs_to_many || name == :default_users
                  association.class.exists?(association.id).should be_false
                end
              end
            end
          end
        end
      end
    end
  end
end
