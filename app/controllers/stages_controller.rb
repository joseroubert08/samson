require 'open-uri' # needed to fetch from img.shields.io using open()

class StagesController < ApplicationController
  skip_before_action :login_users, if: :badge?
  before_action :authorize_admin!, except: [:index, :show]
  before_action :authorize_deployer!, unless: :badge?
  before_action :check_token, if: :badge?
  before_action :find_project
  before_action :find_stage, only: [:show, :edit, :update, :destroy, :clone]
  before_action :find_deploy_groups, only: [:edit], if: ENV['DEPLOY_GROUP_FEATURE']

  def index
    @stages = @project.stages

    respond_to do |format|
      format.html
      format.json do
        render json: @stages
      end
    end
  end

  def show
    respond_to do |format|
      format.html do
        @deploys = @stage.deploys.page(params[:page])
      end
      format.svg do
        badge = if deploy = @stage.last_successful_deploy
          "#{badge_safe(@stage.name)}-#{badge_safe(deploy.short_reference)}-green"
        else
          "#{badge_safe(@stage.name)}-None-red"
        end

        if stale?(etag: badge)
          expires_in 1.minute, :public => true
          image = open("http://img.shields.io/badge/#{badge}.svg").read
          render text: image, content_type: Mime::SVG
        end
      end
    end
  end

  def new
    @stage = @project.stages.build(command_ids: Command.global.pluck(:id))
    @stage.new_relic_applications.build
  end

  def create
    # Need to ensure project is already associated
    @stage = @project.stages.build
    @stage.attributes = stage_params

    if @stage.save
      redirect_to project_stage_path(@project, @stage)
    else
      flash[:error] = @stage.errors.full_messages

      @stage.new_relic_applications.build

      render :new
    end
  end

  def edit
    @stage.new_relic_applications.build
  end

  def update
    if @stage.update_attributes(stage_params)
      redirect_to project_stage_path(@project, @stage)
    else
      flash[:error] = @stage.errors.full_messages

      @stage.new_relic_applications.build

      render :edit
    end
  end

  def destroy
    @stage.soft_delete!
    redirect_to project_path(@project)
  end

  def reorder
    Stage.reorder(params[:stage_id])

    head :ok
  end

  def clone
    @stage = Stage.build_clone(@stage)
    render :new
  end

  private

  def badge_safe(string)
    CGI.escape(string)
      .gsub('+','%20')
      .gsub(/-+/,'--')
  end

  def check_token
    unless params[:token] == Rails.application.config.samson.badge_token
      raise ActiveRecord::RecordNotFound
    end
  end

  def badge?
    action_name == 'show' && request.format == Mime::SVG
  end

  def stage_params
    params.require(:stage).permit([
      :name, :command, :confirm, :permalink, :dashboard,
      :production,
      :notify_email_address,
      :deploy_on_release,
      :datadog_tags,
      :datadog_monitor_ids,
      :update_github_pull_requests,
      :email_committers_on_automated_deploy_failure,
      :static_emails_on_automated_deploy_failure,
      deploy_group_ids: [],
      command_ids: [],
      new_relic_applications_attributes: [:id, :name, :_destroy]
    ] + Samson::Hooks.fire(:stage_permitted_params))
  end

  def find_project
    @project = Project.find_by_param!(params[:project_id])
  end

  def find_stage
    @stage = @project.stages.find_by_param!(params[:id])
  end

  def find_deploy_groups
    @deploy_groups = DeployGroup.includes(:environment).order(:environment_id, :name).all
  end
end
