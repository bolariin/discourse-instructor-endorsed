# name: discourse-instructor-endorsed
# about: Add an endorse button to posts on Discourse
# version: 0.1
# url: https://github.com/bolariin/discourse-instructor-endorsed

enabled_site_setting :endorse_enabled

PLUGIN_NAME = "discourse_instructor_endorsed".freeze

register_asset 'stylesheets/solutions.scss'

after_initialize do

  # we got to do a one time upgrade
  if defined?(UserAction::ENDORSED)
    unless $redis.get('endorsed_already_upgraded')
      unless UserAction.where(action_type: UserAction::ENDORSED).exists?
        Rails.logger.info("Upgrading storage for endorsed")
        sql = <<SQL
        INSERT INTO user_actions(action_type,
                                 user_id,
                                 target_topic_id,
                                 target_post_id,
                                 acting_user_id,
                                 created_at,
                                 updated_at)
        SELECT :endorsed,
               p.user_id,
               p.topic_id,
               p.id,
               t.user_id,
               pc.created_at,
               pc.updated_at
        FROM
          post_custom_fields pc
        JOIN
          posts p ON p.id = pc.post_id
        JOIN
          topics t ON t.id = p.topic_id
        WHERE
          pc.name = 'is_endorsed_answer' AND
          pc.value = 'true' AND
          p.user_id IS NOT NULL
