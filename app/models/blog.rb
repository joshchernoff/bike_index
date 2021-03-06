class Blog < ApplicationRecord
  include ActionView::Helpers::TextHelper
  include Localizable

  belongs_to :user
  has_many :public_images, as: :imageable, dependent: :destroy
  has_many :listicles, dependent: :destroy
  accepts_nested_attributes_for :listicles, allow_destroy: true

  validates_presence_of :title, :body, :user_id
  validates_uniqueness_of :title, message: "has already been taken. If you believe that this message is an error, contact us!"
  validates_uniqueness_of :title_slug, message: "somehow that overlaps with another title! Sorrys."

  before_save :set_calculated_attributes
  before_create :set_title_slug

  attr_accessor :post_date, :post_now, :update_title, :user_email, :timezone

  scope :published, -> { where(published: true) }
  scope :listicle_blogs, -> { where(is_listicle: true) }
  scope :blog, -> { where(is_info: false) }
  scope :info, -> { where(is_info: true) }
  default_scope { order("published_at desc") }

  include PgSearch::Model
  pg_search_scope :text_search, against: {title: "A", body: "B"}

  def self.slugify_title(str)
    # Truncate, slugify, also - remove last char if a dash (slugify should take care of removing the dash now, but whatever)
    return nil unless str.present?
    Slugifyer.slugify(str)[0, 70].gsub(/-$/, "")
  end

  def self.integer_slug?(n)
    n.is_a?(Integer) || n.match(/\A\d+\z/).present?
  end

  def self.friendly_find(str)
    return nil unless str.present?
    return find(str) if integer_slug?(str)
    slug = slugify_title(str)
    find_by_title_slug(slug) || find_by_old_title_slug(slug) ||
      find_by_title_slug(str) || find_by_title(str)
  end

  def self.why_donate_slug
    "end-2020-with-a-donation-to-bike-index"
  end

  def info?
    is_info
  end

  def blog?
    !info?
  end

  def to_param
    title_slug
  end

  def set_calculated_attributes
    self.published_at ||= Time.current # We need to have a published time...
    self.canonical_url = Urlifyer.urlify(canonical_url)
    set_published_at_and_published
    self.published_at = Time.current if is_info
    update_title_save
    create_abbreviation
    set_index_image
  end

  def set_published_at_and_published
    if post_date.present?
      self.published_at = TimeParser.parse(post_date, timezone)
    end
    self.published_at = Time.current if post_now == "1"
    if user_email.present?
      u = User.fuzzy_email_find(user_email)
      self.user_id = u.id if u.present?
    end
  end

  def description
    return description_abbr if description_abbr.present?
    body_abbr
  end

  def feed_content
    if is_listicle
      listicles.collect { |l|
        ApplicationController.helpers.listicle_html(l)
      }.join.html_safe
    else
      Kramdown::Document.new(body).to_html
    end
  end

  def update_title_save
    return true unless update_title.present?
    return true if update_title == false || update_title == "0"
    self.old_title_slug = title_slug
    set_title_slug
  end

  def set_title_slug
    # We want to only set this once, and not change it, so that links don't break
    self.title_slug = self.class.slugify_title(title)
  end

  def create_abbreviation
    if description_abbr.present?
      self.body_abbr = description_abbr
    else
      if is_listicle && listicles.first.present?
        body_html = listicles.first.body_html
      else
        # Render markdown,
        markdown = Kramdown::Document.new(body)
        body_html = markdown.to_html
      end
      abbr = strip_tags(body_html)
      # strip tags, then remove extra spaces
      abbr = abbr.tr("\n", " ").gsub(/\s+/, " ").strip if abbr.present?
      self.body_abbr = truncate(abbr, length: 200)
    end
    true
  end

  def set_index_image
    self.index_image_id = nil unless PublicImage.where(id: index_image_id).present?
    if index_image_id.present?
      if index_image_id == 0
        self.index_image = nil
      elsif is_listicle
        li = listicles.find(index_image_id)
      else
        pi = public_images.find(index_image_id)
      end
    elsif is_listicle && listicles.present? && listicles.first.image.present?
      li = listicles.first
      # self.index_image = listicles.first.image_url(:medium)
      self.index_image_id = li.id
    elsif public_images.present?
      pi = public_images.last
      self.index_image_id = public_images.last.id
    end
    if li.present?
      self.index_image = li.image_url(:medium)
      self.index_image_lg = li.image_url(:large)
    elsif pi.present?
      self.index_image = pi.image_url(:small)
      self.index_image_lg = pi.image_url(:large)
    end
    true
  end
end
