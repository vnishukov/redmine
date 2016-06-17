# Copyright © Emilio González Montaña
# Licence: Attribution & no derivates
#   * Attribution to the plugin web page URL should be done if you want to use it.
#     https://redmine.ociotec.com/projects/redmine-plugin-scrum
#   * No derivates of this plugin (or partial) are allowed.
# Take a look to licence.txt file at plugin root folder for further details.

class ScrumController < ApplicationController

  menu_item :product_backlog, :except => [:stats]
  menu_item :overview, :only => [:stats]

  before_filter :find_issue, :only => [:change_story_points, :change_pending_effort, :change_assigned_to,
                                       :new_time_entry, :create_time_entry, :edit_task, :update_task,
                                       :change_pending_efforts]
  before_filter :find_sprint, :only => [:new_pbi, :create_pbi]
  before_filter :find_pbi, :only => [:new_task, :create_task, :edit_pbi, :update_pbi, :move_pbi,
                                     :move_to_last_sprint, :move_to_product_backlog]
  before_filter :find_project_by_project_id, :only => [:release_plan, :stats]
  before_filter :authorize, :except => [:new_pbi, :create_pbi, :new_task, :create_task,
                                        :new_time_entry, :create_time_entry,
                                        :change_pending_efforts]
  before_filter :authorize_add_issues, :only => [:new_pbi, :create_pbi, :new_task, :create_task]
  before_filter :authorize_log_time, :only => [:new_time_entry, :create_time_entry]
  before_filter :authorize_edit_issues, :only => [:change_pending_efforts]

  helper :scrum
  helper :timelog
  helper :custom_fields
  helper :projects

  def change_story_points
    begin
      @issue.story_points = params[:value]
      status = 200
    rescue
      status = 503
    end
    render :nothing => true, :status => status
  end

  def change_pending_effort
    PendingEffort.create(issue_id: @issue.id, date: Time.now, effort: params[:value].to_f)
    render :nothing => true, :status => 200
  end

  def change_pending_efforts
    params['pending_efforts'].each_pair do |id, value|
      pending_effort = PendingEffort.find(id)
      raise "Invalid pending effort ID #{id}" if pending_effort.nil?
      raise "Pending effort ID #{id} is not owned by this issue" if pending_effort.issue_id != @issue.id
      pending_effort.effort = value.to_f
      pending_effort.save!
    end
    redirect_to issue_path(@issue)
  end

  def change_assigned_to
    @issue.init_journal(User.current)
    @issue.assigned_to = params[:value].blank? ? nil : User.find(params[:value].to_i)
    @issue.save!
    render_task(@project, @issue, params)
  end

  def new_time_entry
    @pbi_status_id = params[:pbi_status_id]
    @other_pbi_status_ids = params[:other_pbi_status_ids]
    @task_id = params[:task_id]
    respond_to do |format|
      format.js
    end
  end

  def create_time_entry
    begin
      time_entry_params = params[:time_entry]
      time_entry = TimeEntry.new(time_entry_params.except(:adjust_effort, :pending_efforts))
      time_entry.project_id = @project.id
      time_entry.issue_id = @issue.id
      time_entry.user_id = time_entry_params[:user_id]
      call_hook(:controller_timelog_edit_before_save, {:params => params, :time_entry => time_entry})
      time_entry.save!

      if time_entry_params[:adjust_effort].present?
        is_manual = (time_entry_params[:adjust_effort] == 'manual')
        effort = is_manual ? time_entry_params[:pending_efforts].to_f : @issue.pending_effort - time_entry_params[:hours].to_f
        if @issue.pending_effort > 0 || (is_manual && effort > 0)
          PendingEffort.create(issue_id: @issue.id, date: Time.now, effort: effort > 0 ? effort : 0)
        end
      end

    rescue Exception => @exception
      logger.error("Exception: #{@exception.inspect}")
    end
    respond_to do |format|
      format.js
    end
  end

  def new_pbi
    @pbi = Issue.new
    @pbi.project = @project
    @pbi.tracker = @project.trackers.find(params[:tracker_id])
    @pbi.author = User.current
    @pbi.sprint = @sprint
    @top = true unless params[:top].nil? or (params[:top] == "false")
    respond_to do |format|
      format.html
      format.js
    end
  end

  def create_pbi
    begin
      @continue = !(params[:create_and_continue].nil?)
      @top = !(params[:top].nil?)
      @pbi = Issue.new
      @pbi.project = @project
      @pbi.author = User.current
      @pbi.tracker_id = params[:issue][:tracker_id]
      update_attributes(@pbi, params)
      if @top
        @pbi.set_on_top
        @pbi.save!
      end
      @pbi.sprint = @sprint
      @pbi.save!
    rescue Exception => @exception
      logger.error("Exception: #{@exception.inspect}")
    end
    respond_to do |format|
      format.js
    end
  end

  def edit_pbi
    respond_to do |format|
      format.js
    end
  end

  def update_pbi
    begin
      @pbi.init_journal(User.current, params[:issue][:notes])
      update_attributes(@pbi, params)
      @pbi.save!
    rescue Exception => @exception
      logger.error("Exception: #{@exception.inspect}")
    end
    respond_to do |format|
      format.js
    end
  end

  def move_pbi
    begin
      @position = params[:position]
      case params[:position]
        when "top", "bottom"
          @pbi.move_pbi_to(@position)
        when "before"
          @other_pbi = params[:before_other_pbi]
          @pbi.move_pbi_to(@position, @other_pbi)
        when "after"
          @other_pbi = params[:after_other_pbi]
          @pbi.move_pbi_to(@position, @other_pbi)
        else
          raise "Invalid position: #{@position.inspect}"
      end
    rescue Exception => @exception
      logger.error("Exception: #{@exception.inspect}")
    end
  end

  def move_to_last_sprint
    begin
      raise "The project hasn't defined any Sprint yet" unless @project.last_sprint
      @previous_sprint = @pbi.sprint
      move_issue_to_sprint(@pbi, @project.last_sprint)
    rescue Exception => @exception
      logger.error("Exception: #{@exception.inspect}")
    end
    respond_to do |format|
      format.js
    end
  end

  def move_to_product_backlog
    begin
      raise "The project hasn't defined the Product Backlog yet" unless @project.product_backlog
      move_issue_to_sprint(@pbi, @project.product_backlog)
    rescue Exception => @exception
      logger.error("Exception: #{@exception.inspect}")
    end
    respond_to do |format|
      format.js
    end
  end

  def new_task
    @task = Issue.new
    @task.project = @project
    @task.tracker = Tracker.find(params[:tracker_id])
    @task.parent = @pbi
    @task.author = User.current
    @task.sprint = @sprint
    if Scrum::Setting.inherit_pbi_attributes
      @task.inherit_from_issue(@pbi)
    end
    respond_to do |format|
      format.html
      format.js
    end
  rescue Exception => e
    logger.error("Exception: #{e.inspect}")
    render_404
  end

  def create_task
    begin
      @continue = !(params[:create_and_continue].nil?)
      @task = Issue.new
      @task.project = @project
      @task.parent_issue_id = @pbi.id
      @task.author = User.current
      @task.sprint = @sprint
      @task.tracker_id = params[:issue][:tracker_id]
      update_attributes(@task, params)
      @task.save!
      @task.pending_effort = params[:issue][:pending_effort]
    rescue Exception => @exception
    end
    respond_to do |format|
      format.js
    end
  end

  def edit_task
    respond_to do |format|
      format.js
    end
  end

  def update_task
    begin
      @issue.init_journal(User.current, params[:issue][:notes])
      @old_status = @issue.status
      update_attributes(@issue, params)
      @issue.save!
      @issue.pending_effort = params[:issue][:pending_effort]
      unless @issue.parent_id.blank?
        parent = Issue.find_by_id(@issue.parent_id)
        parent_issues_statuses_ids = Issue.all.where(parent_id: parent.id).collect(&:status_id).uniq
        if parent_issues_statuses_ids.size.eql? 1
          if Scrum::Setting.when_all_subtasks_status_id.eql? parent_issues_statuses_ids[0]
            parent.status = IssueStatus.find(Scrum::Setting.user_story_move_status_id)
            parent.save!
          end
        end
      end
    rescue Exception => @exception
      logger.error("Exception: #{@exception.inspect}")
    end
    respond_to do |format|
      format.js
    end
  end

  def release_plan
    @product_backlog = @project.product_backlog
    @sprints = []
    velocity_all_pbis, velocity_scheduled_pbis, @sprints_count = @project.story_points_per_sprint
    @velocity_type = params[:velocity_type] || "only_scheduled"
    case @velocity_type
      when "all"
        @velocity = velocity_all_pbis
      when "only_scheduled"
        @velocity = velocity_scheduled_pbis
      else
        @velocity = params[:custom_velocity].to_f unless params[:custom_velocity].blank?
    end
    @velocity = 1.0 if @velocity.blank? or @velocity < 1.0
    @total_story_points = 0.0
    @pbis_with_estimation = 0
    @pbis_without_estimation = 0
    versions = {}
    accumulated_story_points = @velocity
    current_sprint = {:pbis => [], :story_points => 0.0, :versions => []}
    if @project.product_backlog
      @project.product_backlog.pbis.each do |pbi|
        if pbi.story_points
          @pbis_with_estimation += 1
          story_points = pbi.story_points.to_f
          @total_story_points += story_points
          while accumulated_story_points < story_points
            @sprints << current_sprint
            accumulated_story_points += @velocity
            current_sprint = {:pbis => [], :story_points => 0.0, :versions => []}
          end
          accumulated_story_points -= story_points
          current_sprint[:pbis] << pbi
          current_sprint[:story_points] += story_points
          if pbi.fixed_version
            versions[pbi.fixed_version.id] = {:version => pbi.fixed_version,
                                              :sprint => @sprints.count}
          end
        else
          @pbis_without_estimation += 1
        end
      end
      if current_sprint and (current_sprint[:pbis].count > 0)
        @sprints << current_sprint
      end
      versions.values.each do |info|
        @sprints[info[:sprint]][:versions] << info[:version]
      end
    end
  end

  def stats
    if User.current.allowed_to_view_all_time_entries?(@project)
      cond = @project.project_condition(Setting.display_subprojects_issues?)
      @total_hours = TimeEntry.visible.where(cond).sum(:hours).to_f
    end

    @hours_per_story_point = @project.hours_per_story_point
    @hours_per_story_point_chart = {:id => "hours_per_story_point", :height => 400}

    @sps_by_pbi_category, @sps_by_pbi_category_total = @project.sps_by_category
    @sps_by_pbi_type, @sps_by_pbi_type_total = @project.sps_by_pbi_type
    @effort_by_activity, @effort_by_activity_total = @project.effort_by_activity
  end

