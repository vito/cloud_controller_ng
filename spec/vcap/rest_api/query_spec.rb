# Copyright (c) 2009-2012 VMware, Inc.
require File.expand_path("../spec_helper", __FILE__)

module VCAP::RestAPI
  describe VCAP::RestAPI::Query do
    include VCAP::RestAPI

    let(:num_authors) { 10 }
    let(:books_per_author) { 2 }

    class Author < ActiveRecord::Base
      has_many :books
    end

    class Book < ActiveRecord::Base
      belongs_to :author
    end

    before(:all) { books_migration }

    def books_migration
      ActiveRecord::Migration.class_eval do
        create_table :authors do |t|
          t.integer :num_val
          t.string  :str_val
          t.integer :protected
          t.boolean :published
        end

        create_table :books do |t|
          t.integer :num_val
          t.string  :str_val

          t.belongs_to :author
        end
      end
    end

    def reset_books
      ActiveRecord::Migration.class_eval do
        drop_table :authors
        drop_table :books
      end
    end

    before do
      reset_books
      books_migration

      (num_authors - 1).times do |i|
        # mysql does typecasting of strings to ints, so start values at 0
        # so that the query using string tests don't find the 0 values.
        a = Author.create(:num_val => i + 1, :str_val => "str #{i}", :published => (i == 0))
        books_per_author.times do |j|
          a.books << Book.create(:num_val => j + 1, :str_val => "str #{i} #{j}")
        end
      end

      @owner_nil_num = Author.create(:str_val => "no num", :published => false)
      @queryable_attributes = Set.new(%w(num_val str_val author_id book_id published))
    end

    describe "#filtered_dataset_from_query_params" do
      describe "no query" do
        it "should return the full dataset" do
          ds = Query.filtered_dataset_from_query_params(Author, Author.scoped,
                                                        @queryable_attributes, {})
          ds.count.should == num_authors
        end
      end

      describe "exact query on a unique integer" do
        it "should return the correct record" do
          q = "num_val:5"
          ds = Query.filtered_dataset_from_query_params(Author, Author.scoped,
                                                        @queryable_attributes, :q => q)
          ds.all.should == Author.where(:num_val => 5)
        end
      end

      describe "greater-than comparison query on an integer within the range" do
        it "should return no results" do
          q = "num_val>#{num_authors - 5}"
          ds = Query.filtered_dataset_from_query_params(Author, Author.scoped,
            @queryable_attributes, :q => q)

          expected = Author.all.select do |a|
            a.num_val && a.num_val > num_authors - 5
          end

          ds.all.should =~ expected
        end
      end

      describe "greater-than equals comparison query on an integer within the range" do
        it "should return no results" do
          q = "num_val>=#{num_authors - 5}"
          ds = Query.filtered_dataset_from_query_params(Author, Author.scoped,
            @queryable_attributes, :q => q)

          expected = Author.all.select do |a|
            a.num_val && a.num_val >= num_authors - 5
          end

          ds.all.should =~ expected
        end
      end

      describe "less-than comparison query on an integer within the range" do
        it "should return no results" do
          q = "num_val<#{num_authors - 5}"
          ds = Query.filtered_dataset_from_query_params(Author, Author.scoped,
            @queryable_attributes, :q => q)

          expected = Author.all.select do |a|
            a.num_val && a.num_val < num_authors - 5
          end

          ds.all.should =~ expected
        end
      end

      describe "less-than equals comparison query on an integer within the range" do
        it "should return no results" do
          q = "num_val<=#{num_authors - 5}"
          ds = Query.filtered_dataset_from_query_params(Author, Author.scoped,
            @queryable_attributes, :q => q)

          expected = Author.all.select do |a|
            a.num_val && a.num_val <= num_authors - 5
          end

          ds.all.should =~ expected
        end
      end

      describe "exact query on a nonexistent integer" do
        it "should return no results" do
          q = "num_val:#{num_authors + 10}"
          ds = Query.filtered_dataset_from_query_params(Author, Author.scoped,
            @queryable_attributes, :q => q)
          ds.count.should == 0
        end
      end

      describe "exact query on an integer field with a string" do
        it "should return no results" do
          q = "num_val:a"
          ds = Query.filtered_dataset_from_query_params(Author, Author.scoped,
                                                        @queryable_attributes, :q => q)
          ds.count.should == 0
        end
      end

      describe "exact query on a unique string" do
        it "should return the correct record" do
          q = "str_val:str 5"
          ds = Query.filtered_dataset_from_query_params(Author, Author.scoped,
                                                        @queryable_attributes, :q => q)
          ds.all.should == Author.where(:str_val => "str 5")
        end
      end

      describe "exact query on a nonexistent string" do
        it "should return the correct record" do
          q = "str_val:fnord"
          ds = Query.filtered_dataset_from_query_params(Author, Author.scoped,
                                                        @queryable_attributes, :q => q)
          ds.count.should == 0
        end
      end

      describe "exact query on a string prefix" do
        it "should return no results" do
          q = "str_val:str"
          ds = Query.filtered_dataset_from_query_params(Author, Author.scoped,
                                                        @queryable_attributes, :q => q)
          ds.count.should == 0
        end
      end

      describe "exact query on a nonexistent attribute" do
        it "should raise BadQueryParameter" do
          q = "bogus_val:1"
          expect {
            Query.filtered_dataset_from_query_params(Author, Author.scoped,
                                                          @queryable_attributes, :q => q)
          }.to raise_error(VCAP::Errors::BadQueryParameter)
        end
      end

      describe "exact query on a nonallowed attribute" do
        it "should raise BadQueryParameter" do
          q = "protected:1"
          expect {
            Query.filtered_dataset_from_query_params(Author, Author.scoped,
                                                          @queryable_attributes, :q => q)
          }.to raise_error(VCAP::Errors::BadQueryParameter)
        end
      end

      describe "querying multiple values" do
        it "should return the correct record" do
          q = "num_val:5;str_val:str 4"
          ds = Query.filtered_dataset_from_query_params(Author, Author.scoped,
            @queryable_attributes, :q => q)
          ds.all.should == Author.where(:num_val => 5, :str_val => "str 4")
        end
      end

      describe "without a key" do
        it "should raise BadQueryParameter" do
          q = ":10"
          expect {
            Query.filtered_dataset_from_query_params(Author, Author.scoped,
                                                          @queryable_attributes, :q => q)
          }.to raise_error(VCAP::Errors::BadQueryParameter)
        end
      end

      describe "exact query with nil value" do
        it "should return records with nil entries" do
          q = "num_val:"
          ds = Query.filtered_dataset_from_query_params(Author, Author.scoped,
                                                        @queryable_attributes, :q => q)
          ds.all.should == [@owner_nil_num]
        end
      end

      describe "exact query with an nonexistent id from a to_many relation" do
        xit "should return no results" do
          q = "book_id:9999"
          ds = Query.filtered_dataset_from_query_params(Author, Author.scoped,
                                                        @queryable_attributes, :q => q)
          ds.count.should == 0
        end
      end

      describe "exact query with an id from a to_many relation" do
        xit "should return no results" do
          q = "book_id:2"
          ds = Query.filtered_dataset_from_query_params(Author, Author.scoped,
                                                        @queryable_attributes, :q => q)
          ds.all.should == Author.find(Book.find(2).author_id)
        end
      end

      describe "exact query with an nonexistent id from a to_one relation" do
        it "should return no results" do
          q = "author_id:9999"
          ds = Query.filtered_dataset_from_query_params(Book, Book.scoped,
                                                        @queryable_attributes, :q => q)
          ds.count.should == 0
        end
      end

      describe "exact query with an id from a to_one relation" do
        it "should return the correct results" do
          q = "author_id:1"
          ds = Query.filtered_dataset_from_query_params(Book, Book.scoped,
                                                        @queryable_attributes, :q => q)
          ds.all.should == Author.find(1).books
        end
      end

      describe "boolean values on boolean column" do
        it "returns correctly filtered results for true" do
          ds = Query.filtered_dataset_from_query_params(
            Author, Author.scoped, @queryable_attributes, :q => "published:t")
          ds.all.should == [Author.first]
        end

        it "returns correctly filtered results for false" do
          ds = Query.filtered_dataset_from_query_params(
            Author, Author.scoped, @queryable_attributes, :q => "published:f")
          ds.all.should == Author.all - [Author.first]
        end
      end
    end
  end
end
