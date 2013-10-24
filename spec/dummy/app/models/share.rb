class Share < ActiveRecord::Base
  has_many :shares_items, as: :shareable
  belongs_to :owner, :polymorphic => true
  belongs_to :app_file

end
