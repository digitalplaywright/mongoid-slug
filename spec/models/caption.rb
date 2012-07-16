class Caption
  include Mongoid::Document
  include Mongoid::Slug
  field :my_identity, :type => String
  field :title
  field :medium

  # A fairly complex scenario, where we want to create a slug out of an
  # my_identity field, which comprises name of artist and some more bibliographic
  # info in parantheses, and the title of the work.
  #
  # We are only interested in the name of the artist so we remove the
  # paranthesized details.
  slug :my_identity, :title do |doc|
    [doc.my_identity.gsub(/\s*\([^)]+\)/, ''), doc.title].join(' ')
  end
end