private

  def render_task(project, task, params)
    render :partial => "post_its/sprint_board/task",
           :status => 200,
           :locals => {:project => project,
                       :task => task,
                       :pbi_status_id => params[:pbi_status_id],
                       :other_pbi_status_ids => params[:other_pbi_status_ids].split(","),
                       :task_id => params[:task_id],
                       :read_only => false}
  end

  def find_sprint
    @sprint = Sprint.find(params[:sprint_id])
    @project = @sprint.project
  rescue
    logger.error("Sprint #{params[:sprint_id]} not found")
    render_404
  end

  def find_pbi
    @pbi = Issue.find(params[:pbi_id])
    @sprint = @pbi.sprint
    @project = @sprint.project
  rescue
    logger.error("PBI #{params[:pbi_id]} not found")
    render_404
  end

  def authorize_action_on_current_project(action)
    if User.current.allowed_to?(action, @project)
      return true
    else
      render_403
      return false
    end
  end

  def authorize_add_issues
    authorize_action_on_current_project(:add_issues)
  end

  def authorize_log_time
    authorize_action_on_current_project(:log_time)
  end

  def authorize_edit_issues
    authorize_action_on_current_project(:edit_issues)
  end

  def update_attributes(issue, params)
    issue.status_id = params[:issue][:status_id] unless params[:issue][:status_id].nil?
    raise 'New status is not allowed' unless issue.new_statuses_allowed_to.include?(issue.status)
    issue.assigned_to_id = params[:issue][:assigned_to_id] unless params[:issue][:assigned_to_id].nil?
    issue.subject = params[:issue][:subject] unless params[:issue][:subject].nil?
    issue.priority_id = params[:issue][:priority_id] unless params[:issue][:priority_id].nil?
    issue.estimated_hours = params[:issue][:estimated_hours].gsub(',', '.') unless params[:issue][:estimated_hours].nil?
    issue.done_ratio = params[:issue][:done_ratio] unless params[:issue][:done_ratio].nil?
    issue.description = params[:issue][:description] unless params[:issue][:description].nil?
    issue.category_id = params[:issue][:category_id] if issue.safe_attribute?(:category_id) and (!(params[:issue][:category_id].nil?))
    issue.fixed_version_id = params[:issue][:fixed_version_id] if issue.safe_attribute?(:fixed_version_id) and (!(params[:issue][:fixed_version_id].nil?))
    issue.start_date = params[:issue][:start_date] if issue.safe_attribute?(:start_date) and (!(params[:issue][:start_date].nil?))
    issue.due_date = params[:issue][:due_date] if issue.safe_attribute?(:due_date) and (!(params[:issue][:due_date].nil?))
    issue.custom_field_values = params[:issue][:custom_field_values] unless params[:issue][:custom_field_values].nil?
  end

  def move_issue_to_sprint(issue, sprint)
    issue.init_journal(User.current)
    issue.sprint = sprint
    issue.save!
    issue.children.each do |child|
      unless child.closed?
        move_issue_to_sprint(child, sprint)
      end
    end
  end

end