SQL

        UserAction.exec_sql(sql, endorsed: UserAction::ENDORSED)
      end
      $redis.set("endorsed_already_upgraded", "true")
    end
  end

  module ::DiscourseInstructorEndorsed
    class Engine < ::Rails::Engine
      engine_name PLUGIN_NAME
      isolate_namespace DiscourseInstructorEndorsed
    end
  end

  require_dependency "application_controller"
  class DiscourseInstructorEndorsed::AnswerController < ::ApplicationController

    def endorse

      post = Post.find(params[:id].to_i)
      topic = post.topic

      guardian.ensure_can_endorse_answer!(topic)

      endorsed_id = topic.custom_fields["endorsed_answer_post_id"].to_i
      if endorsed_id > 0
        if p2 = Post.find_by(id: endorsed_id)
          p2.custom_fields["is_endorsed_answer"] = nil
          p2.save!

          if defined?(UserAction::ENDORSED)
            UserAction.where(action_type: UserAction::ENDORSED, target_post_id: p2.id).destroy_all
          end
        end
      end

      post.custom_fields["is_endorsed_answer"] = "true"
      topic.custom_fields["endorsed_answer_post_id"] = post.id
      topic.save!
      post.save!

      if defined?(UserAction::ENDORSED)
        UserAction.log_action!(
          action_type: UserAction::ENDORSED,
          user_id: post.user_id,
          acting_user_id: guardian.user.id,
          target_post_id: post.id,
          target_topic_id: post.topic_id
        )
      end

      unless current_user.id == post.user_id
        Notification.create!(
          notification_type: Notification.types[:custom],
          user_id: post.user_id,
          topic_id: post.topic_id,
          post_number: post.post_number,
          data: {
            message: 'endorse.endorsed_notification',
            display_username: current_user.username,
            topic_title: topic.title
          }.to_json
        )
      end

      if (auto_close_hours = SiteSetting.endorsed_topics_auto_close_hours) > (0) && !topic.closed
        topic.set_or_create_timer(
          TopicTimer.types[:close],
          auto_close_hours,
          based_on_last_post: true
        )

        MessageBus.publish("/topic/#{topic.id}", reload_topic: true)
      end

      DiscourseEvent.trigger(:endorsed_solution, post)
      render json: success_json
    end

    def unendorse

      post = Post.find(params[:id].to_i)
      topic = post.topic

      guardian.ensure_can_endorse_answer!(topic)

      post.custom_fields["is_endorsed_answer"] = nil
      topic.custom_fields["endorsed_answer_post_id"] = nil
      topic.save!
      post.save!

      # TODO remove_action! does not allow for this type of interface
      if defined? UserAction::ENDORSED
        UserAction.where(
          action_type: UserAction::ENDORSED,
          target_post_id: post.id
        ).destroy_all
      end

      # yank notification
      notification = Notification.find_by(
         notification_type: Notification.types[:custom],
         user_id: post.user_id,
         topic_id: post.topic_id,
         post_number: post.post_number
      )

      notification.destroy if notification

      DiscourseEvent.trigger(:unendorsed_solution, post)

      render json: success_json
    end
  end

  DiscourseInstructorEndorsed::Engine.routes.draw do
    post "/endorse" => "answer#endorse"
    post "/unendorse" => "answer#unendorse"
  end

  Discourse::Application.routes.append do
    mount ::DiscourseInstructorEndorsed::Engine, at: "solution"
  end

  TopicView.add_post_custom_fields_whitelister do |user|
    ["is_endorsed_answer"]
  end

  if Report.respond_to?(:add_report)
    AdminDashboardData::GLOBAL_REPORTS << "endorsed_solutions"

    Report.add_report("endorsed_solutions") do |report|
      report.data = []
      endorsed_solutions = TopicCustomField.where(name: "endorsed_answer_post_id")
      endorsed_solutions = endorsed_solutions.joins(:topic).where("topics.category_id = ?", report.category_id) if report.category_id
      endorsed_solutions.where("topic_custom_fields.created_at >= ?", report.start_date)
        .where("topic_custom_fields.created_at <= ?", report.end_date)
        .group("DATE(topic_custom_fields.created_at)")
        .order("DATE(topic_custom_fields.created_at)")
        .count
        .each do |date, count|
        report.data << { x: date, y: count }
      end
      report.total = endorsed_solutions.count
      report.prev30Days = endorsed_solutions.where("topic_custom_fields.created_at >= ?", report.start_date - 30.days)
        .where("topic_custom_fields.created_at <= ?", report.start_date)
        .count
    end
  end

  if defined?(UserAction::ENDORSED)
    require_dependency 'user_summary'
    class ::UserSummary
      def endorsed_count
        UserAction
          .where(user: @user)
          .where(action_type: UserAction::ENDORSED)
          .count
      end
    end

    require_dependency 'user_summary_serializer'
    class ::UserSummarySerializer
      attributes :endorsed_count

      def endorsed_count
        object.endorsed_count
      end
    end
  end

  require_dependency 'topic_view_serializer'
  class ::TopicViewSerializer
    attributes :endorsed_answer

    def include_endorsed_answer?
      endorsed_answer_post_id
    end

    def endorsed_answer
      if info = endorsed_answer_post_info
        {
          post_number: info[0],
          username: info[1],
          excerpt: info[2],
          name: info[3]
        }
      end
    end

    def endorsed_answer_post_info
      # TODO: we may already have it in the stream ... so bypass query here
      postInfo = Post.where(id: endorsed_answer_post_id, topic_id: object.topic.id)
        .joins(:user)
        .pluck('post_number', 'username', 'cooked', 'name')
        .first

      if postInfo
        postInfo[2] = PrettyText.excerpt(postInfo[2], SiteSetting.endorsed_quote_length)
        return postInfo
      end
    end

    def endorsed_answer_post_id
      id = object.topic.custom_fields["endorsed_answer_post_id"]
      # a bit messy but race conditions can give us an array here, avoid
      id && id.to_i rescue nil
    end

  end

  class ::Category
    after_save :reset_endorsed_cache

    protected
    def reset_endorsed_cache
      ::Guardian.reset_endorsed_answer_cache
    end
  end

  class ::Guardian

    @@endorsed_cache = DistributedCache.new("endorsed")

    def self.reset_endorsed_answer_cache
      @@endorsed_cache["allowed"] =
        begin
          Set.new(
            CategoryCustomField
              .where(name: "enable_endorse", value: "true")
              .pluck(:category_id)
          )
        end
    end

    def allow_endorsement_on_category?(category_id)
      return true if SiteSetting.allow_endorsement_on_all_topics

      self.class.reset_endorsed_answer_cache unless @@endorsed_cache["allowed"]
      @@endorsed_cache["allowed"].include?(category_id)
    end

    def can_endorse_answer?(topic)
      SiteSetting.endorse_enabled && allow_endorsement_on_category?(topic.category_id) && (
          authenticated? &&  (current_user.trust_level >= SiteSetting.endorsement_trust_level)
      )
    end
  end

  require_dependency 'post_serializer'
  class ::PostSerializer
    attributes :can_endorse_answer, :can_unendorse_answer, :endorsed_answer

    def can_endorse_answer
      topic = (topic_view && topic_view.topic) || object.topic

      if topic
        return scope.can_endorse_answer?(topic) && object.post_number > 1 && !endorsed_answer
      end

      false
    end

    def can_unendorse_answer
      topic = (topic_view && topic_view.topic) || object.topic
      if topic
        return scope.can_endorse_answer?(topic) && (post_custom_fields["is_endorsed_answer"] == 'true')
      end
    end

    def endorsed_answer
      post_custom_fields["is_endorsed_answer"] == 'true'
    end
  end

  require_dependency 'search'

  #TODO Remove when plugin is 1.0
  if Search.respond_to? :advanced_filter
    Search.advanced_filter(/in:endorsed/) do |posts|
      posts.where("topics.id IN (
        SELECT tc.topic_id
        FROM topic_custom_fields tc
        WHERE tc.name = 'endorsed_answer_post_id' AND
                        tc.value IS NOT NULL
        )")

    end

    Search.advanced_filter(/in:unendorsed/) do |posts|
      posts.where("topics.id NOT IN (
        SELECT tc.topic_id
        FROM topic_custom_fields tc
        WHERE tc.name = 'endorsed_answer_post_id' AND
                        tc.value IS NOT NULL
        )")

    end
  end

  if Discourse.has_needed_version?(Discourse::VERSION::STRING, '1.8.0.beta6')
    require_dependency 'topic_query'

    TopicQuery.add_custom_filter(:endorsed) do |results, topic_query|
      if topic_query.options[:endorsed] == 'yes'
        results = results.where("topics.id IN (
          SELECT tc.topic_id
          FROM topic_custom_fields tc
          WHERE tc.name = 'endorsed_answer_post_id' AND
                          tc.value IS NOT NULL
          )")
      elsif topic_query.options[:endorsed] == 'no'
        results = results.where("topics.id NOT IN (
          SELECT tc.topic_id
          FROM topic_custom_fields tc
          WHERE tc.name = 'endorsed_answer_post_id' AND
                          tc.value IS NOT NULL
          )")
      end
      results
    end
  end

  require_dependency 'topic_list_item_serializer'
  require_dependency 'listable_topic_serializer'

  class ::TopicListItemSerializer
    attributes :has_endorsed_answer, :can_endorse_answer

    def has_endorsed_answer
      object.custom_fields["endorsed_answer_post_id"] ? true : false
    end

    def can_endorse_answer
      return true if SiteSetting.allow_endorsement_on_all_topics
      return false if object.closed || object.archived
      return scope.allow_endorsement_on_category?(object.category_id)
    end

    def include_can_endorse_answer?
      SiteSetting.empty_circle_on_unendorsed
    end
  end

  class ::ListableTopicSerializer
    attributes :has_endorsed_answer, :can_endorse_answer

    def has_endorsed_answer
      object.custom_fields["endorsed_answer_post_id"] ? true : false
    end

    def can_endorse_answer
      return true if SiteSetting.allow_endorsement_on_all_topics
      return false if object.closed || object.archived
      return scope.allow_endorsement_on_category?(object.category_id)
    end

    def include_can_endorse_answer?
      SiteSetting.empty_circle_on_unendorsed
    end
  end

  TopicList.preloaded_custom_fields << "endorsed_answer_post_id" if TopicList.respond_to? :preloaded_custom_fields

  if CategoryList.respond_to?(:preloaded_topic_custom_fields)
    CategoryList.preloaded_topic_custom_fields << "endorsed_answer_post_id"
  end

end
